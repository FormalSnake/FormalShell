//! NowPlaying.qml: the music glyph and the active source's track as the
//! strip's first free label, which keeps its room longest. Right click skips
//! ahead and the wheel steps previous and next.

use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Env, Limits, Look, Part, View};

/// The cell's own ceiling on a strip long enough to afford it.
const CAP: f64 = 220.0;

#[derive(Default)]
pub struct NowPlaying {
    track: Option<(String, String)>,
}

impl Cell for NowPlaying {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Media]
    }

    fn read(&mut self, env: &Env) -> bool {
        let track = env.store.media.active().map(|a| (if a.title.is_empty() { a.identity } else { a.title }, a.artist));
        let changed = track != self.track;
        self.track = track;
        changed
    }

    fn view(&self, look: &Look) -> View {
        let available = self.track.is_some();
        let mut parts = vec![Part::Icon { name: "music".into(), dim: !available, dot: false }];
        if let Some((title, _)) = &self.track {
            parts.push(Part::Free { text: title.clone(), dim: false, lead: 0.0, ceiling: CAP });
        }
        let tooltip = match &self.track {
            None => "NOTHING PLAYING / CLICK FOR THE RADIO".to_owned(),
            Some((title, artist)) => {
                let by = if artist.is_empty() { String::new() } else { format!("{artist} / ") };
                format!("NOW PLAYING / {by}{title} / RIGHT NEXT / SCROLL PREV NEXT")
            }
        };
        View::new(parts, look.xxs).panel("media").tooltip(tooltip)
    }

    fn limits(&self, look: &Look, along: f64, _rest: f64) -> Option<Limits> {
        let cap = CAP.min(along * 0.15);
        Some(Limits { cap, min: cap.min(look.narrow / 2.0) })
    }

    fn click(&mut self, button: Button, _: (f64, f64), _: &Env) -> Action {
        match button {
            Button::Left => Action::Panel("media"),
            Button::Right => Action::MediaNext,
            Button::Middle => Action::None,
        }
    }

    fn wheel(&mut self, up: bool, _: &Env) -> Action {
        if up { Action::MediaNext } else { Action::MediaPrevious }
    }
}
