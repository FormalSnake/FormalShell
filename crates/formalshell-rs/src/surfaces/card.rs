//! A card hanging off the bar's line (Panel.qml over Drawer.qml), on any of
//! the four edges. Under the `join` emerge habit it is DrawerJoin.qml's
//! shape: Presence's emerge on the theme's `emerge` clock, Joint's let-go on
//! `spatialFast`, Deform's springs and Shoulders' outline cut at the line.
//! Under `popover` it is DrawerPopover.qml's: a plain card on its casts,
//! fading on `effects` while it grows out of 0.97 on `spatialFast`.
//!
//! The motion is worked out for a top edge, in the card's own coordinates:
//! `u` along the line, `v` away from the output's edge. [`Card::edge_map`]
//! turns those into the surface's, so every edge shares one implementation.
//! Content is never mirrored: it is placed at the mapped card rect.

use std::time::Instant;

use fs_chrome::types::Edge;
use vello_cpu::kurbo::{Affine, Rect};

use crate::motion::{Animated, Deform, EMERGE, SPATIAL_FAST, SPATIAL_FAST_MS};
use crate::scene::{Cast, IRect, NodeId, Paint, Scene};
use crate::surfaces::shoulders;
use fs_theme::color::Rgba;
use fs_theme::style::Radius;
use fs_theme::theme::Theme;
use serde_json::json;

use crate::services::theme::getter;

/// Drawer.qml's `deformAmount` for a popout.
const DEFORM_AMOUNT: f64 = 0.15;
/// Room past the card's resting rect for the overshoot, the deform's
/// stretch and the cast.
pub const SLACK: i32 = 48;
/// Past any output's edge, for the half-plane beyond the line.
const FAR: f64 = 1.0e5;

/// What the card takes off the theme: the `card` role, and pantheon's card
/// casts for the spike's `cast` switch.
struct Look {
    fill: Rgba,
    border: Rgba,
    border_width: f64,
    radius: f64,
    casts: Vec<fs_theme::style::Cast<Rgba>>,
    popover: bool,
    effects_ms: f64,
}

impl Look {
    fn new(theme: &Theme, cast: bool, role: &str) -> Self {
        let card = theme.box_style(role, None);
        let border = card.border.clone().unwrap_or(fs_theme::style::Line { color: Rgba::TRANSPARENT, width: 0.0 });
        let popover = theme.habit("emerge").and_then(|v| v.as_str()) == Some("popover");
        let casts = if popover {
            card.casts.clone()
        } else if cast {
            let pantheon = Theme::resolve(
                getter(json!({ "theme": { "preset": "pantheon" } })),
                &fs_theme::palette::fallback(&theme.colors.mode),
            );
            pantheon.box_style(role, None).casts
        } else {
            Vec::new()
        };
        Self {
            fill: card.fill,
            border: border.color,
            border_width: border.width,
            radius: match card.radius {
                Radius::Px(px) => px,
                Radius::Pill => theme.radii.xl,
            },
            casts,
            popover,
            effects_ms: theme.motion().families.effects,
        }
    }
}

pub struct Card {
    pub scene: Scene,
    look: Look,
    pub edge: Edge,
    /// The resting rect, `u` along and `v` away from the output's edge.
    rest: Rect,
    line_at: f64,
    /// Where the card was asked to centre along the line, the line's length
    /// and the padding it keeps off either end, for a resize to clamp again.
    anchor: f64,
    length: i32,
    pad: f64,
    open: bool,
    mapped: bool,
    progress: Animated,
    attach: Animated,
    morph: Animated,
    deform: Deform,
    deform_running: bool,
    last_tick: Option<Instant>,
    scale: f64,
    casts: NodeId,
    shape: NodeId,
    /// The join a joined card publishes: along, width, reach.
    pub join: Option<(f64, f64, f64)>,
    /// Where content goes this frame, in surface pixels, and how opaque.
    pub content: (IRect, f32),
}

impl Card {
    /// A card `size` (along, depth) centred along the line on `anchor`,
    /// clamped a `screenPadding` in from either end, a `barMargin` off the
    /// line at `line_at`; `length` is the output's length along the edge.
    #[allow(clippy::too_many_arguments)]
    pub fn new(theme: &Theme, edge: Edge, length: i32, line_at: f64, anchor: f64, size: (f64, f64), scale: f64, cast: bool) -> Self {
        let look = Look::new(theme, cast, "card");
        let (w, h) = size;
        let pad = theme.space.screen_padding;
        let u = (anchor - w / 2.0).clamp(pad, (length as f64 - w - pad).max(pad)).round();
        let v = line_at + theme.space.bar_margin;
        let rest = Rect::new(u, v, u + w, v + h);
        let depth = rest.y1 as i32 + SLACK;
        let (sw, sh) = if edge.is_vertical() { (depth, length) } else { (length, depth) };
        let mut scene = Scene::new(sw, sh);
        let empty = || Paint::Shape { fill: None, strokes: Vec::new() };
        let casts = scene.add(IRect::default(), empty());
        let shape = scene.add(IRect::default(), empty());
        for id in [casts, shape] {
            scene.set_visible(id, false);
        }
        Self {
            scene,
            look,
            edge,
            rest,
            line_at,
            anchor,
            length,
            pad,
            open: true,
            mapped: false,
            progress: Animated::new(0.0, EMERGE.1),
            attach: Animated::new(1.0, SPATIAL_FAST),
            morph: Animated::new(0.0, SPATIAL_FAST),
            deform: Deform::new(),
            deform_running: false,
            last_tick: None,
            scale,
            casts,
            shape,
            join: None,
            content: (IRect::default(), 0.0),
        }
    }

