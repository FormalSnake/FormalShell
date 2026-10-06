//! A retained scene: nodes in paint order, each with the device-pixel bounds
//! it covers. Every change marks the old and the new bounds dirty, and the
//! renderer redraws only the dirty rects.

use vello_cpu::kurbo::{Affine, BezPath, Rect};

use crate::text::ShapedText;
use crate::theme::Rgba;

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

pub enum Paint {
    Rect { fill: Rgba, radius: f32 },
    Text { text: ShapedText, color: Rgba },
    /// A filled outline and its strokes, in the node's own coordinates.
    Shape { fill: Option<(BezPath, Rgba)>, strokes: Vec<(BezPath, Rgba, f64)> },
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

pub struct Scene {
    pub size: IRect,
    nodes: Vec<Node>,
    damage: Vec<IRect>,
}

impl Scene {
    pub fn new(width: i32, height: i32) -> Self {
        let size = IRect::new(0, 0, width, height);
        Self { size, nodes: Vec::new(), damage: vec![size] }
    }

    pub fn resize(&mut self, width: i32, height: i32) {
        self.size = IRect::new(0, 0, width, height);
        self.damage = vec![self.size];
    }

    pub fn add(&mut self, bounds: IRect, paint: Paint) -> NodeId {
        self.nodes.push(Node { bounds, paint, visible: true, transform: Affine::IDENTITY, clip: None });
        self.mark(bounds);
        NodeId(self.nodes.len() - 1)
    }

    pub fn nodes(&self) -> impl Iterator<Item = &Node> {
        self.nodes.iter().filter(|n| n.visible)
    }

    /// Replaces a node's bounds and paint, damaging both rects only when
    /// something actually changed.
    pub fn update(&mut self, id: NodeId, bounds: IRect, paint: Paint, visible: bool) {
        let (transform, clip) = (self.nodes[id.0].transform, self.nodes[id.0].clip);
        self.update_with(id, bounds, paint, visible, transform, clip);
    }

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
        // Shapes and casts are rebuilt only by an animation tick, which has
        // already moved them.
        _ => false,
    }
}
