//! The Wayland side: the bar's layer surface, a panel's and a scrim's when
//! they are up, and which owner a configure or a frame callback belongs to.

use std::time::Instant;

use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState, Region};
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::reexports::client::globals::GlobalList;
use smithay_client_toolkit::reexports::client::protocol::{wl_output, wl_surface};
use smithay_client_toolkit::reexports::client::{Connection, QueueHandle};
use smithay_client_toolkit::registry::{ProvidesRegistryState, RegistryState};
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::{
    Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface,
    LayerSurfaceConfigure,
};
use smithay_client_toolkit::shm::{Shm, ShmHandler};
use smithay_client_toolkit::{delegate_dispatch2, delegate_registry, registry_handlers};

use fs_chrome::types::Edge;

use crate::surfaces::bar::Bar;
use crate::surfaces::panel::{Panel, Scrim};
use crate::ipc;
use crate::runtime::Msg;
use crate::store::Store;
use crate::surface::{PixelSurface, Pixels, Surface};
use crate::surfaces;
use crate::theme;

/// Anchors the bar's layer on `edge`, across the whole of it, reserving
/// its own thickness.
fn place_bar(layer: &LayerSurface, edge: Edge) {
    let t = surfaces::bar::thickness(edge);
    let (anchor, w, h) = match edge {
        Edge::Top => (Anchor::TOP | Anchor::LEFT | Anchor::RIGHT, 0, t),
        Edge::Bottom => (Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT, 0, t),
        Edge::Left => (Anchor::LEFT | Anchor::TOP | Anchor::BOTTOM, t, 0),
        Edge::Right => (Anchor::RIGHT | Anchor::TOP | Anchor::BOTTOM, t, 0),
    };
    layer.set_anchor(anchor);
    layer.set_size(w as u32, h as u32);
    layer.set_exclusive_zone(t);
    layer.commit();
}

/// The panel's one line of content, standing in for a real panel body.
const PANEL_LABEL: &str = "Calendar";
const PANEL_HEIGHT: f64 = 200.0;

pub struct App {
    registry: RegistryState,
    outputs: OutputState,
    compositor: CompositorState,
    layer_shell: LayerShell,
    shm: Shm,
    pixels: Pixels,
    qh: QueueHandle<Self>,
    pub store: Store,
    pub bar: Bar,
    bar_surface: Surface,
    panel: Option<(Panel, Surface)>,
    scrim: Option<(Scrim, PixelSurface)>,
    /// `debug motionScale`: every duration multiplied by this.
    pub motion_scale: f64,
    /// pantheon's cast under the panel card.
    pub cast: bool,
    /// `debug join`'s x and width on the top line, held under any panel's.
    debug_join: Option<(i32, i32)>,
    pub exit: bool,
    started: Instant,
}

enum Owner {
    Bar,
    Panel,
    Scrim,
}

impl App {
    /// `started` is the clock every logged `t=` counts from.
    pub fn new(globals: &GlobalList, qh: &QueueHandle<Self>, started: Instant) -> Self {
        let compositor = CompositorState::bind(globals, qh).expect("wl_compositor is not available");
        let layer_shell = LayerShell::bind(globals, qh).expect("zwlr_layer_shell_v1 is not available");
        let shm = Shm::bind(globals, qh).expect("wl_shm is not available");
        let pixels = Pixels::bind(globals, qh)
            .expect("wp_viewporter, wp_single_pixel_buffer_manager_v1 and wp_alpha_modifier_v1 are required");

        let surface = compositor.create_surface(qh);
        let layer = layer_shell.create_layer_surface(qh, surface, Layer::Top, Some("formalshell:bar"), None);
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        place_bar(&layer, Edge::Top);
        let bar_surface = Surface::new("bar", layer, &shm, started);

        Self {
            registry: RegistryState::new(globals),
            outputs: OutputState::new(globals, qh),
            compositor,
            layer_shell,
            shm,
            pixels,
            qh: qh.clone(),
            store: Store::default(),
            bar: Bar::new(Edge::Top),
            bar_surface,
            panel: None,
            scrim: None,
            motion_scale: 1.0,
            cast: false,
            debug_join: None,
            exit: false,
            started,
        }
    }

