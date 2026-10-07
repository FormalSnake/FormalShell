//! The Wayland side: the bar's layer surface (gone while a fullscreen window
//! covers its output), the frame's four exclusion zones, the cards hanging
//! off the bar (the chevron's second bar, a panel), the tooltip, the scrim,
//! the pointer and the keyboard, and which owner a configure, a frame
//! callback or an input event belongs to.

mod caffeinate;
pub mod capture;
mod console;
mod headset;
mod hotcorners;
mod launcher;
pub mod lock;
mod osd;
mod polkit;
mod picker;
mod preview;
mod screensaver;
pub mod switcher;
mod toasts;

use std::time::Instant;

use calloop::LoopHandle;
use calloop::timer::{TimeoutAction, Timer};
use fs_chrome::bar::layout;
use fs_chrome::types::{Edge, Region as BarRegion};
use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState, Region};
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::reexports::client::globals::GlobalList;
use smithay_client_toolkit::reexports::client::protocol::{wl_keyboard, wl_output, wl_pointer, wl_seat, wl_surface};
use smithay_client_toolkit::reexports::client::{Connection, QueueHandle};
use smithay_client_toolkit::registry::{ProvidesRegistryState, RegistryState};
use smithay_client_toolkit::reexports::protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape, WpCursorShapeDeviceV1};
use smithay_client_toolkit::seat::pointer::cursor_shape::CursorShapeManager;
use smithay_client_toolkit::seat::keyboard::{KeyEvent, KeyboardHandler, Keysym, Modifiers, RawModifiers};
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
use crate::services::{barpaint, commands, devices, hyprland, info, media, nightlight, theme, tray, wallpaper};
use crate::store::{Store, Topic};
use crate::surface::{Backdrop, PixelSurface, Pixels, Surface};
use crate::surfaces;
use crate::surfaces::bar::Bar;
use crate::surfaces::bar::cell::{Action, Button, Env, TrayClick};
use crate::surfaces::bar::cells::tray as tray_cell;
use crate::surfaces::bar::slot::Slot;
use crate::surfaces::card::{Card, Ends, Scrim, Target};
use crate::surfaces::panel::{self, host::{Host, Key, Out, Place}};
use crate::surfaces::tooltip;
use crate::surfaces::tray_menu::{Hit, Menu, Outcome};

/// One axis of a scroll in wheel notches: the steps a wheel reports, or a
/// continuous axis at 15 units to the notch, the libinput/Qt ratio a
/// touchpad's swipe is read at.
fn notches(axis: &smithay_client_toolkit::seat::pointer::AxisScroll) -> f64 {
    if axis.value120 != 0 {
        axis.value120 as f64 / 120.0
    } else if axis.discrete != 0 {
        axis.discrete as f64
    } else {
        axis.absolute / 15.0
    }
}

fn edge_anchor(edge: Edge) -> Anchor {
    match edge {
        Edge::Top => Anchor::TOP | Anchor::LEFT | Anchor::RIGHT,
        Edge::Bottom => Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT,
        Edge::Left => Anchor::LEFT | Anchor::TOP | Anchor::BOTTOM,
        Edge::Right => Anchor::RIGHT | Anchor::TOP | Anchor::BOTTOM,
    }
}

/// The chevron's second bar: a card holding the governed cells.
pub struct Popout {
    pub name: String,
    pub region: Option<BarRegion>,
    pub card: Card,
    surface: Surface,
    pub slots: Vec<Slot>,
    pub hover: Option<usize>,
    /// A tray item's dbusmenu in place of cells (`traymenu`).
    menu: Option<Menu>,
}

impl Popout {
    fn finished(&self, now: Instant) -> bool {
        self.surface.mapped && self.card.finished(now)
    }

    /// Lays its content out at the card's content rect this frame.
    fn layout(&mut self, bar: &mut Bar, now: Instant) {
        let (rect, alpha) = self.card.content;
        let clip = self.card.content_clip();
        if let Some(menu) = &mut self.menu {
            menu.layout(&mut bar.kit, &mut self.card.scene, rect, alpha, clip);
            return;
        }
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
    }

