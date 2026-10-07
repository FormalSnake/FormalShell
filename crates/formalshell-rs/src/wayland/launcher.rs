//! The launcher's window on the App: its overlay surface, the two
//! single-pixel scrim surfaces under it (Scrim.qml's band over the top
//! line's own inset, riding `1 - attach`, and the rest of the output), the
//! keyboard and pointer routed to it, and the `menu` verbs.

use std::time::Instant;

use fs_chrome::types::Edge;
use fs_menu::nav;
use smithay_client_toolkit::compositor::Region;
use smithay_client_toolkit::seat::keyboard::{KeyEvent, Keysym};
use smithay_client_toolkit::seat::pointer::{PointerEvent, PointerEventKind};
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::{Anchor, KeyboardInteractivity, Layer};

use super::{App, Owner};
use crate::services::menu::{self as index, Ask};
use crate::surface::{PixelSurface, Surface};
use crate::surfaces::card::Ends;
use crate::surfaces::launcher::{Out, Shown};

const WIFI_PASSWORD: &str = "wifi-password";
const WIFI_IDENTITY: &str = "wifi-identity";

pub struct Window {
    pub shown: Shown,
    /// The Wi-Fi route keeps the scanner awake while it is the level
    /// (Menu.qml's `_wantsWifiScan`).
    scan: Option<crate::services::devices::network::Hold>,
    /// The top line's own band, and everything under it.
    band: Option<PixelSurface>,
    dim: PixelSurface,
    tone: f64,
    pressed: Option<String>,
}

impl Window {
    pub fn finished(&self, now: Instant) -> bool {
        self.shown.finished(now)
    }
}

impl App {
    /// Theme.edgeInset's top: the bar's thickness on a top bar, the frame
    /// ring's on a framed one, nothing on a bare edge.
    fn top_inset(&self) -> f64 {
        if self.bar.hidden {
            0.0
        } else if self.bar.edge() == Edge::Top {
            self.bar.thickness() as f64
        } else if self.bar.framed() {
            self.bar.frame_thickness()
        } else {
            0.0
        }
    }

    /// The window for an open, created fresh unless one is already up.
    fn show_launcher(&mut self) {
        self.launcher_resolve = true;
        if self.launch.as_ref().is_some_and(|w| w.shown.open) {
            return;
        }
        self.launch = None;
        let theme = &self.store.theme.theme;
        let output = self.output_size();
        let inset = self.top_inset();
        let framed = self.bar.framed();
        let ft = if framed { self.bar.frame_thickness() } else { 0.0 };
        let ends = Ends { along: output.0, inset_start: ft, inset_end: ft, radius: if framed { theme.frame_radius } else { 0.0 } };
        let band = (inset > 0.0).then(|| {
            let ls = self.overlay("formalshell:menu", Layer::Overlay, Anchor::TOP | Anchor::LEFT | Anchor::RIGHT, (0, inset as u32), -1);
            PixelSurface::new("menu-scrim-band", ls, &self.pixels, &self.qh, self.started)
        });
        let ls = self.layer_shell.create_layer_surface(&self.qh, self.compositor.create_surface(&self.qh), Layer::Overlay, Some("formalshell:menu"), None);
        ls.set_anchor(Anchor::all());
        ls.set_size(0, 0);
        ls.set_margin(inset as i32, 0, 0, 0);
        ls.set_exclusive_zone(-1);
        ls.set_keyboard_interactivity(KeyboardInteractivity::None);
        if let Ok(region) = Region::new(&self.compositor) {
            ls.set_input_region(Some(region.wl_region()));
        }
        ls.commit();
        let dim = PixelSurface::new("menu-scrim", ls, &self.pixels, &self.qh, self.started);
        let layer = self.overlay("formalshell:menu", Layer::Overlay, Anchor::all(), (0, 0), -1);
        layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
        layer.commit();
        let mut surface = Surface::new("menu", layer, &self.shm, self.started);
        surface.wait_map = true;
        let shown = Shown::new(theme, surface, output, inset, ends, self.motion_scale, self.cast);
        let tone = f64::from(theme.box_style("scrim", None).fill.a);
        self.launch = Some(Window { shown, scan: None, band, dim, tone, pressed: None });
        self.log("menu mapped");
    }

    fn hide_launcher(&mut self) {
        if let Some(w) = &mut self.launch {
            w.shown.close(Instant::now());
            self.log("menu closing");
        }
        self.sync_join();
    }

    pub fn menu_open(&mut self, route: Option<&str>) {
        self.launcher.open(&self.store, route);
        self.show_launcher();
    }

