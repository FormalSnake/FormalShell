//! The wallpaper route: image rows for the grid, the picker directory scan,
//! and the Dark/Light variant split.
//!
//! The picker's grid lives inside the launcher, so its cells are ordinary
//! display rows, kind "image", carrying the absolute path; every piece of
//! machinery the launcher has (cursor wrap, `activate(index)` over IPC, the
//! confirm and close paths) applies to them unchanged.

use crate::jsstr;
use crate::node::{Kind, Node};

/// The file name of a path.
pub fn image_basename(path: &str) -> &str {
    match path.rfind('/') {
        Some(cut) => &path[cut + 1..],
        None => path,
    }
}

/// The picker directory scan, as one argv. There is no directory-listing
/// type in the toolkit, and two callers need the same answer: the picker route
/// re-scans on every entry so a directory edited between opens is picked up,
/// and the thumbnail service scans the configured directory at startup to
/// prerender its thumbnails. One definition of what counts as a pickable
/// image, so the grid and the cache can never disagree about the listing.
///
/// Both variant subdirectories are named as starting points alongside the
/// directory itself: `find` reports a missing one on stderr (swallowed) and
/// carries on with the rest, so one invocation covers every layout, and
/// `-maxdepth 1` per starting point is what keeps an unrelated subdirectory
/// of wallpapers out of the listing. `sort -u` because a case-insensitive
/// filesystem answers both `Dark` and `dark` with the same directory.
pub fn picker_scan_command(dir: &str) -> Vec<String> {
    [
        "sh",
        "-c",
        "find \"$1\" \"$1/Dark\" \"$1/dark\" \"$1/Light\" \"$1/light\" -maxdepth 1 -type f \
         \\( -iname \"*.png\" -o -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.webp\" -o -iname \"*.bmp\" \\) \
         2>/dev/null | sort -u",
        "sh",
        dir,
    ]
    .iter()
    .map(|s| s.to_string())
    .collect()
}

/// The scan's listing split by variant.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct WallpaperVariants {
    pub has_variants: bool,
    pub dark: Vec<String>,
    pub light: Vec<String>,
    pub root: Vec<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Variant {
    Dark,
    Light,
}

/// The scan hands over everything it found directly under the picker
/// directory AND directly under its `Dark`/`Light` subdirectories (either
/// case) in one listing; this decides which of the three each path belongs
/// to, from its position relative to `base_dir` rather than from its parent
/// directory's name alone: a picker directory itself called `Dark` must not
/// turn its own root listing into a variant.
///
/// `has_variants` is what the route keys its switcher off: neither
/// subdirectory means one flat listing and no switcher at all. One of the two
/// present is still variant mode, with the other variant simply empty: an
/// empty grid under a LIGHT header reads honestly, where silently falling back
/// to the root listing would look like the switcher did nothing.
pub fn wallpaper_variants(paths: &[String], base_dir: &str) -> WallpaperVariants {
    let base = base_dir.trim_end_matches('/');
    let mut out = WallpaperVariants::default();
    for p in paths {
        match path_variant(p, base) {
            Some(Variant::Dark) => out.dark.push(p.clone()),
            Some(Variant::Light) => out.light.push(p.clone()),
            None => out.root.push(p.clone()),
        }
    }
    out.has_variants = !out.dark.is_empty() || !out.light.is_empty();
    out
}

fn path_variant(path: &str, base: &str) -> Option<Variant> {
    let rest = if base.is_empty() {
        path
    } else {
        path.strip_prefix(base)?.strip_prefix('/')?
    };
    let (segment, _) = rest.split_once('/')?;
    match segment.to_lowercase().as_str() {
        "dark" => Some(Variant::Dark),
        "light" => Some(Variant::Light),
        _ => None,
    }
}

/// The listing one variant shows: the single entry point for it, so the grid,
/// `picker choose`'s membership check and `picker status`'s count can never
/// disagree about what is currently on screen. An unknown variant resolves to
/// dark rather than to nothing, which is what `None` stands for here.
pub fn wallpaper_listing(variants: &WallpaperVariants, variant: Option<Variant>) -> &[String] {
    if !variants.has_variants {
        return &variants.root;
    }
    if variant == Some(Variant::Light) { &variants.light } else { &variants.dark }
}

/// The mode a pick commits to: the set it came from when the listing is
/// split, `None` for a flat listing, where the pick says nothing about mode
/// and the theme keeps whatever it was in. A wallpaper filed under Dark is a
/// dark-mode wallpaper by the owner's own sorting, so choosing it while the
/// theme is light must flip the theme along with it, otherwise the Dark |
/// Light switch reads as a browsing filter that never does anything.
pub fn wallpaper_pick_mode(variants: &WallpaperVariants, variant: Option<Variant>) -> Option<Variant> {
    if !variants.has_variants {
        return None;
    }
    Some(if variant == Some(Variant::Light) { Variant::Light } else { Variant::Dark })
}

/// Rows for the "wallpaper" route. `query` filters on the basename only: a
/// path's directory component is identical for every row in a listing, so
/// matching it would make every query match everything.
pub fn image_rows(paths: &[String], query: &str) -> Vec<Node> {
    let q = jsstr::trim(query).to_lowercase();
    paths
        .iter()
        .filter(|p| q.is_empty() || image_basename(p).to_lowercase().contains(&q))
        .map(|p| Node {
            parent_id: Some("wallpaper".to_string()),
            path: p.clone(),
            ..Node::new(format!("wallpaper.{p}"), image_basename(p), Kind::Image)
        })
        .collect()
}