    /// How far past the output's edge the card's far side rests, which is
    /// where a card hanging off this one has its line.
    pub fn far_edge(&self) -> f64 {
        self.rest.y1
    }

    /// The card as a menu: the `menu` role's fill, border and radius.
    pub fn menu(&mut self, theme: &Theme, cast: bool) {
        self.look = Look::new(theme, cast, "menu");
    }

    /// The same card at a new size inside the surface it was made for, kept
    /// on its anchor. The surface must already be deep enough.
    pub fn resize(&mut self, now: Instant, size: (f64, f64)) {
        let (w, h) = size;
        let u = (self.anchor - w / 2.0).clamp(self.pad, (self.length as f64 - w - self.pad).max(self.pad)).round();
        self.rest = Rect::new(u, self.rest.y0, u + w, self.rest.y0 + h);
        self.tick(now);
    }

    /// The surface's extent away from its edge.
    pub fn depth(&self) -> i32 {
        if self.edge.is_vertical() { self.scene.size.w } else { self.scene.size.h }
    }

    /// The card's resting rect in surface pixels: its input region, and
    /// where its content sits once it has landed.
    pub fn rest_rect(&self) -> IRect {
        Scene::cover(self.rest, self.edge_map(), 0.0)
    }

    /// From the card's own (u, v) to surface pixels.
    pub fn edge_map(&self) -> Affine {
        let d = self.depth() as f64;
        match self.edge {
            Edge::Top => Affine::IDENTITY,
            Edge::Bottom => Affine::new([1.0, 0.0, 0.0, -1.0, 0.0, d]),
            Edge::Left => Affine::new([0.0, 1.0, 1.0, 0.0, 0.0, 0.0]),
            Edge::Right => Affine::new([0.0, 1.0, -1.0, 0.0, d, 0.0]),
        }
    }

    /// Presence's `mapped`: the enter starts once the window is on screen.
    pub fn mapped(&mut self, now: Instant) {
        if !self.mapped {
            self.mapped = true;
            self.set_open(now, self.open);
        }
    }

    pub fn set_open(&mut self, now: Instant, open: bool) {
        self.open = open;
        let held = open && !self.mapped;
        let target = if open && !held { 1.0 } else { 0.0 };
        let clock = if self.look.popover { self.look.effects_ms } else { EMERGE.0 };
        self.progress.set(now, target, clock * self.scale);
        self.morph.set(now, target, SPATIAL_FAST_MS * self.scale);
        self.tick(now);
    }

    pub fn is_open(&self) -> bool {
        self.open
    }

    fn shown(&self, now: Instant) -> bool {
        self.open || self.progress.value(now) > 0.0
    }

    /// Gone: closed with the pose back under its closed rest.
    pub fn finished(&self, now: Instant) -> bool {
        !self.shown(now) || (!self.open && !self.progress.running(now))
    }

    pub fn animating(&self, now: Instant) -> bool {
        !self.mapped
            || self.progress.running(now)
            || self.attach.running(now)
            || self.morph.running(now)
            || !self.deform.at_rest
    }

    pub fn tick(&mut self, now: Instant) {
        if self.look.popover {
            self.tick_popover(now);
        } else {
            self.tick_join(now);
        }
    }

