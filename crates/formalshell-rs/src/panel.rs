//! One panel hanging off the bar's line, drawn the way DrawerJoin.qml
//! assembles it: Presence's emerge on the theme's `emerge` clock, Joint's
//! let-go on `spatialFast`, Deform's springs, and Shoulders' outline cut at
//! the line. Top edge, no walls, no owner, which is a panel under a cell in
//! the middle of the strip.

use std::time::Instant;

use parley::GenericFamily;
use vello_cpu::kurbo::{Affine, Rect};

use crate::motion::{Animated, Deform, EMERGE, SPATIAL_FAST, SPATIAL_FAST_MS};
use crate::scene::{Cast, IRect, NodeId, Paint, Scene};
use crate::shoulders;
use crate::text::{Family, ShapedText, Text, TextStyle};
use crate::theme::{self, DARK, Rgba};

/// Drawer.qml's `deformAmount` for a popout.
const DEFORM_AMOUNT: f64 = 0.15;
/// Room under the card's resting rect for the overshoot, the deform's
/// stretch and the cast.
const SLACK: i32 = 48;
const TITLE: TextStyle =
    TextStyle { family: Family::Generic(GenericFamily::SansSerif), size: theme::FONT_BODY, weight: theme::WEIGHT_MEDIUM };

pub struct Panel {
    pub scene: Scene,
    rest: Rect,
    line_at: f64,
    open: bool,
    mapped: bool,
    progress: Animated,
    attach: Animated,
    deform: Deform,
    deform_running: bool,
    last_tick: Option<Instant>,
    scale: f64,
    cast: bool,
    title: ShapedText,
    casts: NodeId,
    shape: NodeId,
    label: NodeId,
    pub join: Option<(f64, f64, f64)>,
}

impl Panel {
    /// A panel centred under `cell`, clamped a `screenPadding` in from
    /// either end, a `barMargin` under the bar's line.
    pub fn new(output_width: i32, cell: IRect, height: f64, scale: f64, cast: bool, text: &mut Text, label: &str) -> Self {
        let w = theme::POPUP_WIDTH_DEFAULT as f64;
        let centre = cell.x as f64 + cell.w as f64 / 2.0;
        let pad = theme::SCREEN_PADDING as f64;
        let x = (centre - w / 2.0).clamp(pad, output_width as f64 - w - pad).round();
        let line_at = theme::BAR_THICKNESS as f64;
        let rest = Rect::new(x, line_at + theme::BAR_MARGIN as f64, x + w, line_at + theme::BAR_MARGIN as f64 + height);
        let mut scene = Scene::new(output_width, rest.y1 as i32 + SLACK);
        let empty = || Paint::Shape { fill: None, strokes: Vec::new() };
        let casts = scene.add(IRect::default(), empty());
        let shape = scene.add(IRect::default(), empty());
        let title = text.shape(label, TITLE);
        let label = scene.add(IRect::default(), Paint::Text { text: title.clone(), color: DARK.foreground });
        for id in [casts, shape, label] {
            scene.set_visible(id, false);
        }
        Self {
            scene,
            rest,
            line_at,
            open: true,
            mapped: false,
            progress: Animated::new(0.0, EMERGE.1),
            attach: Animated::new(1.0, SPATIAL_FAST),
            deform: Deform::new(),
            deform_running: false,
            last_tick: None,
            scale,
            cast,
            title,
            casts,
            shape,
            label,
            join: None,
        }
    }

    pub fn surface_height(&self) -> i32 {
        self.scene.size.h
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
        self.progress.set(now, target, EMERGE.0 * self.scale);
        self.tick(now);
    }

    pub fn is_open(&self) -> bool {
        self.open
    }

    fn pose(&self, now: Instant) -> f64 {
        self.progress.value(now)
    }

    fn shown(&self, now: Instant) -> bool {
        self.open || self.pose(now) > 0.0
    }

    /// Gone: closed with the pose back under its closed rest.
    pub fn finished(&self, now: Instant) -> bool {
        !self.shown(now) || (!self.open && !self.progress.running(now))
    }

    pub fn animating(&self, now: Instant) -> bool {
        !self.mapped || self.progress.running(now) || self.attach.running(now) || !self.deform.at_rest
    }

