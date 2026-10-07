//! The sonner depth stack's geometry: where every toast card lands in both
//! modes. The slot pool and animation bookkeeping live with the surface.
//!
//! COLLAPSED is the depth stack: the front card at full width, each level
//! behind it a real card sized narrower by one `peek_inset` per side per
//! level (never a fractional scale, which rasterizes a 1px border blurry),
//! horizontally centred on the front card, offset toward the anchored edge by
//! `peek_offset` so only its edge sliver shows. At most `max_peek_levels`
//! levels peek; deeper cards take the last level's geometry and sit behind
//! it. EXPANDED is the plain list: every card full width, `gap` apart, in the
//! order given.
//!
//! A `None` key is an entry with no slot of its own: it draws nothing but
//! still consumes its rank, so the cards around it keep the level they would
//! have had. Each geometry carries its `rank`, its place in the pass that laid
//! it out, which is what a staggered restack shares its window out by.

use std::collections::HashMap;
use std::hash::Hash;

#[derive(Clone, Debug)]
pub struct StackParams<K> {
    pub frame_width: f64,
    pub peek_inset: f64,
    pub peek_offset: f64,
    pub max_peek_levels: usize,
    pub gap: f64,
    pub top: bool,
    pub heights: HashMap<K, f64>,
    pub collapsed: Vec<Option<K>>,
    pub expanded: Vec<Option<K>>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Geom {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub z: i64,
    pub rank: usize,
    pub content_visible: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SlotGeom {
    pub collapsed: Option<Geom>,
    pub expanded: Option<Geom>,
}

#[derive(Clone, Debug)]
pub struct StackLayout<K> {
    pub by_key: HashMap<K, SlotGeom>,
    /// Every peek level pokes out past the front card by its own offset, so
    /// the pile is that much taller than the card in front of it.
    pub collapsed_height: f64,
    pub expanded_height: f64,
}

impl<K> Default for StackParams<K> {
    fn default() -> Self {
        StackParams {
            frame_width: 0.0,
            peek_inset: 0.0,
            peek_offset: 0.0,
            max_peek_levels: 0,
            gap: 0.0,
            top: false,
            heights: HashMap::new(),
            collapsed: Vec::new(),
            expanded: Vec::new(),
        }
    }
}

pub fn layout<K: Clone + Eq + Hash>(p: &StackParams<K>) -> StackLayout<K> {
    let mut by_key: HashMap<K, SlotGeom> = HashMap::new();
    let height_of = |key: &K| p.heights.get(key).copied().unwrap_or(0.0);

    for (r, key) in p.collapsed.iter().enumerate() {
        let Some(key) = key else { continue };
        let level = r.min(p.max_peek_levels);
        let inset = level as f64 * p.peek_inset;
        by_key.entry(key.clone()).or_default().collapsed = Some(Geom {
            x: inset,
            width: p.frame_width - inset * 2.0,
            // The reveal recedes away from the anchored edge: that edge
            // already carries the front card flush against it.
            y: if p.top {
                level as f64 * p.peek_offset
            } else {
                (p.max_peek_levels - level) as f64 * p.peek_offset
            },
            z: (p.collapsed.len() - r) as i64,
            rank: r,
            content_visible: r == 0,
        });
    }

    // The expanded pass reuses the collapsed z rather than deriving its own.
    // The two orders are different lists (a critical toast floats to the
    // front of the collapsed one, the expanded one is chronological), so a z
    // of its own restacked every card on the frame the pointer arrived, while
    // its x and y were still gliding. Expanded cards do not overlap, so z
    // buys nothing there, and holding the collapsed order keeps the fan-out
    // reading as one stack opening rather than a reshuffle.
    let mut y = 0.0;
    for (i, key) in p.expanded.iter().enumerate() {
        let Some(key) = key else { continue };
        let slot = by_key.entry(key.clone()).or_default();
        let z = slot
            .collapsed
            .map_or((p.expanded.len() - i) as i64, |c| c.z);
        slot.expanded = Some(Geom {
            x: 0.0,
            width: p.frame_width,
            y,
            z,
            rank: i,
            content_visible: true,
        });
        y += height_of(key) + p.gap;
    }

    let front_height = p
        .collapsed
        .first()
        .and_then(Option::as_ref)
        .map_or(0.0, height_of);

    StackLayout {
        by_key,
        collapsed_height: front_height + p.max_peek_levels as f64 * p.peek_offset,
        expanded_height: if y > 0.0 { y - p.gap } else { 0.0 },
    }
}