    fn tick_popover(&mut self, now: Instant) {
        let pose = self.progress.value(now).clamp(0.0, 1.0);
        let zoom = 0.97 + 0.03 * self.morph.value(now);
        let shown = self.shown(now) && pose > 0.0;
        let (w, h) = (self.rest.width(), self.rest.height());
        // Grown out of the edge it hangs off.
        let origin = (self.rest.x0 + w / 2.0, self.rest.y0);
        let local = Affine::translate(origin) * Affine::scale(zoom) * Affine::translate((-origin.0, -origin.1));
        let map = self.edge_map();
        let device = Scene::cover(self.rest, map, 0.0);
        let radius = self.look.radius;
        let alpha = pose as f32;
        let layers: Vec<Cast> = self
            .look
            .casts
            .iter()
            .map(|c| Cast { x: c.x, y: c.y, blur: c.blur, spread: c.spread, color: c.color.with_alpha(c.color.a * alpha) })
            .collect();
        let reach = layers.iter().map(|c| c.blur + c.spread.max(0.0) + c.x.abs().max(c.y.abs())).fold(0.0, f64::max);
        let card = Rect::new(device.x as f64, device.y as f64, device.right() as f64, device.bottom() as f64);
        let scale_at = map * local * map.inverse();
        let cutout = vello_cpu::kurbo::RoundedRect::from_rect(card, radius);
        let cutout = vello_cpu::kurbo::Shape::to_path(&cutout, 0.1);
        self.scene.update_with(
            self.casts,
            Scene::cover(card, scale_at, reach * 1.25 + 2.0).intersect(&self.scene.size),
            Paint::Casts { rect: card, radius, layers, cutout },
            shown && !self.look.casts.is_empty(),
            scale_at,
            None,
        );
        let fill = self.look.fill.with_alpha(self.look.fill.a * alpha);
        let border = self.look.border.with_alpha(self.look.border.a * alpha);
        let mut path = vello_cpu::kurbo::BezPath::new();
        let rr = vello_cpu::kurbo::RoundedRect::from_rect(card, radius);
        path.extend(vello_cpu::kurbo::Shape::path_elements(&rr, 0.1));
        let half = self.look.border_width / 2.0;
        let line = vello_cpu::kurbo::Shape::to_path(
            &vello_cpu::kurbo::RoundedRect::from_rect(card.inflate(-half, -half), (radius - half).max(0.0)),
            0.1,
        );
        let mut closed = line.clone();
        closed.close_path();
        self.scene.update_with(
            self.shape,
            Scene::cover(card, scale_at, 2.0),
            Paint::Shape { fill: Some((path, fill)), strokes: vec![(closed, border, self.look.border_width)] },
            shown,
            scale_at,
            None,
        );
        self.content = (device, alpha);
        self.join = None;
        let _ = (w, h);
    }

    fn tick_join(&mut self, now: Instant) {
        let dt = self.last_tick.map(|t| now.saturating_duration_since(t).as_secs_f64()).unwrap_or(0.0);
        self.last_tick = Some(now);

        let (w, h) = (self.rest.width(), self.rest.height());
        let border = self.look.border_width;
        let radius = self.look.radius;
        let depth = (self.rest.y0 - self.line_at).max(0.0) + border;
        let travel = h + depth;
        let release_at = 0.85 - 0.35 * (depth / h.max(1.0)).clamp(0.0, 1.0);
        let amount = DEFORM_AMOUNT * h / (h + depth).max(1.0);
        let cut = self.rest.y0 - depth;

        let pose = self.progress.value(now);
        let shown = self.shown(now);
        let attach_target = if self.open && pose >= release_at { 0.0 } else { 1.0 };
        if shown {
            self.attach.set(now, attach_target, SPATIAL_FAST_MS * self.scale);
        } else {
            self.attach.jump(attach_target);
        }
        let a = self.attach.value(now).clamp(0.0, 1.0);

        let slide = (1.0 - pose) * travel;
        let shape_depth = (h + depth - slide).max(0.0);
        let neck = (depth - slide).max(0.0);
        let near_inset = neck * (1.0 - a);
        let reach = shoulders::fillet_radius(radius * (2.0 * a - 1.0), shape_depth - near_inset);
        let pivot_inset = (depth - slide) * a;

        let frame_y = self.rest.y0 - slide;
        let settled = self.mapped && !self.progress.running(now);
        let running = !settled || !self.deform.at_rest;
        if running {
            if !self.deform_running {
                self.deform.unsample();
            }
            self.deform.step(dt, self.rest.x0, frame_y, h, amount);
        }
        self.deform_running = running;

        let d = &self.deform;
        let (cx, cy) = (w / 2.0, -pivot_inset);
        let matrix = Affine::new([d.m00, d.m01, d.m01, d.m11, 0.0, 0.0]);
        let frame = Affine::translate((self.rest.x0, frame_y))
            * Affine::translate((cx, cy))
            * matrix
            * Affine::translate((-cx, -cy));

        let map = self.edge_map();
        let band = Scene::cover(Rect::new(-FAR, cut.floor(), FAR, FAR), map, 0.0).intersect(&self.scene.size);

        let item = map * frame * Affine::translate((-radius, slide - depth));
        let item_rect = Rect::new(0.0, 0.0, w + radius * 2.0, shape_depth);
        let visible = shown && shape_depth > 0.0;
        let paths = shoulders::paths(item_rect.width(), shape_depth, radius, border, a, near_inset);
        let fill = self.look.fill;
        let line = self.look.border;
        let near = line.with_alpha(line.a * (1.0 - a) as f32);
        let bounds = Scene::cover(item_rect, item, 2.0).intersect(&band);
        let cutout = paths.fill.clone();
        self.scene.update_with(
            self.shape,
            bounds,
            Paint::Shape {
                fill: Some((paths.fill, fill)),
                strokes: vec![(paths.outer, line, border), (paths.near, near, border)],
            },
            visible,
            item,
            Some(band),
        );

        let cast_alpha = 1.0 - a;
        let layers: Vec<Cast> = self
            .look
            .casts
            .iter()
            .map(|c| Cast {
                x: c.x,
                y: c.y,
                blur: c.blur,
                spread: c.spread,
                color: c.color.with_alpha(c.color.a * cast_alpha as f32),
            })
            .collect();
        let reach_out = layers.iter().map(|c| c.blur + c.spread.max(0.0) + c.y.abs()).fold(0.0, f64::max);
        let card = Rect::new(radius, near_inset, radius + w, shape_depth);
        self.scene.update_with(
            self.casts,
            Scene::cover(card, item, reach_out * 1.25 + 2.0).intersect(&band),
            Paint::Casts { rect: card, radius, layers, cutout },
            visible && cast_alpha > 0.0 && !self.look.casts.is_empty(),
            item,
            Some(band),
        );

        // Content rides the card's slide, unmirrored and undeformed.
        let content = ((pose - 0.3) / 0.7).clamp(0.0, 1.0);
        let at = Rect::new(self.rest.x0, frame_y, self.rest.x1, frame_y + h);
        self.content = (Scene::cover(at, map, 0.0), if visible { content as f32 } else { 0.0 });

        self.join = (shown && a > 0.0).then(|| (self.rest.x0 + w * (1.0 - a) / 2.0, w * a, reach));
    }