    pub fn menu_toggle(&mut self) {
        if self.launcher.open {
            self.menu_close();
        } else {
            self.menu_open(None);
        }
    }

    pub fn menu_close(&mut self) {
        self.launcher.close();
        self.hide_launcher();
    }

    pub fn menu_select(&mut self, prompt: &str, options: Vec<String>, token: &str) {
        self.launcher.open_select(prompt, options, token);
        self.show_launcher();
    }

    pub fn menu_input(&mut self, prompt: &str, token: &str) {
        self.menu_input_as(prompt, token, false);
    }

    /// An input step; a secret one is drawn masked and never filed.
    fn menu_input_as(&mut self, prompt: &str, token: &str, secret: bool) {
        self.launcher.open_input(prompt, token, secret);
        self.launcher_resolve = true;
        self.show_launcher();
    }

    pub fn menu_filter(&mut self, text: &str) -> bool {
        if !self.launcher.open {
            return false;
        }
        self.launcher.set_query(&self.store, text);
        self.launcher_resolve = true;
        true
    }

    pub fn menu_activate(&mut self, index: usize, alternate: bool) -> bool {
        if !self.launcher.open {
            return false;
        }
        self.resolve_launcher();
        let out = if alternate { self.launcher.activate_alternate(&self.store, index) } else { self.launcher.activate(&self.store, index) };
        self.launcher_out(out);
        true
    }

    /// The rows again, now, so an IPC read answers off the same state a
    /// frame would draw.
    pub fn resolve_launcher(&mut self) {
        if self.launcher_resolve {
            self.launcher_resolve = false;
            self.launcher.resolve(&self.store, &self.store.theme.theme, &mut self.bar.kit);
        }
    }

    fn launcher_out(&mut self, out: Out) {
        self.launcher_resolve = true;
        match out {
            Out::None => {}
            Out::Close => self.hide_launcher(),
            Out::Internal(name) => {
                if !self.launcher.open {
                    self.hide_launcher();
                }
                self.dispatch_internal(&name);
            }
        }
    }

    /// Menu.qml's `_dispatchInternal`, for the targets this shell serves.
    fn dispatch_internal(&mut self, name: &str) {
        if let Some((verb, value)) = name.split_once('.').map(|(_, rest)| rest.split_once(':').unwrap_or((rest, "")))
            && let Some(group) = name.split('.').next()
            && matches!(group, "wifi" | "bluetooth" | "audio" | "radio")
        {
            return self.device_action(group, verb, value);
        }
        match name {
            "theme.toggleMode" => {
                let key = crate::services::theme::mode_key(self.store.config.settings());
                if let Ok(mode) = crate::services::theme::request_mode("toggle", &self.store.state.data.mode, key) {
                    crate::services::state::set(vec![crate::services::state::Field::Mode(mode)]);
                }
            }
            "caffeinate.toggle" => {
                let on = !self.store.caffeinate.active;
                self.set_caffeinated(on);
            }
            other => eprintln!("Menu: unknown internal action: {other}"),
        }
    }

