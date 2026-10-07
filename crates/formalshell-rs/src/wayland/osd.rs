//! The bottom-centre volume, brightness and media pill, one
//! `popupWidthNarrow` card out of the bottom edge's line, no keyboard focus
//! and no pointer input at all, gone `HIDE` after the last trigger. The
//! layer surface exists only while the card is drawn, and is a band along
//! the bottom rather than the whole output: it has to reach the line the
//! pill buds off and cover its silhouette, which is the pill, the room it
//! rests off the line and a fillet either side of it, and nothing above
//! that. The pill's own height again on top is room for the travel's
//! overshoot and the deform's stretch.
//!
//! The volume kind shows itself whenever the default sink's volume or mute
//! changes, ours or external (`wpctl`, a hardware key). Brightness and
//! media only ever show over IPC: a brightness keybind runs `brightnessctl`
//! itself first.

use std::time::{Duration, Instant};

use fs_chrome::types::Edge;
use smithay_client_toolkit::reexports::client::protocol::wl_surface;
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::{Anchor, Layer};
use vello_cpu::kurbo::Rect;

use super::App;
use crate::surface::Surface;
use crate::surfaces::card::{Card, Ends};
use crate::surfaces::osd::{self, Kind, Reading};
use crate::surfaces::popup::{self, Popup};

const HIDE: Duration = Duration::from_millis(1600);
/// Harder than a panel: the pill is small, it travels its whole height,
/// and 0.25 is what caelestia gives an OSD.
const DEFORM: f64 = 0.25;

#[derive(Default)]
pub struct Osd {
    pub(super) pill: Option<Popup>,
    kind: Option<Kind>,
    media: String,
    hide_at: Option<Instant>,
    /// The sink's last reading, for the change that fires the pill.
    audio_seen: Option<(f64, bool)>,
}

impl App {
    pub fn osd_show(&mut self, kind: Kind, text: &str) {
        let now = Instant::now();
        self.osd.kind = Some(kind);
        if kind == Kind::Media {
            self.osd.media = text.to_owned();
        }
        self.osd.hide_at = Some(now + HIDE);
        match &mut self.osd.pill {
            Some(p) => {
                if !p.is_open() {
                    p.set_open(now, true);
                }
            }
            None => self.osd_create(),
        }
    }

    pub fn osd_close(&mut self) {
        self.osd.hide_at = None;
        self.osd.kind = None;
        if let Some(p) = &mut self.osd.pill {
            p.set_open(Instant::now(), false);
        }
    }

    /// The OSD's `state` over IPC.
    pub fn osd_state(&self) -> String {
        let visible = self.osd.pill.is_some();
        let kind = self.osd.kind.map_or("", Kind::name);
        format!(
            r#"{{"visible":{visible},"kind":"{kind}","mediaText":{}}}"#,
            serde_json::Value::String(self.osd.media.clone())
        )
    }

    /// The default sink moved: ours, or something else's.
    pub fn osd_audio(&mut self) {
        let a = &self.store.devices.audio;
        let reading = a.volume.map(|v| (v, a.muted));
        let before = std::mem::replace(&mut self.osd.audio_seen, reading);
        if let (Some(b), Some(n)) = (before, reading)
            && b != n
        {
            self.osd_show(Kind::Volume, "");
        }
    }

    fn osd_reading(&self) -> Reading {
        let audio = &self.store.devices.audio;
        Reading {
            kind: self.osd.kind.unwrap_or(Kind::Volume),
            media: self.osd.media.clone(),
            volume: audio.volume.unwrap_or(0.0),
            muted: audio.muted,
            brightness: self.store.brightness.percent,
        }
    }

    /// What the bottom edge carries: the bar's strip on a bottom bar, the
    /// frame ring's band with a frame, nothing on a bare edge.
    fn bottom_inset(&self) -> f64 {
        let bar = &self.bar;
        if bar.edge() == Edge::Bottom {
            bar.thickness() as f64
        } else if bar.framed() {
            bar.frame_thickness()
        } else {
            0.0
        }
    }

    fn osd_create(&mut self) {
        let (out_w, out_h) = self.output_size();
        if out_w <= 0.0 || out_h <= 0.0 {
            return;
        }
        let theme = &self.store.theme.theme;
        let pad = theme.space.panel_padding;
        let width = theme.space.popup_width_narrow;
        let reading = self.osd_reading();
        let el = osd::content(&reading, theme, &mut self.bar.kit, width - pad * 2.0);
        let height = popup::content_height(&el, width - pad * 2.0, theme, &mut self.bar.kit) + pad * 2.0;
        let inset = self.bottom_inset();
        let rest = inset + theme.space.screen_padding;
        let band = out_h.min(rest + height * 2.0);
        let u = ((out_w - width) / 2.0).round();
        let rest_rect = Rect::new(u, rest, u + width, rest + height);
        let mut card =
            Card::build(theme, "card", Edge::Bottom, (out_w as i32, band as i32), inset, rest_rect, self.motion_scale, self.cast, true);
        let ft = if self.bar.framed() { self.bar.frame_thickness() } else { 0.0 };
        card.ends = Ends { along: out_w, inset_start: ft, inset_end: ft, radius: if self.bar.framed() { theme.frame_radius } else { 0.0 } };
        card.deform_amount = DEFORM;
        let layer = self.overlay("formalshell:osd", Layer::Overlay, Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT, (0, band as u32), -1);
        let surface = Surface::new("osd", layer, &self.shm, self.started);
        let mut popup = Popup::new(surface, card);
        popup.set_open(Instant::now(), true);
        self.osd.pill = Some(popup);
        self.log("osd mapped");
    }

    pub(super) fn osd_frame(&mut self, now: Instant) {
        if let Some(p) = &mut self.osd.pill {
            p.frame(now);
        }
        self.sync_join();
    }

    pub(super) fn osd_owns(&self, surface: &wl_surface::WlSurface) -> bool {
        self.osd.pill.as_ref().is_some_and(|p| p.surface.layer.wl_surface() == surface)
    }

    /// The gaps the pill and the headset card open in the lines.
    pub(super) fn popup_joins(&self) -> Vec<(Edge, f64, f64, f64)> {
        let mut joins = self.headset.joins();
        if let Some(p) = &self.osd.pill {
            joins.extend(p.card.joins.iter().map(|j| (j.edge, j.x, j.width, j.reach)));
        }
        joins
    }

    pub(super) fn osd_configure(&mut self) {
        if let Some(p) = &mut self.osd.pill {
            p.configure();
        }
    }

    pub(super) fn osd_wake(&self) -> Option<Instant> {
        self.osd.hide_at
    }

    pub(super) fn osd_present(&mut self, now: Instant) {
        if self.osd.hide_at.is_some_and(|t| t <= now) {
            self.osd_close();
        }
        if self.osd.pill.as_ref().is_some_and(|p| p.finished(now)) {
            self.osd.pill = None;
            self.sync_join();
            self.log("osd unmapped");
            return;
        }
        if self.osd.pill.is_none() {
            return;
        }
        let reading = self.osd_reading();
        let theme = &self.store.theme.theme;
        let qh = self.qh.clone();
        let Some(p) = &mut self.osd.pill else { return };
        let width = p.card.rest().width() - theme.space.panel_padding * 2.0;
        let el = osd::content(&reading, theme, &mut self.bar.kit, width);
        let drawn = p.draw(&el, theme, &mut self.bar.kit, now);
        let animating = p.animating(now) || drawn.animating;
        p.present(animating, &qh);
    }
}
