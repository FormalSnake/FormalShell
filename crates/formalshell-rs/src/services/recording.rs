//! Whether a screen recording is running, for the bar's recording indicator.
//! The recorder child and its verbs belong to the capture milestone, which
//! publishes here; until it does nothing is recording.

#[derive(Default)]
pub struct State {
    pub active: bool,
    /// Milliseconds since the recording started.
    pub elapsed_ms: u64,
}

#[allow(dead_code)]
pub enum Diff {
    Active { active: bool, elapsed_ms: u64 },
}

impl State {
    pub fn apply(&mut self, diff: Diff) -> bool {
        let Diff::Active { active, elapsed_ms } = diff;
        let changed = (self.active, self.elapsed_ms) != (active, elapsed_ms);
        (self.active, self.elapsed_ms) = (active, elapsed_ms);
        changed
    }
}
