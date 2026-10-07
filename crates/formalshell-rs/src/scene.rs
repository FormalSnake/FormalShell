//! A retained scene: nodes in paint order, each with the device-pixel bounds
//! it covers. Every change marks the old and the new bounds dirty, and the
//! renderer redraws only the dirty rects.

use std::sync::Arc;

use vello_cpu::kurbo::{Affine, BezPath, Rect};
use vello_cpu::{PixelMetadata, Pixmap};

use crate::text::ShapedText;
use fs_theme::color::Rgba;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct IRect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

impl IRect {
    pub const fn new(x: i32, y: i32, w: i32, h: i32) -> Self {
        Self { x, y, w, h }
    }

    pub fn is_empty(&self) -> bool {
        self.w <= 0 || self.h <= 0
    }

    pub fn right(&self) -> i32 {
        self.x + self.w
    }

    pub fn bottom(&self) -> i32 {
        self.y + self.h
    }

    pub fn intersect(&self, o: &IRect) -> IRect {
        let x = self.x.max(o.x);
        let y = self.y.max(o.y);
        IRect::new(x, y, self.right().min(o.right()) - x, self.bottom().min(o.bottom()) - y)
    }

    pub fn intersects(&self, o: &IRect) -> bool {
        !self.intersect(o).is_empty()
    }

    pub fn contains(&self, o: &IRect) -> bool {
        o.x >= self.x && o.y >= self.y && o.right() <= self.right() && o.bottom() <= self.bottom()
    }

    pub fn union(&self, o: &IRect) -> IRect {
        let x = self.x.min(o.x);
        let y = self.y.min(o.y);
        IRect::new(x, y, self.right().max(o.right()) - x, self.bottom().max(o.bottom()) - y)
    }

    pub fn area(&self) -> i64 {
        if self.is_empty() { 0 } else { self.w as i64 * self.h as i64 }
    }
}

/// One of a Box's casts (Components/Box.qml): CSS's offset, blur radius
/// and spread, drawn analytically.
#[derive(Clone, Copy, Debug)]
pub struct Cast {
    pub x: f64,
    pub y: f64,
    pub blur: f64,
    pub spread: f64,
    pub color: Rgba,
}

/// A decoded picture ready to draw at its own size (a tray icon, a menu row's
/// icon): premultiplied, shared between the nodes that show it.
#[derive(Clone)]
pub struct Bitmap {
    pub pixmap: Arc<Pixmap>,
}

impl Bitmap {
    /// `rgba` is straight alpha, `width * height * 4` bytes.
    pub fn from_rgba(width: u16, height: u16, mut rgba: Vec<u8>) -> Self {
        for px in rgba.chunks_exact_mut(4) {
            let a = px[3] as u32;
            for c in &mut px[..3] {
                *c = ((*c as u32 * a + 127) / 255) as u8;
            }
        }
        Self::from_premultiplied(width, height, rgba)
    }

    /// `rgba` already premultiplied, `width * height * 4` bytes.
    pub fn from_premultiplied(width: u16, height: u16, rgba: Vec<u8>) -> Self {
        Self { pixmap: Arc::new(Pixmap::from_parts(rgba, width, height, PixelMetadata::default())) }
    }

    pub fn same_as(&self, other: &Bitmap) -> bool {
        Arc::ptr_eq(&self.pixmap, &other.pixmap)
    }
}

impl std::fmt::Debug for Bitmap {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Bitmap({}x{})", self.pixmap.width(), self.pixmap.height())
    }
}

impl Cast {
    fn same(&self, o: &Cast) -> bool {
        (self.x, self.y, self.blur, self.spread) == (o.x, o.y, o.blur, o.spread) && self.color == o.color
    }
}

