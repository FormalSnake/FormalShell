//! Where the cursor was when a hot corner's action ended, as the compositor
//! answered (`j/cursorpos`); the corners themselves live on the UI thread.

#[derive(Default)]
pub struct State {
    /// The action, when it ended (ms since the epoch), the cursor if known.
    pub ended: Option<(String, i64, Option<(f64, f64)>)>,
}

pub enum Diff {
    Ended(String, i64, Option<(f64, f64)>),
}

impl State {
    pub fn apply(&mut self, diff: Diff) -> bool {
        let Diff::Ended(action, at, cursor) = diff;
        self.ended = Some((action, at, cursor));
        true
    }
}
