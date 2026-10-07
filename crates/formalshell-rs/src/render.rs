//! Rasterises dirty rects of the scene into one persistent premultiplied
//! RGBA canvas. Only nodes crossing a rect are encoded, and only that rect is
//! rasterised; the rest of the canvas keeps what it last held.

use vello_cpu::color::{AlphaColor, Srgb};
use vello_cpu::kurbo::{Affine, Cap, Join, Rect, RoundedRect, Shape, Stroke, Vec2};
use vello_cpu::peniko::{BlendMode, Compose, Fill, Mix};
use vello_cpu::{Pixmap, RenderContext, Resources};

use crate::scene::{IRect, Paint, Scene};
use fs_theme::color::Rgba;

pub struct Renderer {
    ctx: RenderContext,
    resources: Resources,
    canvas: Pixmap,
}

impl Renderer {
    pub fn new(width: u16, height: u16) -> Self {
        Self {
            ctx: RenderContext::new(1, 1),
            resources: Resources::new(),
            canvas: Pixmap::new(width, height),
        }
    }

    pub fn resize(&mut self, width: u16, height: u16) {
        self.canvas = Pixmap::new(width, height);
    }

    pub fn width(&self) -> u16 {
        self.canvas.width()
    }

    pub fn height(&self) -> u16 {
        self.canvas.height()
    }

    pub fn canvas(&self) -> &Pixmap {
        &self.canvas
    }

