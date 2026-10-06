//! A drawer's geometry as pure functions: where the line a card comes out of
//! lies, how deep the shape reaches back to it, and the band the card may
//! paint in.
//!
//! A consumer states the edge it comes out of and its resting rect; every
//! number below follows from those, the output and the edge insets, so a
//! surface that moves, resizes or changes edge at runtime is followed without
//! being told.

use crate::types::{Edge, Insets, Rect};

/// Which way the line lies from the card: +1 for one at the far end of the
/// across axis (a bottom bar, the output's right edge), -1 for one at its
/// origin.
pub fn to_line(edge: Edge) -> f64 {
    match edge {
        Edge::Bottom | Edge::Right => 1.0,
        Edge::Top | Edge::Left => -1.0,
    }
}

/// The card's own anchored side, the one that faces the line.
pub fn near_edge(edge: Edge, rect: Rect) -> f64 {
    match edge {
        Edge::Bottom => rect.y + rect.height,
        Edge::Left => rect.x,
        Edge::Right => rect.x + rect.width,
        Edge::Top => rect.y,
    }
}

/// The card's size across the line, which is how far behind it a closed card
/// sits.
pub fn across(edge: Edge, rect: Rect) -> f64 {
    if edge.is_vertical() {
        rect.width
    } else {
        rect.height
    }
}

/// The card's rect along the line, as a start.
pub fn along_start(edge: Edge, rect: Rect) -> f64 {
    if edge.is_vertical() { rect.y } else { rect.x }
}

/// The card's rect along the line, as a length.
pub fn along_length(edge: Edge, rect: Rect) -> f64 {
    if edge.is_vertical() {
        rect.height
    } else {
        rect.width
    }
}

/// Where the line lies, across it: the far edge of the surface this card
/// hangs off (a tray item's menu off the tray's second bar), or, with none,
/// the inner edge of the output's own band on that side. `insets` is the
/// bar's thickness on the bar's edge and the frame ring's on the other three;
/// 0 is a bare edge with no line at all, where the card comes out from behind
/// the output itself.
pub fn line_at(
    edge: Edge,
    screen_width: f64,
    screen_height: f64,
    insets: Insets,
    target: Option<Rect>,
) -> f64 {
    if let Some(t) = target {
        return match edge {
            Edge::Bottom => t.y,
            Edge::Left => t.x + t.width,
            Edge::Right => t.x,
            Edge::Top => t.y + t.height,
        };
    }
    match edge {
        Edge::Bottom => screen_height - insets.bottom,
        Edge::Left => insets.left,
        Edge::Right => screen_width - insets.right,
        Edge::Top => insets.top,
    }
}

/// The room the card rests in between its own anchored edge and that line:
/// one `barMargin` under the bar, one `screenPadding` off the ring.
pub fn gap(edge: Edge, rest_rect: Rect, at: f64) -> f64 {
    to_line(edge) * (at - near_edge(edge, rest_rect))
}

/// How far past its own rect the shape reaches back toward the line: that
/// room, and the line's own row on top of it, so the fillets land on the line
/// and the two windows read as one silhouette.
pub fn depth(edge: Edge, rest_rect: Rect, at: f64, border_width: f64) -> f64 {
    gap(edge, rest_rect, at).max(0.0) + border_width
}

/// Where that reach lands, which is the row the card is cut at.
pub fn cut(edge: Edge, rest_rect: Rect, depth: f64) -> f64 {
    near_edge(edge, rest_rect) + to_line(edge) * depth
}

/// The band the card may paint in: everything on the card's side of that cut,
/// out to the far edge of the output. A card displaced behind the line by the
/// emerge is cut there, so it comes out from under the bar rather than
/// passing over it.
pub fn clip_band(edge: Edge, at: f64, screen_width: f64, screen_height: f64) -> Rect {
    match edge {
        Edge::Bottom => Rect::new(0.0, 0.0, screen_width, at.max(0.0)),
        Edge::Left => Rect::new(at, 0.0, (screen_width - at).max(0.0), screen_height),
        Edge::Right => Rect::new(0.0, 0.0, at.max(0.0), screen_height),
        Edge::Top => Rect::new(0.0, at, screen_width, (screen_height - at).max(0.0)),
    }
}