    pub fn tick(&mut self, now: Instant) {
        let dt = self.last_tick.map(|t| now.saturating_duration_since(t).as_secs_f64()).unwrap_or(0.0);
        self.last_tick = Some(now);

        let (w, h) = (self.rest.width(), self.rest.height());
        let border = theme::EDGE_WIDTH as f64;
        let radius = theme::radius_xl() as f64;
        let depth = (self.rest.y0 - self.line_at).max(0.0) + border;
        let travel = h + depth;
        let release_at = 0.85 - 0.35 * (depth / h.max(1.0)).clamp(0.0, 1.0);
        let amount = DEFORM_AMOUNT * h / (h + depth).max(1.0);
        let cut = self.rest.y0 - depth;

        let pose = self.pose(now);
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

        let size = self.scene.size;
        let band = IRect::new(0, cut.floor() as i32, size.w, size.h - cut.floor() as i32);

        let item = frame * Affine::translate((-radius, slide - depth));
        let item_rect = Rect::new(0.0, 0.0, w + radius * 2.0, shape_depth);
        let visible = shown && shape_depth > 0.0;
        let paths = shoulders::paths(item_rect.width(), shape_depth, radius, border, a, near_inset);
        let fill = DARK.card.with_alpha(theme::SURFACE_OPACITY);
        let near = DARK.border.with_alpha((1.0 - a) as f32);
        let bounds = Scene::cover(item_rect, item, 2.0).intersect(&band);
        let cutout = paths.fill.clone();
        self.scene.update_with(
            self.shape,
            bounds,
            Paint::Shape {
                fill: Some((paths.fill, fill)),
                strokes: vec![(paths.outer, DARK.border, border), (paths.near, near, border)],
            },
            visible,
            item,
            Some(band),
        );

        let cast_alpha = if self.cast { 1.0 - a } else { 0.0 };
        let layers: Vec<Cast> = theme::PANTHEON_SHADOW_2
            .iter()
            .map(|&(y, blur, spread, alpha)| Cast {
                x: 0.0,
                y,
                blur,
                spread,
                color: Rgba::hex(0).with_alpha(alpha * cast_alpha as f32),
            })
            .collect();
        let reach_out = layers.iter().map(|c| c.blur + c.spread.max(0.0) + c.y.abs()).fold(0.0, f64::max);
        let card = Rect::new(radius, near_inset, radius + w, shape_depth);
        self.scene.update_with(
            self.casts,
            Scene::cover(card, item, reach_out * 1.25 + 2.0).intersect(&band),
            Paint::Casts { rect: card, radius, layers, cutout },
            visible && cast_alpha > 0.0,
            item,
            Some(band),
        );

        let content = ((pose - 0.3) / 0.7).clamp(0.0, 1.0);
        let pad = theme::PANEL_PADDING as f64;
        let (tw, th) = self.title.box_size();
        let label_rect = Rect::new(pad, pad, pad + tw as f64, pad + th as f64);
        let label_bounds = Scene::cover(label_rect, frame, 1.0).intersect(&band);
        let text_at = frame
            * Affine::translate((pad, pad))
            * Affine::translate((-label_bounds.x as f64, -label_bounds.y as f64));
        self.scene.update_with(
            self.label,
            label_bounds,
            Paint::Text { text: self.title.clone(), color: DARK.foreground.with_alpha(content as f32) },
            visible && content > 0.0,
            text_at,
            Some(band),
        );

        self.join = (shown && a > 0.0).then(|| (self.rest.x0 + w * (1.0 - a) / 2.0, w * a, reach));
    }
}

/// A full-output black scrim on the pose a modal drawer rides (Scrim.qml),
/// here on its own `emerge` clock with no card in front of it.
pub struct Scrim {
    pub scene: Scene,
    node: NodeId,
    open: bool,
    mapped: bool,
    pose: Animated,
    scale: f64,
}

impl Scrim {
    pub fn new(width: i32, height: i32, scale: f64) -> Self {
        let mut scene = Scene::new(width, height);
        let node = scene.add(IRect::new(0, 0, width, height), Paint::Rect { fill: Rgba::hex(0).with_alpha(0.0), radius: 0.0 });
        Self { scene, node, open: true, mapped: false, pose: Animated::new(0.0, EMERGE.1), scale }
    }

    pub fn resize(&mut self, width: i32, height: i32) {
        self.scene.resize(width, height);
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
        self.tick(now);
    }

    pub fn animating(&self, now: Instant) -> bool {
        !self.mapped || self.pose.running(now)
    }

    pub fn finished(&self, now: Instant) -> bool {
        !self.open && !self.pose.running(now)
    }

    pub fn tick(&mut self, now: Instant) {
        // The spatial pose overshoots both ends; an opacity may not.
        let pose = self.pose.value(now).clamp(0.0, 1.0);
        let size = self.scene.size;
        let fill = Rgba::hex(0).with_alpha(theme::SCRIM_ALPHA * pose as f32);
        self.scene.update(self.node, size, Paint::Rect { fill, radius: 0.0 }, true);
    }
}
