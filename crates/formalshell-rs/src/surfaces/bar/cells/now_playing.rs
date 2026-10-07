//! NowPlaying.qml: the music glyph and the active source's track as the
//! strip's first free label, which keeps its room longest. Right click skips
//! ahead and the wheel steps previous and next. Once the source has art, its
//! cover takes the glyph's slot.

use crate::scene::Bitmap;
use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Env, Limits, Look, Part, View};

/// The cell's own ceiling on a strip long enough to afford it.
const CAP: f64 = 220.0;

#[derive(Default)]
pub struct NowPlaying {
    track: Option<(String, String)>,
    /// The cover's slot and picture, while the source has art.
    cover: Option<(f64, Option<Bitmap>)>,
}

/// The slot ActiveWindow's app icon takes: a body-size line of text.
fn slot(env: &Env) -> f64 {
    (env.store.theme.theme.font_size.body * 1.25).round()
}

impl Cell for NowPlaying {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Media]
    }

    fn read(&mut self, env: &Env) -> bool {
        let active = env.store.media.active();
        let cover = active.as_ref().filter(|a| !a.art_url.is_empty()).map(|a| {
            let size = slot(env);
            let (px, radius) = crate::ui::w::cover_inner(&env.store.theme.theme, size);
            (size, env.store.media.cover(&a.art_url, px, radius))
        });
        let track = active.map(|a| (if a.title.is_empty() { a.identity } else { a.title }, a.artist));
        let same_cover = match (&cover, &self.cover) {
            (None, None) => true,
            (Some((s1, a)), Some((s2, b))) => s1 == s2 && crate::ui::el::Pic(a.clone()) == crate::ui::el::Pic(b.clone()),
            _ => false,
        };
        let changed = track != self.track || !same_cover;
        self.track = track;
        self.cover = cover;
        changed
    }

    fn view(&self, look: &Look) -> View {
        let available = self.track.is_some();
        let mut parts = vec![match &self.cover {
            Some((size, image)) => Part::Cover { image: crate::ui::el::Pic(image.clone()), size: *size },
            None => Part::Icon { name: "music".into(), dim: !available, dot: false },
        }];
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
