//! IphonePanel.qml: the popout behind the iPhone cell. Honest states first
//! (no bridge on PATH, a bridge whose daemon is not running, a daemon with
//! no phone bonded, which offers Pair with the code the phone shows), then
//! the phone itself, the Focus line worded as an inference (ANCS carries no
//! Focus state, only the `silent` flag a Focus intercept sets), Recent with
//! each notification's phone-side actions and a dismiss synced back to the
//! phone, and the phone's own now-playing with its three transport buttons.
//!
//! The cursor walks Recent by notification id, so a row arriving mid-session
//! never slides the highlight onto another notification. Enter fires a row's
//! positive action, `x` dismisses it, and the transport group and the Pair
//! button are stops of their own; Left and Right step the group's option.

use std::cell::Cell;

use fs_devices::iphone::{self, Notification};
use fs_info::notifications::rel_time;

use super::{Effect, Panel, View};
use crate::services::ams;
use crate::services::info::iphone::{self as service, Cmd};
use crate::services::wants::{Source, Want};
use crate::store::{Store, Topic};
use crate::ui::{El, Event, Ink, Type, Variant, Weight, What, w};
use crate::ui::el::Opt;

const TRANSPORT: [(&str, &str); 3] = [("skip-back", "prev"), ("", "toggle"), ("skip-forward", "next")];

pub struct Iphone {
    _want: Want,
    /// The transport option the cursor sits on.
    np_index: usize,
    /// Whether the cursor is on the transport group, read off the last
    /// body: Left and Right step an option there and walk elsewhere.
    np_on: Cell<bool>,
}

impl Default for Iphone {
    fn default() -> Self {
        Self { _want: Want::new(Source::Iphone), np_index: 1, np_on: Cell::new(false) }
    }
}

fn now_ms() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64)
}

/// The service's error, else the Apple Media Service's own (the two share
/// one line, as IphoneService.lastError does).
pub fn last_error(store: &Store) -> String {
    let s = &store.info.iphone;
    if s.last_error.is_empty() { store.media.ams.error.clone() } else { s.last_error.clone() }
}

fn press(index: usize) {
    if let Some((_, verb)) = TRANSPORT.get(index) {
        ams::command(verb);
    }
}

fn row(v: &View, entry: &Notification, ruled: bool, now: i64) -> El {
    let s = &v.theme.space;
    let summary = if !entry.title.is_empty() {
        entry.title.clone()
    } else {
        let label = iphone::category_label(entry.category);
        if label.is_empty() { entry.app_name.clone() } else { label.to_owned() }
    };
    let body = if entry.subtitle.is_empty() { entry.body.clone() } else { format!("{}\n{}", entry.subtitle, entry.body) };
    let mut head = vec![w::icon(iphone::app_icon(&entry.bundle_id, entry.category)).ink(Ink::Dim), w::section_label(s, &entry.app_name, None, false)];
    if entry.ts > 0.0 {
        head.push(w::value(rel_time(now, entry.ts as i64)).size(Type::Caption).ink(Ink::Muted));
    }
    let mut col = Vec::new();
    if ruled {
        col.push(w::separator());
    }
    col.push(w::row(s.icon_gap, vec![w::row(s.icon_gap, head).fill(), w::icon_button("x").on(format!("dismiss:{}", entry.id))]).fill());
    col.push(w::para(summary, Type::Body, Weight::Medium, Ink::Fg, 2));
    if !body.trim().is_empty() {
        col.push(w::para(body, Type::BodySmall, Weight::Normal, Ink::Dim, 2));
    }
    let mut actions = Vec::new();
    if !entry.positive_action.is_empty() {
        actions.push(w::button(&entry.positive_action).variant(Variant::Outline).on(format!("pos:{}", entry.id)));
    }
    if !entry.negative_action.is_empty() {
        actions.push(w::button(&entry.negative_action).variant(Variant::Outline).on(format!("neg:{}", entry.id)));
    }
    if !actions.is_empty() {
        col.push(w::row(s.sm, actions).pad(0.0, 0.0, 0.0, s.row_gap));
    }
    w::cell(w::column(s.xxs, col)).ghost().interactive().stop(format!("n:{}", entry.id))
}

