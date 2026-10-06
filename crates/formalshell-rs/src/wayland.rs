//! The bar's layer surface and its wl_shm buffers. A commit carries only the
//! rects the scene dirtied, copied out of the renderer's canvas into
//! whichever buffer the compositor has released, plus whatever that buffer
//! missed while the other one was on screen.

use std::time::Instant;

use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState};
use smithay_client_toolkit::reexports::client::globals::GlobalList;
use smithay_client_toolkit::reexports::client::protocol::{wl_output, wl_shm, wl_surface};
use smithay_client_toolkit::reexports::client::{Connection, QueueHandle};
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::registry::{ProvidesRegistryState, RegistryState};
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::{
    Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface,
    LayerSurfaceConfigure,
};
use smithay_client_toolkit::shm::slot::{Buffer, SlotPool};
use smithay_client_toolkit::shm::{Shm, ShmHandler};
use smithay_client_toolkit::{delegate_dispatch2, delegate_registry, registry_handlers};

use crate::bar::Bar;
use crate::render::Renderer;
use crate::scene::IRect;
use crate::theme;

/// Past this many pending rects a buffer just takes their union.
const STALE_LIMIT: usize = 8;

struct ShmBuffer {
    buffer: Buffer,
    stale: Vec<IRect>,
}

pub struct App {
    registry: RegistryState,
    outputs: OutputState,
    shm: Shm,
    layer: LayerSurface,
    pool: SlotPool,
    buffers: Vec<ShmBuffer>,
    configured: bool,
    pub bar: Bar,
    renderer: Renderer,
    pub exit: bool,
    started: Instant,
    commits: u64,
    frame_callbacks: u64,
}

impl App {
    pub fn new(globals: &GlobalList, qh: &QueueHandle<Self>) -> Self {
        let compositor = CompositorState::bind(globals, qh).expect("wl_compositor is not available");
        let layer_shell = LayerShell::bind(globals, qh).expect("zwlr_layer_shell_v1 is not available");
        let shm = Shm::bind(globals, qh).expect("wl_shm is not available");

        let surface = compositor.create_surface(qh);
        let layer = layer_shell.create_layer_surface(qh, surface, Layer::Top, Some("formalshell:bar"), None);
        layer.set_anchor(Anchor::TOP | Anchor::LEFT | Anchor::RIGHT);
        layer.set_size(0, theme::BAR_THICKNESS as u32);
        layer.set_exclusive_zone(theme::BAR_THICKNESS);
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        layer.commit();

        let pool = SlotPool::new(4096, &shm).expect("wl_shm pool");
        Self {
            registry: RegistryState::new(globals),
            outputs: OutputState::new(globals, qh),
            shm,
            layer,
            pool,
            buffers: Vec::new(),
            configured: false,
            bar: Bar::new(1),
            renderer: Renderer::new(1, theme::BAR_THICKNESS as u16),
            exit: false,
            started: Instant::now(),
            commits: 0,
            frame_callbacks: 0,
        }
    }

    pub fn present(&mut self) {
        if !self.configured || !self.bar.scene.has_damage() {
            return;
        }
        let damage = self.bar.scene.take_damage();
        for rect in &damage {
            self.renderer.render(&self.bar.scene, *rect);
        }

        let size = self.bar.scene.size;
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

        let surface = self.layer.wl_surface();
        for rect in &damage {
            surface.damage_buffer(rect.x, rect.y, rect.w, rect.h);
        }
        target.buffer.attach_to(surface).expect("attach released buffer");
        self.layer.commit();

        self.commits += 1;
        let area: i64 = damage.iter().map(IRect::area).sum();
        eprintln!(
            "commit n={} t={}ms wall={} rects={} px={} buffer={} frame_callbacks={}",
            self.commits,
            self.started.elapsed().as_millis(),
            chrono::Local::now().format("%H:%M:%S%.3f"),
            damage.len(),
            area,
            at,
            self.frame_callbacks,
        );
    }
}

impl App {
    pub fn report_exit(&self) {
        eprintln!(
            "exit t={}ms commits={} frame_callbacks={}",
            self.started.elapsed().as_millis(),
            self.commits,
            self.frame_callbacks
        );
    }
}

impl CompositorHandler for App {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: i32) {}

    fn transform_changed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: wl_output::Transform,
    ) {
    }

    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: u32) {
        self.frame_callbacks += 1;
    }

    fn surface_enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}

    fn surface_leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}
}

impl LayerShellHandler for App {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &LayerSurface) {
        self.exit = true;
    }

    fn configure(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &LayerSurface,
        configure: LayerSurfaceConfigure,
        _: u32,
    ) {
        let width = configure.new_size.0 as i32;
        if width > 0 && width != self.bar.scene.size.w {
            self.bar.resize(width);
            self.renderer.resize(width as u16, theme::BAR_THICKNESS as u16);
            self.buffers.clear();
        }
        self.configured = true;
    }
}

impl OutputHandler for App {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.outputs
    }

    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}

    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}

    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
}

impl ShmHandler for App {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

impl ProvidesRegistryState for App {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry
    }
    registry_handlers![OutputState];
}

delegate_registry!(App);
delegate_dispatch2!(App);
