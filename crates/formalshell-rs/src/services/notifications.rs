//! NotificationService.qml and ReminderService.qml: `fs-notifd` serving
//! `org.freedesktop.Notifications` on the service thread, and fs-info's
//! three-tier reducer held here on the UI thread, which is its only writer.
//!
//! The server never closes anything on its own: every close the reducer
//! decides (a toast timing out, a dismiss) goes back to it as a [`Cmd`], so
//! the sender hears the right reason. A close the sender asked for, or the
//! one an action implies, comes in as [`Diff::Closed`].

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use fs_info::notifications::{self as model, Action, AddOpts, Notif, Patch, Urgency};
use fs_info::reminders;
use fs_js as js;
use fs_notifd::{CloseReason, Config, Event, Image, ImageData, Server};
use serde_json::{Value, json};

use super::state::{self, Field};
use crate::runtime::Ctx;
use crate::store;

/// Omarchy's duration bands: low 5s, normal 8s, a sender's own timeout
/// honoured inside them up to 30s.
const LOW_MS: i64 = 5000;
const NORMAL_MS: i64 = 8000;
const MAX_MS: i64 = 30000;
/// How far a hovered toast's deadline is pushed each time it comes due.
const HOVER_HOLD_MS: i64 = 1000;

pub fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64)
}

fn timeout_for(urgency: Urgency, expire_timeout: i32) -> i64 {
    let floor = if urgency == Urgency::Low { LOW_MS } else { NORMAL_MS };
    MAX_MS.min(floor.max(i64::from(expire_timeout.max(0))))
}

/// One arrival or replace, as the reducer takes it.
pub struct Arrival {
    pub notif: Notif,
    pub timeout_ms: i64,
    pub pixels: Option<Arc<ImageData>>,
    pub replaced: bool,
}

pub enum Diff {
    Arrived(Box<Arrival>),
    /// The sender closed it, or an action closed it on the server's side.
    Closed(String),
    /// The bus name could not be had: another daemon owns it.
    Unavailable(String),
}

#[derive(Default)]
pub struct State {
    pub model: model::State,
    /// Why there is no server, when there is none.
    pub unavailable: Option<String>,
    pub center_open: bool,
    /// `notifications expand on`, the rig's stand-in for hovering the stack.
    pub stack_expanded: bool,
    /// Popup ids under the pointer: their countdown holds.
    pub hovered: HashSet<String>,
    /// Decoded `image-data` hints, keyed by the entry's `image` token.
    pub pixels: HashMap<String, Arc<ImageData>>,
    local_serial: u64,
    /// state.json's dnd as last seen, so a setDnd answered here before its
    /// write lands is not rolled back by the old value.
    dnd_seen: Option<bool>,
    pub reminders: Vec<reminders::Entry>,
    reminders_seen: Option<Value>,
    reminder_serial: u64,
}

impl State {
    pub fn apply(&mut self, diff: Diff) -> bool {
        let now = now_ms();
        match diff {
            Diff::Arrived(a) => {
                let Arrival { notif, timeout_ms, pixels, replaced } = *a;
                if let Some(p) = pixels {
                    self.pixels.insert(notif.image.clone(), p);
                }
                let known = self.find(&notif.id).is_some();
                if replaced && known {
                    let patch = Patch {
                        app_name: Some(notif.app_name.clone()),
                        app_icon: Some(notif.app_icon.clone()),
                        desktop_entry: Some(notif.desktop_entry.clone()),
                        summary: Some(notif.summary.clone()),
                        body: Some(notif.body.clone()),
                        urgency: Some(notif.urgency),
                        actions: Some(notif.actions.clone()),
                        image: Some(notif.image.clone()),
                        phone: None,
                    };
                    self.model = model::update(&self.model, &notif.id, &patch, now);
                } else {
                    let opts = AddOpts { quiet: false, timeout_ms: Some(timeout_ms) };
                    self.model = model::add(&self.model, &notif, now, &opts);
                }
                self.after_change();
                true
            }
            Diff::Closed(id) => {
                self.model = model::dismiss_one(&self.model, &id);
                self.after_change();
                true
            }
            Diff::Unavailable(why) => {
                self.unavailable = Some(why);
                true
            }
        }
    }

    pub fn find(&self, id: &str) -> Option<&model::Entry> {
        let m = &self.model;
        m.popups.iter().chain(&m.pending).chain(&m.past).find(|e| e.id == id)
    }

    /// Drops decoded pixels nothing points at any more.
    fn after_change(&mut self) {
        if self.pixels.is_empty() {
            return;
        }
        let live: HashSet<&str> = {
            let m = &self.model;
            m.popups.iter().chain(&m.pending).chain(&m.past).map(|e| e.image.as_str()).collect()
        };
        self.pixels.retain(|k, _| live.contains(k.as_str()));
    }