    /// The band past the line, where content may draw.
    pub fn content_clip(&self) -> IRect {
        let cut = self.line_at + self.look.border_width;
        Scene::cover(Rect::new(-FAR, cut, FAR, FAR), self.edge_map(), 0.0).intersect(&self.scene.size)
    }
}

/// A full-output black scrim on the pose a modal drawer rides (Scrim.qml),
/// here on its own `emerge` clock with no card in front of it. It rasters
/// nothing: its surface is one black pixel the compositor scales and fades.
pub struct Scrim {
    open: bool,
    mapped: bool,
    pose: Animated,
    scale: f64,
    /// The `scrim` role's fill alpha over its plain black.
    alpha: f64,
}

impl Scrim {
    pub fn new(theme: &Theme, scale: f64) -> Self {
        let alpha = f64::from(theme.box_style("scrim", None).fill.a);
        Self { open: true, mapped: false, pose: Animated::new(0.0, EMERGE.1), scale, alpha }
    }

    pub fn mapped(&mut self, now: Instant) {
        if !self.mapped {
            self.mapped = true;
            self.set_open(now, self.open);
        }
    }

    pub fn set_open(&mut self, now: Instant, open: bool) {
        self.open = open;
        let target = if open && self.mapped { 1.0 } else { 0.0 };
        self.pose.set(now, target, EMERGE.0 * self.scale);
    }

    pub fn animating(&self, now: Instant) -> bool {
        !self.mapped || self.pose.running(now)
    }

    pub fn finished(&self, now: Instant) -> bool {
        !self.open && !self.pose.running(now)
    }

    /// The `scrim` role's opacity on this frame.
    pub fn alpha(&self, now: Instant) -> f64 {
        // The spatial pose overshoots both ends; an opacity may not.
        self.alpha * self.pose.value(now).clamp(0.0, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn theme() -> Theme {
        Theme::resolve(getter(json!({})), &fs_theme::palette::fallback("dark"))
    }

    /// The same card on every edge rests a `barMargin` off the line, centred
    /// on its anchor along it, inside the surface.
    #[test]
    fn rests_off_the_line_on_every_edge() {
        let t = theme();
        let margin = t.space.bar_margin as i32;
        for edge in [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right] {
            let card = Card::new(&t, edge, 1080, 40.0, 500.0, (200.0, 60.0), 1.0, false);
            let r = card.rest_rect();
            let depth = card.depth();
            let (along, off) = match edge {
                Edge::Top => (r.x, r.y),
                Edge::Bottom => (r.x, depth - r.bottom()),
                Edge::Left => (r.y, r.x),
                Edge::Right => (r.y, depth - r.right()),
            };
            assert_eq!((along, off), (400, 40 + margin), "{edge:?} {r:?}");
            assert!(card.scene.size.intersect(&r) == r, "{edge:?} outside its surface");
            let clip = card.content_clip();
            assert!(clip.intersect(&r) == r, "{edge:?} content clipped off its own rest");
        }
    }
}