    /// Menu.qml's `wifi.`, `bluetooth.`, `audio.` and `radio.` actions.
    fn device_action(&mut self, group: &str, verb: &str, value: &str) {
        use crate::services::devices::{bluetooth, network as net};
        use crate::services::radio::{self, Cmd};
        let value = value.to_owned();
        let service = |f: Box<dyn FnOnce(&crate::runtime::Ctx) + Send>| {
            if let Some(rt) = &self.runtime {
                rt.service(f);
            }
        };
        match (group, verb) {
            ("wifi", "enable") => service(Box::new(|ctx| net::set_wifi(ctx, true))),
            ("wifi", "forget") => service(Box::new(move |ctx| net::forget(ctx, value))),
            ("wifi", "activate") => {
                let n = &self.store.devices.network;
                let Some(row) = n.row(&value).cloned() else { return };
                if n.action.is_some() {
                    return;
                }
                if row.connected {
                    return service(Box::new(move |ctx| net::disconnect(ctx, value)));
                }
                // A secured network nobody knows, or one whose last attempt
                // failed on the secret, asks for it: a wrong password is
                // retyped, never retried.
                let retype = n.failure.as_ref().is_some_and(|f| f.ssid == value && f.secret);
                if retype || (row.secured && !row.known) {
                    let (prompt, token) = if row.enterprise {
                        (format!("Identity for {value}"), WIFI_IDENTITY)
                    } else {
                        (format!("Password for {value}"), WIFI_PASSWORD)
                    };
                    self.wifi_pending = Some((value, String::new()));
                    self.menu_input_as(&prompt, token, token == WIFI_PASSWORD);
                } else {
                    service(Box::new(move |ctx| net::connect(ctx, value, net::Secret::Saved)));
                }
            }
            ("bluetooth", "power") if value == "on" => bluetooth::ask(bluetooth::Ask::Power(true)),
            ("bluetooth", "toggle") => {
                let Some(d) = self.store.devices.bluetooth.devices.iter().find(|d| d.address.eq_ignore_ascii_case(&value)) else { return };
                let kind = if d.connected { bluetooth::ActionKind::Disconnect } else { bluetooth::ActionKind::Connect };
                bluetooth::ask(bluetooth::Ask::Run(d.address.clone(), kind));
            }
            ("audio", "sink" | "source") => {
                let c = if verb == "sink" {
                    fs_audio::Command::SetDefaultSink(Some(value))
                } else {
                    fs_audio::Command::SetDefaultSource(Some(value))
                };
                service(Box::new(move |_| crate::services::devices::audio::command(c)));
            }
            ("radio", _) => {
                let r = &self.store.media.radio;
                let results = r.search.as_ref().and_then(|(_, f)| f.clone()).unwrap_or_default();
                let station = r.favorites.iter().chain(results.iter()).find(|s| s.uuid == value).cloned();
                match (verb, station) {
                    ("stop", _) => radio::send(Cmd::Stop),
                    ("fav", Some(s)) => radio::send(Cmd::PlayFromSaved(s, r.favorites.clone())),
                    ("play", Some(s)) => radio::send(Cmd::PlayFromSaved(s, results)),
                    ("favorite" | "unfavorite", Some(s)) => {
                        if r.favorites.iter().any(|f| f.uuid == s.uuid) == (verb == "unfavorite") {
                            radio::send(Cmd::ToggleFavorite(s));
                        }
                    }
                    _ => {}
                }
            }
            _ => eprintln!("Menu: unknown internal action: {group}.{verb}"),
        }
    }

    /// shell.qml's `selectionResolved`: the answers whose token an
    /// in-process owner holds.
    fn launcher_answers(&mut self) {
        for (token, value, cancelled) in self.launcher.take_resolved() {
            if token == WIFI_IDENTITY || token == WIFI_PASSWORD {
                self.wifi_answer(&token, value, cancelled);
            }
        }
    }

    /// WifiService.resolveInput, then the launcher back on the Wi-Fi list.
    fn wifi_answer(&mut self, token: &str, value: Option<String>, cancelled: bool) {
        use crate::services::devices::network as net;
        let Some((ssid, identity)) = self.wifi_pending.take() else { return };
        let value = value.unwrap_or_default();
        if cancelled || value.is_empty() {
            return;
        }
        if token == WIFI_IDENTITY {
            self.wifi_pending = Some((ssid.clone(), value));
            self.menu_input_as(&format!("Password for {ssid}"), WIFI_PASSWORD, true);
            return;
        }
        let Some(row) = self.store.devices.network.row(&ssid) else { return };
        let secret = if !identity.is_empty() && row.enterprise {
            net::Secret::Eap { identity, password: value }
        } else {
            net::Secret::Psk(value)
        };
        if let Some(rt) = &self.runtime {
            rt.service(move |ctx| net::connect(ctx, ssid, secret));
        }
        self.menu_open(Some("wifi"));
    }

    /// The device routes' rows, again from the store.
    pub fn launcher_devices(&mut self) {
        let mut moved = false;
        for (name, rows) in crate::surfaces::launcher::device_sources(&self.store) {
            moved |= self.store.menu.apply(index::Diff::Source(name.into(), rows));
        }
        if moved || self.launcher.open {
            self.launcher_store_changed();
        }
    }

    /// `menu refresh`: the base and the apps read again.
    pub fn menu_refresh(&mut self) {
        self.menu_buttons = None;
        self.menu_launches = None;
        self.launcher_inputs();
    }

    /// The store moved under an open launcher: the rows again.
    pub fn launcher_store_changed(&mut self) {
        if self.launcher.open {
            self.launcher_resolve = true;
        } else {
            self.launcher_warm = true;
        }
    }

