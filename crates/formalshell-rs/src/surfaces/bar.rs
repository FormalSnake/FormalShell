//! The strip under `bar.kind: strip` (BarStrip.qml): the `bar` role's fill
//! with its one hairline along the edge facing the desktop, the workspace
//! cells at the start of the strip and the clock centred, on whichever
//! output edge `bar.position` names.

use std::time::Instant;

use fs_chrome::bar::workspaces::Slot;
use fs_chrome::types::Edge;
use fs_theme::color::Rgba;
use fs_theme::style::{Line, Radius};
use fs_theme::theme::Theme;
use parley::GenericFamily;
use vello_cpu::kurbo::Affine;

use crate::motion::{Animated, EMPHASIZED, PULSE_MS};
use crate::scene::{IRect, NodeId, Paint, Scene};
use crate::text::{self, Family, ShapedText, Text, TextStyle};

const LOADER_CIRCLE: &str = "\u{E10A}";

/// What the strip takes off the theme: the `bar` role's fill and edge, the
/// `cell` role's active fill for the focused pill, the ink, the metrics and
/// the pill's clock.
#[derive(Clone)]
struct Look {
    fill: Rgba,
    edge: Rgba,
    edge_width: i32,
    pill: Rgba,
    pill_radius: f32,
    foreground: Rgba,
    muted: Rgba,
    on_pill: Rgba,
    background: Rgba,
    margin: i32,
    cell_height: i32,
    cell_width: i32,
    xxs: i32,
    sm: i32,
    md: i32,
    pad_x: i32,
    /// `Theme.motion.emphasized`, 0 under `motion.enabled: false`.
    emphasized: f64,
    /// CellLabel.qml off the band: `monospace`, `body`, `Theme.weight.medium`.
    label: TextStyle,
    /// Workspaces.qml's `_badgeSize`: the caption size, the glyph as wide
    /// as the disc under it.
    badge: i32,
    badge_glyph: TextStyle,
}

impl Look {
    fn new(theme: &Theme) -> Self {
        let bar = theme.box_style("bar", None);
        let active = theme.box_style("cell", Some("active"));
        let edge = bar.edge.unwrap_or(Line { color: Rgba::TRANSPARENT, width: 0.0 });
        let space = &theme.space;
        let caption = theme.font_size.caption as f32;
        Self {
            fill: bar.fill,
            edge: edge.color,
            edge_width: edge.width as i32,
            pill: active.fill,
            pill_radius: match active.radius {
                Radius::Px(px) => px as f32,
                Radius::Pill => theme.pill_radius(space.bar_cell_height) as f32,
            },
            foreground: theme.colors.get("foreground"),
            muted: theme.colors.get("mutedForeground"),
            on_pill: theme.colors.get("primaryForeground"),
            background: theme.colors.get("background"),
            margin: space.bar_margin as i32,
            cell_height: space.bar_cell_height as i32,
            cell_width: space.bar_cell_width as i32,
            xxs: space.xxs as i32,
            sm: space.sm as i32,
            md: space.md as i32,
            pad_x: space.control_padding_x as i32,
            emphasized: theme.motion().families.emphasized,
            label: TextStyle {
                family: Family::Generic(GenericFamily::Monospace),
                size: theme.font_size.body as f32,
                weight: fs_theme::tokens::WEIGHTS.medium as f32,
            },
            badge: caption as i32,
            badge_glyph: TextStyle { family: text::ICONS, size: caption, weight: 400.0 },
        }
    }

    /// A cell's extent across the strip: `barCellWidth` on a left or right
    /// one, where a cell stacks rather than runs along.
    fn across(&self, edge: Edge) -> i32 {
        if edge.is_vertical() { self.cell_width } else { self.cell_height }
    }

    /// `stripGeometry`: the cell row plus a `barMargin` band either side,
    /// which is also the exclusive zone.
    fn thickness(&self, edge: Edge) -> i32 {
        self.across(edge) + self.margin * 2
    }
}

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
    look: Look,
    text: Text,
    edge: Edge,
    /// `debug motionScale`, on top of the theme's own clock.
    pub motion_scale: f64,
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

