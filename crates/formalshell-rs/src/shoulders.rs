//! Components/shoulders.js's outline for a card on a top line with no wall
//! and no far gap, and Shoulders.qml's three paths built from it.

use vello_cpu::kurbo::{Arc, BezPath, Point, SvgArc, Vec2};

pub fn fillet_radius(radius: f64, depth: f64) -> f64 {
    radius.min(depth).max(0.0)
}

struct Outline {
    p: [Point; 8],
    /// Per corner arc in path order: radius and whether it is concave.
    arcs: [(f64, bool); 4],
}

/// `outline(edge = "top", ...)` with `walls` and `farGap` absent.
fn outline(width: f64, height: f64, radius: f64, inset: f64, near: f64, corner: f64, lip: f64) -> Outline {
    let r = radius.max(0.0);
    let i = inset.max(0.0);
    let n = near.max(0.0);
    let over = r;
    let depth = height;
    let length = (width - over * 2.0).max(0.0);
    let body = (depth - n).max(0.0);
    let l = lip.max(0.0).min(body);
    let rc = (r.min(length.min(body) / 2.0) - i).max(0.0);
    let concave = corner >= 0.0;
    let rn = if concave {
        if corner > 0.0 { fillet_radius(corner, body) + i } else { 0.0 }
    } else {
        ((-corner).min(length.min(body) / 2.0) - i).max(0.0)
    };
    let signed = if concave { rn } else { -rn };
    let far = depth - i;
    let top = n + i + l;
    let run_start = i + rc;
    let run_end = length - i - rc;
    let canonical = [
        (i - signed, top),
        (i, top + rn),
        (i, far - rc),
        (run_start, far),
        (run_end, far),
        (length - i, far - rc),
        (length - i, top + rn),
        (length - i + signed, top),
    ];
    Outline {
        p: canonical.map(|(u, v)| Point::new(over + u, v)),
        arcs: [(rn, concave), (rc, false), (rc, false), (rn, concave)],
    }
}

/// PathArc from the pen to `to`: Qt's `Clockwise` is SVG's sweep flag on a
/// y-down canvas. A top edge is never mirrored, so concave sweeps
/// clockwise and convex counterclockwise.
fn arc_to(path: &mut BezPath, from: Point, to: Point, (r, concave): (f64, bool)) {
    let svg = SvgArc { from, to, radii: Vec2::new(r, r), x_rotation: 0.0, large_arc: false, sweep: concave };
    match Arc::from_svg_arc(&svg) {
        Some(arc) => path.extend(arc.append_iter(0.05)),
        None => path.line_to(to),
    }
}

pub struct Paths {
    pub fill: BezPath,
    /// The three faces toward the desktop.
    pub outer: BezPath,
    /// The near edge, drawn at `1 - attach` of the border's alpha.
    pub near: BezPath,
}

/// The fill and stroke of a Shoulders item `width` x `height`, its origin
/// at the item's top-left.
pub fn paths(width: f64, height: f64, radius: f64, border: f64, attach: f64, near_inset: f64) -> Paths {
    let a = attach.clamp(0.0, 1.0);
    let corner = radius * (2.0 * a - 1.0);

    let f = outline(width, height, radius, 0.0, near_inset, corner, border * a);
    let mut fill = BezPath::new();
    fill.move_to(f.p[0]);
    arc_to(&mut fill, f.p[0], f.p[1], f.arcs[0]);
    fill.line_to(f.p[2]);
    arc_to(&mut fill, f.p[2], f.p[3], f.arcs[1]);
    fill.line_to(f.p[4]);
    arc_to(&mut fill, f.p[4], f.p[5], f.arcs[2]);
    fill.line_to(f.p[6]);
    arc_to(&mut fill, f.p[6], f.p[7], f.arcs[3]);
    fill.close_path();

    let s = outline(width, height, radius, border / 2.0, near_inset, corner, 0.0);
    let mut outer = BezPath::new();
    outer.move_to(s.p[0]);
    arc_to(&mut outer, s.p[0], s.p[1], s.arcs[0]);
    outer.line_to(s.p[2]);
    arc_to(&mut outer, s.p[2], s.p[3], s.arcs[1]);
    outer.line_to(s.p[4]);
    arc_to(&mut outer, s.p[4], s.p[5], s.arcs[2]);
    outer.line_to(s.p[6]);
    arc_to(&mut outer, s.p[6], s.p[7], s.arcs[3]);

    let mut near = BezPath::new();
    near.move_to(s.p[7]);
    near.line_to(s.p[0]);

    Paths { fill, outer, near }
}
