//! Where the notification centre's card sits and how tall it gets.
//!
//! The card hangs off the right edge one `padding` in, sits that same padding
//! off the bar strip, and is as tall as its own content until that would
//! cross the padding at the far edge, where it stops and the row list scrolls
//! instead. `insets` is the bar's thickness on its own edge and 0 on the
//! other three, so a bottom bar pushes the card up and a right bar pushes it
//! left.

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Insets {
    pub top: f64,
    pub bottom: f64,
    pub left: f64,
    pub right: f64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct CenterParams {
    pub screen_width: f64,
    pub screen_height: f64,
    pub padding: f64,
    pub card_width: f64,
    pub content_height: f64,
    pub insets: Insets,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CenterFrame {
    pub x: f64,
    pub y: f64,
    pub height: f64,
    /// What the output leaves, reported beside the height so the cap can be
    /// read back over IPC rather than measured off a screenshot.
    pub available: f64,
    pub capped: bool,
}

pub fn center_frame(p: &CenterParams) -> CenterFrame {
    let i = p.insets;
    let available = (p.screen_height - i.top - i.bottom - p.padding * 2.0).max(0.0);
    let content = p.content_height.max(0.0);
    let height = content.min(available);

    CenterFrame {
        // Clamped so a card wider than the output starts at the left padding
        // rather than off-screen.
        x: (i.left + p.padding).max(p.screen_width - i.right - p.card_width - p.padding),
        // On a bottom bar the card hangs up from the bar, so a bell at the
        // bottom opens the card above it.
        y: if i.bottom > 0.0 {
            p.screen_height - i.bottom - p.padding - height
        } else {
            i.top + p.padding
        },
        height,
        available,
        capped: content > available,
    }
}