    /// Mirrors state.json's dnd and reminders whenever the file moved.
    pub fn sync(&mut self, data: &state::Data) {
        if self.dnd_seen != Some(data.dnd) {
            self.dnd_seen = Some(data.dnd);
            self.model = model::set_dnd(&self.model, data.dnd);
        }
        if self.reminders_seen.as_ref() != Some(&data.reminders) {
            self.reminders_seen = Some(data.reminders.clone());
            self.reminders = reminders::normalize(&data.reminders);
        }
    }

    pub fn set_dnd(&mut self, on: bool) {
        self.model = model::set_dnd(&self.model, on);
        state::set(vec![Field::Dnd(on)]);
    }

    /// NotificationService.notify(): a shell-authored entry, which earns the
    /// DND bypass at urgency 2 on its own `local` marker.
    pub fn notify(&mut self, summary: &str, body: &str, urgency: Urgency) {
        self.local_serial += 1;
        let notif = Notif {
            id: format!("local-{}", self.local_serial),
            app_name: "formalshell".into(),
            summary: summary.into(),
            body: body.into(),
            urgency,
            local: true,
            ..Default::default()
        };
        self.model = model::add(&self.model, &notif, now_ms(), &AddOpts::default());
    }

    pub fn dismiss_popup(&mut self, id: &str) {
        self.hovered.remove(id);
        self.model = model::dismiss_popup(&self.model, id, now_ms());
        close(id, CloseReason::Dismissed);
    }

    pub fn dismiss_popup_group(&mut self, ids: &[String]) {
        for id in ids {
            self.dismiss_popup(id);
        }
    }

    pub fn dismiss_one(&mut self, id: &str) {
        self.model = model::dismiss_one(&self.model, id);
        self.after_change();
    }

    pub fn dismiss_group(&mut self, ids: &[String]) {
        for id in ids {
            self.dismiss_one(id);
        }
    }

    pub fn dismiss_all(&mut self) {
        self.model = model::dismiss_all(&self.model);
        self.after_change();
    }

    pub fn clear_pending(&mut self) {
        self.model = model::clear_pending(&self.model);
        self.after_change();
    }

    pub fn mark_all_seen(&mut self) {
        self.model = model::mark_all_seen(&self.model, now_ms());
    }

    pub fn set_hovered(&mut self, ids: &[String], hovered: bool) {
        for id in ids {
            if hovered {
                self.hovered.insert(id.clone());
            } else {
                self.hovered.remove(id);
            }
        }
    }

    pub fn invoke_action(&mut self, id: &str, key: &str) {
        invoke(id, key);
    }

    /// The front toast's whole group, the one its close button closes:
    /// `None` when nothing is popped up.
    pub fn front_group(&self) -> Option<Vec<String>> {
        let groups = model::group_entries(&self.model.popups);
        model::stack_order(&groups).into_iter().next().map(|g| g.member_ids)
    }

    pub fn invoke_last(&mut self) {
        let Some(target) = model::invoke_target(&self.model).cloned() else { return };
        if target.actions.iter().any(|a| a.key == "default") {
            invoke(&target.id, "default");
        }
        if self.model.popups.iter().any(|p| p.id == target.id) {
            self.dismiss_popup(&target.id);
        } else {
            self.dismiss_one(&target.id);
        }
    }

    /// The next instant something here starts on its own: a toast timing
    /// out, a seen entry aging out of the past tier, a reminder coming due.
    pub fn wake(&self) -> Option<i64> {
        let past = self.model.past.iter().map(|p| p.seen_at.unwrap_or(p.arrived_at) + model::PAST_TTL_MS).min();
        let due = self.reminders.first().map(|r| r.due_at.ceil() as i64);
        [self.model.next_expiry, past, due].into_iter().flatten().min()
    }

    /// Runs whatever came due by `now`. True when anything moved.
    pub fn tick(&mut self, now: i64) -> bool {
        let mut moved = false;
        if self.model.next_expiry.is_some_and(|t| t <= now) {
            if !self.hovered.is_empty() {
                for p in &mut self.model.popups {
                    if self.hovered.contains(&p.id) && p.expires_at.is_some_and(|t| t != 0 && t <= now) {
                        p.expires_at = Some(now + HOVER_HOLD_MS);
                    }
                }
                self.model.next_expiry = self.model.popups.iter().filter_map(|p| p.expires_at.filter(|t| *t != 0)).min();
            }
            let before: Vec<String> = self.model.popups.iter().map(|p| p.id.clone()).collect();
            let next = model::expire(&self.model, now);
            for id in before.iter().filter(|id| !next.popups.iter().any(|p| &p.id == *id)) {
                self.hovered.remove(id);
                close(id, CloseReason::Expired);
            }
            moved |= next != self.model;
            self.model = next;
        }
        let pruned = model::prune_past(&self.model, now);
        if pruned != self.model {
            self.model = pruned;
            self.after_change();
            moved = true;
        }
        let split = reminders::due(&self.reminders, now as f64);
        if !split.fired.is_empty() {
            for e in &split.fired {
                self.notify("Reminder", &e.message, Urgency::Critical);
            }
            self.store_reminders(split.remaining);
            moved = true;
        }
        moved
    }