impl Bar {
    pub fn new(edge: Edge, theme: &Theme) -> Self {
        let look = Look::new(theme);
        let t = look.thickness(edge);
        let (w, h) = if edge.is_vertical() { (t, 1) } else { (1, t) };
        let mut scene = Scene::new(w, h);
        let fill = scene.add(IRect::default(), rect(look.fill, 0.0));
        let line = scene.add(IRect::default(), rect(look.edge, 0.0));
        let line_end = scene.add(IRect::default(), rect(look.edge, 0.0));
        let pill_node = scene.add(IRect::default(), rect(look.pill, look.pill_radius));
        scene.set_visible(pill_node, false);
        let mut text = Text::new();
        let clock = scene.add(IRect::default(), Paint::Text { text: text.shape("", look.label), color: look.foreground });
        let disc = scene.add(IRect::default(), rect(look.background, look.badge as f32 / 2.0));
        let glyph =
            scene.add(IRect::default(), Paint::Text { text: text.shape("", look.badge_glyph), color: look.foreground });
        scene.set_visible(disc, false);
        scene.set_visible(glyph, false);
        let at = |v| Animated::new(v, EMPHASIZED);
        let mut bar = Self {
            scene,
            look,
            text,
            edge,
            motion_scale: 1.0,
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

    /// The strip's extent across its edge, which is also its exclusive zone.
    pub fn thickness(&self) -> i32 {
        self.look.thickness(self.edge)
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
        let across = self.look.across(self.edge);
        if self.vertical() {
            IRect::new(self.look.margin, start, across, extent)
        } else {
            IRect::new(start, self.look.margin, extent, across)
        }
    }

    /// The size the scene takes on a new edge or thickness: the thickness
    /// across, the current length along when the strip did not turn, and a
    /// placeholder until the configure carrying the new length when it did.
    fn placed_size(&self, turned: bool) -> (i32, i32) {
        let IRect { w, h, .. } = self.scene.size;
        let t = self.thickness();
        match (turned, self.vertical()) {
            (false, true) => (t, h),
            (false, false) => (w, t),
            (true, true) => (t, 1),
            (true, false) => (1, t),
        }
    }

    /// Moves the strip to another edge. To the opposite edge the size stays
    /// and the compositor sends no configure at all.
    pub fn set_edge(&mut self, edge: Edge) {
        if edge == self.edge {
            return;
        }
        let turned = edge.is_vertical() != self.edge.is_vertical();
        self.edge = edge;
        self.gap = None;
        let (w, h) = self.placed_size(turned);
        self.resize(w, h);
    }

    pub fn resize(&mut self, width: i32, height: i32) {
        self.scene.resize(width, height);
        self.relayout();
    }

    /// Repaints every node off a new theme, and takes its thickness.
    pub fn set_theme(&mut self, theme: &Theme) {
        self.look = Look::new(theme);
        self.spinner.shaped = None;
        let (w, h) = self.placed_size(false);
        self.resize(w, h);
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
        self.scene.update(self.fill, IRect::new(0, 0, w, h), rect(self.look.fill, 0.0), true);
        self.layout_line();
    }

    /// BarStrip.qml's two hairline segments either side of the gap, on the
    /// side that faces the desktop.
    fn layout_line(&mut self) {
        let IRect { w, h, .. } = self.scene.size;
        let (t, color) = (self.look.edge_width, self.look.edge);
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
        self.scene.update(self.line, first, rect(color, 0.0), start > 0 && t > 0);
        self.scene.update(self.line_end, second, rect(color, 0.0), end < len && t > 0);
    }

    pub fn line_rects(&self) -> [IRect; 2] {
        self.line_rects
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
        self.scene.update(self.pill.node, bounds, rect(self.look.pill, self.look.pill_radius), true);
    }

    fn draw_spinner(&mut self, now: Instant) {
        let Spinner { disc, glyph, since, .. } = self.spinner;
        let Some(cell) = self.cells.first().copied().filter(|_| since.is_some()) else {
            self.scene.set_visible(disc, false);
            self.scene.set_visible(glyph, false);
            return;
        };
        let size = self.look.badge;
        let badge = IRect::new(cell.right() - self.look.xxs - size, cell.y + self.look.xxs, size, size);
        self.scene.update(disc, badge, rect(self.look.background, size as f32 / 2.0), true);

        let shaped = match &self.spinner.shaped {
            Some(s) => s.clone(),
            None => {
                let s = self.text.shape(LOADER_CIRCLE, self.look.badge_glyph);
                self.spinner.shaped = Some(s.clone());
                s
            }
        };
        // The glyph's line box centred on the disc, as Icon.qml centres its
        // text, turned about the disc's centre.
        let (bw, bh) = shaped.box_size();
        let at = (badge.x + (size - bw) / 2, badge.y + (size - bh) / 2);
        let centre = (badge.x as f64 + size as f64 / 2.0, badge.y as f64 + size as f64 / 2.0);
        let elapsed = now.saturating_duration_since(since.unwrap_or(now)).as_secs_f64() * 1000.0;
        let turn = (elapsed / PULSE_MS).fract() * std::f64::consts::TAU;
        let spin = Affine::translate(centre) * Affine::rotate(turn) * Affine::translate((-centre.0, -centre.1));
        // The glyph is drawn at `bounds` origin plus its own offsets, so the
        // node's bounds sit where the line box goes and the damage is the
        // badge alone.
        let shift = Affine::translate(((at.0 - badge.x) as f64, (at.1 - badge.y) as f64));
        let color = self.look.foreground;
        self.scene.update_with(glyph, badge, Paint::Text { text: shaped, color }, true, spin * shift, None);
    }

    pub fn set_workspaces(&mut self, slots: &[Slot]) {
        let now = Instant::now();
        self.slots = slots.to_vec();
        let look = self.look.clone();
        while self.labels.len() < slots.len() {
            let empty = self.text.shape("", look.label);
            let id = self.scene.add(IRect::default(), Paint::Text { text: empty, color: look.muted });
            self.labels.push(id);
        }
        let mut at = look.md;
        let mut focused = None;
        self.cells.clear();
        for (i, id) in self.labels.clone().into_iter().enumerate() {
            let Some(slot) = slots.get(i) else {
                self.scene.set_visible(id, false);
                continue;
            };
            let shaped = self.text.shape(&slot.label, look.label);
            let extent = if self.vertical() { look.cell_height } else { shaped.width + look.pad_x * 2 };
            let cell = self.cell(at, extent);
            let ink = if slot.is_focused { look.on_pill } else { look.muted };
            let bounds = centred(&shaped, cell);
            self.scene.update(id, bounds, Paint::Text { text: shaped, color: ink }, true);
            self.cells.push(cell);
            if slot.is_focused {
                focused = Some((at as f64, (at + extent) as f64));
            }
            at += extent + look.sm;
        }
        match focused {
            Some((start, end)) if self.pill.shown => {
                let clock = look.emphasized * self.motion_scale;
                self.pill.lead.0.set(now, start, clock);
                self.pill.lead.1.set(now, end, clock);
                self.pill.trail.0.set(now, start, clock * 2.0);
                self.pill.trail.1.set(now, end, clock * 2.0);
            }
            Some((start, end)) => {
                // Arriving rather than travelling: the pill lands on its cell.
                self.pill.shown = true;
                self.pill.lead.0.jump(start);
                self.pill.trail.0.jump(start);
                self.pill.lead.1.jump(end);
                self.pill.trail.1.jump(end);
            }
            None => self.pill.shown = false,
        }
        self.tick(now);
    }

    pub fn set_clock(&mut self, now: &str) {
        self.now = now.to_owned();
        let look = self.look.clone();
        let shaped = self.text.shape(now, look.label);
        let extent = if self.vertical() { look.cell_height } else { shaped.width + look.pad_x * 2 };
        self.clock_cell = self.cell((self.length() - extent) / 2, extent);
        let bounds = centred(&shaped, self.clock_cell);
        self.scene.update(self.clock, bounds, Paint::Text { text: shaped, color: look.foreground }, true);
    }
}

fn rect(fill: Rgba, radius: f32) -> Paint {
    Paint::Rect { fill, radius }
}

/// A label centred in its cell, its line box on a whole pixel.
fn centred(shaped: &ShapedText, cell: IRect) -> IRect {
    let (w, h) = shaped.box_size();
    let left = cell.x + (cell.w - shaped.width) / 2;
    let top = cell.y + (cell.h - shaped.line_height()) / 2;
    IRect::new(left - text::PAD, top - text::PAD, w, h)
}
