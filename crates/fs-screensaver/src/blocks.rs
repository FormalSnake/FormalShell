//! Cell-fraction geometry for the Unicode block elements (U+2580..U+259F),
//! so the screensaver's canvas can paint them as rectangles instead of
//! glyphs.
//!
//! A terminal fills part of its own cell for a block character, so two full
//! blocks never show a seam. A font is under no such obligation: Geist Mono's
//! U+2588 sits 45 units low in its line box and rasterizes about a pixel short
//! of the advance, and a face without the range hands the job to a fallback
//! with its own metrics. Painting the fraction each codepoint denotes takes
//! the font out of the picture.
//!
//! Fractions, not pixels: x/y/w/h are 0..1 of one cell, y measured down from
//! the cell's top edge. The caller owns the cell size and the pixel snapping
//! two abutting cells need to share an edge.
//!
//! Scope stops at U+2580..U+259F because those are the codepoints that have
//! to tile. Surveyed against ttfx 0.3.0 over all 37 effects: box drawing
//! (lines, no seam to close), the geometric shapes blackhole draws and the
//! halfwidth katakana matrix rains keep the font's glyph.

const EIGHTH: f64 = 1.0 / 8.0;
const QUARTER: f64 = 1.0 / 4.0;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    pub alpha: f64,
}

const fn rect(x: f64, y: f64, w: f64, h: f64) -> Rect {
    Rect { x, y, w, h, alpha: 1.0 }
}

const UL: u8 = 1;
const UR: u8 = 2;
const LL: u8 = 4;
const LR: u8 = 8;

/// One rect per contiguous half wherever two quadrants share a full edge:
/// two abutting rects would meet on a fractional pixel boundary and each
/// cover half of it, which is the seam this module exists to avoid.
fn quadrants(mask: u8) -> Vec<Rect> {
    let mut out = Vec::new();
    let top = mask & UL != 0 && mask & UR != 0;
    let bottom = mask & LL != 0 && mask & LR != 0;
    if top {
        out.push(rect(0.0, 0.0, 1.0, 0.5));
    }
    if bottom {
        out.push(rect(0.0, 0.5, 1.0, 0.5));
    }
    if !top && mask & UL != 0 {
        out.push(rect(0.0, 0.0, 0.5, 0.5));
    }
    if !top && mask & UR != 0 {
        out.push(rect(0.5, 0.0, 0.5, 0.5));
    }
    if !bottom && mask & LL != 0 {
        out.push(rect(0.0, 0.5, 0.5, 0.5));
    }
    if !bottom && mask & LR != 0 {
        out.push(rect(0.5, 0.5, 0.5, 0.5));
    }
    out
}

/// The shades carry no geometry of their own: one full-cell rect at the
/// coverage the name states, which the caller multiplies into whatever alpha
/// it is already drawing at.
fn shade(coverage: f64) -> Vec<Rect> {
    vec![Rect { x: 0.0, y: 0.0, w: 1.0, h: 1.0, alpha: coverage }]
}

/// The rectangles covering `code`, or None when nothing here draws it and the
/// caller should fall back to the font's own glyph. U+0020 is deliberately
/// absent: callers skip an empty cell before asking.
pub fn rects_for(code: u32) -> Option<Vec<Rect>> {
    Some(match code {
        0x2580 => vec![rect(0.0, 0.0, 1.0, 0.5)],
        0x2581..=0x2587 => {
            let n = (code - 0x2580) as f64;
            vec![rect(0.0, 1.0 - n * EIGHTH, 1.0, n * EIGHTH)]
        }
        0x2588 => vec![rect(0.0, 0.0, 1.0, 1.0)],
        0x2589..=0x258F => {
            let m = (code - 0x2588) as f64;
            vec![rect(0.0, 0.0, (8.0 - m) * EIGHTH, 1.0)]
        }
        0x2590 => vec![rect(0.5, 0.0, 0.5, 1.0)],
        0x2591 => shade(QUARTER),
        0x2592 => shade(0.5),
        0x2593 => shade(3.0 * QUARTER),
        0x2594 => vec![rect(0.0, 0.0, 1.0, EIGHTH)],
        0x2595 => vec![rect(1.0 - EIGHTH, 0.0, EIGHTH, 1.0)],
        0x2596 => quadrants(LL),
        0x2597 => quadrants(LR),
        0x2598 => quadrants(UL),
        0x2599 => quadrants(UL | LL | LR),
        0x259A => quadrants(UL | LR),
        0x259B => quadrants(UL | UR | LL),
        0x259C => quadrants(UL | UR | LR),
        0x259D => quadrants(UR),
        0x259E => quadrants(UR | LL),
        0x259F => quadrants(UR | LL | LR),
        _ => return None,
    })
}

/// Whether `rects` is the whole cell at full coverage, the one case a caller
/// can widen across a horizontal run of the same codepoint and fill in a
/// single call.
pub fn is_full_cell(rects: Option<&[Rect]>) -> bool {
    matches!(rects, Some([r]) if r.x == 0.0 && r.y == 0.0 && r.w == 1.0 && r.h == 1.0 && r.alpha == 1.0)
}

