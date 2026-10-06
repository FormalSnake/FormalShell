//! One layer surface and its wl_shm buffers. A commit carries only the
//! rects the scene dirtied, copied out of the renderer's canvas into
//! whichever buffer the compositor has released, plus whatever that buffer
//! missed while the other one was on screen. A frame callback is asked for
//! only on a commit made while something on the surface animates.

use std::time::Instant;

use smithay_client_toolkit::compositor::FrameCallbackData;
use smithay_client_toolkit::reexports::client::QueueHandle;
use smithay_client_toolkit::reexports::client::protocol::wl_shm;
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::LayerSurface;
use smithay_client_toolkit::shm::Shm;
use smithay_client_toolkit::shm::slot::{Buffer, SlotPool};

use crate::render::Renderer;
use crate::scene::{IRect, Scene};
use crate::wayland::App;

/// Past this many pending rects a buffer just takes their union.
const STALE_LIMIT: usize = 8;

struct ShmBuffer {
    buffer: Buffer,
    stale: Vec<IRect>,
}

pub struct Surface {
    pub name: &'static str,
    pub layer: LayerSurface,
    pool: SlotPool,
    buffers: Vec<ShmBuffer>,
    renderer: Renderer,
    pub configured: bool,
    /// A frame callback is outstanding: nothing is drawn until it lands.
    pub frame_pending: bool,
    /// The first callback after the first commit, which is when the
    /// surface is on screen.
    pub mapped: bool,
    /// Whether the owner waits on `mapped` before it animates.
    pub wait_map: bool,
    started: Instant,
    commits: u64,
    pub callbacks: u64,
}

impl Surface {
    pub fn new(name: &'static str, layer: LayerSurface, shm: &Shm, started: Instant) -> Self {
        Self {
            name,
            layer,
            pool: SlotPool::new(4096, shm).expect("wl_shm pool"),
            buffers: Vec::new(),
            renderer: Renderer::new(1, 1),
            configured: false,
            frame_pending: false,
            mapped: false,
            wait_map: false,
            started,
            commits: 0,
            callbacks: 0,
        }
    }

    /// The compositor's size, which the owner has resized its scene to.
    pub fn configure(&mut self, width: i32, height: i32) {
        self.configured = true;
        if (self.renderer.width() as i32, self.renderer.height() as i32) != (width, height) {
            self.renderer.resize(width as u16, height as u16);
            self.buffers.clear();
        }
    }

    pub fn present(&mut self, scene: &mut Scene, animating: bool, qh: &QueueHandle<App>) {
        if !self.configured || self.frame_pending {
            return;
        }
        // An animation whose frame changed nothing (a card still wholly
        // behind its line) still needs the next callback to carry on.
        let request = animating || (self.wait_map && !self.mapped);
        if !scene.has_damage() {
            if request && self.commits > 0 {
                let surface = self.layer.wl_surface();
                surface.frame(qh, FrameCallbackData(surface.clone()));
                self.frame_pending = true;
                self.layer.commit();
            }
            return;
        }
        let damage = scene.take_damage();
        let t0 = Instant::now();
        for rect in &damage {
            self.renderer.render(scene, *rect);
        }
        let render_us = t0.elapsed().as_micros();

        let t1 = Instant::now();
        let size = scene.size;
        let at = match self.buffers.iter().position(|b| b.buffer.canvas(&mut self.pool).is_some()) {
            Some(at) => at,
            None => {
                let (buffer, _) = self
                    .pool
                    .create_buffer(size.w, size.h, size.w * 4, wl_shm::Format::Argb8888)
                    .expect("wl_shm buffer");
                self.buffers.push(ShmBuffer { buffer, stale: vec![size] });
                self.buffers.len() - 1
            }
        };

        for (i, b) in self.buffers.iter_mut().enumerate() {
            if i != at {
                b.stale.extend_from_slice(&damage);
                if b.stale.len() > STALE_LIMIT {
                    let union = b.stale.iter().fold(b.stale[0], |u, r| u.union(r));
                    b.stale = vec![union];
                }
            }
        }

        let target = &mut self.buffers[at];
        let mut copy = std::mem::take(&mut target.stale);
        copy.extend_from_slice(&damage);
        let canvas = target.buffer.canvas(&mut self.pool).expect("released buffer");
        let src = self.renderer.canvas().data();
        let stride = self.renderer.width() as usize;
        for rect in &copy {
            let rect = rect.intersect(&size);
            for row in rect.y..rect.bottom() {
                let start = row as usize * stride + rect.x as usize;
                let pixels = &src[start..start + rect.w as usize];
                let out = &mut canvas[start * 4..(start + rect.w as usize) * 4];
                // wl_shm ARGB8888 is premultiplied BGRA in memory on little endian.
                for (px, dst) in pixels.iter().zip(out.chunks_exact_mut(4)) {
                    dst.copy_from_slice(&[px.b, px.g, px.r, px.a]);
                }
            }
        }
        let copy_us = t1.elapsed().as_micros();

        let surface = self.layer.wl_surface();
        for rect in &damage {
            surface.damage_buffer(rect.x, rect.y, rect.w, rect.h);
        }
        // Until the first callback the surface may not be on screen yet,
        // and an enter waits for it (Presence.qml's `mapped`).
        if request {
            surface.frame(qh, FrameCallbackData(surface.clone()));
            self.frame_pending = true;
        }
        target.buffer.attach_to(surface).expect("attach released buffer");
        self.layer.commit();

        self.commits += 1;
        let area: i64 = damage.iter().map(IRect::area).sum();
        let rects: Vec<String> = damage.iter().map(|r| format!("{},{},{}x{}", r.x, r.y, r.w, r.h)).collect();
        eprintln!(
            "commit surface={} n={} t={}ms render_us={} copy_us={} rects={} px={} damage=[{}] buffer={} frame_callbacks={} request={}",
            self.name,
            self.commits,
            self.started.elapsed().as_millis(),
            render_us,
            copy_us,
            damage.len(),
            area,
            rects.join(" "),
            at,
            self.callbacks,
            request as u8,
        );
    }

    pub fn report(&self) -> String {
        format!("{}: commits={} frame_callbacks={}", self.name, self.commits, self.callbacks)
    }
}
