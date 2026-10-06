//! Rasterises dirty rects of the scene into one persistent premultiplied
//! RGBA canvas. Only nodes crossing a rect are encoded, and only that rect is
//! rasterised; the rest of the canvas keeps what it last held.

use vello_cpu::color::{AlphaColor, Srgb};
use vello_cpu::kurbo::{Affine, Rect, RoundedRect, Shape};
use vello_cpu::{Pixmap, RenderContext, Resources};

use crate::scene::{IRect, Paint, Scene};
use crate::theme::Rgba;

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
        for node in scene.nodes().filter(|n| n.bounds.intersects(&rect)) {
            match &node.paint {
                Paint::Rect { fill, radius } => {
                    self.ctx.set_transform(origin);
                    self.ctx.set_paint(color(*fill));
                    let b = node.bounds;
                    let r = Rect::new(b.x as f64, b.y as f64, b.right() as f64, b.bottom() as f64);
                    if *radius > 0.0 {
                        self.ctx.fill_path(&RoundedRect::from_rect(r, *radius as f64).to_path(0.1));
                    } else {
                        self.ctx.fill_rect(&r);
                    }
                }
                Paint::Text { text, color: ink } => {
                    self.ctx.set_paint(color(*ink));
                    for glyph in &text.glyphs {
                        let at = (node.bounds.x + glyph.x, node.bounds.y + glyph.y);
                        self.ctx.set_transform(origin * Affine::translate((at.0 as f64, at.1 as f64)));
                        self.ctx.fill_path(&glyph.path);
                    }
                }
            }
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

fn color(c: Rgba) -> AlphaColor<Srgb> {
    AlphaColor::from_rgba8(c.r, c.g, c.b, c.a)
}
