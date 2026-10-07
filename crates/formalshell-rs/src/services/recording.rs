//! Whether a screen recording is running, for the bar's recording indicator.
//! `surfaces::capture::record` owns the recorder and writes this slice.

#[derive(Default)]
pub struct State {
    pub active: bool,
    /// Milliseconds since the recording started.
    pub elapsed_ms: u64,
}

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
