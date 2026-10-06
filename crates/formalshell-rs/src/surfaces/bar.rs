//! The strip under `bar.kind: strip` (BarStrip.qml): a `card` fill at the
//! surface alpha with one `border` hairline along the edge facing the
//! desktop, the workspace cells at the start of the strip and the clock
//! centred, on whichever output edge `bar.position` names.

use std::time::Instant;

use fs_chrome::bar::workspaces::Slot;
use fs_chrome::types::Edge;
use parley::GenericFamily;
use vello_cpu::kurbo::Affine;

use crate::motion::{Animated, EMPHASIZED, EMPHASIZED_MS, PULSE_MS};
use crate::scene::{IRect, NodeId, Paint, Scene};
use crate::text::{self, Family, ShapedText, Text, TextStyle};
use crate::theme::{self, Palette};

/// CellLabel.qml off the band: `monospace`, `body`, `Theme.weight.medium`.
const LABEL: TextStyle =
    TextStyle { family: Family::Generic(GenericFamily::Monospace), size: theme::FONT_BODY, weight: theme::WEIGHT_MEDIUM };

/// Workspaces.qml's `_badgeSize`: the caption size, the glyph as wide as
/// the disc under it.
const BADGE: i32 = theme::FONT_CAPTION as i32;
const BADGE_GLYPH: TextStyle = TextStyle { family: text::ICONS, size: theme::FONT_CAPTION, weight: 400.0 };
const LOADER_CIRCLE: &str = "\u{E10A}";

/// The herdr "working" badge: a `loader-circle` turning once per pulse,
/// linear, as `RotationAnimator` runs it.
struct Spinner {
    disc: NodeId,
    glyph: NodeId,
    shaped: Option<ShapedText>,
    since: Option<Instant>,
}

/// The focused workspace's fill. Its two edges chase the same cell, the
/// leading pair on `emphasized` and the trailing pair on twice that clock,
/// so a switch stretches one shape across both cells before it lands.
struct Pill {
    node: NodeId,
    shown: bool,
    lead: (Animated, Animated),
    trail: (Animated, Animated),
}

impl Pill {
    fn span(&self, now: Instant) -> (f64, f64) {
        let from = self.lead.0.value(now).min(self.trail.0.value(now));
        let to = self.lead.1.value(now).max(self.trail.1.value(now));
        (from, to)
    }

    fn running(&self, now: Instant) -> bool {
        [&self.lead.0, &self.lead.1, &self.trail.0, &self.trail.1].iter().any(|a| a.running(now))
    }
}

pub struct Bar {
    pub scene: Scene,
    text: Text,
    edge: Edge,
    palette: Palette,
    /// `debug motionScale` and `motion.enabled`, the pill's clock.
    pub motion_scale: f64,
    pub motion_enabled: bool,
    fill: NodeId,
    line: NodeId,
    line_end: NodeId,
    /// The gap a joined card opens in the line, `[start, end)`.
    gap: Option<(i32, i32)>,
    /// The two line segments as laid out, drawn or not (`debug dump`).
    line_rects: [IRect; 2],
    pill: Pill,
    slots: Vec<Slot>,
    cells: Vec<IRect>,
    spinner: Spinner,
    clock_cell: IRect,
    labels: Vec<NodeId>,
    clock: NodeId,
    now: String,
}

/// The strip's extent across the bar: the cell row with a `barMargin` band
/// either side, a vertical strip's cells as wide as `barCellWidth`.
pub fn thickness(edge: Edge) -> i32 {
    cell_thickness(edge) + theme::BAR_MARGIN * 2
}

fn cell_thickness(edge: Edge) -> i32 {
    if edge.is_vertical() { theme::BAR_CELL_WIDTH } else { theme::BAR_CELL_HEIGHT }
}