    /// The menu's close button as `usize::MAX`, a row by its index.
    fn menu_hit(&self, x: f64, y: f64) -> Option<usize> {
        match self.menu.as_ref()?.hit(x.floor() as i32, y.floor() as i32)? {
            Hit::Close => Some(usize::MAX),
            Hit::Row(i) => Some(i),
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
    Menu,
    Outgoing,
    Tooltip,
    Toasts,
    Preview,
    Scrim,
    Osd,
    Headset,
    Zone(usize),
    Backdrop,
    Launcher,
    /// The launcher's scrim: 0 the top line's band, 1 the rest.
    LauncherScrim(u8),
    Switcher,
    Picker(usize),
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
    caffeinate: caffeinate::Caffeinate,
    console: console::Console,
    saver: screensaver::Saver,
    pub lock: lock::Lock,
    hot: hotcorners::HotCorners,
    polkit: Option<polkit::Dialog>,
    osd: osd::Osd,
    headset: headset::Headset,
    thumbnails: capture::Capture,
    pub switcher: switcher::State,
    peek: preview::State,
    pub bar: Bar,
    bar_surface: Option<Surface>,
    backdrop: Option<Backdrop>,
    zones: Vec<(Edge, PixelSurface)>,
    pub overflow: Option<Popout>,
    pub panel: Option<Host>,
    /// A handoff's outgoing card, until the incoming one starts moving.
    outgoing: Option<Host>,
    panel_dirty: bool,
    keyboard: Option<wl_keyboard::WlKeyboard>,
    tips: tooltip::Group,
    tip_card: Option<tooltip::Card>,
    toasts: Option<surfaces::toasts::Toasts>,
    toasts_dirty: bool,
    /// `debug join`'s card, hung in the gap it opens.
    preview: Option<(Surface, crate::scene::Scene, Vec<NodeId>)>,
    /// The tray item menu, over whatever popout it hangs off.
    pub menu: Option<Popout>,
    scrim: Option<(Scrim, PixelSurface)>,
    pointer: Option<wl_pointer::WlPointer>,
    /// The pointing hand over a cell that answers a click (Cell.qml's
    /// `cursorShape`), where the compositor offers cursor shapes.
    cursor_shapes: Option<CursorShapeManager>,
    cursor_device: Option<WpCursorShapeDeviceV1>,
    cursor: Option<(u32, Shape)>,
    /// The surface the click being acted on came from.
    act_owner: Option<Owner>,
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
    pub launcher: crate::surfaces::launcher::Model,
    launch: Option<launcher::Window>,
    launcher_resolve: bool,
    /// The index moved while the launcher was shut: resolve its root once
    /// at the next idle frame, so the first open finds the text and rows
    /// already laid out.
    launcher_warm: bool,
    /// The network the launcher's password step is for, and the identity
    /// an enterprise one was given first (WifiService.pendingSsid).
    wifi_pending: Option<(String, String)>,
    mods: fs_menu::nav::Modifiers,
    menu_buttons: Option<crate::services::menu::BaseInputs>,
    menu_launches: Option<serde_json::Value>,
    pub capture: crate::surfaces::capture::Capture,
    pickers: picker::Pickers,
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
            caffeinate: caffeinate::Caffeinate::bind(globals, qh),
            console: console::Console::default(),
            saver: screensaver::Saver::default(),
            lock: lock::Lock::bind(globals, qh),
            hot: Default::default(),
            polkit: None,
            osd: osd::Osd::default(),
            headset: headset::Headset::default(),
            thumbnails: capture::Capture::bind(globals, qh),
            switcher: switcher::State::default(),
            peek: preview::State::default(),
            bar,
            bar_surface: None,
            backdrop: None,
            zones: Vec::new(),
            overflow: None,
            panel: None,
            menu: None,
            outgoing: None,
            panel_dirty: false,
            keyboard: None,
            tips: tooltip::Group::default(),
            tip_card: None,
            toasts: None,
            toasts_dirty: false,
            preview: None,
            scrim: None,
            pointer: None,
            cursor_shapes: CursorShapeManager::bind(globals, qh).ok(),
            cursor_device: None,
            cursor: None,
            act_owner: None,
            pointer_on: None,
            pressed: None,
            bar_dirty: true,
            wake: None,
            motion_scale: 1.0,
            cast: false,
            debug_join: None,
            exit: false,
            started,
            launcher: Default::default(),
            launch: None,
            launcher_resolve: true,
            launcher_warm: false,
            wifi_pending: None,
            mods: Default::default(),
            menu_buttons: None,
            menu_launches: None,
            capture: Default::default(),
            pickers: Default::default(),
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
        let theme = &self.store.theme.theme;
        let dither = theme.wallpaper_dither.then(|| self.store.config.f64("wallpaper.ditherColors").unwrap_or(6.0).max(1.0) as usize);
        wallpaper::show(&self.store.state.data.wallpaper, w as u32, h as u32, dither);
        let background = theme.colors.get("background");
        let picture = self.store.wallpaper.picture.clone();
        let wanted = &self.store.state.data.wallpaper;
        let reveal = theme.motion().families.reveal * self.motion_scale;
        b.draw(picture.filter(|p| p.path == *wanted && p.dither == dither), background, reveal, &self.qh);
    }

    pub fn set_handle(&mut self, handle: LoopHandle<'static, App>) {
        self.handle = Some(handle);
        self.start_lock();
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
            self.drop_tray_menu();
            self.outgoing = None;
            self.tip_card = None;
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
        self.sync_hot_corners();
        let bar_cfg = self.store.config.get("bar").cloned();
        let resolved = layout::resolve(bar_cfg.as_ref(), &self.store.plugins.bar_plugins());
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
        media::configure(self.store.config.settings());
        nightlight::configure(self.store.config.settings());
        info::configure(self.store.config.settings());
        self.arm_caffeinate();
        let edge = layout::position(self.store.config.str("bar.position"));
        let moved = self.bar.set_edge(edge);
        let relaid = self.bar.set_layout(resolved);
        if moved || relaid {
            self.overflow = None;
            self.panel = None;
            self.drop_tray_menu();
            self.outgoing = None;
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
        if let Some(p) = &mut self.overflow {
            let env = Env { store: &self.store, edge: env_edge, output: &self.bar.output };
            for s in &mut p.slots {
                if topic.is_none_or(|t| s.cell.reads().contains(&t)) {
                    s.refresh(&mut self.bar.kit, &env, false, false, 0.0, now);
                }
            }
        }
        if self.panel.as_ref().is_some_and(|p| topic.is_none_or(|t| p.module.reads().contains(&t) || t == Topic::Theme)) {
            self.panel_dirty = true;
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

    /// An IPC verb for the open panel `name`; `None` when it is not up or
    /// answers none.
    pub fn panel_call(&mut self, name: &str, verb: &str, arg: &str) -> Option<String> {
        let reply = self.panel.as_mut().filter(|p| p.is_open() && p.id() == name)?.module.call(verb, arg);
        self.panel_dirty = true;
        reply
    }

    /// The open panel by its `panel` name; the gallery is no panel's.
    pub fn panel_open(&self) -> Option<&str> {
        let tray = self.overflow.as_ref().filter(|p| p.name == "trayoverflow" && p.card.is_open());
        tray.map(|_| "trayoverflow").or_else(|| self.panel.as_ref().filter(|p| p.is_open()).map(|p| p.id()).and_then(panel::known))
    }

    pub fn gallery_open(&self) -> bool {
        self.panel.as_ref().is_some_and(|p| p.is_open() && p.id() == "gallery")
    }

    pub fn overflow_open(&self) -> Option<BarRegion> {
        self.overflow.as_ref().filter(|p| p.card.is_open()).and_then(|p| p.region)
    }

    fn sync_open(&mut self, now: Instant) {
        let panel = self.panel_open().map(str::to_owned);
        let overflow = self.overflow_open();
        self.bar.set_open(panel.as_deref(), overflow, now);
        devices::earbuds::panel(panel.as_deref() == Some("earbuds"));
        devices::bluetooth::panel(panel.as_deref() == Some("bluetooth"));
        devices::audio::panel(panel.as_deref() == Some("audio"));
        devices::power::panel(panel.as_deref() == Some("dualsense"));
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
        if join.is_none() {
            self.preview = None;
            return;
        }
        if self.preview.is_none() {
            let (w, h) = self.output_size();
            let layer = self.overlay("formalshell:debug-join", Layer::Overlay, Anchor::all(), (0, 0), -1);
            let surface = Surface::new("debug-join", layer, &self.shm, self.started);
            self.preview = Some((surface, crate::scene::Scene::clear(w as i32, h as i32), Vec::new()));
        }
        let edge = self.bar.edge();
        let line = self.bar.thickness() as f64;
        if let Some((_, scene, nodes)) = &mut self.preview {
            let join = join.map(|(x, w)| (x as f64, w as f64));
            crate::surfaces::shoulders::preview(scene, nodes, &self.store.theme.theme, edge, line, join);
        }
    }

    /// A card's own join wins over `debug join`'s while the card is up. A
    /// panel hanging off the second bar opens its gap in that card's far
    /// edge rather than in the bar's line.
    fn sync_join(&mut self) {
        let nested = self.panel.as_ref().is_some_and(|p| p.place.target.is_some());
        let mut joins: Vec<(Edge, f64, f64, f64)> = Vec::new();
        let child = if nested { self.panel.as_ref().and_then(|p| p.card.join()) } else { None };
        if let Some(o) = &mut self.overflow {
            o.card.far_gap = child.map(|(x, w, r)| (x - r, x + w + r));
        }
        for h in [&self.panel, &self.outgoing].into_iter().flatten().filter(|h| h.place.target.is_none()) {
            joins.extend(h.card.joins.iter().map(|j| (j.edge, j.x, j.width, j.reach)));
        }
        if let Some(o) = &self.overflow {
            joins.extend(o.card.joins.iter().map(|j| (j.edge, j.x, j.width, j.reach)));
        }
        joins.extend(self.launcher_joins());
        joins.extend(self.popup_joins());
        let edge = self.bar.edge();
        if !joins.iter().any(|j| j.0 == edge)
            && let Some((x, width)) = self.debug_join
        {
            joins.push((edge, x as f64, width as f64, self.store.theme.theme.radii.xl));
        }
        // One gap per edge: the strip's own goes to the first card on it.
        let mut seen = Vec::new();
        joins.retain(|j| if seen.contains(&j.0) { false } else { seen.push(j.0); true });
        self.bar.set_joins(&joins);
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
                self.close_tray_menu();
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
        let mut card = self.new_card(anchor, size);
        card.ends = self.panel_place(None, false).ends;
        let surface = self.popout_surface(&card, Layer::Top);
        self.overflow = Some(Popout {
            name: format!("overflow:{}", region.as_str()),
            region: Some(region),
            card,
            surface,
            slots,
            hover: None,
            menu: None,
        });
        self.sync_open(now);
        self.log("overflow mapped");
    }

    /// Where a panel hangs: off the bar's line, or off the second bar's far
    /// edge for a cell inside it, centred on `anchor` or at the line's end.
    fn panel_place(&self, anchor: Option<f64>, nested: bool) -> Place {
        let edge = self.bar.edge();
        let output = self.output_size();
        let vertical = edge.is_vertical();
        let framed = self.bar.framed();
        let ft = if framed { self.bar.frame_thickness() } else { 0.0 };
        let ends = Ends {
            along: if vertical { output.1 } else { output.0 },
            inset_start: ft,
            inset_end: ft,
            radius: if framed { self.store.theme.theme.frame_radius } else { 0.0 },
        };
        let owner = self.overflow.as_ref().filter(|o| nested && o.card.is_open()).map(|o| {
            let live = o.card.live();
            (Target { along: live.x0, length: live.width(), radius: o.card.radius() }, live.y1)
        });
        Place {
            edge,
            output,
            line_at: owner.map_or(self.bar.thickness() as f64, |(_, far)| far),
            ends,
            far_inset: ft,
            anchor,
            target: owner.map(|(t, _)| t),
        }
    }

    /// A panel by name, hung at `anchor` along the line (its own cell's
    /// centre) or at the line's end. A panel opened over another hands the
    /// card over.
    pub fn set_panel(&mut self, name: &str, open: bool, anchor: Option<f64>) {
        self.set_panel_from(name, open, anchor, false);
    }

    fn set_panel_from(&mut self, name: &str, open: bool, anchor: Option<f64>, nested: bool) {
        let now = Instant::now();
        // A menu hangs off the popout under it and goes with it, or with
        // whatever replaces it.
        let kept = open && self.panel_open() == Some(name);
        if !kept {
            self.close_tray_menu();
        }
        if !open {
            if self.panel_open() == Some(name) {
                self.close_panels();
            }
            return;
        }
        if kept {
            return;
        }
        if name == "trayoverflow" {
            if let Some(h) = &mut self.panel {
                h.close(now);
                self.panel_dirty = true;
            }
            self.open_tray_overflow(anchor);
            return;
        }
        self.close_tray_overflow(now);
        let Some(module) = panel::build(name) else { return };
        self.open_host(module, anchor, nested, now);
    }

    pub fn set_gallery(&mut self, open: bool) {
        let now = Instant::now();
        if !open {
            if self.gallery_open() {
                self.close_panels();
            }
            return;
        }
        if !self.gallery_open() {
            self.open_host(Box::new(panel::gallery::Gallery::new()), None, false, now);
        }
    }

    fn open_host(&mut self, module: Box<dyn panel::Panel>, anchor: Option<f64>, nested: bool, now: Instant) {
        let place = self.panel_place(anchor, nested);
        self.open_host_at(module, place, now);
    }

    fn open_host_at(&mut self, module: Box<dyn panel::Panel>, place: Place, now: Instant) {
        let id = module.id();
        if self.panel.as_ref().is_some_and(|p| p.id() == id && p.is_open()) {
            return;
        }
        let layer = self.overlay("formalshell:panel", Layer::Overlay, Anchor::all(), (0, 0), -1);
        let keyboard = if module.takes_keyboard() { KeyboardInteractivity::Exclusive } else { KeyboardInteractivity::None };
        layer.set_keyboard_interactivity(keyboard);
        layer.commit();
        let mut surface = Surface::new("panel", layer, &self.shm, self.started);
        surface.wait_map = true;
        let mut host = Host::new(module, place, &self.store.theme.theme, surface, self.motion_scale, self.cast);
        host.module.start(&mut panel::Effect { store: &self.store, runtime: self.runtime.as_ref(), close: false });
        match self.panel.take() {
            Some(mut old) if old.is_open() => {
                host.take_over(old.card.live(), now);
                old.hand_over();
                self.outgoing = Some(old);
            }
            Some(old) => self.outgoing = Some(old),
            None => {}
        }
        host.card.set_open(now, true);
        self.panel = Some(host);
        self.panel_dirty = true;
        self.tips.hide(None, now);
        self.sync_open(now);
        self.log(&format!("panel {id} mapped"));
    }

    /// TrayOverflow.qml: the whole tray as a strip-sized card hanging off
    /// the toggle that replaced it on the bar.
    fn open_tray_overflow(&mut self, anchor: Option<f64>) {
        let now = Instant::now();
        let edge = self.bar.edge();
        let env = Env { store: &self.store, edge, output: &self.bar.output };
        let mut slot = Slot::of("tray".into(), BarRegion::Right, Box::new(tray_cell::Tray::rail()));
        slot.refresh(&mut self.bar.kit, &env, false, false, 0.0, now);
        let look = self.bar.kit.look.clone();
        let across = if edge.is_vertical() { look.cell_width } else { look.cell_height };
        let size = (slot.natural + look.panel_padding * 2.0, across + look.panel_padding * 2.0);
        let anchor = anchor.or_else(|| self.bar.panel_anchor("trayoverflow")).unwrap_or(self.bar.length() as f64);
        let mut card = self.new_card(anchor, size);
        card.ends = self.panel_place(None, false).ends;
        let surface = self.popout_surface(&card, Layer::Top);
        self.overflow = Some(Popout {
            name: "trayoverflow".to_owned(),
            region: None,
            card,
            surface,
            slots: vec![slot],
            hover: None,
            menu: None,
        });
        self.sync_open(now);
        self.log("panel trayoverflow mapped");
    }

    /// Shuts the tray's second bar, if that is what the second bar is.
    fn close_tray_overflow(&mut self, now: Instant) {
        if let Some(p) = self.overflow.as_mut().filter(|p| p.name == "trayoverflow" && p.card.is_open()) {
            p.card.set_open(now, false);
            self.sync_open(now);
        }
    }

    /// The input region over a popout's resting rect.
    fn set_popout_input(&self, p: &Popout) {
        if let Ok(region) = Region::new(&self.compositor) {
            let r = p.card.rest_rect();
            region.add(r.x, r.y, r.w, r.h);
            p.surface.layer.set_input_region(Some(region.wl_region()));
        }
    }

    /// A tray item's menu, hung off `anchor` along the line (its icon's
    /// centre) or at the strip's end, and off `over` when that is the popout
    /// the icon is in, which it then stands clear of.
    fn open_tray_menu(&mut self, id: &str, anchor: Option<f64>, over: Option<Owner>) -> Result<(), String> {
        let Some(item) = self.store.tray.by_id(id).cloned() else { return Err(format!("error: no tray item with id '{id}'")) };
        if !item.has_menu {
            return Err(format!("error: tray item '{id}' has no menu"));
        }
        let now = Instant::now();
        self.drop_tray_menu();
        let owner = match over {
            Some(Owner::Overflow) => self.overflow.as_ref(),
            _ => None,
        };
        let owner_edge = owner.filter(|p| p.card.is_open()).map(|p| p.card.rest().y1);
        if owner_edge.is_none() {
            self.close_panels();
        }
        let theme = &self.store.theme.theme;
        let edge = self.bar.edge();
        let vertical = edge.is_vertical();
        let line_at = owner_edge.unwrap_or(self.bar.thickness() as f64);
        let (_, output_height) = self.output_size();
        let pad = theme.space.screen_padding;
        let cap = if vertical { output_height - pad * 2.0 } else { output_height - line_at - theme.space.bar_margin - pad };
        let mut menu = Menu::new(theme, item.id.clone(), item.key.clone(), item.tooltip.clone());
        menu.cap = cap.max(menu.width());
        let width = menu.width();
        let oriented = |h: f64| if vertical { (h, width) } else { (width, h) };
        let anchor = anchor.unwrap_or(self.bar.length() as f64);
        menu.anchor = anchor;
        let mut card = Card::new(theme, edge, self.bar.length(), line_at, anchor, oriented(menu.cap), self.motion_scale, self.cast);
        card.menu(theme, self.cast);
        card.resize(now, anchor, self.bar.length(), pad, oriented(menu.height().min(menu.cap)));
        let surface = self.popout_surface(&card, Layer::Overlay);
        self.menu = Some(Popout {
            name: "traymenu".to_owned(),
            region: None,
            card,
            surface,
            slots: Vec::new(),
            hover: None,
            menu: Some(menu),
        });
        let key = item.key;
        if let Some(rt) = &self.runtime {
            rt.service(move |ctx| tray::open_menu(ctx, key));
        }
        self.log("tray menu mapped");
        Ok(())
    }

    /// Closes the menu through its exit, telling the item.
    pub fn close_tray_menu(&mut self) {
        let now = Instant::now();
        let Some(p) = self.menu.as_mut().filter(|p| p.card.is_open()) else { return };
        p.card.set_open(now, false);
        let key = p.menu.as_ref().map(|m| m.key.clone());
        if let (Some(key), Some(rt)) = (key, &self.runtime) {
            rt.service(move |ctx| tray::close_menu(ctx, key));
        }
    }

    /// Takes the menu off screen at once, telling the item if it was up.
    fn drop_tray_menu(&mut self) {
        self.close_tray_menu();
        self.menu = None;
    }

    /// The menu's card at the height its rows ask for, capped to the room.
    fn resize_menu(&mut self) {
        let now = Instant::now();
        let vertical = self.bar.edge().is_vertical();
        let length = self.bar.length();
        let pad = self.store.theme.theme.space.screen_padding;
        if let Some(p) = &mut self.menu {
            if let Some(m) = &p.menu {
                let (w, h) = (m.width(), m.height().min(m.cap));
                p.card.resize(now, m.anchor, length, pad, if vertical { (h, w) } else { (w, h) });
            }
        }
        if let Some(p) = &self.menu {
            self.set_popout_input(p);
        }
    }

    /// The tray changed: a menu waiting on its tree gets it, one whose item
    /// went away shuts.
    pub fn tray_changed(&mut self) {
        let Some(p) = &mut self.menu else { return };
        let Some(menu) = &mut p.menu else { return };
        if self.store.tray.by_id(&menu.id).is_none() {
            self.close_tray_menu();
            return;
        }
        if let Some(tree) = self.store.tray.menu.as_ref().filter(|m| m.key == menu.key) {
            menu.set_tree(Some(&tree.root));
        }
        self.resize_menu();
    }

    fn menu_outcome(&mut self, outcome: Outcome) {
        let Some(key) = self.menu.as_ref().and_then(|p| p.menu.as_ref()).map(|m| m.key.clone()) else { return };
        match outcome {
            Outcome::None => {}
            Outcome::Click(id) => {
                if let Some(rt) = &self.runtime {
                    rt.service(move |ctx| tray::menu_click(ctx, key, id));
                }
                self.close_tray_menu();
            }
            Outcome::Toggled(id, opened) => {
                if let (true, Some(rt)) = (opened, &self.runtime) {
                    rt.service(move |ctx| tray::menu_about_to_show(ctx, key, id));
                }
                self.resize_menu();
            }
        }
    }

    fn open_menu_mut(&mut self) -> Option<&mut Menu> {
        self.menu.as_mut().filter(|p| p.card.is_open()).and_then(|p| p.menu.as_mut())
    }

    /// `tray activate`: the item's own Activate, as its cell's click does.
    pub fn tray_activate(&self, id: &str) -> String {
        let Some(item) = self.store.tray.by_id(id) else { return format!("error: no tray item with id '{id}'") };
        let key = item.key.clone();
        if let Some(rt) = &self.runtime {
            rt.service(move |ctx| tray::activate(ctx, key));
        }
        "ok".into()
    }

    /// `tray menu`: opens over the second bar while that is up, as a right
    /// click on its cell does.
    pub fn tray_menu(&mut self, id: &str) -> String {
        let over = (self.panel_open() == Some("trayoverflow")).then_some(Owner::Overflow);
        match self.open_tray_menu(id, None, over) {
            Ok(()) => "ok".into(),
            Err(e) => e,
        }
    }

    pub fn tray_menu_cursor(&mut self, delta: i32) -> String {
        match self.open_menu_mut() {
            Some(m) => {
                m.move_cursor(delta);
                "ok".into()
            }
            None => "error: no tray menu open".into(),
        }
    }

    pub fn tray_menu_activate(&mut self) -> String {
        let Some(m) = self.open_menu_mut() else { return "error: no tray menu open".into() };
        let outcome = m.activate_cursor();
        self.menu_outcome(outcome);
        "ok".into()
    }

    /// `tray status`'s `overflow` block: whether the second bar is up and how
    /// many icons the strip kept.
    pub fn tray_inline(&self) -> usize {
        tray_cell::inline_count().min(self.store.tray.items.len())
    }

    pub fn close_panels(&mut self) {
        self.close_tray_menu();
        let now = Instant::now();
        if let Some(p) = &mut self.panel {
            p.close(now);
        }
        self.close_tray_overflow(now);
        self.panel_dirty = true;
        self.tips.hide(None, now);
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
            Action::WorkspaceAt(idx) => hyprland::focus_workspace_at(idx),
            Action::Window(id) => hyprland::focus_window(&id),
            Action::Device(op) => {
                if let Some(rt) = &self.runtime {
                    rt.service(move |ctx| devices::run(ctx, op));
                }
            }
            Action::Tray { id, click: TrayClick::Menu, offset } => {
                let over = self.act_owner.filter(|o| *o == Owner::Overflow);
                let _ = self.open_tray_menu(&id, Some(anchor + offset), over);
            }
            Action::Tray { id, click, .. } => {
                let Some(key) = self.store.tray.by_id(&id).map(|i| i.key.clone()) else { return };
                if let Some(rt) = &self.runtime {
                    rt.service(move |ctx| match click {
                        TrayClick::Secondary => tray::secondary_activate(ctx, key),
                        _ => tray::activate(ctx, key),
                    });
                }
                // Reaching an item is the second bar's whole errand.
                if self.act_owner == Some(Owner::Overflow) {
                    self.close_tray_overflow(Instant::now());
                }
            }
            Action::Caffeinate(on) => self.set_caffeinated(on),
            Action::MediaNext => self.store.media.next(),
            Action::MediaPrevious => self.store.media.previous(),
            Action::Center => {
                let open = !self.store.notifications.center_open;
                self.set_center(open);
            }
            Action::Dnd(on) => {
                self.store.notifications.set_dnd(on);
                surfaces::changed(self, Topic::Notifications);
            }
        }
    }

    pub fn present(&mut self) {
        self.preview_present();
        crate::surfaces::capture::flush(self);
        let now = Instant::now();
        self.tick_notifications();
        if self.panel.as_ref().is_some_and(|p| p.finished(now)) {
            self.panel = None;
            self.sync_join();
            self.sync_open(now);
            self.log("panel unmapped");
        }
        if self.outgoing.as_ref().is_some_and(|p| p.finished(now)) {
            self.outgoing = None;
            self.sync_join();
        }
        if self.overflow.as_ref().is_some_and(|p| p.finished(now)) {
            self.overflow = None;
            self.sync_join();
            self.log("overflow unmapped");
        }
        if self.menu.as_ref().is_some_and(|p| p.finished(now)) {
            self.menu = None;
            self.log("tray menu unmapped");
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
        for p in [&mut self.overflow, &mut self.menu].into_iter().flatten() {
            p.layout(&mut self.bar, now);
            let kit = &self.bar.kit;
            let content = p.slots.iter_mut().any(|s| s.animating(kit, true, now));
            let animating = p.card.animating(now) || content;
            p.surface.present(&mut p.card.scene, animating, &qh);
        }
        let theme = &self.store.theme.theme;
        for h in [&mut self.outgoing, &mut self.panel].into_iter().flatten() {
            if h.prime_until.is_some_and(|t| t <= now) {
                h.primed();
            }
            let animating = h.animating(now) || h.content_animating(now);
            if self.panel_dirty || animating {
                h.sync_region(&self.compositor);
                h.layout(&self.store, theme, &mut self.bar.kit, now);
            }
            let animating = h.animating(now) || h.content_animating(now);
            h.surface.present(&mut h.card.scene, animating, &qh);
        }
        self.panel_dirty = false;
        self.present_launcher(now);
        self.switcher_present();
        self.present_saver(now);
        self.present_tooltip(now);
        self.present_toasts(now);
        self.osd_present(now);
        self.headset_present(now);
        if let Some((surface, scene, _)) = &mut self.preview {
            surface.present(scene, false, &qh);
        }
        for (_, z) in &mut self.zones {
            z.present(0.0, false, &qh);
        }
        if let Some((scrim, surface)) = &mut self.scrim {
            surface.present(scrim.alpha(now), scrim.animating(now), &qh);
        }
        self.present_picker(now);
        self.present_polkit();
        self.present_lock();
        self.arm_wake(now);
    }

    /// The tooltip group's answer on screen: a card created for a show,
    /// travelling for a hand-off, and gone once its exit has run.
    fn present_tooltip(&mut self, now: Instant) {
        self.tips.tick(now);
        self.tips.drawn = self.tip_card.is_some();
        let theme = &self.store.theme.theme;
        match self.tips.shown.clone() {
            Some(ask) => {
                if self.tip_card.is_none() {
                    let size = self.output_size();
                    let layer = self.overlay("formalshell:tooltip", Layer::Overlay, Anchor::all(), (0, 0), -1);
                    let mut surface = Surface::new("tooltip", layer, &self.shm, self.started);
                    surface.wait_map = true;
                    self.tip_card = Some(tooltip::Card::new(surface, (size.0 as i32, size.1 as i32), self.motion_scale));
                }
                let travel = self.tips.travel;
                let card = self.tip_card.as_mut().expect("tooltip card");
                card.take(theme, &mut self.bar.kit, &ask, travel, now);
                card.set_open(theme, true, now);
            }
            None => {
                if let Some(c) = &mut self.tip_card {
                    c.set_open(theme, false, now);
                }
            }
        }
        if self.tip_card.as_ref().is_some_and(|c| c.surface.mapped && c.finished(now)) {
            self.tip_card = None;
        }
        let qh = self.qh.clone();
        if let Some(c) = &mut self.tip_card {
            c.draw(theme, &mut self.bar.kit, now);
            let animating = c.animating(now);
            c.surface.present(&mut c.scene, animating, &qh);
        }
    }

    /// A timer for the next thing that starts on its own (a marquee
    /// leaving its hold, a tooltip's delay, a panel's keyboard prime), so
    /// nothing asks for frames while it waits.
    fn arm_wake(&mut self, now: Instant) {
        let hosts = [&self.panel, &self.outgoing];
        let notifications = self.store.notifications.wake().map(|at| crate::services::notifications::instant_at(at, now));
        let at = [self.bar.wake(now), self.tips.wake(), notifications, self.osd_wake(), self.headset.wake(), self.switcher_deadline(), self.preview_deadline()]
            .into_iter()
            .chain(hosts.iter().filter_map(|h| h.as_ref()).flat_map(|h| [h.prime_until, h.wake.filter(|w| *w > now)]))
            .flatten()
            .min();
        let Some(at) = at else { return };
        if self.wake.is_some_and(|w| w <= at && w > now) {
            return;
        }
        let Some(handle) = &self.handle else { return };
        self.wake = Some(at);
        let _ = handle.insert_source(Timer::from_deadline(at), |_, _, app: &mut App| {
            app.wake = None;
            app.bar_dirty = true;
            app.panel_dirty = true;
            TimeoutAction::Drop
        });
    }

    fn owner(&self, surface: &wl_surface::WlSurface) -> Option<Owner> {
        if let Some(o) = self.launcher_owner(surface) {
            return Some(o);
        }
        if self.bar_surface.as_ref().is_some_and(|s| s.layer.wl_surface() == surface) {
            return Some(Owner::Bar);
        }
        if self.overflow.as_ref().is_some_and(|p| p.surface.layer.wl_surface() == surface) {
            return Some(Owner::Overflow);
        }
        if self.panel.as_ref().is_some_and(|p| p.surface.layer.wl_surface() == surface) {
            return Some(Owner::Panel);
        }
        if self.menu.as_ref().is_some_and(|p| p.surface.layer.wl_surface() == surface) {
            return Some(Owner::Menu);
        }
        if self.outgoing.as_ref().is_some_and(|p| p.surface.layer.wl_surface() == surface) {
            return Some(Owner::Outgoing);
        }
        if self.tip_card.as_ref().is_some_and(|c| c.surface.layer.wl_surface() == surface) {
            return Some(Owner::Tooltip);
        }
        if self.toasts.as_ref().is_some_and(|t| t.surface.layer.wl_surface() == surface) {
            return Some(Owner::Toasts);
        }
        if self.preview.as_ref().is_some_and(|(s, _, _)| s.layer.wl_surface() == surface) {
            return Some(Owner::Preview);
        }
        if self.scrim.as_ref().is_some_and(|(_, s)| s.layer.wl_surface() == surface) {
            return Some(Owner::Scrim);
        }
        if self.osd_owns(surface) {
            return Some(Owner::Osd);
        }
        if self.headset_owns(surface) {
            return Some(Owner::Headset);
        }
        if self.backdrop.as_ref().is_some_and(|b| b.layer.wl_surface() == surface) {
            return Some(Owner::Backdrop);
        }
        if self.switcher.owns(surface) {
            return Some(Owner::Switcher);
        }
        if let Some(i) = self.picker_owner(surface) {
            return Some(Owner::Picker(i));
        }
        self.zones.iter().position(|(_, z)| z.layer.wl_surface() == surface).map(Owner::Zone)
    }

    pub fn report_exit(&self) {
        let mut parts: Vec<String> = self.bar_surface.iter().map(|s| s.report()).collect();
        parts.extend(self.panel.as_ref().map(|p| p.surface.report()));
        parts.extend(self.outgoing.as_ref().map(|p| p.surface.report()));
        parts.extend(self.overflow.as_ref().map(|p| p.surface.report()));
        parts.extend(self.menu.as_ref().map(|p| p.surface.report()));
        parts.extend(self.tip_card.as_ref().map(|c| c.surface.report()));
        parts.extend(self.scrim.as_ref().map(|(_, s)| s.report()));
        parts.extend(self.launch.as_ref().map(|w| w.shown.surface.report()));
        eprintln!("exit t={}ms {}", self.started.elapsed().as_millis(), parts.join(" "));
    }

    /// Where a surface hugging the bar's edge `depth` deep sits on the
    /// output, for a rect on it in the output's coordinates.
    fn edge_origin(&self, depth: i32) -> (i32, i32) {
        let (w, h) = self.output_size();
        match self.bar.edge() {
            Edge::Bottom => (0, h as i32 - depth),
            Edge::Right => (w as i32 - depth, 0),
            _ => (0, 0),
        }
    }

    fn hover(&mut self, owner: Option<Owner>, at: (f64, f64)) {
        let now = Instant::now();
        let bar_hover = (owner == Some(Owner::Bar)).then(|| self.bar.hit(at.0, at.1)).flatten();
        if bar_hover != self.bar.hover {
            self.bar.hover = bar_hover;
            for s in &mut self.bar.slots {
                s.dirty = true;
            }
            self.bar_dirty = true;
        }
        if self.bar.pointer(bar_hover, at, &self.store, Instant::now()) {
            self.bar_dirty = true;
        }
        if let Some(p) = &mut self.overflow {
            let hit = (owner == Some(Owner::Overflow)).then(|| p.hit(at.0, at.1)).flatten();
            for (i, s) in p.slots.iter_mut().enumerate() {
                let rel = (hit == Some(i)).then(|| (at.0 - s.rect.x as f64, at.1 - s.rect.y as f64));
                if s.cell.custom().is_some_and(|c| c.pointer(rel).0) {
                    s.dirty = true;
                }
            }
            p.hover = hit;
        }
        if let Some(menu) = self.menu.as_mut() {
            let hit = (owner == Some(Owner::Menu)).then(|| menu.menu_hit(at.0, at.1)).flatten();
            let hit = hit.map(|i| if i == usize::MAX { Hit::Close } else { Hit::Row(i) });
            if let Some(m) = &mut menu.menu {
                m.hover(hit);
            }
        }
        self.hover_toasts((owner == Some(Owner::Toasts)).then_some(at));
        if let Some(h) = &mut self.panel {
            let point = (owner == Some(Owner::Panel)).then_some(at);
            if h.pointer(point, &self.store, self.runtime.as_ref()) {
                self.panel_dirty = true;
            }
        }
        // The tooltip the item under the pointer carries, in the output's
        // coordinates.
        let ask = match owner {
            Some(Owner::Bar) => self.bar.tooltip().map(|(text, r, edge)| {
                let (ox, oy) = if self.bar.framed() { (0, 0) } else { self.edge_origin(self.bar.thickness()) };
                let rect = IRect::new(r.x + ox, r.y + oy, r.w, r.h);
                tooltip::Ask { owner: format!("bar:{}:{}", rect.x, rect.y), text, rect, bar: Some(edge) }
            }),
            Some(Owner::Overflow) => self.overflow.as_ref().and_then(|p| {
                let s = p.slots.get(p.hover?)?;
                let (ox, oy) = self.edge_origin(p.card.depth());
                let rect = IRect::new(s.rect.x + ox, s.rect.y + oy, s.rect.w, s.rect.h);
                (!s.view.tooltip.is_empty()).then(|| tooltip::Ask {
                    owner: format!("overflow:{}", s.name),
                    text: s.view.tooltip.clone(),
                    rect,
                    bar: Some(self.bar.edge()),
                })
            }),
            Some(Owner::Panel) => self.panel.as_ref().and_then(|h| h.tooltip()).map(|(text, rect)| tooltip::Ask {
                owner: format!("panel:{}:{}", rect.x, rect.y),
                text,
                rect,
                bar: None,
            }),
            _ => None,
        };
        match ask {
            Some(ask) => self.tips.show(ask, now),
            None => self.tips.hide(None, now),
        }
        self.preview_pointer(owner == Some(Owner::Bar), owner == Some(Owner::Panel), at);
    }

    fn pointer_events(&mut self, events: &[PointerEvent]) {
        for e in events {
            if self.saver_owns(&e.surface) {
                let input = match e.kind {
                    PointerEventKind::Enter { serial } => match self.pointer.clone() {
                        Some(p) => screensaver::SaverInput::Enter(p, serial, e.position),
                        None => continue,
                    },
                    PointerEventKind::Motion { .. } => screensaver::SaverInput::Motion(e.position),
                    PointerEventKind::Press { .. } => screensaver::SaverInput::Press,
                    _ => continue,
                };
                self.saver_pointer(input);
                continue;
            }
            let owner = self.owner(&e.surface);
            if let Some(Owner::Picker(i)) = owner {
                self.picker_pointer(i, e);
                continue;
            }
            if self.launcher_pointer(e, owner) {
                continue;
            }
            let (x, y) = e.position;
            self.headset_pointer(owner, &e.kind);
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
                PointerEventKind::Press { .. } => {
                    if owner == Some(Owner::Switcher) {
                        self.switcher_close();
                        continue;
                    }
                    if owner == Some(Owner::Toasts) {
                        if let Some(t) = &mut self.toasts {
                            t.press(x, y);
                        }
                        self.pressed = Some((Owner::Toasts, 0));
                        continue;
                    }
                    if owner == Some(Owner::Panel) {
                        if let Some(h) = &mut self.panel {
                            h.press(x, y, &self.store, self.runtime.as_ref());
                        }
                        self.pressed = Some((Owner::Panel, 0));
                        self.panel_dirty = true;
                        continue;
                    }
                    let hit = match owner {
                        Some(Owner::Bar) => self.bar.hit(x, y),
                        Some(Owner::Overflow) => self.overflow.as_ref().and_then(|p| p.hit(x, y)),
                        Some(Owner::Menu) => self.menu.as_ref().and_then(|p| p.menu_hit(x, y)),
                        _ => None,
                    };
                    self.pressed = owner.zip(hit);
                }
                PointerEventKind::Release { button, .. } => {
                    let Some((o, i)) = self.pressed.take() else { continue };
                    if o == Owner::Toasts {
                        self.release_toasts(x, y);
                        continue;
                    }
                    if o == Owner::Panel {
                        let out = self.panel.as_mut().map_or(Out::None, |h| h.release(x, y, &self.store, self.runtime.as_ref()));
                        if out == Out::Close {
                            self.close_panels();
                        }
                        self.panel_dirty = true;
                        continue;
                    }
                    let button = match button {
                        0x111 => Button::Right,
                        0x112 => Button::Middle,
                        _ => Button::Left,
                    };
                    self.click(o, i, button, (x, y));
                }
                PointerEventKind::Axis { vertical, horizontal, .. } => {
                    if owner == Some(Owner::Panel) {
                        let (dx, dy) = (notches(&horizontal), notches(&vertical));
                        if let Some(h) = self.panel.as_mut().filter(|_| dx != 0.0 || dy != 0.0) {
                            h.scroll(x, y, dx, dy, &self.store, self.runtime.as_ref());
                        }
                        self.panel_dirty = true;
                        continue;
                    }
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
            Some(Owner::Panel) => self.panel.as_ref().is_some_and(|h| h.hand()),
            Some(Owner::Headset) => true,
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
        match owner {
            Owner::Bar if i < self.bar.slots.len() => {
                let a = self.bar.click(i, button, at.0, at.1, &self.store);
                let anchor = self.bar.slot_anchor(i);
                self.act(a, anchor);
            }
            Owner::Menu => {
                if button != Button::Left {
                    return;
                }
                let outcome = match self.menu.as_mut().and_then(|p| p.menu.as_mut()) {
                    Some(_) if i == usize::MAX => return self.close_tray_menu(),
                    Some(m) => m.activate(i),
                    None => return,
                };
                return self.menu_outcome(outcome);
            }
            Owner::Overflow => {
                let Some(p) = &mut self.overflow else { return };
                let Some(s) = p.slots.get_mut(i) else { return };
                let env = Env { store: &self.store, edge, output: &self.bar.output };
                let r = s.rect;
                let a = s.cell.click(button, (at.0 - r.x as f64, at.1 - r.y as f64), &env);
                let anchor = if edge.is_vertical() { r.y as f64 + r.h as f64 / 2.0 } else { r.x as f64 + r.w as f64 / 2.0 };
                // A cell in the second bar opens its panel off that card.
                if let Action::Panel(name) = a {
                    let open = self.panel_open() != Some(name);
                    self.set_panel_from(name, open, Some(anchor), true);
                } else {
                    self.act_owner = Some(owner);
                    self.act(a, anchor);
                    self.act_owner = None;
                }
            }
            _ => {}
        }
    }

    /// One key on the keyboard: the open panel's, as KeyCatcher.qml binds
    /// them.
    fn key_event(&mut self, event: KeyEvent) {
        self.key_event_from(event, false);
    }

    fn key_event_from(&mut self, event: KeyEvent, repeat: bool) {
        if self.lock_key(&event) || self.polkit_key(&event) || self.picker_key_event(&event) || self.launcher_key(&event, repeat) || self.headset_key(&event) || self.switcher_key(event.keysym) {
            return;
        }
        let editing = self.panel.as_ref().is_some_and(|h| h.editing());
        let key = match event.keysym {
            Keysym::space if editing => Key::Text(" ".into()),
            Keysym::BackSpace => Key::Back,
            Keysym::Escape => Key::Escape,
            Keysym::Tab => Key::Tab(1),
            Keysym::ISO_Left_Tab => Key::Tab(-1),
            Keysym::Down => Key::Move(0, 1),
            Keysym::Up => Key::Move(0, -1),
            Keysym::Right => Key::Move(1, 0),
            Keysym::Left => Key::Move(-1, 0),
            Keysym::Return | Keysym::KP_Enter | Keysym::space => Key::Activate,
            _ => match event.utf8 {
                Some(t) if t.chars().count() == 1 && t.chars().all(|c| c as u32 >= 0x20) => Key::Text(t),
                _ => return,
            },
        };
        let Some(h) = &mut self.panel else { return };
        let out = h.key(key, &self.store, self.runtime.as_ref());
        self.panel_dirty = true;
        if out == Out::Close {
            self.close_panels();
        }
    }

    fn popout_of(&mut self, owner: Owner) -> Option<&mut Popout> {
        match owner {
            Owner::Overflow => self.overflow.as_mut(),
            Owner::Menu => self.menu.as_mut(),
            _ => None,
        }
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
                s.landed(now);
                s.mapped = true;
                self.bar_dirty = true;
            }
            Some(o @ (Owner::Overflow | Owner::Menu)) => {
                let Some(p) = self.popout_of(o) else { return };
                let s = &mut p.surface;
                s.landed(now);
                if s.mapped {
                    p.card.tick(now);
                } else {
                    s.mapped = true;
                    p.card.mapped(now);
                }
                self.sync_join();
            }
            Some(o @ (Owner::Panel | Owner::Outgoing)) => {
                let theme = &self.store.theme.theme;
                let h = if o == Owner::Panel { &mut self.panel } else { &mut self.outgoing };
                let Some(h) = h else { return };
                let s = &mut h.surface;
                (s.frame_pending, s.callbacks) = (false, s.callbacks + 1);
                let mut cut = false;
                if s.mapped {
                    h.card.tick(now);
                } else {
                    s.mapped = true;
                    cut = h.mapped(theme, now);
                }
                // The card that took this one's place is moving: the
                // outgoing window goes on this tick, while the two still
                // stand exactly on top of each other.
                if cut && let Some(old) = &mut self.outgoing {
                    old.handed = true;
                }
                self.panel_dirty = true;
                self.sync_join();
            }
            Some(Owner::Tooltip) => {
                let theme = &self.store.theme.theme;
                let Some(c) = &mut self.tip_card else { return };
                let s = &mut c.surface;
                (s.frame_pending, s.callbacks) = (false, s.callbacks + 1);
                if !s.mapped {
                    s.mapped = true;
                    c.mapped(theme, now);
                }
            }
            Some(Owner::Toasts) => {
                let Some(t) = &mut self.toasts else { return };
                let s = &mut t.surface;
                (s.frame_pending, s.callbacks) = (false, s.callbacks + 1);
                if !s.mapped {
                    s.mapped = true;
                    self.toasts_dirty = true;
                }
            }
            Some(Owner::Scrim) => {
                let Some((scrim, s)) = &mut self.scrim else { return };
                (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
                scrim.mapped(now);
            }
            Some(Owner::Osd) => self.osd_frame(now),
            Some(Owner::Headset) => self.headset_frame(now),
            Some(Owner::Preview) => {
                let Some((s, _, _)) = &mut self.preview else { return };
                (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
            }
            Some(Owner::Zone(i)) => {
                let z = &mut self.zones[i].1;
                (z.frame_pending, z.mapped, z.callbacks) = (false, true, z.callbacks + 1);
            }
            Some(Owner::Switcher) => self.switcher_frame(),
            Some(o @ (Owner::Launcher | Owner::LauncherScrim(_))) => self.launcher_frame(o, now),
            Some(Owner::Picker(i)) => self.picker_frame(i),
            Some(Owner::Backdrop) => {
                if let Some(b) = &mut self.backdrop {
                    b.step(now, &self.qh);
                }
            }
            None if self.saver_owns(surface) => self.saver_frame_callback(),
            None => {
                if !self.polkit_frame(surface) {
                    self.lock_frame(surface);
                }
            }
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
            Some(Owner::Outgoing) => {
                self.outgoing = None;
                self.sync_join();
            }
            Some(Owner::Tooltip) => self.tip_card = None,
            Some(Owner::Toasts) => self.toasts = None,
            Some(Owner::Preview) => self.preview = None,
            Some(Owner::Overflow) => {
                self.overflow = None;
                self.sync_join();
            }
            Some(Owner::Menu) => self.menu = None,
            Some(Owner::Scrim) => self.scrim = None,
            Some(Owner::Osd) => self.osd.pill = None,
            Some(Owner::Headset) => {
                self.headset.card = None;
                self.sync_join();
            }
            Some(Owner::Backdrop) => self.backdrop = None,
            Some(Owner::Launcher) => self.launcher_closed(),
            Some(Owner::Switcher) => self.switcher_close(),
            Some(Owner::Picker(i)) => self.picker_closed(i),
            None if self.saver_owns(layer.wl_surface()) => self.saver_closed(),
            Some(Owner::Zone(_) | Owner::LauncherScrim(_)) | None => {}
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
            Some(o @ (Owner::Overflow | Owner::Menu)) => {
                let Some(p) = self.popout_of(o) else { return };
                let size = p.card.scene.size;
                p.surface.configure(size.w, size.h);
            }
            Some(o @ (Owner::Panel | Owner::Outgoing)) => {
                let h = if o == Owner::Panel { &mut self.panel } else { &mut self.outgoing };
                let Some(h) = h else { return };
                let size = h.card.scene.size;
                h.surface.configure(size.w, size.h);
                self.panel_dirty = true;
            }
            Some(Owner::Tooltip) => {
                let Some(c) = &mut self.tip_card else { return };
                let size = c.scene.size;
                c.surface.configure(size.w, size.h);
            }
            Some(Owner::Toasts) => {
                let Some(t) = &mut self.toasts else { return };
                let size = t.scene.size;
                t.surface.configure(size.w, size.h);
            }
            Some(Owner::Preview) => {
                let Some((s, scene, _)) = &mut self.preview else { return };
                s.configure(scene.size.w, scene.size.h);
            }
            Some(Owner::Scrim) => {
                let Some((_, s)) = &mut self.scrim else { return };
                s.configure(width, height);
            }
            Some(Owner::Osd) => self.osd_configure(),
            Some(Owner::Headset) => self.headset_configure(),
            Some(Owner::Zone(i)) => self.zones[i].1.configure(width.max(1), height.max(1)),
            Some(Owner::Backdrop) => {
                if let Some(b) = &mut self.backdrop {
                    b.configure(width, height);
                }
                self.update_backdrop();
            }
            Some(o @ (Owner::Launcher | Owner::LauncherScrim(_))) => self.launcher_configure(o, width, height),
            Some(Owner::Switcher) => self.switcher_configure(width, height),
            Some(Owner::Picker(i)) => self.picker_configure(i, width, height),
            None if self.caffeinate_owns(layer) => self.caffeinate_configure(),
            None if self.saver_owns(layer.wl_surface()) => self.saver_configure(width, height),
            None if self.hot_corner_owns(layer) => self.hot_corner_configure(layer),
            None if self.polkit_owns(layer) => self.polkit_configure(width, height),
            None => {}
        }
    }
}

impl SeatHandler for App {
    fn seat_state(&mut self) -> &mut SeatState {
        &mut self.seats
    }

    fn new_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {
        self.arm_idle();
    }

    fn new_capability(&mut self, _: &Connection, qh: &QueueHandle<Self>, seat: wl_seat::WlSeat, capability: Capability) {
        if capability == Capability::Pointer && self.pointer.is_none() {
            self.pointer = self.seats.get_pointer(qh, &seat).ok();
            self.cursor_device = match (&self.cursor_shapes, &self.pointer) {
                (Some(m), Some(p)) => Some(m.get_shape_device(p, qh)),
                _ => None,
            };
        }
        if capability == Capability::Keyboard && self.keyboard.is_none() {
            // Repeats come off the loop, so a held arrow glides the cursor.
            let repeat: smithay_client_toolkit::seat::keyboard::repeat::RepeatCallback<App> = Box::new(|app, _, event| app.key_event_from(event, true));
            self.keyboard = match self.handle.clone() {
                Some(handle) => self.seats.get_keyboard_with_repeat(qh, &seat, None, handle, repeat).ok(),
                None => self.seats.get_keyboard(qh, &seat, None).ok(),
            };
        }
    }

    fn remove_capability(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat, capability: Capability) {
        if let Some(p) = self.pointer.take().filter(|_| capability == Capability::Pointer) {
            p.release();
        }
        if let Some(k) = self.keyboard.take().filter(|_| capability == Capability::Keyboard) {
            k.release();
        }
    }

    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
}

impl PointerHandler for App {
    fn pointer_frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_pointer::WlPointer, events: &[PointerEvent]) {
        self.lock_pointer(events.iter().map(|e| e.surface.clone()));
        let rest = self.hot_corner_pointer(events);
        if !rest.is_empty() {
            self.pointer_events(&rest);
        }
    }
}

impl KeyboardHandler for App {
    fn enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, surface: &wl_surface::WlSurface, _: u32, _: &[u32], _: &[Keysym]) {
        self.headset_focus(surface, true);
    }

    fn leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, surface: &wl_surface::WlSurface, _: u32) {
        self.headset_focus(surface, false);
    }

    fn press_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, event: KeyEvent) {
        if self.saver.active && !self.lock.locked {
            self.saver_pointer(screensaver::SaverInput::Key);
            return;
        }
        self.key_event(event);
    }

    fn repeat_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, event: KeyEvent) {
        self.key_event_from(event, true);
    }

    fn release_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, _: KeyEvent) {}

    fn update_modifiers(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, m: Modifiers, _: RawModifiers, _: u32) {
        self.mods = fs_menu::nav::Modifiers { ctrl: m.ctrl, shift: m.shift, alt: m.alt };
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
        self.lock_outputs();
        self.sync_hot_corners();
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
