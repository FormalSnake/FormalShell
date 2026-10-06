//! The Wayland side: the bar's layer surface (gone while a fullscreen window
//! covers its output), the frame's four exclusion zones, the cards hanging
//! off the bar (the chevron's second bar, a panel), the scrim, the pointer,
//! and which owner a configure, a frame callback or a pointer event belongs
//! to.

use std::time::Instant;

use calloop::LoopHandle;
use calloop::timer::{TimeoutAction, Timer};
use fs_chrome::bar::layout;
use fs_chrome::types::{Edge, Region as BarRegion};
use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState, Region};
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::reexports::client::globals::GlobalList;
use smithay_client_toolkit::reexports::client::protocol::{wl_output, wl_pointer, wl_seat, wl_surface};
use smithay_client_toolkit::reexports::client::{Connection, QueueHandle};
use smithay_client_toolkit::registry::{ProvidesRegistryState, RegistryState};
use smithay_client_toolkit::reexports::protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape, WpCursorShapeDeviceV1};
use smithay_client_toolkit::seat::pointer::cursor_shape::CursorShapeManager;
use smithay_client_toolkit::seat::pointer::{PointerEvent, PointerEventKind, PointerHandler};
use smithay_client_toolkit::seat::{Capability, SeatHandler, SeatState};
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::{
    Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface, LayerSurfaceConfigure,
};
use smithay_client_toolkit::shm::{Shm, ShmHandler};
use smithay_client_toolkit::{delegate_dispatch2, delegate_registry, registry_handlers};

use crate::ipc;
use crate::runtime::{Msg, Runtime};
use crate::scene::{IRect, NodeId};
use crate::services::{barpaint, commands, devices, hyprland, theme, wallpaper};
use crate::store::{Store, Topic};
use crate::surface::{Backdrop, PixelSurface, Pixels, Surface};
use crate::surfaces;
use crate::surfaces::bar::Bar;
use crate::surfaces::bar::cell::{Action, Button, Env, Painter};
use crate::surfaces::bar::slot::Slot;
use crate::surfaces::card::{Card, Scrim};
use crate::text::ShapedText;

/// The panels `panel` can open (PanelIpc.qml's registry), and the title the
/// card carries until each one's body lands with its own milestone.
pub const PANELS: [(&str, &str); 19] = [
    ("appmenu", "App menu"),
    ("audio", "Audio"),
    ("calendar", "Calendar"),
    ("network", "Network"),
    ("bluetooth", "Bluetooth"),
    ("earbuds", "Earbuds"),
    ("iphone", "iPhone"),
    ("dualsense", "DualSense"),
    ("power", "Power"),
    ("weather", "Weather"),
    ("media", "Media"),
    ("github", "GitHub"),
    ("usage", "Usage"),
    ("tailscale", "Tailscale"),
    ("systemupdate", "System update"),
    ("display", "Display"),
    ("monitor", "Monitor"),
    ("trayoverflow", "Tray"),
    ("radio", "Radio"),
];

/// The stand-in panel's depth until panels carry their own bodies.
const PANEL_HEIGHT: f64 = 200.0;

fn edge_anchor(edge: Edge) -> Anchor {
    match edge {
        Edge::Top => Anchor::TOP | Anchor::LEFT | Anchor::RIGHT,
        Edge::Bottom => Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT,
        Edge::Left => Anchor::LEFT | Anchor::TOP | Anchor::BOTTOM,
        Edge::Right => Anchor::RIGHT | Anchor::TOP | Anchor::BOTTOM,
    }
}

/// A card off the bar and what it holds: the chevron's governed cells, or
/// a panel's title.
pub struct Popout {
    pub name: String,
    pub region: Option<BarRegion>,
    pub card: Card,
    surface: Surface,
    pub slots: Vec<Slot>,
    title: Option<ShapedText>,
    title_nodes: Vec<NodeId>,
    pub hover: Option<usize>,
}

impl Popout {
    fn finished(&self, now: Instant) -> bool {
        self.surface.mapped && self.card.finished(now)
    }

    /// Lays its content out at the card's content rect this frame.
    fn layout(&mut self, bar: &mut Bar, now: Instant) {
        let (rect, alpha) = self.card.content;
        let clip = self.card.content_clip();
        let look = bar.kit.look.clone();
        let padding = look.panel_padding;
        let vertical = self.card.edge.is_vertical();
        let mut at = if vertical { rect.y as f64 + padding } else { rect.x as f64 + padding };
        for (i, slot) in self.slots.iter_mut().enumerate() {
            let e = slot.extent(now);
            if e <= 0.0 {
                slot.rect = IRect::default();
            } else if vertical {
                slot.rect = IRect::new(rect.x + padding as i32, at.round() as i32, look.cell_width as i32, e.round() as i32);
                at += e + look.sm;
            } else {
                slot.rect = IRect::new(at.round() as i32, rect.y + padding as i32, e.round() as i32, look.cell_height as i32);
                at += e + look.sm;
            }
            slot.clip = clip;
            let hovered = self.hover == Some(i);
            slot.paint(&mut bar.kit, &mut self.card.scene, self.card.edge, hovered, None, alpha, true, now);
        }
        if let Some(title) = &self.title {
            let mut p = Painter::new(&mut self.card.scene, &mut self.title_nodes, Some(clip));
            let x = rect.x + padding as i32;
            let y = rect.y + padding as i32;
            p.text(title, (x, y), look.foreground.with_alpha(look.foreground.a * alpha), &[]);
            p.finish();
        }
    }

