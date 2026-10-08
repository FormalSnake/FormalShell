//! One layer surface and its wl_shm buffers. A commit carries only the
//! rects the scene dirtied, copied out of the renderer's canvas into
//! whichever buffer the compositor has released, plus whatever that buffer
//! missed while the other one was on screen. A frame callback is asked for
//! only on a commit made while something on the surface animates.
//! A flat full-output fill skips all of that: see [`PixelSurface`].

use std::time::Instant;

use smithay_client_toolkit::compositor::FrameCallbackData;
use smithay_client_toolkit::dispatch2::Dispatch2;
use smithay_client_toolkit::reexports::client::globals::{BindError, GlobalList};
use smithay_client_toolkit::reexports::client::protocol::wl_buffer::WlBuffer;
use smithay_client_toolkit::reexports::client::protocol::wl_callback::WlCallback;
use smithay_client_toolkit::reexports::client::protocol::wl_shm;
use smithay_client_toolkit::reexports::client::{Connection, Dispatch, Proxy, QueueHandle};
use smithay_client_toolkit::reexports::protocols::wp::alpha_modifier::v1::client::wp_alpha_modifier_surface_v1::WpAlphaModifierSurfaceV1;
use smithay_client_toolkit::reexports::protocols::wp::alpha_modifier::v1::client::wp_alpha_modifier_v1::WpAlphaModifierV1;
use smithay_client_toolkit::reexports::protocols::wp::single_pixel_buffer::v1::client::wp_single_pixel_buffer_manager_v1::WpSinglePixelBufferManagerV1;
use smithay_client_toolkit::reexports::protocols::wp::viewporter::client::wp_viewport::WpViewport;
use smithay_client_toolkit::reexports::protocols::wp::viewporter::client::wp_viewporter::WpViewporter;
use smithay_client_toolkit::reexports::client::protocol::wl_subcompositor::WlSubcompositor;
use smithay_client_toolkit::reexports::client::protocol::wl_subsurface::WlSubsurface;
use smithay_client_toolkit::reexports::client::protocol::wl_surface::WlSurface;
use smithay_client_toolkit::session_lock::SessionLockSurface;
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

/// What a [`Surface`] is to the compositor: a layer surface, or a lock
/// surface on one output.
pub trait Role {
    fn role_surface(&self) -> &WlSurface;
    fn role_commit(&self);
}

impl Role for LayerSurface {
    fn role_surface(&self) -> &WlSurface {
        WaylandSurface::wl_surface(self)
    }

    fn role_commit(&self) {
        WaylandSurface::commit(self);
    }
}

impl Role for SessionLockSurface {
    fn role_surface(&self) -> &WlSurface {
        SessionLockSurface::wl_surface(self)
    }

    fn role_commit(&self) {
        SessionLockSurface::wl_surface(self).commit();
    }
}

/// A synchronized subsurface: its commits wait for its parent's.
pub struct Sub {
    pub surface: WlSurface,
    pub sub: WlSubsurface,
}

impl Role for Sub {
    fn role_surface(&self) -> &WlSurface {
        &self.surface
    }

    fn role_commit(&self) {
        self.surface.commit();
    }
}

impl Drop for Sub {
    fn drop(&mut self) {
        self.sub.destroy();
        self.surface.destroy();
    }
}

