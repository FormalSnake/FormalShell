//! NowPlaying.qml: the music glyph and the active player's track as the
//! strip's first free label, which keeps its room longest.

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
        let media = &env.store.media;
        let track = media.title().map(|t| (t, media.active.as_ref().map(|p| p.artist.clone()).unwrap_or_default()));
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
            _ => Action::None,
        }
    }
}