impl Bar {
    pub fn new(edge: Edge) -> Self {
        let palette = theme::DARK;
        let (w, h) = if edge.is_vertical() { (thickness(edge), 1) } else { (1, thickness(edge)) };
        let mut scene = Scene::new(w, h);
        let fill = scene.add(IRect::default(), rect(palette.card.with_alpha(theme::SURFACE_OPACITY), 0.0));
        let line = scene.add(IRect::default(), rect(palette.border, 0.0));
        let line_end = scene.add(IRect::default(), rect(palette.border, 0.0));
        let pill_node = scene.add(IRect::default(), rect(palette.primary, theme::radius_md()));
        scene.set_visible(pill_node, false);
        let mut text = Text::new();
        let clock = scene.add(IRect::default(), Paint::Text { text: text.shape("", LABEL), color: palette.foreground });
        let disc = scene.add(IRect::default(), rect(palette.background, BADGE as f32 / 2.0));
        let glyph = scene.add(IRect::default(), Paint::Text { text: text.shape("", BADGE_GLYPH), color: palette.foreground });
        scene.set_visible(disc, false);
        scene.set_visible(glyph, false);
        let at = |v| Animated::new(v, EMPHASIZED);
        let mut bar = Self {
            scene,
            text,
            edge,
            palette,
            motion_scale: 1.0,
            motion_enabled: true,
            fill,
            line,
            line_end,
            gap: None,
            line_rects: [IRect::default(); 2],
            pill: Pill { node: pill_node, shown: false, lead: (at(0.0), at(0.0)), trail: (at(0.0), at(0.0)) },
            slots: Vec::new(),
            cells: Vec::new(),
            spinner: Spinner { disc, glyph, shaped: None, since: None },
            clock_cell: IRect::default(),
            labels: Vec::new(),
            clock,
            now: String::new(),
        };
        bar.layout_strip();
        bar
    }

    pub fn edge(&self) -> Edge {
        self.edge
    }

    fn vertical(&self) -> bool {
        self.edge.is_vertical()
    }

    /// The strip's length along its own edge.
    fn length(&self) -> i32 {
        if self.vertical() { self.scene.size.h } else { self.scene.size.w }
    }

    /// A cell at `start` along the strip, `extent` long.
    fn cell(&self, start: i32, extent: i32) -> IRect {
        let across = cell_thickness(self.edge);
        if self.vertical() {
            IRect::new(theme::BAR_MARGIN, start, across, extent)
        } else {
            IRect::new(start, theme::BAR_MARGIN, extent, across)
        }
    }

    /// Moves the strip to another edge. Across the output it waits on the
    /// configure that carries the new length; to the opposite edge the size
    /// stays and the compositor sends no configure at all.
    pub fn set_edge(&mut self, edge: Edge) {
        if edge == self.edge {
            return;
        }
        let turned = edge.is_vertical() != self.edge.is_vertical();
        self.edge = edge;
        self.gap = None;
        let IRect { w, h, .. } = self.scene.size;
        let (w, h) = match (turned, edge.is_vertical()) {
            (false, _) => (w, h),
            (true, true) => (thickness(edge), 1),
            (true, false) => (1, thickness(edge)),
        };
        self.resize(w, h);
    }

    pub fn resize(&mut self, width: i32, height: i32) {
        self.scene.resize(width, height);
        self.relayout();
    }

    pub fn set_palette(&mut self, palette: Palette) {
        if palette == self.palette {
            return;
        }
        self.palette = palette;
        self.relayout();
    }

    fn relayout(&mut self) {
        self.layout_strip();
        let slots = std::mem::take(&mut self.slots);
        self.pill.shown = false;
        self.set_workspaces(&slots);
        let now = std::mem::take(&mut self.now);
        self.set_clock(&now);
        self.tick(Instant::now());
    }

    fn layout_strip(&mut self) {
        let IRect { w, h, .. } = self.scene.size;
        let fill = self.palette.card.with_alpha(theme::SURFACE_OPACITY);
        self.scene.update(self.fill, IRect::new(0, 0, w, h), rect(fill, 0.0), true);
        self.layout_line();
    }