pub struct Surface<R: Role = LayerSurface> {
    pub name: &'static str,
    pub layer: R,
    /// ABGR8888 where the compositor takes it: the canvas's own byte order,
    /// copied without a swizzle.
    format: wl_shm::Format,
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
    /// When the outstanding frame callback was asked for, and how long the
    /// last one took to land: a slow compositor reads here, a slow shell
    /// in `event loop:` lines.
    asked: Option<Instant>,
    waited_us: u128,
    landed_at: Option<Instant>,
    /// No buffer has been dropped out of the pool, so every byte of it a
    /// new buffer gets is still the zero (clear) memfd fill.
    pool_clean: bool,
    /// Everything the renderer has drawn since its canvas was cleared: all
    /// a buffer cut from a clean pool lacks.
    drawn: Option<IRect>,
    /// Set, a frame is drawn in bands across loop turns, each turn stopping
    /// once it has run this long, so a large first frame never holds
    /// another surface's due frame (the bar's) behind it.
    pub raster_budget: Option<std::time::Duration>,
    /// The frame being drawn: all its damage, and the bands still to draw.
    raster: Vec<IRect>,
    left: std::collections::VecDeque<IRect>,
    react_us: u128,
    render_us: u128,
    slices: u32,
}

/// Rows per band of a sliced frame.
const BAND: i32 = 96;

fn bands(rect: IRect) -> impl Iterator<Item = IRect> {
    (rect.y..rect.bottom()).step_by(BAND as usize).map(move |y| IRect::new(rect.x, y, rect.w, BAND.min(rect.bottom() - y)))
}

/// A closed window's pool, buffers and canvas, kept for the next window of
/// the same kind so its first frames write into pages already faulted in
/// rather than fresh memfd and heap pages, a fault per 4 KiB.
pub struct Kept {
    pool: SlotPool,
    buffers: Vec<ShmBuffer>,
    renderer: Renderer,
    pool_clean: bool,
    drawn: Option<IRect>,
}

/// linux/mman.h, Linux 5.14: fault the range in writable without touching
/// its contents, so it can run beside a writer.
const MADV_POPULATE_WRITE: libc::c_int = 23;

impl Kept {
    /// A clean pool two `size` buffers deep and a canvas of `size`, both
    /// faulted in on the blocking pool while nothing draws from them.
    pub fn prefaulted(shm: &Shm, size: (i32, i32), runner: &crate::runtime::Pool) -> Option<Self> {
        let bytes = size.0.max(1) as usize * size.1.max(1) as usize * 4 * 2;
        let mut pool = SlotPool::new(bytes, shm).ok()?;
        let slot = pool.new_slot(bytes).ok()?;
        let data = pool.raw_data_mut(&slot);
        let (at, len) = (data.as_mut_ptr() as usize, data.len());
        drop(slot);
        let mut renderer = Renderer::new(size.0.max(1) as u16, size.1.max(1) as u16);
        let canvas = renderer.canvas_bytes_mut();
        let (canvas_at, canvas_len) = (canvas.as_mut_ptr() as usize, canvas.len());
        runner.submit(move || {
            // SAFETY: madvise only faults the pages in; a range unmapped
            // meanwhile (a resized pool) answers ENOMEM and nothing else.
            unsafe {
                libc::madvise(at as *mut libc::c_void, len, MADV_POPULATE_WRITE);
                libc::madvise(canvas_at as *mut libc::c_void, canvas_len, MADV_POPULATE_WRITE);
            }
        });
        Some(Self { pool, buffers: Vec::new(), renderer, pool_clean: true, drawn: None })
    }
}

impl<R: Role> Surface<R> {
    pub fn commits(&self) -> u64 {
        self.commits
    }

    /// The pool, buffers and canvas, for [`Surface::adopt`] on the next
    /// window of this kind.
    pub fn keep(self) -> Kept {
        Kept { pool: self.pool, buffers: self.buffers, renderer: self.renderer, pool_clean: self.pool_clean, drawn: self.drawn }
    }

    /// Takes over a kept pool, buffers and canvas. What the last window
    /// drew is cleared off the canvas and stale in every buffer, so each
    /// takes the clear canvas there on its first use.
    pub fn adopt(&mut self, mut kept: Kept) {
        if let Some(old) = kept.drawn {
            kept.renderer.clear(old);
            for b in &mut kept.buffers {
                b.stale.push(old);
            }
        }
        self.pool = kept.pool;
        self.buffers = kept.buffers;
        self.renderer = kept.renderer;
        self.pool_clean = kept.pool_clean;
    }

