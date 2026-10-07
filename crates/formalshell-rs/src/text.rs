//! Shaping through parley, outlines through skrifa hinted at the pixel size
//! they are drawn at. Layout advances stay linear; what hinting moves is the
//! outline inside each glyph's box, and every glyph origin and baseline is
//! snapped to a whole device pixel so the hinted stems land on the grid.

use std::borrow::Cow;
use std::collections::HashMap;
use std::sync::Arc;

use parley::fontique::Blob;
use parley::{
    FontContext, FontFamily, FontFamilyName, FontWeight, GenericFamily, Layout, LayoutContext, PositionedLayoutItem,
    StyleProperty,
};
use skrifa::bitmap::{BitmapData, BitmapStrikes};
use skrifa::instance::{LocationRef, NormalizedCoord, Size};
use skrifa::outline::{
    DrawSettings, Engine, HintingInstance, HintingOptions, OutlinePen, SmoothMode, Target,
};
use skrifa::raw::types::F2Dot14;
use skrifa::string::StringId;
use skrifa::{FontRef, GlyphId, MetadataProvider};
use vello_cpu::kurbo::BezPath;

use crate::fontconfig::{self, HintStyle, Rendering};

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Family {
    Generic(GenericFamily),
    /// A family registered by name, the icon font.
    Named(&'static str),
}


#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TextStyle {
    pub family: Family,
    pub size: f32,
    pub weight: f32,
}

/// Room left round the line box for ink that overhangs it (side bearings,
/// overshoot), so a text node's bounds cover everything it paints.
pub const PAD: i32 = 2;

#[derive(Clone)]
pub struct PlacedGlyph {
    pub path: Arc<BezPath>,
    pub x: i32,
    pub y: i32,
    /// A colour bitmap (CBDT, sbix) drawn instead of the outline, already
    /// at the pixel size, its top-left at `x, y`.
    pub image: Option<crate::scene::Bitmap>,
}

/// The colour emoji face the package ships beside the icon fonts, named so
/// a family that lacks a glyph falls through to it before fontconfig's own
/// `emoji` alias.
const EMOJI_FAMILY: &str = "Noto Color Emoji";

/// A shaped single line, glyphs placed relative to the line's top-left with
/// the baseline already on a whole pixel.
#[derive(Clone)]
pub struct ShapedText {
    source: String,
    style: TextStyle,
    /// The advance of the line, unpadded.
    pub width: i32,
    pub ascent: f32,
    pub descent: f32,
    pub glyphs: Vec<PlacedGlyph>,
}

impl ShapedText {
    pub fn line_height(&self) -> i32 {
        (self.ascent + self.descent).ceil() as i32
    }

    /// The node box this line paints into, padding included.
    pub fn box_size(&self) -> (i32, i32) {
        (self.width + PAD * 2, self.line_height() + PAD * 2)
    }

    pub fn same_as(&self, other: &ShapedText) -> bool {
        self.source == other.source && self.style == other.style
    }
}

#[derive(Hash, PartialEq, Eq)]
struct InstanceKey {
    blob: u64,
    index: u32,
    size_bits: u32,
    coords: Vec<i16>,
}

#[derive(Hash, PartialEq, Eq)]
struct GlyphKey {
    instance: usize,
    glyph: u32,
}

pub struct Text {
    fcx: FontContext,
    lcx: LayoutContext<()>,
    rendering: Rendering,
    instance_ids: HashMap<InstanceKey, usize>,
    instances: Vec<Option<HintingInstance>>,
    outlines: HashMap<GlyphKey, Arc<BezPath>>,
    /// Colour bitmaps by face, glyph and pixel size; `None` where the face
    /// has no bitmap for the glyph.
    bitmaps: HashMap<(u64, u32, u32, u32), Option<(crate::scene::Bitmap, i32, i32)>>,
}