    /// BarStrip.qml's two hairline segments either side of the gap, on the
    /// side that faces the desktop.
    fn layout_line(&mut self) {
        let IRect { w, h, .. } = self.scene.size;
        let t = theme::EDGE_WIDTH;
        let len = self.length();
        let (start, end) = self.gap.unwrap_or((0, 0));
        let (start, end) = (start.clamp(0, len), end.clamp(start.clamp(0, len), len));
        let segment = |a: i32, b: i32| match self.edge {
            Edge::Top => IRect::new(a, h - t, b - a, t),
            Edge::Bottom => IRect::new(a, 0, b - a, t),
            Edge::Left => IRect::new(w - t, a, t, b - a),
            Edge::Right => IRect::new(0, a, t, b - a),
        };
        let (first, second) = (segment(0, start), segment(end, len));
        self.line_rects = [first, second];
        let border = self.palette.border;
        self.scene.update(self.line, first, rect(border, 0.0), start > 0);
        self.scene.update(self.line_end, second, rect(border, 0.0), end < len);
    }

    /// The join a card publishes (Joint.qml's `join`): its x and width along
    /// the line and the fillets' reach, or none.
    pub fn set_join(&mut self, join: Option<(f64, f64, f64)>) {
        let gap = join.map(|(x, width, reach)| ((x - reach).round() as i32, (x + width + reach).round() as i32));
        if gap != self.gap {
            self.gap = gap;
            self.layout_line();
        }
    }

    pub fn line_rects(&self) -> [IRect; 2] {
        self.line_rects
    }

    pub fn text_mut(&mut self) -> &mut Text {
        &mut self.text
    }

    pub fn clock_cell(&self) -> IRect {
        self.clock_cell
    }

    pub fn set_spinner(&mut self, now: Instant, on: bool) {
        match (on, self.spinner.since) {
            (true, None) => self.spinner.since = Some(now),
            (false, Some(_)) => self.spinner.since = None,
            _ => return,
        }
        self.tick(now);
    }

    pub fn animating(&self) -> bool {
        self.spinner.since.is_some() || self.pill.running(Instant::now())
    }

    /// One frame of whatever the bar animates: the pill's edges and the
    /// spinner's angle.
    pub fn tick(&mut self, now: Instant) {
        self.draw_pill(now);
        self.draw_spinner(now);
    }

    fn draw_pill(&mut self, now: Instant) {
        if !self.pill.shown {
            self.scene.set_visible(self.pill.node, false);
            return;
        }
        let (from, to) = self.pill.span(now);
        let (from, to) = (from.round() as i32, to.round() as i32);
        let bounds = self.cell(from, to - from);
        self.scene.update(self.pill.node, bounds, rect(self.palette.primary, theme::radius_md()), true);
    }

    fn draw_spinner(&mut self, now: Instant) {
        let Spinner { disc, glyph, since, .. } = self.spinner;
        let Some(cell) = self.cells.first().copied().filter(|_| since.is_some()) else {
            self.scene.set_visible(disc, false);
            self.scene.set_visible(glyph, false);
            return;
        };
        let badge = IRect::new(cell.right() - theme::SPACE_XXS - BADGE, cell.y + theme::SPACE_XXS, BADGE, BADGE);
        self.scene.update(disc, badge, rect(self.palette.background, BADGE as f32 / 2.0), true);

        let shaped = match &self.spinner.shaped {
            Some(s) => s.clone(),
            None => {
                let s = self.text.shape(LOADER_CIRCLE, BADGE_GLYPH);
                self.spinner.shaped = Some(s.clone());
                s
            }
        };
        // The glyph's line box centred on the disc, as Icon.qml centres its
        // text, turned about the disc's centre.
        let (bw, bh) = shaped.box_size();
        let at = (badge.x + (BADGE - bw) / 2, badge.y + (BADGE - bh) / 2);
        let centre = (badge.x as f64 + BADGE as f64 / 2.0, badge.y as f64 + BADGE as f64 / 2.0);
        let elapsed = now.saturating_duration_since(since.unwrap_or(now)).as_secs_f64() * 1000.0;
        let turn = (elapsed / PULSE_MS).fract() * std::f64::consts::TAU;
        let spin = Affine::translate(centre) * Affine::rotate(turn) * Affine::translate((-centre.0, -centre.1));
        // The glyph is drawn at `bounds` origin plus its own offsets, so the
        // node's bounds sit where the line box goes and the damage is the
        // badge alone.
        let shift = Affine::translate(((at.0 - badge.x) as f64, (at.1 - badge.y) as f64));
        let paint = Paint::Text { text: shaped, color: self.palette.foreground };
        self.scene.update_with(glyph, badge, paint, true, spin * shift, None);
    }

