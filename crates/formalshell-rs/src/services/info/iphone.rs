// Portions from omarchy-iphone (MIT, Copyright (c) 2026 kbbahaPro)

//! The iPhone the bar cell shows (IphoneService.qml's bridge half): one
//! long-lived `omarchy-iphone-bridge listen` child turning ancs4linux's
//! signals into JSONL, restarted on a doubling backoff. No bridge on PATH is
//! `installed: false` and the cell never appears; a bridge whose daemon does
//! not own its bus name is not `observer`. Neither fakes a phone. The
//! notification mirror, pairing and Apple Media Service halves belong to
//! the notification and media milestones.

use std::collections::HashSet;
use std::time::Duration;

use async_io::Timer;
use fs_devices::iphone::{self, Event, Verdict};
use futures_lite::io::BufReader;
use futures_lite::{AsyncBufReadExt, StreamExt};

use super::settings;
use crate::runtime::Ctx;
use crate::services::proc::MISSING;
use crate::store;

const BRIDGE: &str = "omarchy-iphone-bridge";
const HISTORY_LIMIT: usize = 200;
const BASE_BACKOFF: Duration = Duration::from_secs(2);
const MAX_BACKOFF: Duration = Duration::from_secs(60);

#[derive(Clone, Debug, Default, PartialEq)]
pub struct State {
    pub installed: bool,
    pub observer: bool,
    pub connected: bool,
    pub device_name: String,
    /// 0..1, only while connected and the bridge has read one.
    pub battery: Option<f64>,
    pub unread: u32,
}

#[derive(Default)]
struct Session {
    state: State,
    known: HashSet<i64>,
}

impl Session {
    /// Applies one bridge line; true when the state moved.
    fn event(&mut self, event: Event) -> bool {
        let before = self.state.clone();
        match event {
            Event::Status(s) => {
                self.state.observer = s.observer;
                self.state.connected = s.connected;
                self.state.device_name = s.device_name;
                self.state.battery = (s.connected && s.battery >= 0.0).then_some(s.battery / 100.0);
            }
            Event::History(items) => self.known = items.iter().map(|n| n.id).collect(),
            Event::Notification(entry) => {
                let cfg = settings();
                let block: Vec<String> = cfg
                    .get("iphone.notifications.block")
                    .and_then(|b| b.as_array())
                    .map(|a| a.iter().filter_map(|v| v.as_str().map(str::to_owned)).collect())
                    .unwrap_or_default();
                if !iphone::is_blocked(&entry, &block) && self.known.insert(entry.id) {
                    let mode = cfg.str("iphone.notifications.focus").unwrap_or("respect");
                    if iphone::focus_verdict(Some(&entry), mode) != Verdict::Drop {
                        self.state.unread += 1;
                    }
                }
            }
            Event::Dismiss { id } => {
                self.known.remove(&id);
            }
            _ => {}
        }
        self.state != before
    }
}

fn on_path(name: &str) -> bool {
    super::monitor::on_path(name)
}

async fn listen(ctx: &Ctx, session: &mut Session) -> i32 {
    let child = async_process::Command::new(BRIDGE)
        .args(["listen", "--limit", &HISTORY_LIMIT.to_string()])
        .stdin(async_process::Stdio::null())
        .stdout(async_process::Stdio::piped())
        .stderr(async_process::Stdio::null())
        .kill_on_drop(true)
        .spawn();
    let mut child = match child {
        Ok(child) => child,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return MISSING,
        Err(_) => return -1,
    };
    let Some(stdout) = child.stdout.take() else { return -1 };
    let mut lines = BufReader::new(stdout).lines();
    while let Some(Ok(line)) = lines.next().await {
        if let Some(event) = iphone::parse_event(&line) {
            session.state.installed = true;
            session.event(event);
            publish(ctx, &session.state);
        }
    }
    child.status().await.ok().and_then(|s| s.code()).unwrap_or(-1)
}

fn publish(ctx: &Ctx, state: &State) {
    ctx.publish(store::Diff::Info(super::Diff::Iphone(state.clone())));
}

pub async fn run(ctx: Ctx) {
    let mut session = Session::default();
    let mut backoff = BASE_BACKOFF;
    session.state.installed = on_path(BRIDGE);
    publish(&ctx, &session.state);
    loop {
        if !settings().flag("iphone.enable", true) {
            Timer::after(MAX_BACKOFF).await;
            continue;
        }
        let code = listen(&ctx, &mut session).await;
        session.state = State { installed: code != MISSING, unread: session.state.unread, ..State::default() };
        publish(&ctx, &session.state);
        Timer::after(backoff).await;
        backoff = (backoff * 2).min(MAX_BACKOFF);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn status(connected: bool, battery: f64) -> Event {
        iphone::parse_event(&format!(r#"{{"type":"status","observer":true,"connected":{connected},"deviceName":"Phone","battery":{battery}}}"#)).unwrap()
    }

    #[test]
    fn battery_reads_only_while_connected() {
        let mut s = Session::default();
        s.event(status(true, 80.0));
        assert_eq!(s.state.battery, Some(0.8));
        s.event(status(false, 80.0));
        assert_eq!(s.state.battery, None);
        s.event(status(true, -1.0));
        assert_eq!(s.state.battery, None);
    }

    #[test]
    fn a_notification_counts_once() {
        let mut s = Session::default();
        let n = iphone::parse_event(r#"{"type":"notification","id":7,"title":"t"}"#).unwrap();
        s.event(n.clone());
        s.event(n);
        assert_eq!(s.state.unread, 1);
    }
}