impl Text {
    pub fn new() -> Self {
        let rendering = fontconfig::rendering();
        eprintln!("text: fontconfig {rendering:?}");
        let mut fcx = FontContext::new();
        // The package wraps the binary with the lucide font's path, the way
        // nix/package.nix puts it on XDG_DATA_DIRS for Qt.
        match std::env::var("FS_RS_ICON_FONT").map(std::fs::read) {
            Ok(Ok(data)) => {
                let families = fcx.collection.register_fonts(Blob::new(Arc::new(data)), None);
                eprintln!("text: icon font registered ({} families)", families.len());
            }
            Ok(Err(err)) => eprintln!("text: icon font unreadable: {err}"),
            Err(_) => eprintln!("text: FS_RS_ICON_FONT unset, no icons"),
        }
        // font-logos and the Nerd set, by directory: the package does not
        // name one file of it.
        for dir in std::env::var("FS_RS_FONT_DIRS").unwrap_or_default().split(':').filter(|d| !d.is_empty()) {
            let mut stack = vec![std::path::PathBuf::from(dir)];
            while let Some(path) = stack.pop() {
                let Ok(entries) = std::fs::read_dir(&path) else { continue };
                for entry in entries.flatten() {
                    let p = entry.path();
                    if p.is_dir() {
                        stack.push(p);
                    } else if let Some(data) =
                        p.extension().filter(|e| *e == "ttf" || *e == "otf").and_then(|_| std::fs::read(&p).ok())
                    {
                        fcx.collection.register_fonts(Blob::new(Arc::new(data)), None);
                        eprintln!("text: registered {}", p.display());
                    }
                }
            }
        }
        Self {
            fcx,
            lcx: LayoutContext::new(),
            rendering,
            instance_ids: HashMap::new(),
            instances: Vec::new(),
            outlines: HashMap::new(),
            bitmaps: HashMap::new(),
        }
    }

    pub fn shape(&mut self, source: &str, style: TextStyle) -> ShapedText {
        let mut builder = self.lcx.ranged_builder(&mut self.fcx, source, 1.0, true);
        match style.family {
            Family::Generic(g) => {
                builder.push_default(StyleProperty::FontFamily(FontFamily::List(Cow::Owned(vec![
                    FontFamilyName::Generic(g),
                    FontFamilyName::Named(Cow::Borrowed(EMOJI_FAMILY)),
                    FontFamilyName::Generic(GenericFamily::Emoji),
                ]))));
                // DejaVu, behind every sans-serif, draws many emoji as
                // outlines; an emoji run asks the colour face first, the way
                // a browser honours emoji presentation.
                for range in emoji_runs(source) {
                    let stack = FontFamily::List(Cow::Owned(vec![
                        FontFamilyName::Named(Cow::Borrowed(EMOJI_FAMILY)),
                        FontFamilyName::Generic(GenericFamily::Emoji),
                        FontFamilyName::Generic(g),
                    ]));
                    builder.push(StyleProperty::FontFamily(stack), range);
                }
            }
            Family::Named(name) => builder.push_default(StyleProperty::from(FontFamily::Source(Cow::Borrowed(name)))),
        }
        builder.push_default(StyleProperty::FontSize(style.size));
        builder.push_default(StyleProperty::FontWeight(FontWeight::new(style.weight)));
        let mut layout: Layout<()> = builder.build(source);
        layout.break_all_lines(None);

        let mut shaped = ShapedText {
            source: source.to_owned(),
            style,
            width: layout.width().ceil() as i32,
            ascent: 0.0,
            descent: 0.0,
            glyphs: Vec::new(),
        };
        let Some(line) = layout.lines().next() else {
            return shaped;
        };
        let metrics = line.metrics();
        shaped.ascent = metrics.ascent;
        shaped.descent = metrics.descent;
        let baseline = metrics.ascent.round();
        let line_baseline = metrics.baseline;

        for item in line.items() {
            let PositionedLayoutItem::GlyphRun(glyph_run) = item else {
                continue;
            };
            let run = glyph_run.run();
            let font = run.font();
            let size = run.font_size();
            let coords: Vec<i16> = run.normalized_coords().to_vec();
            let Ok(font_ref) = FontRef::from_index(font.data.as_ref(), font.index) else {
                continue;
            };
            let instance = self.instance(&font_ref, font.data.id(), font.index, size, &coords);
            for glyph in glyph_run.positioned_glyphs() {
                let x = PAD + glyph.x.round() as i32;
                let y = PAD + (baseline + glyph.y - line_baseline).round() as i32;
                if let Some((image, dx, dy)) = self.bitmap(&font_ref, font.data.id(), font.index, glyph.id, size) {
                    shaped.glyphs.push(PlacedGlyph { path: Arc::new(BezPath::new()), x: x + dx, y: y + dy, image: Some(image) });
                    continue;
                }
                let path = self.outline(&font_ref, instance, glyph.id, size, &coords);
                shaped.glyphs.push(PlacedGlyph { path, x, y, image: None });
            }
        }
        shaped
    }