    /// The launcher's frame, its scrim on the card's own pose.
    pub(super) fn present_launcher(&mut self, now: Instant) {
        self.launcher_answers();
        if let Some(w) = &mut self.launch {
            let want = self.launcher.open && w.shown.open && self.launcher.level.as_deref() == Some("wifi");
            if want != w.scan.is_some() {
                w.scan = want.then(crate::services::devices::network::Hold::new);
            }
        }
        if self.launch.as_ref().is_some_and(|w| w.finished(now)) {
            self.launch = None;
            self.sync_join();
            self.log("menu unmapped");
            return;
        }
        if self.launch.is_none() {
            if self.launcher_warm && !self.launcher.open {
                self.launcher_warm = false;
                self.launcher.resolve(&self.store, &self.store.theme.theme, &mut self.bar.kit);
            }
            return;
        }
        let t0 = Instant::now();
        self.resolve_launcher();
        let resolved = t0.elapsed();
        let qh = self.qh.clone();
        let theme = &self.store.theme.theme;
        let Some(w) = &mut self.launch else { return };
        let animating = w.shown.animating(now);
        let t1 = Instant::now();
        if self.launcher.dirty || animating || !w.shown.surface.mapped {
            w.shown.sync_region(&self.compositor);
            w.shown.layout(&mut self.launcher, &self.store, theme, &mut self.bar.kit, now);
            self.launcher.dirty = false;
        }
        let laid = t1.elapsed();
        let animating = w.shown.animating(now);
        w.shown.surface.present(&mut w.shown.card.scene, animating, &qh);
        if t0.elapsed().as_millis() >= 8 {
            eprintln!(
                "event loop: slow launcher t={}ms resolve_us={} layout_us={} total_us={}",
                self.started.elapsed().as_millis(),
                resolved.as_micros(),
                laid.as_micros(),
                t0.elapsed().as_micros()
            );
        }
        let pose = w.shown.card.pose(now);
        let attach = w.shown.card.attach(now);
        if let Some(b) = &mut w.band {
            b.present(w.tone * pose * (1.0 - attach), animating, &qh);
        }
        w.dim.present(w.tone * pose, animating, &qh);
        if animating {
            self.sync_join();
        }
    }

    pub(super) fn launcher_owner(&self, surface: &smithay_client_toolkit::reexports::client::protocol::wl_surface::WlSurface) -> Option<Owner> {
        let w = self.launch.as_ref()?;
        if w.shown.surface.layer.wl_surface() == surface {
            return Some(Owner::Launcher);
        }
        if w.dim.layer.wl_surface() == surface {
            return Some(Owner::LauncherScrim(1));
        }
        if w.band.as_ref().is_some_and(|b| b.layer.wl_surface() == surface) {
            return Some(Owner::LauncherScrim(0));
        }
        None
    }

