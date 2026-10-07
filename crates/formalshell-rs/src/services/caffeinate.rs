//! What caffeinate reads as: the toggle, the surface holding the Wayland
//! idle inhibitor, and the session's idle state off ext-idle-notify. The
//! UI thread owns all three (they are Wayland objects and events), so the
//! slice is written from there and read by the indicators cell.

#[derive(Default)]
pub struct State {
    /// The toggle, never persisted: a restart comes back to
    /// `caffeinate.onStartup`.
    pub active: bool,
    /// The inhibitor is created and its surface mapped.
    pub inhibiting: bool,
    /// ext-idle-notify (respecting inhibitors) says the session is idle.
    pub idle: bool,
}

pub enum Diff {
    Active(bool),
    Inhibiting(bool),
    Idle(bool),
}

impl State {
    pub fn apply(&mut self, diff: Diff) -> bool {
        let (slot, value) = match diff {
            Diff::Active(v) => (&mut self.active, v),
            Diff::Inhibiting(v) => (&mut self.inhibiting, v),
            Diff::Idle(v) => (&mut self.idle, v),
        };
        let changed = *slot != value;
        *slot = value;
        changed
    }

    /// The IPC `status` reply.
    pub fn status(&self) -> String {
        format!(r#"{{"active":{},"inhibiting":{},"isIdle":{}}}"#, self.active, self.inhibiting, self.idle)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_reads_like_the_golden_reply() {
        let mut s = State::default();
        assert_eq!(s.status(), r#"{"active":false,"inhibiting":false,"isIdle":false}"#);
        assert!(s.apply(Diff::Active(true)));
        assert!(!s.apply(Diff::Active(true)));
        assert_eq!(s.status(), r#"{"active":true,"inhibiting":false,"isIdle":false}"#);
    }
}
