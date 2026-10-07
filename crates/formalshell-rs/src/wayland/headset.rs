//! The headset connect card (new in the Rust shell, after macOS's AirPods
//! popup): when a Bluetooth audio device goes from disconnected to
//! connected, a card buds off the bar's line in the joined-shape motion
//! with the device's icon, its name over "Connected" and one battery ring
//! per part that reports a level. It never fires for a device already
//! connected when the shell started or one that reconnects inside
//! `RECONNECT`, holds `HOLD` while the pointer is off it, dismisses on the
//! pointer leaving it or on Escape (the card takes the keyboard only while
//! the pointer is on it), opens the earbuds or Bluetooth panel on
//! a click, and stays down under fullscreen and do-not-disturb.
//!
//! While the card is up it holds the earbuds service, which is what makes a
//! backend report its parts; the hold ends with the card.

use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};

use fs_chrome::types::Edge;
use smithay_client_toolkit::reexports::client::protocol::wl_surface;
use smithay_client_toolkit::seat::keyboard::{KeyEvent, Keysym};
use smithay_client_toolkit::seat::pointer::PointerEventKind;
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::{KeyboardInteractivity, Layer};

use super::{App, Owner};
use crate::services::devices::earbuds;
use crate::surfaces::headset;
use crate::surfaces::popup::Popup;

const HOLD: Duration = Duration::from_secs(4);
const RECONNECT: Duration = Duration::from_secs(3);

struct Known {
    connected: bool,
    lost_at: Option<Instant>,
}

pub(super) struct Shown {
    popup: Popup,
    address: String,
    /// The hold's end; none while the pointer is on the card.
    hold_until: Option<Instant>,
    entered: bool,
    pressed: bool,
    /// The earbuds service is held on this card's account.
    held: bool,
    focused: bool,
}

#[derive(Default)]
pub struct Headset {
    pub(super) card: Option<Shown>,
    known: HashMap<String, Known>,
    /// The first Bluetooth reading has been seen: what it holds connected
    /// was connected at startup.
    primed: bool,
}

impl Headset {
    pub fn wake(&self) -> Option<Instant> {
        self.card.as_ref().and_then(|c| c.hold_until)
    }

    /// The gaps this card opens in the lines, for the bar to take.
    pub fn joins(&self) -> Vec<(Edge, f64, f64, f64)> {
        self.card.iter().flat_map(|c| c.popup.card.joins.iter().map(|j| (j.edge, j.x, j.width, j.reach))).collect()
    }
}

impl Shown {
    fn release(&mut self) {
        if std::mem::take(&mut self.held) {
            earbuds::release();
        }
    }
}

impl Drop for Shown {
    fn drop(&mut self) {
        self.release();
    }
}

impl App {
    /// The Bluetooth audio devices moved: a disconnected one that is now
    /// connected earns a card.
    pub fn headset_devices(&mut self) {
        let Some(list) = self.store.devices.bluetooth.headsets.clone() else { return };
        let now = Instant::now();
        let first = !std::mem::replace(&mut self.headset.primed, true);
        let mut show = None;
        let mut seen = HashSet::new();
        for h in &list {
            seen.insert(h.address.clone());
            let k = self.headset.known.entry(h.address.clone()).or_insert(Known { connected: false, lost_at: None });
            if h.connected && !k.connected && !first && !k.lost_at.is_some_and(|t| now.duration_since(t) < RECONNECT) {
                show = Some(h.address.clone());
            }
            if !h.connected && k.connected {
                k.lost_at = Some(now);
            }
            k.connected = h.connected;
        }
        for (address, k) in &mut self.headset.known {
            if !seen.contains(address) && k.connected {
                k.connected = false;
                k.lost_at = Some(now);
            }
        }
        let gone = self.headset.card.as_ref().is_some_and(|c| self.headset.known.get(&c.address).is_none_or(|k| !k.connected));
        if gone {
            self.headset_dismiss(now);
        }
        if let Some(address) = show {
            self.headset_show(&address, now);
        }
    }

    fn headset_down(&self) -> bool {
        self.store.state.data.dnd || self.chrome_hidden()
    }