impl Panel for Iphone {
    fn id(&self) -> &'static str {
        "iphone"
    }

    fn title(&self, _: &View) -> String {
        "iPhone".into()
    }

    fn icon(&self, _: &View) -> String {
        "smartphone".into()
    }

    fn reads(&self) -> &'static [Topic] {
        &[Topic::Info, Topic::Media, Topic::Clock]
    }

    fn opened(&mut self) {
        service::command(Cmd::MarkRead);
    }

    fn actions(&self, v: &View) -> Vec<El> {
        if v.store.info.iphone.recent.is_empty() {
            return Vec::new();
        }
        vec![w::icon_button("trash").tip("Clear all").on("clear").key("clear")]
    }

    fn steps(&self) -> bool {
        self.np_on.get()
    }

    fn body(&self, v: &View) -> El {
        let s = &v.theme.space;
        let st = &v.store.info.iphone;
        let ams = &v.store.media.ams;
        self.np_on.set(v.cursor == Some("np"));
        let not_installed = !st.installed;
        let daemon_down = st.installed && !st.observer;
        let no_phone = st.observer && !st.connected;
        let connected = st.connected;
        let pairing = st.advertising || !st.pairing_code.is_empty();
        let stale_bond = no_phone && st.bonded;
        let now_playing = connected && ams.available && !ams.title.is_empty();
        let name = if st.device_name.is_empty() { "iPhone".to_owned() } else { st.device_name.clone() };
        let error = last_error(v.store);

        let mut parts: Vec<El> = Vec::new();
        if not_installed {
            parts.push(w::section_label(s, "No bridge on PATH", None, true));
        }
        if daemon_down {
            parts.push(w::column(
                s.xxs,
                vec![
                    w::section_label(s, "Bridge not running", None, true),
                    w::para("Enable services.formalshell.iphone.enable and rebuild", Type::BodySmall, Weight::Normal, Ink::Muted, 4).pad_start(s.control_padding_x),
                ],
            ));
        }
        if !error.is_empty() && !not_installed && !daemon_down {
            parts.push(w::para(error, Type::BodySmall, Weight::Normal, Ink::Destructive, 4).pad_start(s.control_padding_x));
        }
        if connected && !pairing {
            let pct = st.battery.map(|b| format!("{}%", (b * 100.0 + 0.5).floor()));
            parts.push(w::hero(
                s,
                w::Hero {
                    glyph: "smartphone".into(),
                    title: name.clone(),
                    meta: "Connected".into(),
                    readout: pct.unwrap_or_default(),
                    trailing: None,
                    rail: st.battery,
                    rail_on: None,
                },
            ));
        }
        if no_phone || pairing {
            let title = if connected && !st.device_name.is_empty() {
                format!("Pairing with {}", st.device_name)
            } else if stale_bond {
                format!("{name} not connected")
            } else {
                "No phone paired".into()
            };
            let meta = if !st.pairing_code.is_empty() {
                "Check this matches the code on your iPhone"
            } else if pairing {
                "Advertising for pairing"
            } else if stale_bond {
                "Paired here, not on the phone? Pair again"
            } else {
                "Not paired"
            };
            parts.push(w::hero_with(
                s,
                w::Hero { glyph: "smartphone".into(), title, meta: meta.into(), readout: st.pairing_code.clone(), trailing: None, rail: None, rail_on: None },
                false,
                Type::DisplayLarge,
                None,
            ));
        }
        if connected && st.in_focus {
            parts.push(w::row(
                s.icon_gap,
                vec![
                    w::icon("moon").ink(Ink::Muted),
                    w::para("Focus likely on, so notifications are held back", Type::BodySmall, Weight::Normal, Ink::Muted, 4),
                ],
            ));
        }
        if connected || no_phone {
            let now = now_ms();
            let mut list = vec![w::section_label(s, "Recent", Some(st.recent.len()), true)];
            if st.recent.is_empty() {
                list.push(w::section_label(s, "None", None, true));
            }
            let rows = st.recent.iter().enumerate().map(|(i, e)| row(v, e, i > 0, now)).collect();
            list.push(w::column(0.0, rows));
            parts.push(w::column(s.row_gap, list));
        }
        if connected {
            let mut np = vec![w::section_label(s, "Now playing", None, true)];
            if !now_playing {
                np.push(w::section_label(s, "Not available yet", None, true));
            } else {
                let mut lines = vec![w::label(&ams.title).elide().pad(s.control_padding_x, 0.0, s.control_padding_x, 0.0)];
                if !ams.artist.is_empty() {
                    lines.push(w::value(&ams.artist).size(Type::BodySmall).ink(Ink::Muted).elide().pad(s.control_padding_x, 0.0, s.control_padding_x, 0.0));
                }
                let toggle = if ams.playback == "playing" { "pause" } else { "play" };
                let options = TRANSPORT
                    .iter()
                    .map(|(glyph, verb)| Opt::new("").icon(if *verb == "toggle" { toggle } else { glyph }))
                    .collect();
                let group = w::group(options, 0, false).ring(self.np_index);
                lines.push(group.hug().pad_start(s.control_padding_x).stop("np").on("np"));
                np.push(w::column(s.xxs, lines));
            }
            parts.push(w::column(s.row_gap, np));
        }
        if no_phone {
            parts.push(w::separator());
            let label = if pairing {
                "Pairing"
            } else if stale_bond {
                "Pair again"
            } else {
                "Pair"
            };
            parts.push(w::icon_text_button("smartphone", label).variant(Variant::Outline).enabled(!pairing).stop("pair").on("pair"));
        }
        w::column(s.section_gap, parts)
    }

    fn event(&mut self, ev: &Event, fx: &mut Effect) {
        let id = |prefix: &str| ev.on.strip_prefix(prefix).and_then(|i| i.parse::<i64>().ok());
        if let Some(id) = id("dismiss:") {
            service::command(Cmd::Dismiss(id));
        } else if let Some(id) = id("pos:") {
            service::command(Cmd::Invoke { id, positive: true });
        } else if let Some(id) = id("neg:") {
            service::command(Cmd::Invoke { id, positive: false });
        } else {
            match (ev.on.as_str(), &ev.what) {
                ("clear", _) => service::command(Cmd::Clear),
                ("pair", _) => service::command(Cmd::Pair),
                ("np", What::Pick(i)) => {
                    self.np_index = *i;
                    press(*i);
                }
                _ => {}
            }
        }
        let _ = fx;
    }

    fn activate(&mut self, stop: &str, fx: &mut Effect) {
        if let Some(id) = stop.strip_prefix("n:").and_then(|i| i.parse::<i64>().ok()) {
            let positive = fx.store.info.iphone.recent.iter().find(|e| e.id == id).is_some_and(|e| !e.positive_action.is_empty());
            if positive {
                service::command(Cmd::Invoke { id, positive: true });
            }
        } else if stop == "np" {
            press(self.np_index);
        } else if stop == "pair" {
            service::command(Cmd::Pair);
        }
    }

    fn step(&mut self, stop: &str, direction: i32, _: &mut Effect) {
        if stop == "np" {
            self.np_index = (self.np_index as i32 + direction).clamp(0, TRANSPORT.len() as i32 - 1) as usize;
        }
    }

    fn delete(&mut self, stop: &str, _: &mut Effect) {
        if let Some(id) = stop.strip_prefix("n:").and_then(|i| i.parse::<i64>().ok()) {
            service::command(Cmd::Dismiss(id));
        }
    }
}