    pub fn set_workspaces(&mut self, slots: &[Slot]) {
        let now = Instant::now();
        self.slots = slots.to_vec();
        while self.labels.len() < slots.len() {
            let empty = self.text.shape("", LABEL);
            let id = self.scene.add(IRect::default(), Paint::Text { text: empty, color: self.palette.muted_foreground });
            self.labels.push(id);
        }
        let mut at = theme::SPACE_MD;
        let mut focused = None;
        self.cells.clear();
        for (i, id) in self.labels.clone().into_iter().enumerate() {
            let Some(slot) = slots.get(i) else {
                self.scene.set_visible(id, false);
                continue;
            };
            let shaped = self.text.shape(&slot.label, LABEL);
            let extent =
                if self.vertical() { theme::BAR_CELL_HEIGHT } else { shaped.width + theme::CONTROL_PADDING_X * 2 };
            let cell = self.cell(at, extent);
            let ink = if slot.is_focused { self.palette.primary_foreground } else { self.palette.muted_foreground };
            let bounds = centred(&shaped, cell);
            self.scene.update(id, bounds, Paint::Text { text: shaped, color: ink }, true);
            self.cells.push(cell);
            if slot.is_focused {
                focused = Some((at as f64, (at + extent) as f64));
            }
            at += extent + theme::SPACE_SM;
        }
        match focused {
            Some((start, end)) if self.pill.shown => {
                let clock = EMPHASIZED_MS * self.motion_scale * if self.motion_enabled { 1.0 } else { 0.0 };
                self.pill.lead.0.set(now, start, clock);
                self.pill.lead.1.set(now, end, clock);
                self.pill.trail.0.set(now, start, clock * 2.0);
                self.pill.trail.1.set(now, end, clock * 2.0);
            }
            Some((start, end)) => {
                // Arriving rather than travelling: the pill lands on its cell.
                self.pill.shown = true;
                for a in [&mut self.pill.lead.0, &mut self.pill.trail.0] {
                    a.jump(start);
                }
                for a in [&mut self.pill.lead.1, &mut self.pill.trail.1] {
                    a.jump(end);
                }
            }
            None => self.pill.shown = false,
        }
        self.tick(now);
    }

    pub fn set_clock(&mut self, now: &str) {
        self.now = now.to_owned();
        let shaped = self.text.shape(now, LABEL);
        let extent = if self.vertical() { theme::BAR_CELL_HEIGHT } else { shaped.width + theme::CONTROL_PADDING_X * 2 };
        self.clock_cell = self.cell((self.length() - extent) / 2, extent);
        let bounds = centred(&shaped, self.clock_cell);
        self.scene.update(self.clock, bounds, Paint::Text { text: shaped, color: self.palette.foreground }, true);
    }
}

fn rect(fill: theme::Rgba, radius: f32) -> Paint {
    Paint::Rect { fill, radius }
}

/// A label centred in its cell, its line box on a whole pixel.
fn centred(shaped: &ShapedText, cell: IRect) -> IRect {
    let (w, h) = shaped.box_size();
    let left = cell.x + (cell.w - shaped.width) / 2;
    let top = cell.y + (cell.h - shaped.line_height()) / 2;
    IRect::new(left - text::PAD, top - text::PAD, w, h)
}
