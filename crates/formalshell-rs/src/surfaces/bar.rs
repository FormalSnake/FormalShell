//! The strip under `bar.kind: strip` (BarStrip.qml): the `bar` role's fill
//! with its one hairline along the edge facing the desktop, the workspace
//! cells in the left region and the clock centred.

use std::time::Instant;

use fs_theme::color::Rgba;
use fs_theme::style::{Line, Radius};
use fs_theme::theme::Theme;
use parley::GenericFamily;
use vello_cpu::kurbo::Affine;

use crate::motion::PULSE_MS;
use crate::scene::{IRect, NodeId, Paint, Scene};
use crate::services::hyprland::Slot;
use crate::text::{self, Family, ShapedText, Text, TextStyle};

const LOADER_CIRCLE: &str = "\u{E10A}";

/// What the strip takes off the theme: the `bar` role's fill and edge, the
/// `cell` role's active fill for the focused pill, the ink, and the metrics.
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
    thickness: i32,
    cell_y: i32,
    cell_height: i32,
    xxs: i32,
    sm: i32,
    md: i32,
    pad_x: i32,
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
            thickness: (space.bar_cell_height + space.bar_margin * 2.0) as i32,
            cell_y: space.bar_margin as i32,
            cell_height: space.bar_cell_height as i32,
            xxs: space.xxs as i32,
            sm: space.sm as i32,
            md: space.md as i32,
            pad_x: space.control_padding_x as i32,
            label: TextStyle {
                family: Family::Generic(GenericFamily::Monospace),
                size: theme.font_size.body as f32,
                weight: fs_theme::tokens::WEIGHTS.medium as f32,
            },
            badge: caption as i32,
            badge_glyph: TextStyle { family: text::ICONS, size: caption, weight: 400.0 },
        }
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

pub struct Bar {
    pub scene: Scene,
    look: Look,
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
    slots: Vec<Slot>,
}

impl Bar {
    pub fn new(width: i32, theme: &Theme) -> Self {
        let look = Look::new(theme);
        let mut scene = Scene::new(width, look.thickness);
        let fill = scene.add(IRect::default(), rect(look.fill, 0.0));
        let edge = scene.add(IRect::default(), rect(look.edge, 0.0));
        let edge_end = scene.add(IRect::default(), rect(look.edge, 0.0));
        let pill = scene.add(IRect::default(), rect(look.pill, look.pill_radius));
        let mut text = Text::new();
        let clock = scene.add(IRect::default(), Paint::Text { text: text.shape("", look.label), color: look.foreground });
        let disc = scene.add(IRect::default(), rect(look.background, look.badge as f32 / 2.0));
        let glyph =
            scene.add(IRect::default(), Paint::Text { text: text.shape("", look.badge_glyph), color: look.foreground });
        scene.set_visible(disc, false);
        scene.set_visible(glyph, false);
        let spinner = Spinner { disc, glyph, shaped: None, since: None };
        let mut bar = Self {
            scene,
            look,
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
            slots: Vec::new(),
        };
        bar.layout_strip();
        bar
    }

    /// The strip's height on its edge, which is also its exclusive zone.
    pub fn thickness(&self) -> i32 {
        self.look.thickness
    }

    /// Repaints every node off a new theme. The thickness is the layer
    /// surface's size, so it holds until the surface is remade.
    pub fn set_theme(&mut self, theme: &Theme) {
        let thickness = self.look.thickness;
        self.look = Look { thickness, ..Look::new(theme) };
        self.spinner.shaped = None;
        self.layout_strip();
        let now = std::mem::take(&mut self.now);
        self.set_clock(&now);
        let slots = std::mem::take(&mut self.slots);
        self.set_workspaces(&slots);
    }

    pub fn resize(&mut self, width: i32) {
        self.scene.resize(width, self.look.thickness);
        self.layout_strip();
        let now = std::mem::take(&mut self.now);
        self.set_clock(&now);
    }

    fn layout_strip(&mut self) {
        let IRect { w, h, .. } = self.scene.size;
        self.scene.update(self.fill, IRect::new(0, 0, w, h), rect(self.look.fill, 0.0), true);
        self.layout_line();
    }

    /// BarStrip.qml's two hairline segments either side of the gap.
    fn layout_line(&mut self) {
        let IRect { w, h, .. } = self.scene.size;
        let (line, color) = (self.look.edge_width, self.look.edge);
        let (start, end) = self.gap.unwrap_or((0, 0));
        let (start, end) = (start.clamp(0, w), end.clamp(start.clamp(0, w), w));
        self.scene.update(self.edge, IRect::new(0, h - line, start, line), rect(color, 0.0), start > 0 && line > 0);
        self.scene.update(self.edge_end, IRect::new(end, h - line, w - end, line), rect(color, 0.0), end < w && line > 0);
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
        self.slots = slots.to_vec();
        let look = self.look.clone();
        while self.labels.len() < slots.len() {
            let empty = self.text.shape("", look.label);
            let id = self.scene.add(IRect::default(), Paint::Text { text: empty, color: look.muted });
            self.labels.push(id);
        }
        let mut x = look.md;
        let mut pill = None;
        self.cells.clear();
        for (at, id) in self.labels.clone().into_iter().enumerate() {
            let Some(slot) = slots.get(at) else {
                self.scene.set_visible(id, false);
                continue;
            };
            let shaped = self.text.shape(&slot.idx.to_string(), look.label);
            let cell_w = shaped.width + look.pad_x * 2;
            let ink = if slot.focused { look.on_pill } else { look.muted };
            let bounds = text_bounds(&look, &shaped, x + look.pad_x);
            self.scene.update(id, bounds, Paint::Text { text: shaped, color: ink }, true);
            let cell = IRect::new(x, look.cell_y, cell_w, look.cell_height);
            self.cells.push(cell);
            if slot.focused {
                pill = Some(cell);
            }
            x += cell_w + look.sm;
        }
        match pill {
            Some(b) => self.scene.update(self.pill, b, rect(look.pill, look.pill_radius), true),
            None => self.scene.set_visible(self.pill, false),
        }
        if self.spinner.since.is_some() {
            self.tick(Instant::now());
        }
    }

    pub fn set_clock(&mut self, now: &str) {
        self.now = now.to_owned();
        let look = self.look.clone();
        let shaped = self.text.shape(now, look.label);
        let cell_w = shaped.width + look.pad_x * 2;
        let cell_x = (self.scene.size.w - cell_w) / 2;
        self.clock_cell = IRect::new(cell_x, look.cell_y, cell_w, look.cell_height);
        let bounds = text_bounds(&look, &shaped, cell_x + look.pad_x);
        self.scene.update(self.clock, bounds, Paint::Text { text: shaped, color: look.foreground }, true);
    }
}

fn rect(fill: Rgba, radius: f32) -> Paint {
    Paint::Rect { fill, radius }
}

/// A label centred across the cell row, its line box on a whole pixel.
fn text_bounds(look: &Look, shaped: &ShapedText, x: i32) -> IRect {
    let (w, h) = shaped.box_size();
    let top = look.cell_y + (look.cell_height - shaped.line_height()) / 2;
    IRect::new(x - crate::text::PAD, top - crate::text::PAD, w, h)
}