/// A span along the line: the owner's own extent.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Range {
    pub start: f64,
    pub length: f64,
}

/// What a card with no room to bud at all may paint on along the line: the
/// band above, narrowed to the owner's own span, so a plain card wider than
/// the edge it comes out from under never appears beside it. `range` of
/// `None`, which is every other card, leaves the band whole.
pub fn clip_along(band: Rect, edge: Edge, range: Option<Range>) -> Rect {
    let Some(range) = range else { return band };
    let down = edge.is_vertical();
    let lo = if down { band.y } else { band.x };
    let hi = lo + if down { band.height } else { band.width };
    let start = lo.max(range.start);
    let extent = (hi.min(range.start + range.length) - start).max(0.0);
    if down {
        Rect::new(band.x, start, band.width, extent)
    } else {
        Rect::new(start, band.y, extent, band.height)
    }
}

/// The range a budding card's contents are held to, in the card's own
/// coordinates: the bud the silhouette is clamped into, held to the card's
/// rect. This one is applied inside the deform rather than at the line, so it
/// squashes and stretches with the card: a band cut from the undeformed rect
/// outside the matrix is one the deform carries the card past on a fast
/// widening, and the overrun side loses its border for as long as that lasts.
/// `range` of `None`, a card that is not budding, is the card's whole rect.
pub fn bud_rect(edge: Edge, rect: Rect, range: Option<Range>) -> Rect {
    let Some(range) = range else {
        return Rect::new(0.0, 0.0, rect.width, rect.height);
    };
    let lo = along_start(edge, rect);
    let start = (range.start - lo).max(0.0);
    let extent = ((along_length(edge, rect)).min(range.start + range.length - lo) - start).max(0.0);
    if edge.is_vertical() {
        Rect::new(0.0, start, rect.width, extent)
    } else {
        Rect::new(start, 0.0, extent, rect.height)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The tokens are spelled out rather than read off a theme so a token
    // change has to be a deliberate edit here too: a 40px bar, barMargin 6,
    // screenPadding 12, a 1px border, on a 1920x1080 output.
    const BAR_THICKNESS: f64 = 40.0;
    const BAR_MARGIN: f64 = 6.0;
    const SCREEN_PADDING: f64 = 12.0;
    const BORDER_WIDTH: f64 = 1.0;

    fn insets(edge: Edge) -> Insets {
        let on = |e| if edge == e { BAR_THICKNESS } else { 0.0 };
        Insets {
            top: on(Edge::Top),
            bottom: on(Edge::Bottom),
            left: on(Edge::Left),
            right: on(Edge::Right),
        }
    }

    // A panel resting one barMargin off the bar on the edge it hangs from.
    fn panel_rect(edge: Edge, shift: f64) -> Rect {
        let off = BAR_THICKNESS + BAR_MARGIN + shift;
        match edge {
            Edge::Bottom => Rect::new(400.0, 1080.0 - off - 300.0, 360.0, 300.0),
            Edge::Left => Rect::new(off, 200.0, 360.0, 300.0),
            Edge::Right => Rect::new(1920.0 - off - 360.0, 200.0, 360.0, 300.0),
            Edge::Top => Rect::new(400.0, off, 360.0, 300.0),
        }
    }

    fn line(edge: Edge, target: Option<Rect>) -> f64 {
        line_at(edge, 1920.0, 1080.0, insets(edge), target)
    }

    fn depth_of(edge: Edge, rect: Rect) -> f64 {
        depth(edge, rect, line(edge, None), BORDER_WIDTH)
    }

    // The line

    #[test]
    fn the_line_is_the_output_band_on_the_cards_own_edge() {
        assert_eq!(line(Edge::Top, None), 40.0);
        assert_eq!(line(Edge::Bottom, None), 1040.0);
        assert_eq!(line(Edge::Left, None), 40.0);
        assert_eq!(line(Edge::Right, None), 1880.0);
    }

    // A bare edge, no bar and no frame ring: no line at all, and the depth
    // the consumer is left with is the border alone.
    #[test]
    fn a_bare_edge_puts_the_line_on_the_outputs_own_edge() {
        assert_eq!(
            line_at(Edge::Right, 1920.0, 1080.0, insets(Edge::Top), None),
            1920.0
        );
    }

    // A card hanging off another surface takes that surface's far edge
    // instead, whichever edge it comes out of.
    #[test]
    fn an_owned_card_takes_its_owners_far_edge() {
        let owner = Some(Rect::new(400.0, 46.0, 360.0, 200.0));
        assert_eq!(line(Edge::Top, owner), 246.0);
        assert_eq!(line(Edge::Bottom, owner), 46.0);
        assert_eq!(line(Edge::Left, owner), 760.0);
        assert_eq!(line(Edge::Right, owner), 400.0);
    }

    // The depth back to it: one barMargin of room and the line's own row on
    // top of it, so the fillets land on the line, whichever edge the card is on.

    #[test]
    fn every_edge_reaches_one_margin_and_one_row_back() {
        for edge in [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right] {
            assert_eq!(depth_of(edge, panel_rect(edge, 0.0)), 7.0, "{edge:?}");
        }
    }

    // The notification centre's own case: it rests a screenPadding off the
    // ring rather than a barMargin off the bar, and states nothing extra for
    // it.
    #[test]
    fn a_card_resting_further_off_reaches_further_back() {
        let rect = Rect::new(1920.0 - 40.0 - 12.0 - 420.0, 52.0, 420.0, 600.0);
        assert_eq!(depth_of(Edge::Right, rect), SCREEN_PADDING + 1.0);
    }

    // A card hanging off another one reaches back to its far edge, one
    // barMargin clear of it, and states nothing about where the bar is.
    #[test]
    fn an_owned_card_reaches_back_to_its_owner() {
        let owner = Rect::new(400.0, 46.0, 360.0, 194.0);
        let child = panel_rect(Edge::Top, 200.0);
        assert_eq!(
            depth(Edge::Top, child, line(Edge::Top, Some(owner)), BORDER_WIDTH),
            7.0
        );
    }

    // The slit: the band runs from the shape's own far reach, one row into
    // the line, out to the far edge of the output.

    fn band(edge: Edge, owner: Option<Rect>) -> Rect {
        let rect = panel_rect(edge, if owner.is_some() { 200.0 } else { 0.0 });
        let at = line(edge, owner);
        let d = depth(edge, rect, at, BORDER_WIDTH);
        clip_band(edge, cut(edge, rect, d), 1920.0, 1080.0)
    }

    #[test]
    fn a_top_bar_cuts_the_card_at_the_bars_own_line() {
        let b = band(Edge::Top, None);
        assert_eq!(
            (b.x, b.y, b.width, b.height),
            (0.0, 39.0, 1920.0, 1080.0 - 39.0)
        );
    }

    #[test]
    fn a_bottom_bar_cuts_the_card_at_the_bars_own_line() {
        let b = band(Edge::Bottom, None);
        assert_eq!(b.y, 0.0);
        assert_eq!(b.height, 1041.0);
    }

    #[test]
    fn a_left_bar_cuts_the_card_at_the_bars_own_line() {
        let b = band(Edge::Left, None);
        assert_eq!(b.x, 39.0);
        assert_eq!(b.width, 1920.0 - 39.0);
        assert_eq!(b.height, 1080.0);
    }

    #[test]
    fn a_right_bar_cuts_the_card_at_the_bars_own_line() {
        let b = band(Edge::Right, None);
        assert_eq!(b.x, 0.0);
        assert_eq!(b.width, 1881.0);
    }

    // A card hanging off another one comes out from under the owner's inner
    // edge, which is where its own resting edge is.
    #[test]
    fn an_owned_card_is_cut_at_the_owners_inner_edge() {
        assert_eq!(
            band(Edge::Top, Some(Rect::new(400.0, 46.0, 360.0, 194.0))).y,
            239.0
        );
        assert_eq!(
            band(Edge::Bottom, Some(Rect::new(400.0, 840.0, 360.0, 194.0))).height,
            841.0
        );
    }

    // The bud's own range

    #[test]
    fn a_bud_narrows_the_band_along_the_line() {
        let b = clip_band(Edge::Top, 39.0, 1920.0, 1080.0);
        let narrowed = clip_along(
            b,
            Edge::Top,
            Some(Range {
                start: 500.0,
                length: 200.0,
            }),
        );
        assert_eq!(narrowed.x, 500.0);
        assert_eq!(narrowed.width, 200.0);
        assert_eq!(narrowed.y, 39.0);
        assert_eq!(narrowed.height, 1080.0 - 39.0);
    }

    #[test]
    fn a_bud_is_clamped_into_the_band_it_narrows() {
        let b = clip_band(Edge::Left, 39.0, 1920.0, 1080.0);
        let narrowed = clip_along(
            b,
            Edge::Left,
            Some(Range {
                start: -100.0,
                length: 300.0,
            }),
        );
        assert_eq!(narrowed.y, 0.0);
        assert_eq!(narrowed.height, 200.0);
        assert_eq!(narrowed.x, 39.0);
    }

    #[test]
    fn no_bud_leaves_the_band_whole() {
        let b = clip_band(Edge::Top, 39.0, 1920.0, 1080.0);
        assert_eq!(clip_along(b, Edge::Top, None).height, b.height);
    }

    // The bud the contents are held to: the same range again, in the card's
    // own coordinates, applied under the deform where it stretches with the
    // card instead of cutting the border off a shape the deform has carried
    // past it.

    #[test]
    fn a_bud_holds_the_contents_to_its_own_range() {
        let rect = Rect::new(1400.0, 46.0, 400.0, 300.0);
        let bud = bud_rect(
            Edge::Top,
            rect,
            Some(Range {
                start: 1520.0,
                length: 160.0,
            }),
        );
        assert_eq!(
            (bud.x, bud.width, bud.y, bud.height),
            (120.0, 160.0, 0.0, 300.0)
        );
    }

    // A bud reaching past the card is the fillets' own reach, which lies
    // outside it: the contents stop at the card either way.
    #[test]
    fn a_bud_is_held_to_the_cards_own_rect() {
        let rect = Rect::new(1400.0, 46.0, 400.0, 300.0);
        let bud = bud_rect(
            Edge::Top,
            rect,
            Some(Range {
                start: 1380.0,
                length: 500.0,
            }),
        );
        assert_eq!(bud.x, 0.0);
        assert_eq!(bud.width, 400.0);
    }

    #[test]
    fn a_bud_beside_a_vertical_bar_runs_down_the_card() {
        let rect = Rect::new(46.0, 200.0, 360.0, 400.0);
        let bud = bud_rect(
            Edge::Left,
            rect,
            Some(Range {
                start: 260.0,
                length: 100.0,
            }),
        );
        assert_eq!(
            (bud.y, bud.height, bud.x, bud.width),
            (60.0, 100.0, 0.0, 360.0)
        );
    }

    #[test]
    fn no_bud_is_the_cards_whole_rect() {
        let rect = Rect::new(1400.0, 46.0, 400.0, 300.0);
        assert_eq!(
            bud_rect(Edge::Top, rect, None),
            Rect::new(0.0, 0.0, 400.0, 300.0)
        );
    }

    // The card's own axes

    #[test]
    fn the_across_and_along_axes_follow_the_edge() {
        let rect = Rect::new(400.0, 46.0, 360.0, 300.0);
        assert_eq!(across(Edge::Top, rect), 300.0);
        assert_eq!(across(Edge::Left, rect), 360.0);
        assert_eq!(along_start(Edge::Top, rect), 400.0);
        assert_eq!(along_length(Edge::Top, rect), 360.0);
        assert_eq!(along_start(Edge::Right, rect), 46.0);
        assert_eq!(along_length(Edge::Right, rect), 300.0);
    }
}