    fn store_reminders(&mut self, list: Vec<reminders::Entry>) {
        let value = Value::Array(list.iter().map(reminder_json).collect());
        self.reminders = list;
        state::set(vec![Field::Reminders(value)]);
    }

    /// ReminderService.setFromParts(): the stored entry, or `None` when the
    /// duration does not parse.
    pub fn set_reminder(&mut self, duration: &str, message: &str, default_message: &str) -> Option<reminders::Entry> {
        let seconds = reminders::parse_duration(duration)?;
        let text = js::trim(message);
        let text = if text.is_empty() { default_message } else { text };
        self.reminder_serial += 1;
        let entry = reminders::make_entry(seconds, text, now_ms() as f64, self.reminder_serial);
        let list = reminders::add(&self.reminders, entry.clone());
        self.store_reminders(list);
        Some(entry)
    }

    pub fn clear_reminders(&mut self) -> usize {
        let dropped = self.reminders.len();
        if dropped > 0 {
            self.store_reminders(Vec::new());
        }
        dropped
    }

    pub fn show_reminders(&mut self) {
        if self.reminders.is_empty() {
            self.notify("Reminders", "None pending", Urgency::Normal);
            return;
        }
        let lines = reminders::summary_lines(&self.reminders, now_ms() as f64).join("\n");
        self.notify("Reminders", &lines, Urgency::Normal);
    }