/// Total ink coverage of one cell, 0..1. Not used to paint: it states what a
/// codepoint means without restating the rectangle list, and makes an
/// overlapping or oversized table entry fail loudly.
pub fn coverage(code: u32) -> f64 {
    match rects_for(code) {
        None => 0.0,
        Some(rects) => rects.iter().map(|r| r.w * r.h * r.alpha).sum(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const BANNER_CODES: [u32; 3] = [0x2580, 0x2584, 0x2588];

    fn close(a: f64, b: f64) {
        assert!((a - b).abs() < 1e-9, "{a} != {b}");
    }

    fn area(rects: &[Rect]) -> f64 {
        rects.iter().map(|r| r.w * r.h).sum()
    }

    #[test]
    fn full_block_is_the_whole_cell() {
        let rects = rects_for(0x2588).unwrap();
        assert_eq!(rects.len(), 1);
        assert_eq!((rects[0].x, rects[0].y, rects[0].w, rects[0].h, rects[0].alpha), (0.0, 0.0, 1.0, 1.0, 1.0));
        assert!(is_full_cell(Some(&rects)));
    }

    #[test]
    fn half_blocks_take_their_named_half() {
        let upper = rects_for(0x2580).unwrap();
        assert_eq!(upper.len(), 1);
        assert_eq!((upper[0].y, upper[0].h, upper[0].w), (0.0, 0.5, 1.0));
        let lower = rects_for(0x2584).unwrap();
        assert_eq!((lower[0].y, lower[0].h), (0.5, 0.5));
        let left = rects_for(0x258C).unwrap();
        assert_eq!((left[0].x, left[0].w, left[0].h), (0.0, 0.5, 1.0));
        let right = rects_for(0x2590).unwrap();
        assert_eq!((right[0].x, right[0].w), (0.5, 0.5));
    }

    #[test]
    fn upper_and_lower_half_tile_the_cell() {
        let upper = rects_for(0x2580).unwrap()[0];
        let lower = rects_for(0x2584).unwrap()[0];
        assert_eq!(upper.y + upper.h, lower.y);
        assert_eq!(lower.y + lower.h, 1.0);
        assert_eq!(coverage(0x2580) + coverage(0x2584), 1.0);
    }

    #[test]
    fn lower_eighth_blocks_grow_upward_from_the_bottom() {
        for n in 1..=7u32 {
            let rects = rects_for(0x2580 + n).unwrap();
            assert_eq!(rects.len(), 1);
            assert_eq!((rects[0].x, rects[0].w), (0.0, 1.0));
            assert_eq!(rects[0].y + rects[0].h, 1.0);
            close(rects[0].h, n as f64 / 8.0);
        }
    }

    #[test]
    fn left_eighth_blocks_shrink_from_the_left_edge() {
        for m in 1..=7u32 {
            let rects = rects_for(0x2588 + m).unwrap();
            assert_eq!(rects.len(), 1);
            assert_eq!((rects[0].x, rects[0].y, rects[0].h), (0.0, 0.0, 1.0));
            close(rects[0].w, (8 - m) as f64 / 8.0);
        }
        close(rects_for(0x2594).unwrap()[0].h, 1.0 / 8.0);
        assert_eq!(rects_for(0x2594).unwrap()[0].y, 0.0);
        close(rects_for(0x2595).unwrap()[0].w, 1.0 / 8.0);
        close(rects_for(0x2595).unwrap()[0].x, 7.0 / 8.0);
    }

    #[test]
    fn quadrants_cover_their_named_corners() {
        let cases = [
            (0x2596, 1), (0x2597, 1), (0x2598, 1), (0x2599, 3), (0x259A, 2),
            (0x259B, 3), (0x259C, 3), (0x259D, 1), (0x259E, 2), (0x259F, 3),
        ];
        for (code, quarters) in cases {
            close(coverage(code), quarters as f64 / 4.0);
        }
        let ll = rects_for(0x2596).unwrap();
        assert_eq!(ll.len(), 1);
        assert_eq!((ll[0].x, ll[0].y), (0.0, 0.5));
        assert_eq!(rects_for(0x259B).unwrap().len(), 2);
        assert_eq!(rects_for(0x259B).unwrap()[0].w, 1.0);
        assert_eq!(rects_for(0x259A).unwrap().len(), 2);
    }

    #[test]
    fn shades_are_one_full_cell_rect_at_their_own_coverage() {
        for (code, alpha) in [(0x2591, 0.25), (0x2592, 0.5), (0x2593, 0.75)] {
            let rects = rects_for(code).unwrap();
            assert_eq!(rects.len(), 1);
            assert_eq!((rects[0].w, rects[0].h, rects[0].alpha), (1.0, 1.0, alpha));
            assert!(!is_full_cell(Some(&rects)));
            assert_eq!(coverage(code), alpha);
        }
    }

    #[test]
    fn every_entry_stays_inside_one_cell_without_overlapping() {
        for code in 0x2580..=0x259F {
            let rects = rects_for(code).unwrap();
            assert!(!rects.is_empty());
            for (i, a) in rects.iter().enumerate() {
                assert!(a.x >= 0.0 && a.y >= 0.0 && a.w > 0.0 && a.h > 0.0);
                assert!(a.x + a.w <= 1.0 + 1e-9);
                assert!(a.y + a.h <= 1.0 + 1e-9);
                assert!(a.alpha > 0.0 && a.alpha <= 1.0);
                for b in &rects[i + 1..] {
                    let ox = (a.x + a.w).min(b.x + b.w) - a.x.max(b.x);
                    let oy = (a.y + a.h).min(b.y + b.h) - a.y.max(b.y);
                    assert!(ox <= 1e-9 || oy <= 1e-9);
                }
            }
            assert!(area(&rects) <= 1.0 + 1e-9);
        }
    }

    #[test]
    fn the_bundled_banners_own_characters_are_all_tabled() {
        for code in BANNER_CODES {
            assert!(rects_for(code).is_some());
        }
    }

    #[test]
    fn non_block_codepoints_fall_through_to_the_font() {
        let outside = [0x20, 0x41, 0x30, 0x2f, 0x2500, 0x2502, 0x257f, 0x25a0, 0x25cf, 0x25e6, 0xff71];
        for code in outside {
            assert_eq!(rects_for(code), None);
            assert_eq!(coverage(code), 0.0);
        }
        assert!(!is_full_cell(None));
    }
}
