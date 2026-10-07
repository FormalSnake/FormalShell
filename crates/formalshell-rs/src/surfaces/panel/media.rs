//! MediaPanel.qml: the active source's now-playing column. The source menu
//! trigger (Auto or a pinned pick) with its menu inline under it, the cover
//! beside the title, artist and album with the spectrum at the row's
//! trailing end, the position row (elapsed, the track, total) and the
//! transport beside the player's own volume.
//!
//! Every control is gated on what the source can do: no seek makes the
//! position row a readout, no shuffle or loop leaves those buttons out, no
//! volume leaves the volume out, AirPlay gets no transport at all (UxPlay
//! takes no remote command), and no source at all is the dim `No player`.
//!
//! The panel redraws on its own once per elapsed second while playing,
//! which keeps the readout and the fill on the position `media status`
//! reports; nothing ticks while paused.

use std::cell::Cell;
use std::time::{Duration, Instant};

use fs_media::visualizer::styles;

use super::{Effect, Panel, View};
use crate::services::media::Active;
use crate::services::visualizer::{self, Avail};
use crate::store::{self, Topic};
use crate::ui::el::Opt;
use crate::ui::{El, Event, Ink, Type, What, w};

const SEEK_STEP: f64 = 5.0;
const VOLUME_STEP: f64 = 0.05;
const SPECTRUM_COLUMNS: usize = 12;

pub struct Media {
    menu: bool,
    /// The transport button the keyboard sits on.
    transport: usize,
    /// Whether the cursor sits on a stop Left and Right step rather than walk,
    /// read off the last body.
    stepping: Cell<bool>,
    spectrum: Cell<bool>,
    open: bool,
    /// The stops of each keyboard section present in the last body, in Tab
    /// order: the transport, the tracks, the menu.
    sections: std::cell::RefCell<Vec<Vec<String>>>,
}

impl Default for Media {
    fn default() -> Self {
        Self { menu: false, transport: 1, stepping: Cell::new(false), spectrum: Cell::new(false), open: true, sections: Default::default() }
    }
}

impl Drop for Media {
    fn drop(&mut self) {
        visualizer::set_panel(false);
    }
}

fn format_time(seconds: f64) -> String {
    let total = seconds.max(0.0).floor() as u64;
    let (h, m, s) = (total / 3600, (total / 60) % 60, total % 60);
    if h > 0 { format!("{h}:{m:02}:{s:02}") } else { format!("{m:02}:{s:02}") }
}

fn source_icon(kind: &str) -> &'static str {
    match kind {
        "radio" => "radio",
        "iphone" => "smartphone",
        "airplay" => "airplay",
        "stream" => "audio-lines",
        _ => "music",
    }
}

fn has_timeline(a: &Active) -> bool {
    a.kind == "mpris" || (a.kind == "iphone" && a.length > 0.0)
}

/// The transport, in the order the buttons draw.
fn transport(a: &Active) -> Vec<&'static str> {
    if a.kind == "stream" || a.kind == "airplay" {
        return Vec::new();
    }
    let mut out = vec!["previous", "playpause", "next"];
    if a.shuffle.is_some() {
        out.push("shuffle");
    }
    if a.loop_name.is_some() {
        out.push("loop");
    }
    out
}

fn transport_opt(a: &Active, id: &str) -> Opt {
    let icon = match id {
        "previous" => "skip-back",
        "playpause" if a.playing => "pause",
        "playpause" => "play",
        "next" => "skip-forward",
        "shuffle" => "shuffle",
        _ if a.loop_name == Some("track") => "repeat-1",
        _ => "repeat",
    };
    let mut o = Opt::new("").icon(icon);
    o.enabled = match id {
        "previous" => a.can_previous,
        "next" => a.can_next,
        _ => true,
    };
    o.active = match id {
        "shuffle" => a.shuffle == Some(true),
        "loop" => a.loop_name.is_some_and(|l| l != "none"),
        _ => false,
    };
    o
}

fn press(store: &store::Store, id: &str) {
    let m = &store.media;
    match id {
        "previous" => m.previous(),
        "playpause" => m.play_pause(),
        "next" => m.next(),
        "shuffle" => {
            if let Some(on) = m.active().and_then(|a| a.shuffle) {
                m.set_shuffle(!on);
            }
        }
        "loop" => {
            if let Some(l) = m.active().and_then(|a| a.loop_name) {
                m.set_loop(fs_media::media::next_loop(l));
            }
        }
        _ => {}
    }
}