    fn instance(&mut self, font: &FontRef, blob: u64, index: u32, size: f32, coords: &[i16]) -> usize {
        let key = InstanceKey { blob, index, size_bits: size.to_bits(), coords: coords.to_vec() };
        if let Some(id) = self.instance_ids.get(&key) {
            return *id;
        }
        let outlines = font.outline_glyphs();
        let location = location(coords);
        let hinting = hinting_options(self.rendering).and_then(|options| {
            HintingInstance::new(&outlines, Size::new(size), LocationRef::new(&location), options).ok()
        });
        let family = font
            .localized_strings(StringId::FAMILY_NAME)
            .english_or_first()
            .map(|n| n.to_string())
            .unwrap_or_default();
        let subfamily = font
            .localized_strings(StringId::SUBFAMILY_NAME)
            .english_or_first()
            .map(|n| n.to_string())
            .unwrap_or_default();
        eprintln!(
            "text: face \"{family} {subfamily}\" {size}px coords={coords:?} hinted={}",
            hinting.is_some()
        );
        self.instances.push(hinting);
        let id = self.instances.len() - 1;
        self.instance_ids.insert(key, id);
        id
    }

    /// The glyph's colour bitmap scaled to `size` once, and its top-left
    /// against the pen position on the baseline. Only a 32-bit strike is
    /// colour; a mask strike is a monochrome bitmap the outline covers.
    fn bitmap(&mut self, font: &FontRef, blob: u64, index: u32, glyph: u32, size: f32) -> Option<(crate::scene::Bitmap, i32, i32)> {
        let key = (blob, index, glyph, size.to_bits());
        if let Some(hit) = self.bitmaps.get(&key) {
            return hit.clone();
        }
        let strikes = BitmapStrikes::new(font);
        let found = if strikes.is_empty() { None } else { strikes.glyph_for_size(Size::new(size), GlyphId::new(glyph)) };
        let placed = found.and_then(|g| {
            let rgba = match g.data {
                BitmapData::Png(bytes) => image::load_from_memory_with_format(bytes, image::ImageFormat::Png).ok()?.into_rgba8(),
                BitmapData::Bgra(bytes) => {
                    let mut px = bytes.to_vec();
                    for p in px.chunks_exact_mut(4) {
                        p.swap(0, 2);
                        // Premultiplied in the table; from_rgba wants it straight.
                        let a = u32::from(p[3]);
                        if a > 0 {
                            for c in &mut p[..3] {
                                *c = ((u32::from(*c) * 255 + a / 2) / a).min(255) as u8;
                            }
                        }
                    }
                    image::RgbaImage::from_raw(g.width, g.height, px)?
                }
                BitmapData::Mask(_) => return None,
            };
            let scale = size / g.ppem_y.max(1.0);
            let w = ((rgba.width() as f32 * scale).round() as u32).max(1);
            let h = ((rgba.height() as f32 * scale).round() as u32).max(1);
            let scaled = image::imageops::resize(&rgba, w, h, image::imageops::FilterType::Triangle);
            let dx = (g.inner_bearing_x * scale).round() as i32;
            let dy = -(g.inner_bearing_y * scale).round() as i32;
            Some((crate::scene::Bitmap::from_rgba(w as u16, h as u16, scaled.into_raw()), dx, dy))
        });
        self.bitmaps.insert(key, placed.clone());
        placed
    }