    /// A layer surface over the whole output that takes no input and
    /// reserves nothing.
    fn overlay(&self, namespace: &'static str, anchor: Anchor, height: u32) -> LayerSurface {
        let surface = self.compositor.create_surface(&self.qh);
        let layer = self.layer_shell.create_layer_surface(&self.qh, surface, Layer::Top, Some(namespace), None);
        layer.set_anchor(anchor);
        layer.set_size(0, height);
        layer.set_exclusive_zone(-1);
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        if let Ok(region) = Region::new(&self.compositor) {
            layer.set_input_region(Some(region.wl_region()));
        }
        layer.commit();
        layer
    }

    fn log(&self, what: &str) {
        eprintln!("ipc t={}ms {what}", self.started.elapsed().as_millis());
    }

    /// `bar.position`: the strip re-anchored on its new edge, laid out
    /// again once the compositor configures the new size.
    pub fn set_bar_edge(&mut self, edge: Edge) {
        if edge == self.bar.edge() {
            return;
        }
        self.bar.set_edge(edge);
        place_bar(&self.bar_surface.layer, edge);
        self.sync_join();
    }

    /// The output the bar's workspace slots belong to: the first one the
    /// registry announced, the one a layer surface with no output lands on.
    pub fn bar_output_name(&self) -> String {
        self.outputs.outputs().next().and_then(|o| self.outputs.info(&o)).and_then(|i| i.name).unwrap_or_default()
    }

    pub fn panel_open(&self) -> bool {
        self.panel.as_ref().is_some_and(|(p, _)| p.is_open())
    }

    pub fn debug_join(&self) -> Option<(i32, i32)> {
        self.debug_join
    }

    pub fn set_debug_join(&mut self, join: Option<(i32, i32)>) {
        self.debug_join = join;
        self.sync_join();
    }

    /// A panel's own join wins over `debug join`'s while the panel is up.
    fn sync_join(&mut self) {
        let panel = self.panel.as_ref().and_then(|(p, _)| p.join);
        let debug = self.debug_join.map(|(x, width)| (x as f64, width as f64, theme::radius_xl() as f64));
        self.bar.set_join(panel.or(debug));
    }

    pub fn set_panel(&mut self, now: Instant, open: bool) {
        if let Some((panel, _)) = &mut self.panel {
            panel.set_open(now, open);
            self.sync_join();
            return;
        }
        if !open {
            return;
        }
        let width = self.bar.scene.size.w;
        let panel =
            Panel::new(width, self.bar.clock_cell(), PANEL_HEIGHT, self.motion_scale, self.cast, self.bar.text_mut(), PANEL_LABEL);
        let layer = self.overlay("formalshell:panel", Anchor::TOP | Anchor::LEFT | Anchor::RIGHT, panel.surface_height() as u32);
        let mut surface = Surface::new("panel", layer, &self.shm, self.started);
        surface.wait_map = true;
        self.panel = Some((panel, surface));
    }

    pub fn set_scrim(&mut self, now: Instant, open: bool) {
        if let Some((scrim, _)) = &mut self.scrim {
            scrim.set_open(now, open);
            return;
        }
        if !open {
            return;
        }
        let scrim = Scrim::new(self.motion_scale);
        let layer = self.overlay("formalshell:scrim", Anchor::all(), 0);
        let surface = PixelSurface::new("scrim", layer, &self.pixels, &self.qh, self.started);
        self.scrim = Some((scrim, surface));
    }

    pub fn receive(&mut self, msg: Msg) {
        match msg {
            Msg::Diff(diff) => {
                if let Some(topic) = self.store.apply(diff) {
                    surfaces::changed(self, topic);
                }
            }
            Msg::Call(request, reply) => {
                self.log(&format!("{request:?}"));
                let _ = reply.try_send(ipc::dispatch(self, &request));
            }
        }
    }