    pub fn new(name: &'static str, layer: R, shm: &Shm, started: Instant) -> Self {
        Self {
            name,
            layer,
            format: if shm.formats().contains(&wl_shm::Format::Abgr8888) { wl_shm::Format::Abgr8888 } else { wl_shm::Format::Argb8888 },
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
            asked: None,
            waited_us: 0,
            landed_at: None,
            pool_clean: true,
            drawn: None,
            raster_budget: None,
            raster: Vec::new(),
            left: std::collections::VecDeque::new(),
            react_us: 0,
            render_us: 0,
            slices: 0,
        }
    }

    /// Sizes the canvas ahead of the compositor's first configure, so the
    /// first frame is drawn while it is on its way.
    pub fn presize(&mut self, width: i32, height: i32) {
        self.renderer.resize(width.max(1) as u16, height.max(1) as u16);
    }

    /// A whole frame is drawn and waits only to be committed.
    pub fn drawn_ahead(&self) -> bool {
        !self.raster.is_empty() && self.left.is_empty()
    }

    /// Draws the scene's damage into the canvas, as part of the frame in
    /// progress. False while a sliced frame still has bands left.
    fn draw(&mut self, scene: &mut Scene) -> bool {
        if self.raster.is_empty() {
            // From the callback that let this frame go to the start of drawing it.
            self.react_us = self.landed_at.take().map_or(0, |at| at.elapsed().as_micros());
            self.render_us = 0;
            self.slices = 0;
        }
        // Damage that came in while a sliced frame was being drawn joins it.
        for rect in scene.take_damage() {
            self.raster.push(rect);
            match self.raster_budget {
                Some(_) => self.left.extend(bands(rect)),
                None => self.left.push_back(rect),
            }
        }
        let t0 = Instant::now();
        while let Some(rect) = self.left.pop_front() {
            self.renderer.render(scene, rect);
            if self.raster_budget.is_some_and(|budget| t0.elapsed() >= budget) && !self.left.is_empty() {
                self.render_us += t0.elapsed().as_micros();
                self.slices += 1;
                return false;
            }
        }
        self.render_us += t0.elapsed().as_micros();
        self.slices += 1;
        true
    }

    /// Draws the scene's damage without committing it, so a frame can wait
    /// on another surface's: true once the whole frame is drawn, or when
    /// there is nothing to draw or nowhere to draw it yet.
    pub fn prepare(&mut self, scene: &mut Scene) -> bool {
        let sized = (self.renderer.width() as i32, self.renderer.height() as i32) == (scene.size.w, scene.size.h);
        if !self.configured || !sized || (!scene.has_damage() && self.raster.is_empty()) {
            return true;
        }
        self.draw(scene)
    }

    /// A sliced frame is part drawn: the owner holds its scene still and
    /// presents again on the next loop turn.
    pub fn rastering(&self) -> bool {
        !self.left.is_empty()
    }

    /// A frame callback landed.
    pub fn landed(&mut self, now: Instant) {
        self.frame_pending = false;
        self.callbacks += 1;
        if let Some(asked) = self.asked.take() {
            self.waited_us = now.duration_since(asked).as_micros();
        }
        self.landed_at = Some(now);
    }

    /// The compositor's size, which the owner has resized its scene to.
    pub fn configure(&mut self, width: i32, height: i32) {
        self.configured = true;
        if (self.renderer.width() as i32, self.renderer.height() as i32) != (width, height) {
            self.renderer.resize(width as u16, height as u16);
            self.pool_clean &= self.buffers.is_empty();
            self.buffers.clear();
            self.drawn = None;
            self.raster.clear();
            self.left.clear();
        }
    }