    fn outline(&mut self, font: &FontRef, instance: usize, glyph: u32, size: f32, coords: &[i16]) -> Arc<BezPath> {
        let key = GlyphKey { instance, glyph };
        if let Some(path) = self.outlines.get(&key) {
            return path.clone();
        }
        let hinting = self.instances[instance].as_ref();
        let mut pen = FlipPen(BezPath::new());
        if let Some(outline) = font.outline_glyphs().get(GlyphId::new(glyph)) {
            let location = location(coords);
            let drawn = match hinting {
                Some(h) => outline.draw(DrawSettings::hinted(h, false), &mut pen),
                None => outline.draw(DrawSettings::unhinted(Size::new(size), LocationRef::new(&location)), &mut pen),
            };
            if drawn.is_err() {
                pen.0 = BezPath::new();
            }
        }
        let path = Arc::new(pen.0);
        self.outlines.insert(key, path.clone());
        path
    }
}

/// Byte ranges of emoji sequences: pictographs, regional indicators, skin
/// tones, and anything carrying VS16, with the joiners, keycaps and tags
/// that bind them.
fn emoji_runs(source: &str) -> Vec<std::ops::Range<usize>> {
    let chars: Vec<(usize, char)> = source.char_indices().collect();
    let pictographic = |c: char| matches!(c as u32, 0x1F000..=0x1FAFF | 0x2600..=0x27BF | 0x2B00..=0x2BFF);
    let binding = |c: char| matches!(c as u32, 0xFE0F | 0x200D | 0x20E3 | 0xE0020..=0xE007F);
    let mut runs: Vec<std::ops::Range<usize>> = Vec::new();
    for (i, &(at, c)) in chars.iter().enumerate() {
        let next_vs16 = chars.get(i + 1).is_some_and(|&(_, n)| n == '\u{FE0F}' || n == '\u{20E3}');
        let wide = (c as u32) >= 0x1F000 && pictographic(c);
        let continues = binding(c) && runs.last().is_some_and(|r| r.end == at);
        if wide || next_vs16 || continues {
            let end = at + c.len_utf8();
            match runs.last_mut() {
                Some(r) if r.end == at => r.end = end,
                _ => runs.push(at..end),
            }
        }
    }
    runs
}

fn location(coords: &[i16]) -> Vec<NormalizedCoord> {
    coords.iter().map(|c| F2Dot14::from_bits(*c)).collect()
}

/// fontconfig's hintstyle onto skrifa's targets, the way cairo maps it onto
/// FreeType's load targets: slight is FreeType's light target, which runs
/// the autohinter on the vertical axis only, medium and full are the normal
/// target. Grayscale throughout, whatever `rgba` says, so subpixel layouts
/// are not asked for.
fn hinting_options(r: Rendering) -> Option<HintingOptions> {
    if !r.antialias || !r.hinting {
        return None;
    }
    let (engine, mode) = match r.hint_style {
        HintStyle::None => return None,
        HintStyle::Slight => (Engine::Auto(None), SmoothMode::Light),
        HintStyle::Medium | HintStyle::Full => (Engine::AutoFallback, SmoothMode::Normal),
    };
    Some(HintingOptions {
        engine,
        target: Target::Smooth { mode, symmetric_rendering: true, preserve_linear_metrics: true },
    })
}

/// skrifa draws y-up in pixels; the scene is y-down.
struct FlipPen(BezPath);

impl OutlinePen for FlipPen {
    fn move_to(&mut self, x: f32, y: f32) {
        self.0.move_to((x as f64, -y as f64));
    }

    fn line_to(&mut self, x: f32, y: f32) {
        self.0.line_to((x as f64, -y as f64));
    }

    fn quad_to(&mut self, cx0: f32, cy0: f32, x: f32, y: f32) {
        self.0.quad_to((cx0 as f64, -cy0 as f64), (x as f64, -y as f64));
    }

    fn curve_to(&mut self, cx0: f32, cy0: f32, cx1: f32, cy1: f32, x: f32, y: f32) {
        self.0.curve_to((cx0 as f64, -cy0 as f64), (cx1 as f64, -cy1 as f64), (x as f64, -y as f64));
    }

    fn close(&mut self) {
        self.0.close_path();
    }
}