pub enum Paint {
    Rect { fill: Rgba, radius: f32 },
    /// A bitmap drawn at the node's bounds origin, one pixel to a pixel.
    Image { image: Bitmap, alpha: f32 },
    /// A bitmap stretched over the node's bounds inside a rounded rect (a
    /// window thumbnail).
    Picture { image: Bitmap, alpha: f32, radius: f32 },
    /// A rounded rect's fill under a border drawn inside its edge.
    Framed { fill: Rgba, radius: f32, border: Rgba, width: f32 },
    Text { text: ShapedText, color: Rgba },
    /// A line under a real Gaussian blur of `blur` px (the lyrics pane's
    /// depth of field), placed the way `Text` is.
    Blur { text: ShapedText, color: Rgba, blur: f32 },
    /// A blurred copy of a line under its crisp one (Components/InkGlow.qml):
    /// the glyphs offset by `x`, `y` and smeared over `blur` pixels.
    Glow { text: ShapedText, color: Rgba, x: f32, y: f32, blur: f32 },
    /// A filled outline and its strokes, in the node's own coordinates.
    Shape { fill: Option<(BezPath, Rgba)>, strokes: Vec<(BezPath, Rgba, f64)> },
    /// A rounded rect filled top to bottom from one colour to another
    /// (a Box's `face`).
    Face { from: Rgba, to: Rgba, radius: f32 },
    /// Casts under a rounded rect, cut out of the rect's own shape so a
    /// translucent fill over them shows the desktop and not the shadow.
    Casts { rect: Rect, radius: f64, layers: Vec<Cast>, cutout: BezPath },
}

pub struct Node {
    pub bounds: IRect,
    pub paint: Paint,
    pub visible: bool,
    /// From the node's own coordinates to device pixels, after the bounds'
    /// origin for text and before it for everything else.
    pub transform: Affine,
    pub clip: Option<IRect>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NodeId(usize);

/// Nodes live in a slab; `order` is paint order, so a node can be inserted
/// beside another (a widget's wash between its fill and its text) without
/// moving any id.
pub struct Scene {
    pub size: IRect,
    nodes: Vec<Node>,
    order: Vec<NodeId>,
    free: Vec<NodeId>,
    damage: Vec<IRect>,
}

impl Scene {
    pub fn new(width: i32, height: i32) -> Self {
        let size = IRect::new(0, 0, width, height);
        Self { size, nodes: Vec::new(), order: Vec::new(), free: Vec::new(), damage: vec![size] }
    }

    /// A scene whose buffers start out transparent and so owe the
    /// compositor nothing until a node is drawn.
    pub fn clear(width: i32, height: i32) -> Self {
        Self { damage: Vec::new(), ..Self::new(width, height) }
    }

    pub fn resize(&mut self, width: i32, height: i32) {
        self.size = IRect::new(0, 0, width, height);
        self.damage = vec![self.size];
    }

    pub fn add(&mut self, bounds: IRect, paint: Paint) -> NodeId {
        self.add_after(None, bounds, paint)
    }

    /// A node painted right after `prev`, or on top of everything.
    pub fn add_after(&mut self, prev: Option<NodeId>, bounds: IRect, paint: Paint) -> NodeId {
        let node = Node { bounds, paint, visible: true, transform: Affine::IDENTITY, clip: None };
        let id = match self.free.pop() {
            Some(id) => {
                self.nodes[id.0] = node;
                id
            }
            None => {
                self.nodes.push(node);
                NodeId(self.nodes.len() - 1)
            }
        };
        let at = prev.and_then(|p| self.order.iter().position(|o| *o == p)).map_or(self.order.len(), |i| i + 1);
        self.order.insert(at, id);
        self.mark(bounds);
        id
    }

    /// Drops a node for good; its id may be handed out again.
    pub fn remove(&mut self, id: NodeId) {
        self.set_visible(id, false);
        if let Some(i) = self.order.iter().position(|o| *o == id) {
            self.order.remove(i);
            self.free.push(id);
        }
    }

    pub fn nodes(&self) -> impl Iterator<Item = &Node> {
        self.order.iter().map(|id| &self.nodes[id.0]).filter(|n| n.visible)
    }

    /// Damage with no node behind it: the one rect a first commit carries.
    pub fn touch(&mut self, rect: IRect) {
        self.mark(rect);
    }

    /// Replaces a node's bounds and paint, damaging both rects only when
    /// something actually changed.
    pub fn update_with(
        &mut self,
        id: NodeId,
        bounds: IRect,
        paint: Paint,
        visible: bool,
        transform: Affine,
        clip: Option<IRect>,
    ) {
        let node = &self.nodes[id.0];
        let same = node.visible == visible
            && node.bounds == bounds
            && node.transform == transform
            && node.clip == clip
            && paint_eq(&node.paint, &paint);
        if same {
            return;
        }
        let old = if node.visible { node.bounds } else { IRect::default() };
        self.nodes[id.0] = Node { bounds, paint, visible, transform, clip };
        self.mark(old);
        if visible {
            self.mark(bounds);
        }
    }