    pub fn present<D>(&mut self, scene: &mut Scene, animating: bool, qh: &QueueHandle<D>)
    where
        D: Dispatch<WlCallback, FrameCallbackData> + 'static,
    {
        if self.frame_pending {
            return;
        }
        // A scene resized ahead of the compositor's configure (the bar
        // moving edge) keeps its damage until the buffers match it.
        if (self.renderer.width() as i32, self.renderer.height() as i32) != (scene.size.w, scene.size.h) {
            return;
        }
        // A presized canvas draws the first frame while the configure is on
        // its way; the configure then only has it copied and committed.
        if !self.configured {
            if self.commits == 0 && scene.has_damage() {
                self.draw(scene);
            }
            return;
        }
        // An animation whose frame changed nothing (a card still wholly
        // behind its line) still needs the next callback to carry on.
        let request = animating || (self.wait_map && !self.mapped);
        // A scene that starts out clear still owes the compositor one
        // buffer before the surface can map.
        if self.commits == 0 && !scene.has_damage() && self.raster.is_empty() {
            scene.touch(IRect::new(0, 0, 1, 1));
        }
        if !scene.has_damage() && self.raster.is_empty() {
            if request && self.commits > 0 {
                let surface = self.layer.role_surface();
                surface.frame(qh, FrameCallbackData(surface.clone()));
                self.frame_pending = true;
                self.asked = Some(Instant::now());
                self.layer.role_commit();
            }
            return;
        }
        if !self.draw(scene) {
            return;
        }
        let damage = std::mem::take(&mut self.raster);
        let (react_us, render_us) = (self.react_us, self.render_us);
        self.drawn = damage.iter().fold(self.drawn, |u, r| Some(u.map_or(*r, |u| u.union(r))));

        let t1 = Instant::now();
        let size = scene.size;
        let at = match self.buffers.iter().position(|b| b.buffer.canvas(&mut self.pool).is_some()) {
            Some(at) => at,
            None => {
                let (buffer, _) = self
                    .pool
                    .create_buffer(size.w, size.h, size.w * 4, self.format)
                    .expect("wl_shm buffer");
                let stale = if self.pool_clean { self.drawn.into_iter().collect() } else { vec![size] };
                self.buffers.push(ShmBuffer { buffer, stale });
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
        // A rect inside another is copied with it.
        let copy: Vec<IRect> = copy
            .iter()
            .enumerate()
            .filter(|(i, r)| !copy.iter().enumerate().any(|(j, o)| j != *i && o.contains(r) && (o != *r || j < *i)))
            .map(|(_, r)| r.intersect(&size))
            .filter(|r| !r.is_empty())
            .collect();
        let canvas = target.buffer.canvas(&mut self.pool).expect("released buffer");
        let stride = self.renderer.width() as usize;
        if self.format == wl_shm::Format::Abgr8888 {
            // ABGR8888 is the canvas's own RGBA byte order: rows copy whole.
            let src = self.renderer.canvas().data_as_u8_slice();
            for rect in &copy {
                for row in rect.y..rect.bottom() {
                    let start = (row as usize * stride + rect.x as usize) * 4;
                    let end = start + rect.w as usize * 4;
                    canvas[start..end].copy_from_slice(&src[start..end]);
                }
            }
        } else {
            let src = self.renderer.canvas().data();
            for rect in &copy {
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
        }
        let copy_us = t1.elapsed().as_micros();

        let surface = self.layer.role_surface();
        for rect in &damage {
            surface.damage_buffer(rect.x, rect.y, rect.w, rect.h);
        }
        // Until the first callback the surface may not be on screen yet,
        // and an enter waits for it.
        if request {
            surface.frame(qh, FrameCallbackData(surface.clone()));
            self.frame_pending = true;
            self.asked = Some(Instant::now());
        }
        target.buffer.attach_to(surface).expect("attach released buffer");
        self.layer.role_commit();

        self.commits += 1;
        if !crate::tracing() {
            return;
        }
        let area: i64 = damage.iter().map(IRect::area).sum();
        let rects: Vec<String> = damage.iter().map(|r| format!("{},{},{}x{}", r.x, r.y, r.w, r.h)).collect();
        crate::trace(format!(
            "commit surface={} n={} t={}ms render_us={} copy_us={} rects={} px={} damage=[{}] buffer={} frame_callbacks={} request={} last_wait_us={} react_us={} slices={}",
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
            self.waited_us,
            react_us,
            self.slices,
        ));
    }

    pub fn report(&self) -> String {
        format!("{}: commits={} frame_callbacks={}", self.name, self.commits, self.callbacks)
    }
}

/// A layer surface showing one black pixel (`wp_single_pixel_buffer_v1`)
/// stretched over its whole size by `wp_viewporter` and faded by
/// `wp_alpha_modifier_v1`, so the compositor does all of the drawing and a
/// step of a fade is one multiplier and one commit.
///
/// The pixel carries the surface's own alpha and the multiplier only the
/// fade: Hyprland's `ignore_alpha` reads the buffer's alpha, never the
/// modifier's, so an opaque pixel faded to 0.5 is still blurred behind, on
/// every frame and over the whole output for a scrim.
pub struct PixelSurface {
    pub name: &'static str,
    pub layer: LayerSurface,
    viewport: WpViewport,
    fade: WpAlphaModifierSurfaceV1,
    buffer: WlBuffer,
    /// The pixel's own alpha, what the compositor's `ignore_alpha` reads.
    pub alpha: f64,
    size: Option<(i32, i32)>,
    /// A size the next commit has to carry.
    resized: bool,
    multiplier: Option<u32>,
    pub frame_pending: bool,
    pub mapped: bool,
    started: Instant,
    commits: u64,
    pub callbacks: u64,
}

impl PixelSurface {
    pub fn new(name: &'static str, layer: LayerSurface, alpha: f64, pixels: &Pixels, qh: &QueueHandle<App>, started: Instant) -> Self {
        let surface = layer.wl_surface();
        let viewport = pixels.viewporter.get_viewport(surface, qh, Ignore);
        let fade = pixels.alpha.get_surface(surface, qh, Ignore);
        let alpha = alpha.clamp(0.0, 1.0);
        // Premultiplied black is zero in every channel but the alpha.
        let a = (alpha * f64::from(u32::MAX)).round() as u32;
        let buffer = pixels.single_pixel.create_u32_rgba_buffer(0, 0, 0, a, qh, Ignore);
        Self {
            name,
            layer,
            viewport,
            fade,
            buffer,
            alpha,
            size: None,
            resized: false,
            multiplier: None,
            frame_pending: false,
            mapped: false,
            started,
            commits: 0,
            callbacks: 0,
        }
    }

    pub fn configure(&mut self, width: i32, height: i32) {
        if width > 0 && height > 0 && self.size != Some((width, height)) {
            self.size = Some((width, height));
            self.resized = true;
        }
    }

    /// `fade` multiplies the pixel's own alpha, 0 to 1.
    pub fn present(&mut self, fade: f64, animating: bool, qh: &QueueHandle<App>) {
        let Some((width, height)) = self.size else { return };
        if self.frame_pending {
            return;
        }
        let request = animating || !self.mapped;
        let multiplier = (fade.clamp(0.0, 1.0) * u32::MAX as f64).round() as u32;
        let surface = self.layer.wl_surface();
        if self.multiplier == Some(multiplier) && !self.resized {
            if request && self.commits > 0 {
                surface.frame(qh, FrameCallbackData(surface.clone()));
                self.frame_pending = true;
                self.layer.commit();
            }
            return;
        }
        let t0 = Instant::now();
        if self.resized || self.commits == 0 {
            self.viewport.set_destination(width, height);
            surface.attach(Some(&self.buffer), 0, 0);
            self.resized = false;
        }
        self.fade.set_multiplier(multiplier);
        surface.damage_buffer(0, 0, 1, 1);
        if request {
            surface.frame(qh, FrameCallbackData(surface.clone()));
            self.frame_pending = true;
        }
        self.layer.commit();
        self.multiplier = Some(multiplier);
        self.commits += 1;
        if !crate::tracing() {
            return;
        }
        crate::trace(format!(
            "commit surface={} n={} t={}ms render_us={} copy_us=0 rects=1 px=0 damage=[0,0,1x1] buffer=pixel alpha={:.3} frame_callbacks={} request={}",
            self.name,
            self.commits,
            self.started.elapsed().as_millis(),
            t0.elapsed().as_micros(),
            self.alpha * fade,
            self.callbacks,
            request as u8,
        ));
    }

    pub fn report(&self) -> String {
        format!("{}: commits={} frame_callbacks={}", self.name, self.commits, self.callbacks)
    }

    /// The multiplier last committed, 0 to 1.
    pub fn fade(&self) -> f64 {
        self.multiplier.map_or(0.0, |m| f64::from(m) / f64::from(u32::MAX))
    }
}

impl Drop for PixelSurface {
    fn drop(&mut self) {
        self.fade.destroy();
        self.viewport.destroy();
        self.buffer.destroy();
    }
}

/// The three globals a [`PixelSurface`] is made of.
pub struct Pixels {
    pub subcompositor: WlSubcompositor,
    pub viewporter: WpViewporter,
    pub single_pixel: WpSinglePixelBufferManagerV1,
    pub alpha: WpAlphaModifierV1,
}

impl Pixels {
    pub fn bind(globals: &GlobalList, qh: &QueueHandle<App>) -> Result<Self, BindError> {
        Ok(Self {
            subcompositor: globals.bind(qh, 1..=1, Ignore)?,
            viewporter: globals.bind(qh, 1..=1, Ignore)?,
            single_pixel: globals.bind(qh, 1..=1, Ignore)?,
            alpha: globals.bind(qh, 1..=1, Ignore)?,
        })
    }
}

/// User data for objects whose events carry nothing this shell acts on: a
/// buffer that is never redrawn has no use for its release.
pub struct Ignore;

macro_rules! ignore_events {
    ($($iface:ty),*) => {$(
        impl Dispatch2<$iface, App> for Ignore {
            fn event(&self, _: &mut App, _: &$iface, _: <$iface as Proxy>::Event, _: &Connection, _: &QueueHandle<App>) {}
        }
    )*};
}

ignore_events!(WlSubcompositor, WlSubsurface, WpViewporter, WpViewport, WpSinglePixelBufferManagerV1, WpAlphaModifierV1, WpAlphaModifierSurfaceV1, WlBuffer);

/// The desktop's own layer: the theme's background colour,
/// or the wallpaper's ready pixels over the whole output. A new wallpaper
/// crossfades in over `reveal`; nothing draws at rest, and frame callbacks
/// are asked for only while a fade runs.
pub struct Backdrop {
    pub layer: LayerSurface,
    pool: SlotPool,
    buffer: Option<Buffer>,
    size: Option<(i32, i32)>,
    drawn: Option<(String, Option<usize>, i32, i32, [u8; 4])>,
    /// What is on screen once any fade lands.
    shown: Option<std::sync::Arc<crate::services::wallpaper::Picture>>,
    fade: Option<Fade>,
}

struct Fade {
    from: Option<std::sync::Arc<crate::services::wallpaper::Picture>>,
    to: Option<std::sync::Arc<crate::services::wallpaper::Picture>>,
    color: [u8; 4],
    start: Instant,
    ms: f64,
}

impl Backdrop {
    pub fn new(layer: LayerSurface, shm: &Shm) -> Self {
        Self { layer, pool: SlotPool::new(4096, shm).expect("wl_shm pool"), buffer: None, size: None, drawn: None, shown: None, fade: None }
    }

    pub fn configure(&mut self, width: i32, height: i32) {
        if width > 0 && height > 0 {
            self.size = Some((width, height));
        }
    }

    pub fn size(&self) -> Option<(i32, i32)> {
        self.size
    }

    /// `picture` when it was made for this size, else the plain colour; a
    /// change after the first paint fades over `reveal_ms`.
    pub fn draw(
        &mut self,
        picture: Option<std::sync::Arc<crate::services::wallpaper::Picture>>,
        background: fs_theme::color::Rgba,
        reveal_ms: f64,
        qh: &QueueHandle<App>,
    ) {
        let Some((w, h)) = self.size else { return };
        let picture = picture.filter(|p| (p.width as i32, p.height as i32) == (w, h));
        let [r, g, b, _] = background.to_u8();
        let color = [b, g, r, 255];
        let key = (picture.as_ref().map(|p| p.path.clone()).unwrap_or_default(), picture.as_ref().and_then(|p| p.dither), w, h, color);
        if self.drawn.as_ref() == Some(&key) {
            return;
        }
        let first = self.drawn.is_none();
        self.drawn = Some(key);
        let from = match self.fade.take() {
            Some(f) => f.to,
            None => self.shown.clone(),
        };
        self.shown = picture.clone();
        if first || reveal_ms <= 0.0 || picture.is_none() {
            self.paint(None, picture.as_deref(), color, 1.0);
            return;
        }
        self.fade = Some(Fade { from, to: picture, color, start: Instant::now(), ms: reveal_ms });
        self.step(Instant::now(), qh);
    }

    /// One frame of a running fade; the frame callback lands back here.
    pub fn step(&mut self, now: Instant, qh: &QueueHandle<App>) {
        let Some(f) = &self.fade else { return };
        let t = (now.duration_since(f.start).as_secs_f64() * 1000.0 / f.ms).clamp(0.0, 1.0);
        // effectsSlow's ease-out, close enough at a crossfade's length.
        let a = 1.0 - (1.0 - t).powi(3);
        let (from, to, color) = (f.from.clone(), f.to.clone(), f.color);
        if t >= 1.0 {
            self.fade = None;
            self.paint(None, to.as_deref(), color, 1.0);
            return;
        }
        let surface = self.layer.wl_surface().clone();
        surface.frame(qh, FrameCallbackData(surface.clone()));
        self.paint(Some(from.as_deref()), to.as_deref(), color, a as f32);
    }

    /// `to` over `from` at `a`; `from` none is no blend at all, `Some(None)`
    /// the plain colour.
    fn paint(
        &mut self,
        from: Option<Option<&crate::services::wallpaper::Picture>>,
        to: Option<&crate::services::wallpaper::Picture>,
        color: [u8; 4],
        a: f32,
    ) {
        let Some((w, h)) = self.size else { return };
        let Ok((buffer, canvas)) = self.pool.create_buffer(w, h, w * 4, wl_shm::Format::Argb8888) else { return };
        match (from, to) {
            (None, Some(p)) => canvas.copy_from_slice(&p.bgra),
            (None, None) => {
                for px in canvas.chunks_exact_mut(4) {
                    px.copy_from_slice(&color);
                }
            }
            (Some(src), dst) => {
                let k = (a.clamp(0.0, 1.0) * 256.0) as u32;
                let pick = |p: Option<&crate::services::wallpaper::Picture>, i: usize| p.map_or(color[i % 4], |p| p.bgra[i]);
                for (i, c) in canvas.iter_mut().enumerate() {
                    let s0 = u32::from(pick(src, i));
                    let d0 = u32::from(pick(dst, i));
                    *c = ((s0 * (256 - k) + d0 * k) >> 8) as u8;
                }
            }
        }
        let surface = self.layer.wl_surface();
        if buffer.attach_to(surface).is_err() {
            return;
        }
        surface.damage_buffer(0, 0, w, h);
        self.layer.commit();
        self.buffer = Some(buffer);
        if from.is_none() {
            eprintln!("commit surface=wallpaper {}x{} picture={}", w, h, to.is_some());
        }
    }
}