    fn headset_show(&mut self, address: &str, now: Instant) {
        if self.headset_down() {
            return;
        }
        if let Some(c) = &mut self.headset.card {
            c.address = address.to_owned();
            c.hold_until = (!c.entered).then_some(now + HOLD);
            if !c.popup.is_open() {
                c.popup.set_open(now, true);
            }
            if !c.held {
                c.held = true;
                earbuds::acquire();
            }
            return;
        }
        let theme = &self.store.theme.theme;
        let face = headset::face(&self.store, address);
        let width = theme.space.popup_width_narrow;
        let height = headset::height(&face, width, theme, &mut self.bar.kit);
        let anchor = self.bar.length() as f64 / 2.0;
        let mut card = self.new_card(anchor, (width, height));
        card.ends = self.panel_place(None, false).ends;
        let surface = self.popout_surface(&card, Layer::Top);
        let mut popup = Popup::new(surface, card);
        popup.set_open(now, true);
        earbuds::acquire();
        self.headset.card = Some(Shown {
            popup,
            address: address.to_owned(),
            hold_until: Some(now + HOLD),
            entered: false,
            pressed: false,
            held: true,
            focused: false,
        });
        self.log("headset card mapped");
    }

    fn headset_dismiss(&mut self, now: Instant) {
        if let Some(c) = &mut self.headset.card {
            c.hold_until = None;
            c.popup.set_keyboard(KeyboardInteractivity::None);
            c.release();
            if c.popup.is_open() {
                c.popup.set_open(now, false);
            }
        }
    }

    pub(super) fn headset_frame(&mut self, now: Instant) {
        if let Some(c) = &mut self.headset.card {
            c.popup.frame(now);
        }
        self.sync_join();
    }

    pub(super) fn headset_configure(&mut self) {
        if let Some(c) = &mut self.headset.card {
            c.popup.configure();
        }
    }

    /// The pointer on the card: entering holds it, leaving lets it go, a
    /// press and release on it opens the device's panel.
    pub(super) fn headset_pointer(&mut self, owner: Option<Owner>, kind: &PointerEventKind) {
        if owner != Some(Owner::Headset) {
            return;
        }
        let now = Instant::now();
        let Some(c) = &mut self.headset.card else { return };
        match kind {
            PointerEventKind::Enter { .. } => {
                c.entered = true;
                c.hold_until = None;
                // Exclusive would pin the pointer to the card, so Escape rides on-demand focus.
                c.popup.set_keyboard(KeyboardInteractivity::OnDemand);
            }
            PointerEventKind::Leave { .. } => {
                c.pressed = false;
                if c.entered {
                    self.headset_dismiss(now);
                }
            }
            PointerEventKind::Press { .. } => c.pressed = true,
            PointerEventKind::Release { .. } => {
                if std::mem::take(&mut c.pressed) && c.popup.is_open() {
                    let panel = headset::face(&self.store, &c.address).panel;
                    let anchor = self.bar.length() as f64 / 2.0;
                    self.headset_dismiss(now);
                    self.set_panel(panel, true, Some(anchor));
                }
            }
            _ => {}
        }
    }

    pub(super) fn headset_focus(&mut self, surface: &wl_surface::WlSurface, on: bool) {
        let mine = self.owner(surface) == Some(Owner::Headset);
        if let Some(c) = self.headset.card.as_mut().filter(|_| mine) {
            c.focused = on;
        }
    }

    /// Escape on the card's own keyboard focus; true when the key was its.
    pub(super) fn headset_key(&mut self, event: &KeyEvent) -> bool {
        if !self.headset.card.as_ref().is_some_and(|c| c.focused) {
            return false;
        }
        if event.keysym == Keysym::Escape {
            self.headset_dismiss(Instant::now());
        }
        true
    }

    pub(super) fn headset_present(&mut self, now: Instant) {
        let down = self.headset_down();
        let Some(c) = &mut self.headset.card else { return };
        if c.popup.is_open() && (down || c.hold_until.is_some_and(|t| t <= now)) {
            self.headset_dismiss(now);
        }
        let Some(c) = &mut self.headset.card else { return };
        if c.popup.finished(now) {
            self.headset.card = None;
            self.sync_join();
            self.log("headset card unmapped");
            return;
        }
        let open = c.popup.is_open();
        c.popup.sync_region(&self.compositor, open);
        let face = headset::face(&self.store, &c.address);
        let theme = &self.store.theme.theme;
        let inner = c.popup.inner(theme);
        let (el, rect) = headset::left(&face, inner, theme, &mut self.bar.kit);
        let drawn = c.popup.draw_in(&el, rect, theme, &mut self.bar.kit, now);
        {
            let (mut painter, alpha) = c.popup.painter();
            headset::paint_rings(&mut painter, alpha, &face, inner, theme, &mut self.bar.kit);
            painter.finish();
        }
        let animating = c.popup.animating(now) || drawn.animating;
        let qh = self.qh.clone();
        c.popup.present(animating, &qh);
    }

    pub(super) fn headset_owns(&self, surface: &wl_surface::WlSurface) -> bool {
        self.headset.card.as_ref().is_some_and(|c| c.popup.surface.layer.wl_surface() == surface)
    }
}
