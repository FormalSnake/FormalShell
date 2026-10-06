//! `tailscale status --json` on a minute (TailscalePanel.qml's poll). No
//! CLI hides the cell; a daemon that answers badly reads as an error and
//! one that wants a login as its own state.

use std::time::Duration;

use fs_devices::tailscale::{self, Status};

use super::{changed, idle, settings};
use crate::runtime::Ctx;
use crate::services::proc::{self, MISSING};
use crate::store;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Poll {
    #[default]
    Unknown,
    Missing,
    Error,
    NeedsLogin,
    Ok,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct State {
    pub poll: Poll,
    /// Meaningful only while `poll` is `Ok` or `NeedsLogin`.
    pub status: Option<Status>,
}

pub fn parse(code: i32, stdout: &str) -> State {
    if code == MISSING {
        return State { poll: Poll::Missing, status: None };
    }
    let status = tailscale::parse_status(stdout);
    if !status.ok {
        return State { poll: Poll::Error, status: None };
    }
    let poll = if status.needs_login { Poll::NeedsLogin } else { Poll::Ok };
    State { poll, status: Some(status) }
}

fn read() -> Duration {
    settings().interval("tailscale.intervalMs", 60_000)
}

pub async fn run(ctx: Ctx) {
    let rx = changed();
    loop {
        let interval = read();
        let done = proc::capture(&proc::argv(&["tailscale", "status", "--json"]), Duration::from_secs(30)).await;
        ctx.publish(store::Diff::Info(super::Diff::Tailscale(parse(done.code, &done.stdout))));
        idle(interval, &rx, &interval, read).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn states() {
        assert_eq!(parse(127, "").poll, Poll::Missing);
        assert_eq!(parse(1, "failed to connect").poll, Poll::Error);
        assert_eq!(parse(0, r#"{"BackendState":"NeedsLogin"}"#).poll, Poll::NeedsLogin);
        let running = parse(0, r#"{"BackendState":"Running"}"#);
        assert!(running.poll == Poll::Ok && running.status.is_some_and(|s| s.running));
    }
}