    pub(super) fn launcher_frame(&mut self, owner: Owner, now: Instant) {
        let Some(w) = &mut self.launch else { return };
        match owner {
            Owner::Launcher => {
                let s = &mut w.shown.surface;
                s.landed(now);
                if s.mapped {
                    w.shown.card.tick(now);
                } else {
                    s.mapped = true;
                    w.shown.card.mapped(now);
                }
                self.launcher.dirty = true;
                self.sync_join();
            }
            Owner::LauncherScrim(i) => {
                let s = if i == 0 { w.band.as_mut() } else { Some(&mut w.dim) };
                if let Some(s) = s {
                    (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
                }
            }
            _ => {}
        }
    }

    pub(super) fn launcher_configure(&mut self, owner: Owner, width: i32, height: i32) {
        let Some(w) = &mut self.launch else { return };
        match owner {
            Owner::Launcher => {
                let size = w.shown.card.scene.size;
                w.shown.surface.configure(size.w, size.h);
                self.launcher.dirty = true;
            }
            Owner::LauncherScrim(0) => {
                if let Some(b) = &mut w.band {
                    b.configure(width, height);
                }
            }
            Owner::LauncherScrim(_) => w.dim.configure(width, height),
            _ => {}
        }
    }

    pub(super) fn launcher_closed(&mut self) {
        self.launch = None;
        self.launcher.close();
        self.sync_join();
    }

    /// One key while the launcher holds the keyboard. False when it is not
    /// up, so the key goes on to the panel.
    pub(super) fn launcher_key(&mut self, event: &KeyEvent, repeat: bool) -> bool {
        if !self.launcher.open || self.launch.as_ref().is_none_or(|w| !w.shown.open) {
            return false;
        }
        let key = match event.keysym {
            Keysym::Up => nav::Key::Up,
            Keysym::Down => nav::Key::Down,
            Keysym::Left => nav::Key::Left,
            Keysym::Right => nav::Key::Right,
            Keysym::Page_Up => nav::Key::PageUp,
            Keysym::Page_Down => nav::Key::PageDown,
            Keysym::Home => nav::Key::Home,
            Keysym::End => nav::Key::End,
            Keysym::Return => nav::Key::Return,
            Keysym::KP_Enter => nav::Key::Enter,
            Keysym::Escape => nav::Key::Escape,
            Keysym::BackSpace => nav::Key::Backspace,
            Keysym::Tab => nav::Key::Tab,
            Keysym::ISO_Left_Tab => nav::Key::Backtab,
            _ => nav::Key::Other,
        };
        let text = event.utf8.as_deref().filter(|t| t.chars().all(|c| c as u32 >= 0x20 && c != '\u{7f}') && !t.is_empty());
        self.resolve_launcher();
        let out = self.launcher.key(&self.store, key, self.mods, repeat, text);
        self.launcher_resolve = true;
        self.launcher_out(out);
        true
    }

    /// The pointer over the launcher's window. True when it took the event.
    pub(super) fn launcher_pointer(&mut self, e: &PointerEvent, owner: Option<Owner>) -> bool {
        if owner != Some(Owner::Launcher) {
            return false;
        }
        let Some(w) = &mut self.launch else { return true };
        let (x, y) = e.position;
        match e.kind {
            PointerEventKind::Enter { .. } | PointerEventKind::Motion { .. } => {
                let hit = w.shown.hit(x, y);
                if w.shown.set_hover(hit.as_ref().map(|h| h.path.clone())) {
                    self.launcher.dirty = true;
                }
                if let Some(i) = hit.and_then(|h| h.on).and_then(|on| on.strip_prefix("row:").and_then(|i| i.parse::<usize>().ok())) {
                    self.launcher.set_cursor(i);
                }
            }
            PointerEventKind::Leave { .. } => {
                if w.shown.set_hover(None) {
                    self.launcher.dirty = true;
                }
            }
            PointerEventKind::Press { .. } => {
                w.pressed = w.shown.hit(x, y).and_then(|h| h.on).or_else(|| (!w.shown.on_card(x, y)).then(|| "outside".into()));
            }
            PointerEventKind::Release { .. } => {
                let pressed = w.pressed.take();
                let on = w.shown.hit(x, y).and_then(|h| h.on).or_else(|| (!w.shown.on_card(x, y)).then(|| "outside".into()));
                if pressed.is_none() || pressed != on {
                    return true;
                }
                match on.as_deref() {
                    Some("outside" | "close") => self.menu_close(),
                    Some("back") => {
                        let out = self.launcher.key(&self.store, nav::Key::Escape, nav::Modifiers::default(), false, None);
                        self.launcher_out(out);
                    }
                    Some("primary") => {
                        let i = self.launcher.cursor;
                        self.menu_activate(i, false);
                    }
                    Some(r) => {
                        if let Some(i) = r.strip_prefix("row:").and_then(|i| i.parse::<usize>().ok()) {
                            self.menu_activate(i, false);
                        }
                    }
                    None => {}
                }
            }
            PointerEventKind::Axis { vertical, .. } => {
                let v = if vertical.discrete != 0 { vertical.discrete as f64 } else { vertical.absolute / 15.0 };
                if v != 0.0 {
                    self.launcher.wheel(v.signum() as i32);
                }
            }
        }
        true
    }

    pub(super) fn launcher_joins(&self) -> Vec<(Edge, f64, f64, f64)> {
        self.launch.as_ref().map_or_else(Vec::new, |w| w.shown.card.joins.iter().map(|j| (j.edge, j.x, j.width, j.reach)).collect())
    }

    /// The tray route's rows, off the tray the bar already holds.
    pub fn launcher_tray(&mut self) {
        let items: Vec<fs_menu::providers::TrayItem> = self
            .store
            .tray
            .items
            .iter()
            .map(|i| fs_menu::providers::TrayItem { id: i.id.clone(), title: i.title.clone(), tooltip_title: i.tooltip.clone() })
            .collect();
        let rows = fs_menu::providers::tray_provider(&items, index::SELF);
        if self.store.menu.apply(index::Diff::Source("tray".into(), rows)) {
            self.launcher_store_changed();
        }
    }

    /// What every store change the launcher's index reads asks of it.
    pub fn launcher_inputs(&mut self) {
        let buttons = self.store.config.get("menu.customPowerButtons").cloned().unwrap_or_default();
        if self.menu_buttons.as_ref() != Some(&buttons) || !self.store.config.loaded {
            self.menu_buttons = Some(buttons.clone());
            index::ask(Ask::Base(buttons));
        }
        let launches = self.store.state.data.app_launches.clone();
        if self.menu_launches.as_ref() != Some(&launches) {
            self.menu_launches = Some(launches);
            index::ask(Ask::Apps(crate::surfaces::launcher::launches(&self.store)));
        }
    }
}