fn spectrum_enabled(v: &View) -> bool {
    v.store.config.bool("media.visualizer").unwrap_or(true)
}

impl Media {
    fn source_menu(&self, v: &View) -> Vec<El> {
        let s = &v.theme.space;
        let m = &v.store.media;
        let mut rows = vec![("".to_owned(), "Auto".to_owned(), "", false)];
        rows.extend(m.players().into_iter().map(|p| (p.id.clone(), p.label.clone(), source_icon(&p.kind), p.is_playing)));
        rows.into_iter()
            .map(|(id, label, icon, playing)| {
                let current = m.selected == id;
                let glyph = if current { "check" } else { icon };
                let mut parts = vec![
                    w::icon(if glyph.is_empty() { "check" } else { glyph })
                        .size(Type::BodySmall)
                        .ink(if glyph.is_empty() { Ink::Color(fs_theme::color::Rgba::TRANSPARENT) } else { Ink::Fg }),
                    w::text(label).size(Type::BodySmall),
                ];
                if playing {
                    parts.push(w::icon("play").size(Type::Caption).ink(Ink::Muted));
                }
                w::cell(w::row(s.icon_gap, parts)).selected(current).interactive().stop(format!("pick:{id}")).on(format!("pick:{id}"))
            })
            .collect()
    }

    fn pick(&mut self, id: &str, fx: &Effect) {
        let id = id.to_owned();
        fx.service(move |ctx| ctx.publish(store::Diff::Media(crate::services::media::Diff::Select(id))));
        self.menu = false;
    }

    fn step_volume(&self, fx: &Effect, by: f64) {
        if let Some(v) = fx.store.media.active().and_then(|a| a.volume) {
            fx.store.media.set_volume(v + by);
        }
    }

    fn seek_by(&self, fx: &Effect, by: f64) {
        if let Some(a) = fx.store.media.active() {
            fx.store.media.seek_to(a.position + by);
        }
    }
}