    /// ReminderIpc.qml's `status`.
    pub fn reminder_status(&self) -> String {
        let now = now_ms() as f64;
        let items: Vec<String> = self
            .reminders
            .iter()
            .map(|e| {
                let secs = reminders::remaining_seconds(e, now);
                format!(
                    r#"{{"id":{},"message":{},"dueAt":{},"remainingSeconds":{},"remaining":{}}}"#,
                    js::stringify(&json!(e.id)),
                    js::stringify(&json!(e.message)),
                    js::num_str(e.due_at),
                    js::num_str(secs),
                    js::stringify(&json!(reminders::countdown_label(secs))),
                )
            })
            .collect();
        format!(r#"{{"count":{},"reminders":[{}]}}"#, self.reminders.len(), items.join(","))
    }
}

fn number(n: f64) -> Value {
    if n.fract() == 0.0 && n.abs() < 9e15 { json!(n as i64) } else { json!(n) }
}

fn reminder_json(e: &reminders::Entry) -> Value {
    json!({ "id": e.id, "message": e.message, "setAt": number(e.set_at), "dueAt": number(e.due_at) })
}

/// The instant `at` (epoch ms) falls on, on the monotonic clock.
pub fn instant_at(at: i64, now: Instant) -> Instant {
    let delta = at - now_ms();
    if delta <= 0 { now } else { now + Duration::from_millis(delta as u64) }
}

enum Cmd {
    Close(u32, CloseReason),
    Invoke(u32, String),
}

static CMD: OnceLock<async_channel::Sender<Cmd>> = OnceLock::new();

/// Ids the server never issued (`local-…`, `iphone-…`) have nobody to tell.
fn server_id(id: &str) -> Option<u32> {
    id.parse().ok()
}

fn close(id: &str, reason: CloseReason) {
    if let (Some(id), Some(tx)) = (server_id(id), CMD.get()) {
        let _ = tx.try_send(Cmd::Close(id, reason));
    }
}

fn invoke(id: &str, key: &str) {
    if let (Some(id), Some(tx)) = (server_id(id), CMD.get()) {
        let _ = tx.try_send(Cmd::Invoke(id, key.to_owned()));
    }
}

/// The image hint as icon.js reads it: a decoded buffer gets a token of its
/// own, a path a file url, a name the icon provider's url.
fn image_of(n: &fs_notifd::Notification) -> (String, Option<Arc<ImageData>>) {
    match &n.image {
        None => (String::new(), None),
        Some(Image::Data(d)) => (format!("image://notification/{}", n.id), Some(Arc::new(d.clone()))),
        Some(Image::Path(p)) if p.starts_with('/') => (format!("file://{p}"), None),
        Some(Image::Path(p)) => (format!("image://icon/{p}"), None),
    }
}

fn arrival(n: &fs_notifd::Notification, replaced: bool) -> Arrival {
    let urgency = match n.urgency {
        fs_notifd::Urgency::Low => Urgency::Low,
        fs_notifd::Urgency::Normal => Urgency::Normal,
        fs_notifd::Urgency::Critical => Urgency::Critical,
    };
    let (image, pixels) = image_of(n);
    Arrival {
        notif: Notif {
            id: n.id.to_string(),
            app_name: n.app_name.clone(),
            app_icon: n.app_icon.clone(),
            desktop_entry: n.desktop_entry.clone(),
            summary: n.summary.clone(),
            body: n.body.clone(),
            urgency,
            actions: n.actions.iter().map(|a| Action { key: a.key.clone(), label: a.label.clone() }).collect(),
            image,
            // Omarchy's rule: the CLI's literal default app name, nothing
            // inferred from urgency alone.
            sender_is_notify_send: n.app_name == "notify-send",
            ..Default::default()
        },
        timeout_ms: timeout_for(urgency, n.expire_timeout),
        pixels,
        replaced,
    }
}

/// The identity Quickshell's NotificationServer gives the QML shell, which
/// senders may key on: its name and version, and the capabilities its
/// flags in NotificationService.qml turn on.
fn config() -> Config {
    Config { version: QUICKSHELL_VERSION.into(), ..Config::default() }
}

const QUICKSHELL_VERSION: &str = "0.2.1";

pub async fn run(ctx: Ctx) {
    let (server, events) = match Server::start(config()).await {
        Ok(s) => s,
        Err(err) => {
            eprintln!("notifications: {err}");
            ctx.publish(store::Diff::Notifications(Diff::Unavailable(err.to_string())));
            return;
        }
    };
    let (tx, rx) = async_channel::unbounded();
    let _ = CMD.set(tx);
    let server = std::rc::Rc::new(server);
    let s = server.clone();
    let c = ctx.clone();
    ctx.spawn(async move {
        while let Ok(cmd) = rx.recv().await {
            match cmd {
                Cmd::Close(id, reason) => {
                    let _ = s.close(id, reason).await;
                }
                Cmd::Invoke(id, key) => {
                    if let Ok(true) = s.invoke_action(id, &key, None).await {
                        c.publish(store::Diff::Notifications(Diff::Closed(id.to_string())));
                    }
                }
            }
        }
    });
    while let Ok(event) = events.recv().await {
        let diff = match event {
            Event::Notified(n) => Diff::Arrived(Box::new(arrival(&n, false))),
            Event::Replaced(n) => Diff::Arrived(Box::new(arrival(&n, true))),
            Event::Closed { id } => Diff::Closed(id.to_string()),
        };
        ctx.publish(store::Diff::Notifications(diff));
    }
}

/// NotificationsIpc.qml's `status`, the centre's numbers handed in by the
/// surface that owns them.
pub fn status(s: &State, center: (f64, f64, bool)) -> String {
    format!(
        r#"{{"dnd":{},"pending":{},"popups":{},"centerOpen":{},"centerHeight":{},"centerMaxHeight":{},"centerCapped":{}}}"#,
        s.model.dnd,
        s.model.pending.len(),
        s.model.popups.len(),
        s.center_open,
        js::num_str(js::round(center.0)),
        js::num_str(js::round(center.1)),
        center.2,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duration_bands() {
        assert_eq!(timeout_for(Urgency::Low, -1), 5000);
        assert_eq!(timeout_for(Urgency::Normal, 0), 8000);
        assert_eq!(timeout_for(Urgency::Normal, 12000), 12000);
        assert_eq!(timeout_for(Urgency::Normal, 90000), 30000);
    }

    #[test]
    fn status_reads_like_the_qml_reply() {
        let s = State::default();
        assert_eq!(
            status(&s, (0.0, 0.0, false)),
            r#"{"dnd":false,"pending":0,"popups":0,"centerOpen":false,"centerHeight":0,"centerMaxHeight":0,"centerCapped":false}"#
        );
    }

    #[test]
    fn a_reminder_fires_through_dnd_into_the_popups() {
        let mut s = State::default();
        s.model = model::set_dnd(&s.model, true);
        s.reminders = vec![reminders::make_entry(1, "m", 0.0, 1)];
        assert!(s.tick(5000));
        assert!(s.reminders.is_empty());
        assert_eq!(s.model.popups.len(), 1);
        assert_eq!(s.model.popups[0].summary, "Reminder");
    }

    #[test]
    fn a_hovered_toast_holds() {
        let mut s = State::default();
        s.notify("a", "b", Urgency::Normal);
        let id = s.model.popups[0].id.clone();
        let at = s.model.next_expiry.unwrap();
        s.set_hovered(std::slice::from_ref(&id), true);
        s.tick(at);
        assert_eq!(s.model.popups.len(), 1);
        s.set_hovered(&[id], false);
        s.tick(at + HOVER_HOLD_MS);
        assert_eq!(s.model.popups.len(), 0);
    }
}