    fn hit(&self, x: f64, y: f64) -> Option<usize> {
        let (x, y) = (x.floor() as i32, y.floor() as i32);
        self.slots.iter().position(|s| {
            let r = s.rect.intersect(&s.clip);
            !r.is_empty() && x >= r.x && x < r.right() && y >= r.y && y < r.bottom()
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Owner {
    Bar,
    Overflow,
    Panel,
    Scrim,
    Zone(usize),
    Backdrop,
}

pub struct App {
    registry: RegistryState,
    outputs: OutputState,
    seats: SeatState,
    compositor: CompositorState,
    layer_shell: LayerShell,
    shm: Shm,
    pixels: Pixels,
    qh: QueueHandle<Self>,
    handle: Option<LoopHandle<'static, App>>,
    pub runtime: Option<Runtime>,
    pub store: Store,
    pub bar: Bar,
    bar_surface: Option<Surface>,
    backdrop: Option<Backdrop>,
    zones: Vec<(Edge, PixelSurface)>,
    pub overflow: Option<Popout>,
    pub panel: Option<Popout>,
    scrim: Option<(Scrim, PixelSurface)>,
    pointer: Option<wl_pointer::WlPointer>,
    /// The pointing hand over a cell that answers a click (Cell.qml's
    /// `cursorShape`), where the compositor offers cursor shapes.
    cursor_shapes: Option<CursorShapeManager>,
    cursor_device: Option<WpCursorShapeDeviceV1>,
    cursor: Option<(u32, Shape)>,
    pointer_on: Option<Owner>,
    pressed: Option<(Owner, usize)>,
    bar_dirty: bool,
    wake: Option<Instant>,
    /// `debug motionScale`: every duration multiplied by this.
    pub motion_scale: f64,
    /// pantheon's cast under a joined card.
    pub cast: bool,
    /// `debug join`'s x and width on the bar's line, held under any card's.
    debug_join: Option<(i32, i32)>,
    pub exit: bool,
    started: Instant,
}

impl App {
    /// `started` is the clock every logged `t=` counts from.
    pub fn new(globals: &GlobalList, qh: &QueueHandle<Self>, started: Instant) -> Self {
        let compositor = CompositorState::bind(globals, qh).expect("wl_compositor is not available");
        let layer_shell = LayerShell::bind(globals, qh).expect("zwlr_layer_shell_v1 is not available");
        let shm = Shm::bind(globals, qh).expect("wl_shm is not available");
        let pixels = Pixels::bind(globals, qh)
            .expect("wp_viewporter, wp_single_pixel_buffer_manager_v1 and wp_alpha_modifier_v1 are required");
        let store = Store::default();
        let bar = Bar::new(Edge::Top, &store.theme.theme);
        let mut app = Self {
            registry: RegistryState::new(globals),
            outputs: OutputState::new(globals, qh),
            seats: SeatState::new(globals, qh),
            compositor,
            layer_shell,
            shm,
            pixels,
            qh: qh.clone(),
            handle: None,
            runtime: None,
            store,
            bar,
            bar_surface: None,
            backdrop: None,
            zones: Vec::new(),
            overflow: None,
            panel: None,
            scrim: None,
            pointer: None,
            cursor_shapes: CursorShapeManager::bind(globals, qh).ok(),
            cursor_device: None,
            cursor: None,
            pointer_on: None,
            pressed: None,
            bar_dirty: true,
            wake: None,
            motion_scale: 1.0,
            cast: false,
            debug_join: None,
            exit: false,
            started,
        };
        app.place_chrome();
        let layer = app.overlay("formalshell:wallpaper", Layer::Background, Anchor::all(), (0, 0), -1);
        app.backdrop = Some(Backdrop::new(layer, &app.shm));
        app
    }

    /// The wallpaper for the output's size, asked for again whenever either
    /// moves, and drawn once it is ready.
    fn update_backdrop(&mut self) {
        let Some(b) = &mut self.backdrop else { return };
        let Some((w, h)) = b.size() else { return };
        wallpaper::show(&self.store.state.data.wallpaper, w as u32, h as u32);
        let background = self.store.theme.theme.colors.get("background");
        let picture = self.store.wallpaper.picture.clone();
        let wanted = &self.store.state.data.wallpaper;
        b.draw(picture.as_deref().filter(|p| p.path == *wanted), background);
    }

    pub fn set_handle(&mut self, handle: LoopHandle<'static, App>) {
        self.handle = Some(handle);
    }

    /// A layer surface that takes no input and reserves nothing.
    fn overlay(&self, namespace: &'static str, layer: Layer, anchor: Anchor, size: (u32, u32), zone: i32) -> LayerSurface {
        let surface = self.compositor.create_surface(&self.qh);
        let ls = self.layer_shell.create_layer_surface(&self.qh, surface, layer, Some(namespace), None);
        ls.set_anchor(anchor);
        ls.set_size(size.0, size.1);
        ls.set_exclusive_zone(zone);
        ls.set_keyboard_interactivity(KeyboardInteractivity::None);
        if let Ok(region) = Region::new(&self.compositor) {
            ls.set_input_region(Some(region.wl_region()));
        }
        ls.commit();
        ls
    }

    fn log(&self, what: &str) {
        eprintln!("ipc t={}ms {what}", self.started.elapsed().as_millis());
    }

    /// While a focused fullscreen window covers the bar's output the bar,
    /// its frame zones and its cards leave the layers (`fullscreen.hideChrome`).
    fn chrome_hidden(&self) -> bool {
        let hide = self.store.config.bool("fullscreen.hideChrome").unwrap_or(true);
        hide && self.store.hyprland.compositor.fullscreen_outputs.contains(&self.bar.output)
    }

    /// The bar's window and the frame's zones as the config and the
    /// fullscreen state want them: re-created rather than re-anchored, so a
    /// framed window and a strip never share a configure.
    fn place_chrome(&mut self) {
        let hidden = self.chrome_hidden();
        self.bar.hidden = hidden;
        if hidden {
            if self.bar_surface.take().is_some() {
                self.log("bar unmapped under fullscreen");
            }
            self.zones.clear();
            self.overflow = None;
            self.panel = None;
            self.sync_join();
            return;
        }
        let framed = self.bar.framed();
        let edge = self.bar.edge();
        let t = self.bar.thickness();
        let surface = self.compositor.create_surface(&self.qh);
        let layer = self.layer_shell.create_layer_surface(&self.qh, surface, Layer::Top, Some("formalshell:bar"), None);
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        if framed {
            layer.set_anchor(Anchor::all());
            layer.set_size(0, 0);
            // The frame's zones reserve each edge; a window anchored to all
            // four has no one edge to reserve against.
            layer.set_exclusive_zone(-1);
        } else {
            let (w, h) = if edge.is_vertical() { (t, 0) } else { (0, t) };
            layer.set_anchor(edge_anchor(edge));
            layer.set_size(w as u32, h as u32);
            layer.set_exclusive_zone(t);
        }
        layer.commit();
        self.bar_surface = Some(Surface::new("bar", layer, &self.shm, self.started));
        self.bar_dirty = true;

        self.zones.clear();
        if framed {
            let ft = self.bar.frame_thickness() as i32;
            for e in [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right] {
                let zone = if e == edge { t } else { ft };
                let size = if e.is_vertical() { (1, 0) } else { (0, 1) };
                let ls = self.overlay("formalshell:frame-zone", Layer::Overlay, edge_anchor(e), size, zone);
                let ps = PixelSurface::new("frame-zone", ls, &self.pixels, &self.qh, self.started);
                self.zones.push((e, ps));
            }
        }
    }

    fn set_input_region(&self) {
        let (Some(s), true) = (&self.bar_surface, self.bar.framed()) else { return };
        if let Ok(region) = Region::new(&self.compositor) {
            let r = self.bar.strip();
            region.add(r.x, r.y, r.w, r.h);
            s.layer.set_input_region(Some(region.wl_region()));
            s.layer.commit();
        }
    }

    /// The settings the bar is built from: its edge, its layout, its
    /// modules. Anything structural re-creates the window.
    pub fn apply_config(&mut self) {
        let bar_cfg = self.store.config.get("bar").cloned();
        let resolved = layout::resolve(bar_cfg.as_ref(), &[]);
        let modules: Vec<commands::Module> = BarRegion::ALL
            .iter()
            .flat_map(|r| resolved.regions.get(*r).to_vec())
            .filter_map(|e| match &e.kind {
                layout::EntryKind::Module { id, module } if module.get("type").and_then(|t| t.as_str()) == Some("command") => {
                    Some(commands::Module::from_json(id, module))
                }
                _ => None,
            })
            .collect();
        commands::configure(modules);
        let edge = layout::position(self.store.config.str("bar.position"));
        let moved = self.bar.set_edge(edge);
        let relaid = self.bar.set_layout(resolved);
        if moved || relaid {
            self.overflow = None;
            self.panel = None;
        }
        if moved {
            self.place_chrome();
        }
        self.refresh_bar(None);
    }

    /// The bar repainted off the store's theme, re-placed when its framing
    /// or thickness moved with it.
    pub fn set_bar_theme(&mut self) {
        let before = (self.bar.thickness(), self.bar.framed(), self.bar.frame_thickness());
        self.bar.set_theme(&self.store.theme.theme);
        if (self.bar.thickness(), self.bar.framed(), self.bar.frame_thickness()) != before {
            self.place_chrome();
        }
        self.refresh_bar(None);
    }

    /// The cells reading `topic` read again, and everything the strip draws
    /// with them.
    pub fn refresh_bar(&mut self, topic: Option<Topic>) {
        let now = Instant::now();
        if matches!(topic, None | Some(Topic::Hyprland) | Some(Topic::Config)) && self.chrome_hidden() != self.bar.hidden {
            self.place_chrome();
        }
        self.bar.update_paint(&self.store);
        self.request_paint();
        self.bar.read(&self.store, topic, now);
        let env_edge = self.bar.edge();
        for p in [&mut self.overflow, &mut self.panel].into_iter().flatten() {
            let env = Env { store: &self.store, edge: env_edge, output: &self.bar.output };
            for s in &mut p.slots {
                if topic.is_none_or(|t| s.cell.reads().contains(&t)) {
                    s.refresh(&mut self.bar.kit, &env, false, false, 0.0, now);
                }
            }
        }
        self.sync_open(now);
        self.update_backdrop();
        self.bar_dirty = true;
    }

    /// The main output's wallpaper reading, for the wingpanel band.
    fn request_paint(&self) {
        if !self.bar.wingpanel() {
            return;
        }
        let size = self.output_size();
        barpaint::sample(barpaint::Request {
            wallpaper: self.store.state.data.wallpaper.clone(),
            edge: self.bar.edge().as_str(),
            thickness: self.bar.thickness() as f64,
            screen: size,
            output: self.bar.output.clone(),
        });
    }

    fn output_size(&self) -> (f64, f64) {
        self.outputs
            .outputs()
            .next()
            .and_then(|o| self.outputs.info(&o))
            .and_then(|i| i.logical_size.or_else(|| i.modes.iter().find(|m| m.current).map(|m| m.dimensions)))
            .map_or((0.0, 0.0), |(w, h)| (w as f64, h as f64))
    }

    /// The output the bar's cells answer for: the first one the registry
    /// announced, the one a layer surface with no output lands on.
    pub fn bar_output_name(&self) -> String {
        self.outputs.outputs().next().and_then(|o| self.outputs.info(&o)).and_then(|i| i.name).unwrap_or_default()
    }

    pub fn panel_open(&self) -> Option<&str> {
        self.panel.as_ref().filter(|p| p.card.is_open()).map(|p| p.name.as_str())
    }

    pub fn overflow_open(&self) -> Option<BarRegion> {
        self.overflow.as_ref().filter(|p| p.card.is_open()).and_then(|p| p.region)
    }

    fn sync_open(&mut self, now: Instant) {
        let panel = self.panel_open().map(str::to_owned);
        let overflow = self.overflow_open();
        self.bar.set_open(panel.as_deref(), overflow, now);
        if let Some(p) = &mut self.overflow {
            for s in &mut p.slots {
                let open = panel.as_deref().is_some_and(|n| s.view.panel == Some(n));
                s.set_open(open, &self.bar.kit, now);
            }
        }
    }

    pub fn debug_join(&self) -> Option<(i32, i32)> {
        self.debug_join
    }

    pub fn set_debug_join(&mut self, join: Option<(i32, i32)>) {
        self.debug_join = join;
        self.sync_join();
    }

    /// A card's own join wins over `debug join`'s while the card is up.
    fn sync_join(&mut self) {
        let card = |p: &Option<Popout>| p.as_ref().and_then(|p| p.card.join);
        let debug = self.debug_join.map(|(x, width)| (x as f64, width as f64, self.store.theme.theme.radii.xl));
        self.bar.set_join(card(&self.panel).or(card(&self.overflow)).or(debug));
        self.bar_dirty = true;
    }

    /// A card's layer surface on the bar's edge, taking input over its
    /// resting rect. A panel sits a layer above the second bar, so one
    /// opened from a cell in that bar lands over it.
    fn popout_surface(&self, card: &Card, layer: Layer) -> Surface {
        let edge = card.edge;
        let depth = card.depth() as u32;
        let size = if edge.is_vertical() { (depth, 0) } else { (0, depth) };
        let layer = self.overlay("formalshell:panel", layer, edge_anchor(edge), size, -1);
        if let Ok(region) = Region::new(&self.compositor) {
            let r = card.rest_rect();
            region.add(r.x, r.y, r.w, r.h);
            layer.set_input_region(Some(region.wl_region()));
            layer.commit();
        }
        let mut surface = Surface::new("panel", layer, &self.shm, self.started);
        surface.wait_map = true;
        surface
    }

    fn new_card(&self, anchor: f64, size: (f64, f64)) -> Card {
        Card::new(
            &self.store.theme.theme,
            self.bar.edge(),
            self.bar.length(),
            self.bar.thickness() as f64,
            anchor,
            size,
            self.motion_scale,
            self.cast,
        )
    }

    /// The chevron's second bar for `region`, hung under its chevron.
    pub fn set_overflow(&mut self, region: BarRegion, open: bool) {
        let now = Instant::now();
        if !open {
            if let Some(p) = self.overflow.as_mut().filter(|p| p.region == Some(region) && p.card.is_open()) {
                p.card.set_open(now, false);
            }
            self.sync_open(now);
            return;
        }
        if self.overflow.as_ref().is_some_and(|p| p.region == Some(region) && p.card.is_open()) {
            return;
        }
        let entries = self.bar.overflow_entries(region);
        let edge = self.bar.edge();
        let env = Env { store: &self.store, edge, output: &self.bar.output };
        let mut slots: Vec<Slot> = entries.iter().map(|e| Slot::new(e, &entries)).collect();
        for s in &mut slots {
            s.refresh(&mut self.bar.kit, &env, false, false, 0.0, now);
        }
        let look = self.bar.kit.look.clone();
        let present: Vec<f64> = slots.iter().filter(|s| s.present()).map(|s| s.natural).collect();
        let rail = present.iter().sum::<f64>() + look.sm * present.len().saturating_sub(1) as f64;
        let across = if edge.is_vertical() { look.cell_width } else { look.cell_height };
        let size = (rail + look.panel_padding * 2.0, across + look.panel_padding * 2.0);
        let anchor = self
            .bar
            .slots
            .iter()
            .position(|s| s.name == "chevron" && s.region == region)
            .map_or(self.bar.length() as f64, |i| self.bar.slot_anchor(i));
        let card = self.new_card(anchor, size);
        let surface = self.popout_surface(&card, Layer::Top);
        self.overflow = Some(Popout {
            name: format!("overflow:{}", region.as_str()),
            region: Some(region),
            card,
            surface,
            slots,
            title: None,
            title_nodes: Vec::new(),
            hover: None,
        });
        self.sync_open(now);
        self.log("overflow mapped");
    }

    /// A panel by name, hung at `anchor` along the line (its own cell's
    /// centre), or under its cell on the strip, or at the strip's end. A
    /// panel opened over another replaces it.
    pub fn set_panel(&mut self, name: &str, open: bool, anchor: Option<f64>) {
        let now = Instant::now();
        if !open {
            if let Some(p) = self.panel.as_mut().filter(|p| p.name == name && p.card.is_open()) {
                p.card.set_open(now, false);
            }
            self.sync_open(now);
            return;
        }
        if self.panel.as_ref().is_some_and(|p| p.name == name && p.card.is_open()) {
            return;
        }
        let title_text = PANELS.iter().find(|(n, _)| *n == name).map_or(name, |(_, t)| t);
        let look = self.bar.kit.look.clone();
        let title = self.bar.kit.shape(title_text, look.sans(fs_theme::tokens::WEIGHTS.medium as f32));
        let anchor = anchor.or_else(|| self.bar.panel_anchor(name)).unwrap_or(self.bar.length() as f64);
        let width = self.store.theme.theme.space.popup_width_default;
        // A card's width runs along a top or bottom line and away from a
        // left or right one.
        let size = if self.bar.edge().is_vertical() { (PANEL_HEIGHT, width) } else { (width, PANEL_HEIGHT) };
        let card = self.new_card(anchor, size);
        let surface = self.popout_surface(&card, Layer::Overlay);
        self.panel = Some(Popout {
            name: name.to_owned(),
            region: None,
            card,
            surface,
            slots: Vec::new(),
            title: Some(title),
            title_nodes: Vec::new(),
            hover: None,
        });
        self.sync_open(now);
        self.log(&format!("panel {name} mapped"));
    }

    pub fn close_panels(&mut self) {
        let now = Instant::now();
        if let Some(p) = &mut self.panel {
            p.card.set_open(now, false);
        }
        self.sync_open(now);
    }

    pub fn set_scrim(&mut self, now: Instant, open: bool) {
        if let Some((scrim, _)) = &mut self.scrim {
            scrim.set_open(now, open);
            return;
        }
        if !open {
            return;
        }
        let scrim = Scrim::new(&self.store.theme.theme, self.motion_scale);
        let layer = self.overlay("formalshell:scrim", Layer::Top, Anchor::all(), (0, 0), -1);
        let surface = PixelSurface::new("scrim", layer, &self.pixels, &self.qh, self.started);
        self.scrim = Some((scrim, surface));
    }

    pub fn set_spinner(&mut self, on: bool) {
        let now = Instant::now();
        for s in &mut self.bar.slots {
            if let Some(c) = s.cell.custom() {
                c.spinner(on, now);
            }
        }
        self.bar_dirty = true;
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

    /// What an input on a cell asks for. `anchor` is that cell's centre
    /// along the line.
    fn act(&mut self, action: Action, anchor: f64) {
        match action {
            Action::None => {}
            Action::Panel(name) => {
                let open = self.panel_open() != Some(name);
                self.set_panel(name, open, Some(anchor));
            }
            Action::Overflow(region) => {
                let open = self.overflow_open() != Some(region);
                self.set_overflow(region, open);
            }
            Action::Workspace(id) => hyprland::focus_workspace(&id),
            Action::Volume(v) => {
                if let Some(rt) = &self.runtime {
                    rt.service(move |ctx| devices::set_volume(ctx, v));
                }
            }
            Action::ToggleMute => {
                if let Some(rt) = &self.runtime {
                    rt.service(devices::toggle_mute);
                }
            }
        }
    }

    pub fn present(&mut self) {
        let now = Instant::now();
        if self.panel.as_ref().is_some_and(|p| p.finished(now)) {
            self.panel = None;
            self.sync_join();
            self.log("panel unmapped");
        }
        if self.overflow.as_ref().is_some_and(|p| p.finished(now)) {
            self.overflow = None;
            self.sync_join();
            self.log("overflow unmapped");
        }
        if self.scrim.as_ref().is_some_and(|(p, s)| s.mapped && p.finished(now)) {
            self.scrim = None;
            self.log("scrim unmapped");
        }
        let qh = self.qh.clone();
        let animating = self.bar.animating(now);
        if self.bar_dirty || animating {
            self.bar.layout(&self.store, now);
            self.bar_dirty = false;
        }
        if let Some(s) = &mut self.bar_surface {
            s.present(&mut self.bar.scene, animating, &qh);
        }
        for p in [&mut self.overflow, &mut self.panel].into_iter().flatten() {
            p.layout(&mut self.bar, now);
            let kit = &self.bar.kit;
            let content = p.slots.iter_mut().any(|s| s.animating(kit, true, now));
            let animating = p.card.animating(now) || content;
            p.surface.present(&mut p.card.scene, animating, &qh);
        }
        for (_, z) in &mut self.zones {
            z.present(0.0, false, &qh);
        }
        if let Some((scrim, surface)) = &mut self.scrim {
            surface.present(scrim.alpha(now), scrim.animating(now), &qh);
        }
        self.arm_wake(now);
    }

    /// A timer for the next thing that starts moving on its own (a marquee
    /// leaving its hold), so nothing asks for frames while it waits.
    fn arm_wake(&mut self, now: Instant) {
        let Some(at) = self.bar.wake(now) else { return };
        if self.wake.is_some_and(|w| w <= at && w > now) {
            return;
        }
        let Some(handle) = &self.handle else { return };
        self.wake = Some(at);
        let _ = handle.insert_source(Timer::from_deadline(at), |_, _, app: &mut App| {
            app.wake = None;
            app.bar_dirty = true;
            TimeoutAction::Drop
        });
    }

    fn owner(&self, surface: &wl_surface::WlSurface) -> Option<Owner> {
        if self.bar_surface.as_ref().is_some_and(|s| s.layer.wl_surface() == surface) {
            return Some(Owner::Bar);
        }
        if self.overflow.as_ref().is_some_and(|p| p.surface.layer.wl_surface() == surface) {
            return Some(Owner::Overflow);
        }
        if self.panel.as_ref().is_some_and(|p| p.surface.layer.wl_surface() == surface) {
            return Some(Owner::Panel);
        }
        if self.scrim.as_ref().is_some_and(|(_, s)| s.layer.wl_surface() == surface) {
            return Some(Owner::Scrim);
        }
        if self.backdrop.as_ref().is_some_and(|b| b.layer.wl_surface() == surface) {
            return Some(Owner::Backdrop);
        }
        self.zones.iter().position(|(_, z)| z.layer.wl_surface() == surface).map(Owner::Zone)
    }

    pub fn report_exit(&self) {
        let mut parts: Vec<String> = self.bar_surface.iter().map(|s| s.report()).collect();
        parts.extend(self.panel.as_ref().map(|p| p.surface.report()));
        parts.extend(self.overflow.as_ref().map(|p| p.surface.report()));
        parts.extend(self.scrim.as_ref().map(|(_, s)| s.report()));
        eprintln!("exit t={}ms {}", self.started.elapsed().as_millis(), parts.join(" "));
    }

    fn hover(&mut self, owner: Option<Owner>, at: (f64, f64)) {
        let bar_hover = (owner == Some(Owner::Bar)).then(|| self.bar.hit(at.0, at.1)).flatten();
        if bar_hover != self.bar.hover {
            self.bar.hover = bar_hover;
            for s in &mut self.bar.slots {
                s.dirty = true;
            }
            self.bar_dirty = true;
        }
        for (o, p) in [(Owner::Overflow, &mut self.overflow), (Owner::Panel, &mut self.panel)] {
            if let Some(p) = p {
                p.hover = (owner == Some(o)).then(|| p.hit(at.0, at.1)).flatten();
            }
        }
    }

    fn pointer_events(&mut self, events: &[PointerEvent]) {
        for e in events {
            let owner = self.owner(&e.surface);
            let (x, y) = e.position;
            match e.kind {
                PointerEventKind::Enter { serial } => {
                    self.cursor = Some((serial, Shape::Default));
                    self.pointer_on = owner;
                    self.hover(owner, (x, y));
                    self.set_cursor(true);
                }
                PointerEventKind::Motion { .. } => {
                    self.pointer_on = owner;
                    self.hover(owner, (x, y));
                    self.set_cursor(false);
                }
                PointerEventKind::Leave { .. } => {
                    self.pointer_on = None;
                    self.hover(None, (x, y));
                }
                PointerEventKind::Press { button, .. } => {
                    let hit = match owner {
                        Some(Owner::Bar) => self.bar.hit(x, y),
                        Some(Owner::Overflow) => self.overflow.as_ref().and_then(|p| p.hit(x, y)),
                        Some(Owner::Panel) => self.panel.as_ref().and_then(|p| p.hit(x, y)),
                        _ => None,
                    };
                    self.pressed = owner.zip(hit);
                    let _ = button;
                }
                PointerEventKind::Release { button, .. } => {
                    let Some((o, i)) = self.pressed.take() else { continue };
                    let button = match button {
                        0x111 => Button::Right,
                        0x112 => Button::Middle,
                        _ => Button::Left,
                    };
                    self.click(o, i, button, (x, y));
                }
                PointerEventKind::Axis { vertical, .. } => {
                    let v = if vertical.discrete != 0 { vertical.discrete as f64 } else { vertical.absolute };
                    if v == 0.0 {
                        continue;
                    }
                    let up = v < 0.0;
                    if let Some(i) = self.bar.hit(x, y).filter(|_| owner == Some(Owner::Bar)) {
                        let action = self.bar.wheel(i, up, &self.store);
                        let anchor = self.bar.slot_anchor(i);
                        self.act(action, anchor);
                    }
                }
            }
        }
    }

    /// The hand over an interactive cell, the arrow anywhere else; sent
    /// only when it changes, or on every enter.
    fn set_cursor(&mut self, entered: bool) {
        let (Some(device), Some((serial, current))) = (&self.cursor_device, self.cursor) else { return };
        let interactive = |slots: &[Slot], i: Option<usize>| i.and_then(|i| slots.get(i)).is_some_and(|s| s.view.interactive);
        let hand = match self.pointer_on {
            Some(Owner::Bar) => interactive(&self.bar.slots, self.bar.hover),
            Some(Owner::Overflow) => self.overflow.as_ref().is_some_and(|p| interactive(&p.slots, p.hover)),
            _ => false,
        };
        let shape = if hand { Shape::Pointer } else { Shape::Default };
        if entered || shape != current {
            device.set_shape(serial, shape);
            self.cursor = Some((serial, shape));
        }
    }

    fn click(&mut self, owner: Owner, i: usize, button: Button, at: (f64, f64)) {
        let edge = self.bar.edge();
        let (action, anchor) = match owner {
            Owner::Bar if i < self.bar.slots.len() => {
                let a = self.bar.click(i, button, at.0, at.1, &self.store);
                (a, self.bar.slot_anchor(i))
            }
            Owner::Overflow => {
                let Some(p) = &mut self.overflow else { return };
                let Some(s) = p.slots.get_mut(i) else { return };
                let env = Env { store: &self.store, edge, output: &self.bar.output };
                let r = s.rect;
                let a = s.cell.click(button, (at.0 - r.x as f64, at.1 - r.y as f64), &env);
                let anchor = if edge.is_vertical() { r.y as f64 + r.h as f64 / 2.0 } else { r.x as f64 + r.w as f64 / 2.0 };
                (a, anchor)
            }
            _ => return,
        };
        self.act(action, anchor);
    }
}

impl CompositorHandler for App {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: i32) {}

    fn transform_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: wl_output::Transform) {}

    /// Every callback ticks its owner once more, so the frame that lands an
    /// animation on its rest is drawn, and that commit asks for no other.
    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &wl_surface::WlSurface, _: u32) {
        let now = Instant::now();
        match self.owner(surface) {
            Some(Owner::Bar) => {
                let Some(s) = &mut self.bar_surface else { return };
                (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
                self.bar_dirty = true;
            }
            Some(o @ (Owner::Overflow | Owner::Panel)) => {
                let p = if o == Owner::Overflow { &mut self.overflow } else { &mut self.panel };
                let Some(p) = p else { return };
                let s = &mut p.surface;
                (s.frame_pending, s.callbacks) = (false, s.callbacks + 1);
                if s.mapped {
                    p.card.tick(now);
                } else {
                    s.mapped = true;
                    p.card.mapped(now);
                }
                self.sync_join();
            }
            Some(Owner::Scrim) => {
                let Some((scrim, s)) = &mut self.scrim else { return };
                (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
                scrim.mapped(now);
            }
            Some(Owner::Zone(i)) => {
                let z = &mut self.zones[i].1;
                (z.frame_pending, z.mapped, z.callbacks) = (false, true, z.callbacks + 1);
            }
            Some(Owner::Backdrop) | None => {}
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
            Some(Owner::Overflow) => {
                self.overflow = None;
                self.sync_join();
            }
            Some(Owner::Scrim) => self.scrim = None,
            Some(Owner::Backdrop) => self.backdrop = None,
            Some(Owner::Zone(_)) | None => {}
        }
    }

    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface, configure: LayerSurfaceConfigure, _: u32) {
        let (width, height) = (configure.new_size.0 as i32, configure.new_size.1 as i32);
        match self.owner(layer.wl_surface()) {
            Some(Owner::Bar) => {
                let current = self.bar.scene.size;
                let w = if width > 0 { width } else { current.w };
                let h = if height > 0 { height } else { current.h };
                self.bar.resize(w, h);
                let size = self.bar.scene.size;
                if let Some(s) = &mut self.bar_surface {
                    s.configure(size.w, size.h);
                }
                self.set_input_region();
                self.refresh_bar(None);
            }
            Some(o @ (Owner::Overflow | Owner::Panel)) => {
                let p = if o == Owner::Overflow { &mut self.overflow } else { &mut self.panel };
                let Some(p) = p else { return };
                let size = p.card.scene.size;
                p.surface.configure(size.w, size.h);
            }
            Some(Owner::Scrim) => {
                let Some((_, s)) = &mut self.scrim else { return };
                s.configure(width, height);
            }
            Some(Owner::Zone(i)) => self.zones[i].1.configure(width.max(1), height.max(1)),
            Some(Owner::Backdrop) => {
                if let Some(b) = &mut self.backdrop {
                    b.configure(width, height);
                }
                self.update_backdrop();
            }
            None => {}
        }
    }
}

impl SeatHandler for App {
    fn seat_state(&mut self) -> &mut SeatState {
        &mut self.seats
    }

    fn new_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}

    fn new_capability(&mut self, _: &Connection, qh: &QueueHandle<Self>, seat: wl_seat::WlSeat, capability: Capability) {
        if capability == Capability::Pointer && self.pointer.is_none() {
            self.pointer = self.seats.get_pointer(qh, &seat).ok();
            self.cursor_device = match (&self.cursor_shapes, &self.pointer) {
                (Some(m), Some(p)) => Some(m.get_shape_device(p, qh)),
                _ => None,
            };
        }
    }

    fn remove_capability(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat, capability: Capability) {
        if let Some(p) = self.pointer.take().filter(|_| capability == Capability::Pointer) {
            p.release();
        }
    }

    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
}

impl PointerHandler for App {
    fn pointer_frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_pointer::WlPointer, events: &[PointerEvent]) {
        self.pointer_events(events);
    }
}

impl OutputHandler for App {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.outputs
    }

    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {
        self.on_outputs();
    }

    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {
        self.on_outputs();
    }

    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
}

impl App {
    fn on_outputs(&mut self) {
        let name = self.bar_output_name();
        if name != self.bar.output {
            self.bar.output = name;
            self.refresh_bar(None);
        } else {
            self.request_paint();
        }
    }
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
    registry_handlers![OutputState, SeatState];
}

delegate_registry!(App);
delegate_dispatch2!(App);

/// The theme engine's inputs once both files have been read.
pub fn theme_inputs(app: &App) {
    let (config, state) = (&app.store.config, &app.store.state);
    if !config.loaded || !state.loaded {
        return;
    }
    let location = match (config.f64("location.latitude"), config.f64("location.longitude")) {
        (Some(lat), Some(lon)) => Some((lat, lon)),
        _ => None,
    };
    theme::send_inputs(theme::Inputs {
        settings: config.settings().clone(),
        wallpaper: state.data.wallpaper.clone(),
        mode: state.data.mode.clone(),
        mode_override: theme::parse_override(&state.data.mode_override),
        location,
    });
}
