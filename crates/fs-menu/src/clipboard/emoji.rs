//! Whether a clipboard capture is nothing but emoji, counted in grapheme
//! clusters, so the launcher can draw it as a picture rather than as a line
//! of body text. Hand-rolled over code points.

/// A capture this many clusters long or longer reads as text, not a picture.
pub const MAX_CLUSTERS: usize = 8;

const ZWJ: u32 = 0x200D;
const VS15: u32 = 0xFE0E;
const VS16: u32 = 0xFE0F;
const KEYCAP: u32 = 0x20E3;
/// Reads as "no code point here" past the end of the capture.
const NONE: u32 = u32::MAX;

/// BMP code points whose default presentation is emoji, so they count bare.
/// Everything else in the BMP symbol blocks defaults to text and counts only
/// with VS16 after it (a heart glyph vs the emoji heart).
const BMP_EMOJI_DEFAULT: &[(u32, u32)] = &[
    (0x231A, 0x231B), (0x23E9, 0x23EC), (0x23F0, 0x23F0), (0x23F3, 0x23F3),
    (0x25FD, 0x25FE), (0x2614, 0x2615), (0x2648, 0x2653), (0x267F, 0x267F),
    (0x2693, 0x2693), (0x26A1, 0x26A1), (0x26AA, 0x26AB), (0x26BD, 0x26BE),
    (0x26C4, 0x26C5), (0x26CE, 0x26CE), (0x26D4, 0x26D4), (0x26EA, 0x26EA),
    (0x26F2, 0x26F3), (0x26F5, 0x26F5), (0x26FA, 0x26FA), (0x26FD, 0x26FD),
    (0x2705, 0x2705), (0x270A, 0x270B), (0x2728, 0x2728), (0x274C, 0x274C),
    (0x274E, 0x274E), (0x2753, 0x2755), (0x2757, 0x2757), (0x2795, 0x2797),
    (0x27B0, 0x27B0), (0x27BF, 0x27BF), (0x2B1B, 0x2B1C), (0x2B50, 0x2B50),
    (0x2B55, 0x2B55),
];

const BMP_EMOJI_TEXT: &[(u32, u32)] = &[
    (0x00A9, 0x00A9), (0x00AE, 0x00AE), (0x203C, 0x203C), (0x2049, 0x2049),
    (0x2122, 0x2122), (0x2139, 0x2139), (0x2194, 0x21AA), (0x231A, 0x23FF),
    (0x24C2, 0x24C2), (0x25AA, 0x25FE), (0x2600, 0x27BF), (0x2934, 0x2935),
    (0x2B05, 0x2B55), (0x3030, 0x3030), (0x303D, 0x303D), (0x3297, 0x3297),
    (0x3299, 0x3299),
];

fn in_ranges(cp: u32, ranges: &[(u32, u32)]) -> bool {
    ranges.iter().any(|&(lo, hi)| cp >= lo && cp <= hi)
}

fn is_regional(cp: u32) -> bool {
    (0x1F1E6..=0x1F1FF).contains(&cp)
}

fn is_skin_tone(cp: u32) -> bool {
    (0x1F3FB..=0x1F3FF).contains(&cp)
}

fn is_tag(cp: u32) -> bool {
    (0xE0020..=0xE007E).contains(&cp)
}

fn is_keycap_base(cp: u32) -> bool {
    (0x30..=0x39).contains(&cp) || cp == 0x23 || cp == 0x2A
}

fn is_supplementary_pictograph(cp: u32) -> bool {
    ((0x1F000..=0x1FAFF).contains(&cp) && !is_regional(cp)) || (0x1FC00..=0x1FFFD).contains(&cp)
}

fn at(cps: &[u32], i: usize) -> u32 {
    cps.get(i).copied().unwrap_or(NONE)
}

/// One emoji element at `cps[i]` (a pictograph with its presentation
/// selector, skin tone and tag run), returning the index past it.
fn element(cps: &[u32], i: usize) -> Option<usize> {
    let cp = cps[i];
    let next = at(cps, i + 1);
    let mut j;
    if is_supplementary_pictograph(cp) {
        j = i + 1;
        if at(cps, j) == VS15 {
            return None;
        }
        if at(cps, j) == VS16 {
            j += 1;
        }
    } else if in_ranges(cp, BMP_EMOJI_DEFAULT) {
        j = i + 1;
        if next == VS15 {
            return None;
        }
        if next == VS16 {
            j += 1;
        }
    } else if in_ranges(cp, BMP_EMOJI_TEXT) {
        if next == VS16 {
            j = i + 2;
        } else if is_skin_tone(next) || next == ZWJ {
            j = i + 1;
        } else {
            return None;
        }
    } else {
        return None;
    }
    if is_skin_tone(at(cps, j)) {
        j += 1;
    }
    if is_tag(at(cps, j)) {
        while is_tag(at(cps, j)) {
            j += 1;
        }
        if at(cps, j) != 0xE007F {
            return None;
        }
        j += 1;
    }
    Some(j)
}

/// One grapheme cluster at `cps[i]`, returning the index past it, or `None`
/// when what starts there is not an emoji.
fn cluster(cps: &[u32], i: usize) -> Option<usize> {
    let cp = cps[i];
    if is_regional(cp) {
        return is_regional(at(cps, i + 1)).then_some(i + 2);
    }
    if is_keycap_base(cp) {
        let mut k = i + 1;
        if at(cps, k) == VS16 {
            k += 1;
        }
        return (at(cps, k) == KEYCAP).then_some(k + 1);
    }
    let mut j = element(cps, i)?;
    while at(cps, j) == ZWJ {
        if j + 1 >= cps.len() {
            return None;
        }
        j = element(cps, j + 1)?;
    }
    Some(j)
}

/// The number of emoji clusters `text` is made of, whitespace between them
/// allowed, or 0 when anything else is in it or it runs to `MAX_CLUSTERS`.
pub fn emoji_count(text: &str) -> usize {
    let cps: Vec<u32> = text.chars().map(u32::from).collect();
    let mut count = 0;
    let mut i = 0;
    while i < cps.len() {
        if matches!(cps[i], 0x20 | 0x09 | 0x0A | 0x0D) {
            i += 1;
            continue;
        }
        let Some(end) = cluster(&cps, i) else { return 0 };
        count += 1;
        if count >= MAX_CLUSTERS {
            return 0;
        }
        i = end;
    }
    count
}

pub fn is_emoji_only(text: &str) -> bool {
    emoji_count(text) > 0
}