impl Panel for Media {
    fn id(&self) -> &'static str {
        "media"
    }

    fn title(&self, _: &View) -> String {
        "Media".into()
    }

    fn icon(&self, _: &View) -> String {
        "music".into()
    }

    fn reads(&self) -> &'static [Topic] {
        &[Topic::Media, Topic::Visualizer, Topic::Config]
    }

    fn width(&self, v: &View) -> f64 {
        v.theme.space.popup_width_wide
    }

    fn actions(&self, v: &View) -> Vec<El> {
        match v.store.media.active() {
            Some(a) if a.can_raise => vec![w::icon_button("external-link").on("raise").key("raise")],
            _ => Vec::new(),
        }
    }

    fn opened(&mut self) {
        self.menu = false;
        self.transport = 1;
    }

    fn closed(&mut self) {
        self.open = false;
        visualizer::set_panel(false);
    }

    fn start(&mut self, fx: &mut Effect) {
        let on = fx.store.config.bool("media.visualizer").unwrap_or(true);
        self.spectrum.set(on);
        visualizer::set_panel(on);
    }

    fn cursor_start(&self) -> Option<String> {
        Some("transport".into())
    }

    fn body(&self, v: &View) -> El {
        let s = &v.theme.space;
        let m = &v.store.media;
        self.stepping.set(matches!(v.cursor, Some("transport" | "progress" | "volume")));
        let enabled = spectrum_enabled(v);
        if self.open && enabled != self.spectrum.get() {
            self.spectrum.set(enabled);
            visualizer::set_panel(enabled);
        }
        let Some(a) = m.active() else {
            self.sections.borrow_mut().clear();
            return w::column(s.section_gap, vec![w::section_label(s, "No player", None, true).pad(0.0, s.sm, 0.0, s.sm)]);
        };
        let mut col = Vec::new();

        let label = m.players().into_iter().find(|r| r.id == a.id).map(|r| r.label).unwrap_or_default();
        let label = if m.selected.is_empty() { format!("Auto · {label}") } else { label };
        col.push(w::row(0.0, vec![w::trigger(s, source_icon(a.kind), &label, self.menu).stop("source").on("source")]));
        if self.menu {
            col.push(w::column(0.0, self.source_menu(v)));
        }

        let mut info = Vec::new();
        if !a.art_url.is_empty() {
            let slot = s.control_height * 3.0;
            let (px, radius) = w::cover_inner(v.theme, slot);
            info.push(w::cover(m.cover(&a.art_url, px, radius), slot));
        }
        let mut words = vec![w::label(if a.title.is_empty() { "Unknown title".to_owned() } else { a.title.clone() }).size(Type::Title).elide()];
        if !a.artist.is_empty() {
            words.push(w::text(a.artist.clone()).elide());
        }
        if !a.album.is_empty() {
            words.push(w::text(a.album.clone()).size(Type::BodySmall).ink(Ink::Muted).elide());
        }
        info.push(w::column(s.xxs, words).fill());
        let vis = &v.store.visualizer;
        if enabled && (vis.avail == Avail::Available || a.kind == "iphone") {
            let style = vis.style(v.store.config.str("media.visualizerStyle").unwrap_or("bars"));
            let tip = styles::label(&style);
            info.push(w::spectrum(style, SPECTRUM_COLUMNS, vis.running).on("spectrum").tip(tip).key("spectrum"));
        }
        col.push(w::row(s.xxl, info).fill());

        if has_timeline(&a) {
            let fraction = if a.length > 0.0 { a.position / a.length } else { 0.0 };
            let track = if a.can_seek { w::slider(fraction) } else { w::track(fraction) };
            col.push(
                w::row(
                    s.icon_gap,
                    vec![
                        w::value(format_time(a.position)).ink(Ink::Fg),
                        track.fill().stop("progress").on("progress"),
                        w::value(format_time(a.length)).ink(Ink::Muted),
                    ],
                )
                .fill()
                .pad(0.0, s.xs, 0.0, s.xs),
            );
        }

        let ids = transport(&a);
        let mut controls = Vec::new();
        if !ids.is_empty() {
            let options: Vec<Opt> = ids.iter().map(|id| transport_opt(&a, id)).collect();
            let index = self.transport.min(ids.len() - 1);
            let group = w::group(options, index, false);
            let group = match group.kind {
                crate::ui::el::Kind::Group { options, index, exclusive, .. } => {
                    El { kind: crate::ui::el::Kind::Group { options, index, exclusive, cursor_index: index }, ..group }
                }
                _ => group,
            };
            controls.push(group.hug().stop("transport").on("transport"));
        }
        if let Some(volume) = a.volume {
            if !controls.is_empty() {
                controls.push(w::space(s.section_gap - s.icon_gap));
            }
            let glyph = if volume <= 0.0 {
                "volume-x"
            } else if volume < 0.5 {
                "volume-1"
            } else {
                "volume-2"
            };
            controls.push(w::icon(glyph).ink(Ink::Muted));
            controls.push(w::slider(volume).fill().stop("volume").on("volume"));
            controls.push(w::value(format!("{}%", (volume * 100.0).round())).ink(Ink::Muted).gauge("100%"));
        }
        if !controls.is_empty() {
            col.push(w::row(s.icon_gap, controls).fill());
        }
        let mut sections = Vec::new();
        if !ids.is_empty() {
            sections.push(vec!["transport".to_owned()]);
        }
        let tracks: Vec<String> = [has_timeline(&a).then_some("progress"), a.volume.map(|_| "volume")].into_iter().flatten().map(str::to_owned).collect();
        if !tracks.is_empty() {
            sections.push(tracks);
        }
        let mut menu = vec!["source".to_owned()];
        if self.menu {
            menu.extend(std::iter::once("pick:".to_owned()).chain(m.players().into_iter().map(|p| format!("pick:{}", p.id))));
        }
        sections.push(menu);
        *self.sections.borrow_mut() = sections;
        w::column(s.section_gap, col)
    }

    fn wake(&self, v: &View) -> Option<Instant> {
        let a = v.store.media.active()?;
        if !a.playing || !has_timeline(&a) {
            return None;
        }
        let into = a.position.fract();
        Some(Instant::now() + Duration::from_secs_f64((1.0 - into).max(0.01)))
    }

    fn event(&mut self, ev: &Event, fx: &mut Effect) {
        if let Some(id) = ev.on.strip_prefix("pick:") {
            self.pick(id, fx);
            return;
        }
        let a = fx.store.media.active();
        match (ev.on.as_str(), &ev.what) {
            ("raise", _) => fx.store.media.raise(),
            ("source", _) => self.menu = !self.menu,
            ("transport", What::Pick(i)) => {
                if let Some(a) = &a
                    && let Some(id) = transport(a).get(*i)
                {
                    self.transport = *i;
                    press(fx.store, id);
                }
            }
            ("progress", What::Fraction(f)) => {
                if let Some(a) = &a {
                    fx.store.media.seek_to(f * a.length);
                }
            }
            ("progress", What::Wheel(d)) => self.seek_by(fx, *d as f64 * SEEK_STEP),
            ("volume", What::Fraction(f)) => fx.store.media.set_volume(*f),
            ("volume", What::Wheel(d)) => self.step_volume(fx, *d as f64 * VOLUME_STEP),
            ("spectrum", What::Click) => {
                let configured = fx.store.config.str("media.visualizerStyle").unwrap_or("bars").to_owned();
                let next = styles::step(&fx.store.visualizer.style(&configured), 1).to_owned();
                fx.service(move |ctx| ctx.publish(store::Diff::Visualizer(visualizer::Diff::Style(next))));
            }
            _ => {}
        }
    }

    fn activate(&mut self, stop: &str, fx: &mut Effect) {
        if let Some(id) = stop.strip_prefix("pick:") {
            self.pick(id, fx);
            return;
        }
        match stop {
            "source" => self.menu = !self.menu,
            "transport" => {
                if let Some(a) = fx.store.media.active() {
                    let ids = transport(&a);
                    if let Some(id) = ids.get(self.transport.min(ids.len().saturating_sub(1))) {
                        let enabled = transport_opt(&a, id).enabled;
                        if enabled {
                            press(fx.store, id);
                        }
                    }
                }
            }
            "progress" => fx.store.media.play_pause(),
            _ => {}
        }
    }

    fn step(&mut self, stop: &str, direction: i32, fx: &mut Effect) {
        match stop {
            "transport" => {
                let n = fx.store.media.active().map_or(0, |a| transport(&a).len());
                if n > 0 {
                    self.transport = (self.transport as i32 + direction).clamp(0, n as i32 - 1) as usize;
                }
            }
            "progress" => self.seek_by(fx, direction as f64 * SEEK_STEP),
            "volume" => self.step_volume(fx, direction as f64 * VOLUME_STEP),
            _ => {}
        }
    }

    fn tab(&mut self, stop: Option<&str>, direction: i32) -> Option<String> {
        let sections = self.sections.borrow();
        if sections.is_empty() {
            return None;
        }
        let n = sections.len() as i32;
        let at = stop.and_then(|k| sections.iter().position(|s| s.iter().any(|x| x == k))).map_or(-1, |i| i as i32);
        let next = if at < 0 { 0 } else { (at + direction).rem_euclid(n) };
        sections[next as usize].first().cloned()
    }

    fn steps(&self) -> bool {
        self.stepping.get()
    }

    fn escape(&mut self) -> bool {
        std::mem::take(&mut self.menu)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn times_read_the_way_the_panel_writes_them() {
        assert_eq!(format_time(0.0), "00:00");
        assert_eq!(format_time(65.9), "01:05");
        assert_eq!(format_time(3725.0), "1:02:05");
        assert_eq!(format_time(-3.0), "00:00");
    }

    #[test]
    fn airplay_has_no_transport_and_a_player_its_own_toggles() {
        let airplay = Active { kind: "airplay", ..Active::default() };
        assert!(transport(&airplay).is_empty());
        let mpv = Active { kind: "mpris", shuffle: Some(true), loop_name: Some("track"), ..Active::default() };
        assert_eq!(transport(&mpv), ["previous", "playpause", "next", "shuffle", "loop"]);
        assert_eq!(transport_opt(&mpv, "loop").icon, "repeat-1");
        assert!(transport_opt(&mpv, "shuffle").active);
        assert!(!transport_opt(&mpv, "next").enabled);
    }

    #[test]
    fn the_phone_has_a_timeline_only_with_a_length() {
        assert!(!has_timeline(&Active { kind: "iphone", ..Active::default() }));
        assert!(has_timeline(&Active { kind: "iphone", length: 200.0, ..Active::default() }));
        assert!(!has_timeline(&Active { kind: "radio", ..Active::default() }));
    }
}
