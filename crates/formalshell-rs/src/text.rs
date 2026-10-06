//! Shaping through parley, outlines through skrifa hinted at the pixel size
//! they are drawn at. Layout advances stay linear; what hinting moves is the
//! outline inside each glyph's box, and every glyph origin and baseline is
//! snapped to a whole device pixel so the hinted stems land on the grid.

use std::collections::HashMap;
use std::sync::Arc;

use parley::{
    FontContext, FontWeight, GenericFamily, Layout, LayoutContext, PositionedLayoutItem,
    StyleProperty,
};
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
pub struct TextStyle {
    pub family: GenericFamily,
    pub size: f32,
    pub weight: f32,
}

/// Room left round the line box for ink that overhangs it (side bearings,
/// overshoot), so a text node's bounds cover everything it paints.
pub const PAD: i32 = 2;

pub struct PlacedGlyph {
    pub path: Arc<BezPath>,
    pub x: i32,
    pub y: i32,
}

/// A shaped single line, glyphs placed relative to the line's top-left with
/// the baseline already on a whole pixel.
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
}

impl Text {
    pub fn new() -> Self {
        let rendering = fontconfig::rendering();
        eprintln!("text: fontconfig {rendering:?}");
        Self {
            fcx: FontContext::new(),
            lcx: LayoutContext::new(),
            rendering,
            instance_ids: HashMap::new(),
            instances: Vec::new(),
            outlines: HashMap::new(),
        }
    }

    pub fn shape(&mut self, source: &str, style: TextStyle) -> ShapedText {
        let mut builder = self.lcx.ranged_builder(&mut self.fcx, source, 1.0, true);
        builder.push_default(StyleProperty::from(style.family));
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
                let path = self.outline(&font_ref, instance, glyph.id, size, &coords);
                shaped.glyphs.push(PlacedGlyph {
                    path,
                    x: PAD + glyph.x.round() as i32,
                    y: PAD + (baseline + glyph.y - line_baseline).round() as i32,
                });
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