    pub fn present(&mut self) {
        let now = Instant::now();
        if self.panel.as_ref().is_some_and(|(p, s)| s.mapped && p.finished(now)) {
            self.panel = None;
            self.sync_join();
            self.log("panel unmapped");
        }
        if self.scrim.as_ref().is_some_and(|(p, s)| s.mapped && p.finished(now)) {
            self.scrim = None;
            self.log("scrim unmapped");
        }
        let qh = self.qh.clone();
        let animating = self.bar.animating();
        self.bar_surface.present(&mut self.bar.scene, animating, &qh);
        if let Some((panel, surface)) = &mut self.panel {
            let animating = panel.animating(now);
            surface.present(&mut panel.scene, animating, &qh);
        }
        if let Some((scrim, surface)) = &mut self.scrim {
            surface.present(scrim.alpha(now), scrim.animating(now), &qh);
        }
    }

    fn owner(&self, surface: &wl_surface::WlSurface) -> Option<Owner> {
        if self.bar_surface.layer.wl_surface() == surface {
            return Some(Owner::Bar);
        }
        if self.panel.as_ref().is_some_and(|(_, s)| s.layer.wl_surface() == surface) {
            return Some(Owner::Panel);
        }
        if self.scrim.as_ref().is_some_and(|(_, s)| s.layer.wl_surface() == surface) {
            return Some(Owner::Scrim);
        }
        None
    }

    pub fn report_exit(&self) {
        let mut parts = vec![self.bar_surface.report()];
        parts.extend(self.panel.as_ref().map(|(_, s)| s.report()));
        parts.extend(self.scrim.as_ref().map(|(_, s)| s.report()));
        eprintln!("exit t={}ms {}", self.started.elapsed().as_millis(), parts.join(" "));
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

    /// Every callback ticks its owner once more, so the frame that lands an
    /// animation on its rest is drawn, and that commit asks for no other.
    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &wl_surface::WlSurface, _: u32) {
        let now = Instant::now();
        match self.owner(surface) {
            Some(Owner::Bar) => {
                let s = &mut self.bar_surface;
                (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
                self.bar.tick(now);
            }
            Some(Owner::Panel) => {
                let Some((panel, s)) = &mut self.panel else { return };
                (s.frame_pending, s.callbacks) = (false, s.callbacks + 1);
                if s.mapped {
                    panel.tick(now);
                } else {
                    s.mapped = true;
                    panel.mapped(now);
                }
                self.sync_join();
            }
            Some(Owner::Scrim) => {
                let Some((scrim, s)) = &mut self.scrim else { return };
                (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
                scrim.mapped(now);
            }
            None => {}
        }
    }

    fn surface_enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}

    fn surface_leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}
}

impl LayerShellHandler for App {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        match self.owner(layer.wl_surface()) {
            Some(Owner::Bar) => self.exit = true,
            Some(Owner::Panel) => {
                self.panel = None;
                self.sync_join();
            }
            Some(Owner::Scrim) => self.scrim = None,
            None => {}
        }
    }

    fn configure(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        layer: &LayerSurface,
        configure: LayerSurfaceConfigure,
        _: u32,
    ) {
        let (width, height) = (configure.new_size.0 as i32, configure.new_size.1 as i32);
        match self.owner(layer.wl_surface()) {
            Some(Owner::Bar) => {
                let current = self.bar.scene.size;
                let w = if width > 0 { width } else { current.w };
                let h = if height > 0 { height } else { current.h };
                if (w, h) != (current.w, current.h) {
                    self.bar.resize(w, h);
                }
                let size = self.bar.scene.size;
                self.bar_surface.configure(size.w, size.h);
            }
            Some(Owner::Panel) => {
                let Some((panel, s)) = &mut self.panel else { return };
                let size = panel.scene.size;
                s.configure(size.w, size.h);
            }
            Some(Owner::Scrim) => {
                let Some((_, s)) = &mut self.scrim else { return };
                s.configure(width, height);
            }
            None => {}
        }
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