    pub fn render(&mut self, scene: &Scene, rect: IRect) {
        let rect = rect.intersect(&scene.size);
        if rect.is_empty() {
            return;
        }
        let (w, h) = (rect.w as u16, rect.h as u16);
        self.ctx.reset_and_resize(w, h);
        let origin = Affine::translate((-rect.x as f64, -rect.y as f64));
        // A clip is a layer composited on its own, so a run of nodes under
        // one clip shares a layer, and a node the clip cannot cut (its box
        // inside the clip, moved by a plain translation at most) needs none.
        // A launcher frame is a few hundred rows under the body's one clip.
        let mut active: Option<IRect> = None;
        for node in scene.nodes().filter(|n| n.bounds.intersects(&rect)) {
            // Casts and glows paint past their own box.
            let spills = matches!(node.paint, Paint::Casts { .. } | Paint::Glow { .. });
            let drawn = drawn_box(node.bounds, node.transform).filter(|_| !spills);
            let inside = |c: &IRect| drawn.is_some_and(|d| c.contains(&d));
            let want = node.clip.filter(|c| !inside(c));
            match want {
                Some(c) if active != Some(c) => {
                    if active.is_some() {
                        self.ctx.pop_layer();
                    }
                    self.ctx.set_transform(origin);
                    let r = Rect::new(c.x as f64, c.y as f64, c.right() as f64, c.bottom() as f64);
                    self.ctx.push_clip_layer(&r.to_path(0.1));
                    active = Some(c);
                }
                None if active.is_some_and(|a| !inside(&a)) => {
                    self.ctx.pop_layer();
                    active = None;
                }
                _ => {}
            }
            let at = origin * node.transform;
            match &node.paint {
                Paint::Rect { fill, radius } => {
                    self.ctx.set_transform(at);
                    self.ctx.set_paint(color(*fill));
                    let b = node.bounds;
                    let r = Rect::new(b.x as f64, b.y as f64, b.right() as f64, b.bottom() as f64);
                    if *radius > 0.0 {
                        self.ctx.fill_path(&RoundedRect::from_rect(r, *radius as f64).to_path(0.1));
                    } else {
                        self.ctx.fill_rect(&r);
                    }
                }
                Paint::Framed { fill, radius, border, width } => {
                    self.ctx.set_transform(at);
                    let b = node.bounds;
                    let r = Rect::new(b.x as f64, b.y as f64, b.right() as f64, b.bottom() as f64);
                    let rr = |r: Rect, radius: f64| RoundedRect::from_rect(r, radius.max(0.0)).to_path(0.1);
                    if fill.to_u8()[3] > 0 {
                        self.ctx.set_paint(color(*fill));
                        self.ctx.fill_path(&rr(r, *radius as f64));
                    }
                    if *width > 0.0 && border.to_u8()[3] > 0 {
                        let half = *width as f64 / 2.0;
                        self.ctx.set_stroke(Stroke::new(*width as f64));
                        self.ctx.set_paint(color(*border));
                        self.ctx.stroke_path(&rr(r.inflate(-half, -half), *radius as f64 - half));
                    }
                }
                Paint::Face { from, to, radius } => {
                    self.ctx.set_transform(at);
                    let b = node.bounds;
                    let r = Rect::new(b.x as f64, b.y as f64, b.right() as f64, b.bottom() as f64);
                    let gradient = vello_cpu::peniko::Gradient::new_linear((r.x0, r.y0), (r.x0, r.y1))
                        .with_stops([color(*from), color(*to)]);
                    self.ctx.set_paint(gradient);
                    self.ctx.fill_path(&RoundedRect::from_rect(r, (*radius as f64).max(0.0)).to_path(0.1));
                }
                Paint::Glow { text, color: ink, x, y, blur } => {
                    // A box of taps over the blur's reach, each carrying its
                    // share of the alpha: cheap, and close enough at the 2px
                    // the tables ask for.
                    let reach = (*blur / 2.0).max(0.0);
                    let taps: &[(f32, f32)] = if reach < 0.25 {
                        &[(0.0, 0.0)]
                    } else {
                        &[(0.0, 0.0), (-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0), (-0.7, -0.7), (0.7, -0.7), (-0.7, 0.7), (0.7, 0.7)]
                    };
                    let share = ink.with_alpha(ink.a / taps.len() as f32 * if taps.len() > 1 { 2.0 } else { 1.0 });
                    self.ctx.set_paint(color(share));
                    for (dx, dy) in taps {
                        for glyph in &text.glyphs {
                            let p = (
                                node.bounds.x as f32 + glyph.x as f32 + x + dx * reach,
                                node.bounds.y as f32 + glyph.y as f32 + y + dy * reach,
                            );
                            self.ctx.set_transform(at * Affine::translate((p.0 as f64, p.1 as f64)));
                            self.ctx.fill_path(&glyph.path);
                        }
                    }
                }
                Paint::Text { text, color: ink } => {
                    for glyph in &text.glyphs {
                        let p = (node.bounds.x + glyph.x, node.bounds.y + glyph.y);
                        self.ctx.set_transform(at * Affine::translate((p.0 as f64, p.1 as f64)));
                        if let Some(image) = &glyph.image {
                            // A colour glyph keeps its own colours and takes only the ink's alpha.
                            self.ctx.set_paint(vello_cpu::Image {
                                image: vello_cpu::ImageSource::Pixmap(image.pixmap.clone()),
                                sampler: vello_cpu::peniko::ImageSampler::default().with_alpha(ink.a),
                            });
                            self.ctx.fill_rect(&Rect::new(0.0, 0.0, image.pixmap.width() as f64, image.pixmap.height() as f64));
                        } else {
                            self.ctx.set_paint(color(*ink));
                            self.ctx.fill_path(&glyph.path);
                        }
                    }
                }
                Paint::Image { image, alpha } => {
                    let b = node.bounds;
                    self.ctx.set_transform(at * Affine::translate((b.x as f64, b.y as f64)));
                    let sampler = vello_cpu::peniko::ImageSampler::default().with_alpha(*alpha);
                    self.ctx.set_paint(vello_cpu::Image {
                        image: vello_cpu::ImageSource::Pixmap(image.pixmap.clone()),
                        sampler,
                    });
                    let (w, h) = (image.pixmap.width() as f64, image.pixmap.height() as f64);
                    self.ctx.fill_rect(&Rect::new(0.0, 0.0, w, h));
                }
                Paint::Picture { image, alpha, radius } => {
                    let b = node.bounds;
                    let r = Rect::new(b.x as f64, b.y as f64, b.right() as f64, b.bottom() as f64);
                    let (iw, ih) = (image.pixmap.width() as f64, image.pixmap.height() as f64);
                    self.ctx.set_transform(at);
                    self.ctx.set_paint_transform(
                        Affine::translate((r.x0, r.y0)) * Affine::scale_non_uniform(r.width() / iw.max(1.0), r.height() / ih.max(1.0)),
                    );
                    let sampler = vello_cpu::peniko::ImageSampler::default().with_alpha(*alpha);
                    self.ctx.set_paint(vello_cpu::Image { image: vello_cpu::ImageSource::Pixmap(image.pixmap.clone()), sampler });
                    self.ctx.fill_path(&RoundedRect::from_rect(r, (*radius as f64).max(0.0)).to_path(0.1));
                    self.ctx.reset_paint_transform();
                }
                Paint::Shape { fill, strokes } => {
                    self.ctx.set_transform(at);
                    if let Some((path, ink)) = fill {
                        // Even-odd, so a band carries its cut-out as a second subpath.
                        self.ctx.set_fill_rule(Fill::EvenOdd);
                        self.ctx.set_paint(color(*ink));
                        self.ctx.fill_path(path);
                        self.ctx.set_fill_rule(Fill::NonZero);
                    }
                    for (path, ink, width) in strokes {
                        if ink.to_u8()[3] == 0 {
                            continue;
                        }
                        // ShapePath's own defaults.
                        self.ctx.set_stroke(Stroke::new(*width).with_caps(Cap::Square).with_join(Join::Bevel));
                        self.ctx.set_paint(color(*ink));
                        self.ctx.stroke_path(path);
                    }
                }
                Paint::Casts { rect: card, radius, layers, cutout } => {
                    self.ctx.set_transform(at);
                    self.ctx.push_layer(None, None, None, None, None);
                    for cast in layers {
                        let shrink = (-cast.spread).max(0.0);
                        let grow = cast.spread.max(0.0);
                        let r = card.inflate(grow - shrink, grow - shrink) + Vec2::new(cast.x, cast.y);
                        self.ctx.set_paint(color(cast.color));
                        // RectangularShadow's blur is CSS's blur radius, twice the deviation.
                        self.ctx.fill_blurred_rounded_rect(&r, (radius - shrink).max(0.0) as f32, (cast.blur / 2.0) as f32, false);
                    }
                    self.ctx.push_layer(None, Some(BlendMode::new(Mix::Normal, Compose::DestOut)), None, None, None);
                    self.ctx.set_paint(color(Rgba::hex(0)));
                    self.ctx.fill_path(cutout);
                    self.ctx.pop_layer();
                    self.ctx.pop_layer();
                }
            }
        }
        if active.is_some() {
            self.ctx.pop_layer();
        }
        self.ctx.flush();
        let mut tile = Pixmap::new(w, h);
        self.ctx.render(&mut tile, &mut self.resources);

        let stride = self.canvas.width() as usize;
        let src = tile.data();
        let dst = self.canvas.data_mut();
        for row in 0..rect.h as usize {
            let d = (rect.y as usize + row) * stride + rect.x as usize;
            let s = row * rect.w as usize;
            dst[d..d + rect.w as usize].copy_from_slice(&src[s..s + rect.w as usize]);
        }
    }
}

/// A node's box where it lands, when its transform is a translation (or
/// nothing); `None` for anything that scales, rotates or skews it.
fn drawn_box(bounds: IRect, transform: Affine) -> Option<IRect> {
    let [a, b, c, d, e, f] = transform.as_coeffs();
    if a != 1.0 || b != 0.0 || c != 0.0 || d != 1.0 {
        return None;
    }
    let (dx, dy) = (e.floor() as i32, f.floor() as i32);
    let (ex, ey) = (i32::from(e.fract() != 0.0), i32::from(f.fract() != 0.0));
    Some(IRect::new(bounds.x + dx, bounds.y + dy, bounds.w + ex, bounds.h + ey))
}

fn color(c: Rgba) -> AlphaColor<Srgb> {
    let [r, g, b, a] = c.to_u8();
    AlphaColor::from_rgba8(r, g, b, a)
}