    pub fn set_visible(&mut self, id: NodeId, visible: bool) {
        if self.nodes[id.0].visible != visible {
            self.nodes[id.0].visible = visible;
            let b = self.nodes[id.0].bounds;
            self.mark(b);
        }
    }

    fn mark(&mut self, rect: IRect) {
        let rect = rect.intersect(&self.size);
        if rect.is_empty() {
            return;
        }
        // Overlapping or touching rects merge, so a cell that changed width
        // is one rect rather than two slivers.
        let mut merged = rect;
        loop {
            let grown = IRect::new(merged.x - 1, merged.y - 1, merged.w + 2, merged.h + 2);
            let before = self.damage.len();
            self.damage.retain(|d| {
                if d.intersects(&grown) {
                    merged = merged.union(d);
                    false
                } else {
                    true
                }
            });
            if self.damage.len() == before {
                break;
            }
        }
        self.damage.push(merged);
    }

    /// A rect's device bounds once transformed, padded for antialiasing.
    pub fn cover(rect: Rect, transform: Affine, pad: f64) -> IRect {
        let r = transform.transform_rect_bbox(rect).inflate(pad, pad);
        let (x0, y0) = (r.x0.floor() as i32, r.y0.floor() as i32);
        IRect::new(x0, y0, r.x1.ceil() as i32 - x0, r.y1.ceil() as i32 - y0)
    }

    pub fn has_damage(&self) -> bool {
        !self.damage.is_empty()
    }

    pub fn take_damage(&mut self) -> Vec<IRect> {
        std::mem::take(&mut self.damage)
    }
}

fn paint_eq(a: &Paint, b: &Paint) -> bool {
    match (a, b) {
        (Paint::Rect { fill: f1, radius: r1 }, Paint::Rect { fill: f2, radius: r2 }) => f1 == f2 && r1 == r2,
        (Paint::Text { text: t1, color: c1 }, Paint::Text { text: t2, color: c2 }) => c1 == c2 && t1.same_as(t2),
        (Paint::Blur { text: t1, color: c1, blur: b1 }, Paint::Blur { text: t2, color: c2, blur: b2 }) => {
            c1 == c2 && b1 == b2 && t1.same_as(t2)
        }
        (
            Paint::Framed { fill: f1, radius: r1, border: b1, width: w1 },
            Paint::Framed { fill: f2, radius: r2, border: b2, width: w2 },
        ) => f1 == f2 && r1 == r2 && b1 == b2 && w1 == w2,
        (Paint::Glow { text: t1, color: c1, x: x1, y: y1, blur: b1 }, Paint::Glow { text: t2, color: c2, x: x2, y: y2, blur: b2 }) => {
            c1 == c2 && t1.same_as(t2) && x1 == x2 && y1 == y2 && b1 == b2
        }
        (Paint::Image { image: i1, alpha: a1 }, Paint::Image { image: i2, alpha: a2 }) => a1 == a2 && i1.same_as(i2),
        (Paint::Picture { image: i1, alpha: a1, radius: r1 }, Paint::Picture { image: i2, alpha: a2, radius: r2 }) => {
            a1 == a2 && r1 == r2 && i1.same_as(i2)
        }
        (Paint::Shape { fill: f1, strokes: s1 }, Paint::Shape { fill: f2, strokes: s2 }) => f1 == f2 && s1 == s2,
        (
            Paint::Casts { rect: r1, radius: a1, layers: l1, cutout: c1 },
            Paint::Casts { rect: r2, radius: a2, layers: l2, cutout: c2 },
        ) => r1 == r2 && a1 == a2 && c1 == c2 && l1.len() == l2.len() && l1.iter().zip(l2).all(|(a, b)| a.same(b)),
        (Paint::Face { from: f1, to: t1, radius: r1 }, Paint::Face { from: f2, to: t2, radius: r2 }) => {
            f1 == f2 && t1 == t2 && r1 == r2
        }
        _ => false,
    }
}
