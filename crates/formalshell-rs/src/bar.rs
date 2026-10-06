//! The strip under `bar.kind: strip` (BarStrip.qml): a `card` fill at the
//! surface alpha with one `border` hairline along the edge facing the
//! desktop, the workspace cells in the left region and the clock centred.

use std::time::Instant;

use parley::GenericFamily;
use vello_cpu::kurbo::Affine;

use crate::hyprland::Slot;
use crate::motion::PULSE_MS;
use crate::scene::{IRect, NodeId, Paint, Scene};
use crate::text::{self, Family, ShapedText, Text, TextStyle};
use crate::theme::{self, DARK};

/// CellLabel.qml off the band: `monospace`, `body`, `Theme.weight.medium`.
const LABEL: TextStyle =
    TextStyle { family: Family::Generic(GenericFamily::Monospace), size: theme::FONT_BODY, weight: theme::WEIGHT_MEDIUM };
const CELL_Y: i32 = theme::BAR_MARGIN;

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

pub struct Bar {
    pub scene: Scene,
    text: Text,
    fill: NodeId,
    edge: NodeId,
    edge_end: NodeId,
    /// The gap a joined card opens in the line, `[start, end)`.
    gap: Option<(i32, i32)>,
    pill: NodeId,
    cells: Vec<IRect>,
    spinner: Spinner,
    clock_cell: IRect,
    labels: Vec<NodeId>,
    clock: NodeId,
    now: String,
}

impl Bar {
    pub fn new(width: i32) -> Self {
        let height = theme::BAR_THICKNESS;
        let mut scene = Scene::new(width, height);
        let fill = scene.add(IRect::default(), rect(DARK.card.with_alpha(theme::SURFACE_OPACITY), 0.0));
        let edge = scene.add(IRect::default(), rect(DARK.border, 0.0));
        let edge_end = scene.add(IRect::default(), rect(DARK.border, 0.0));
        let pill = scene.add(IRect::default(), rect(DARK.primary, theme::radius_md()));
        let mut text = Text::new();
        let clock = scene.add(IRect::default(), Paint::Text { text: text.shape("", LABEL), color: DARK.foreground });
        let disc = scene.add(IRect::default(), rect(DARK.background, BADGE as f32 / 2.0));
        let glyph = scene.add(IRect::default(), Paint::Text { text: text.shape("", BADGE_GLYPH), color: DARK.foreground });
        scene.set_visible(disc, false);
        scene.set_visible(glyph, false);
        let spinner = Spinner { disc, glyph, shaped: None, since: None };
        let mut bar = Self {
            scene,
            text,
            fill,
            edge,
            edge_end,
            gap: None,
            pill,
            cells: Vec::new(),
            spinner,
            clock_cell: IRect::default(),
            labels: Vec::new(),
            clock,
            now: String::new(),
        };
        bar.layout_strip();
        bar
    }

    pub fn resize(&mut self, width: i32) {
        self.scene.resize(width, theme::BAR_THICKNESS);
        self.layout_strip();
        let now = std::mem::take(&mut self.now);
        self.set_clock(&now);
    }

    fn layout_strip(&mut self) {
        let IRect { w, h, .. } = self.scene.size;
        let fill = DARK.card.with_alpha(theme::SURFACE_OPACITY);
        self.scene.update(self.fill, IRect::new(0, 0, w, h), rect(fill, 0.0), true);
        self.layout_line();
    }

    /// BarStrip.qml's two hairline segments either side of the gap.
    fn layout_line(&mut self) {
        let IRect { w, h, .. } = self.scene.size;
        let line = theme::EDGE_WIDTH;
        let (start, end) = self.gap.unwrap_or((0, 0));
        let (start, end) = (start.clamp(0, w), end.clamp(start.clamp(0, w), w));
        self.scene.update(self.edge, IRect::new(0, h - line, start, line), rect(DARK.border, 0.0), start > 0);
        self.scene.update(self.edge_end, IRect::new(end, h - line, w - end, line), rect(DARK.border, 0.0), end < w);
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
        self.spinner.since.is_some()
    }

    /// One frame of whatever the bar animates: the spinner's angle.
    pub fn tick(&mut self, now: Instant) {
        let Spinner { disc, glyph, since, .. } = self.spinner;
        let Some(cell) = self.cells.first().copied().filter(|_| since.is_some()) else {
            self.scene.set_visible(disc, false);
            self.scene.set_visible(glyph, false);
            return;
        };
        let badge = IRect::new(cell.right() - theme::SPACE_XXS - BADGE, cell.y + theme::SPACE_XXS, BADGE, BADGE);
        self.scene.update(disc, badge, rect(DARK.background, BADGE as f32 / 2.0), true);

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
        self.scene.update_with(glyph, badge, Paint::Text { text: shaped, color: DARK.foreground }, true, spin * shift, None);
    }

    pub fn set_workspaces(&mut self, slots: &[Slot]) {
        while self.labels.len() < slots.len() {
            let empty = self.text.shape("", LABEL);
            let id = self.scene.add(IRect::default(), Paint::Text { text: empty, color: DARK.muted_foreground });
            self.labels.push(id);
        }
        let mut x = theme::SPACE_MD;
        let mut pill = None;
        self.cells.clear();
        for (at, id) in self.labels.clone().into_iter().enumerate() {
            let Some(slot) = slots.get(at) else {
                self.scene.set_visible(id, false);
                continue;
            };
            let shaped = self.text.shape(&slot.idx.to_string(), LABEL);
            let cell_w = shaped.width + theme::CONTROL_PADDING_X * 2;
            let ink = if slot.focused { DARK.primary_foreground } else { DARK.muted_foreground };
            let bounds = text_bounds(&shaped, x + theme::CONTROL_PADDING_X);
            self.scene.update(id, bounds, Paint::Text { text: shaped, color: ink }, true);
            let cell = IRect::new(x, CELL_Y, cell_w, theme::BAR_CELL_HEIGHT);
            self.cells.push(cell);
            if slot.focused {
                pill = Some(cell);
            }
            x += cell_w + theme::SPACE_SM;
        }
        match pill {
            Some(b) => self.scene.update(self.pill, b, rect(DARK.primary, theme::radius_md()), true),
            None => self.scene.set_visible(self.pill, false),
        }
        if self.spinner.since.is_some() {
            self.tick(Instant::now());
        }
    }

    pub fn set_clock(&mut self, now: &str) {
        self.now = now.to_owned();
        let shaped = self.text.shape(now, LABEL);
        let cell_w = shaped.width + theme::CONTROL_PADDING_X * 2;
        let cell_x = (self.scene.size.w - cell_w) / 2;
        self.clock_cell = IRect::new(cell_x, CELL_Y, cell_w, theme::BAR_CELL_HEIGHT);
        let bounds = text_bounds(&shaped, cell_x + theme::CONTROL_PADDING_X);
        self.scene.update(self.clock, bounds, Paint::Text { text: shaped, color: DARK.foreground }, true);
    }
}

fn rect(fill: theme::Rgba, radius: f32) -> Paint {
    Paint::Rect { fill, radius }
}

/// A label centred across the cell row, its line box on a whole pixel.
fn text_bounds(shaped: &ShapedText, x: i32) -> IRect {
    let (w, h) = shaped.box_size();
    let top = CELL_Y + (theme::BAR_CELL_HEIGHT - shaped.line_height()) / 2;
    IRect::new(x - crate::text::PAD, top - crate::text::PAD, w, h)
}
