//! The strip under `bar.kind: strip` (BarStrip.qml): a `card` fill at the
//! surface alpha with one `border` hairline along the edge facing the
//! desktop, the workspace cells in the left region and the clock centred.

use crate::hyprland::Slot;
use crate::scene::{IRect, NodeId, Paint, Scene};
use parley::GenericFamily;

use crate::text::{ShapedText, Text, TextStyle};
use crate::theme::{self, DARK};

const LABEL: TextStyle = TextStyle { family: GenericFamily::Monospace, size: theme::FONT_BODY, weight: theme::WEIGHT_MEDIUM };
const CELL_Y: i32 = theme::BAR_MARGIN;

pub struct Bar {
    pub scene: Scene,
    text: Text,
    fill: NodeId,
    edge: NodeId,
    pill: NodeId,
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
        let pill = scene.add(IRect::default(), rect(DARK.primary, theme::radius_md()));
        let mut text = Text::new();
        let clock = scene.add(IRect::default(), Paint::Text { text: text.shape("", LABEL), color: DARK.foreground });
        let mut bar = Self { scene, text, fill, edge, pill, labels: Vec::new(), clock, now: String::new() };
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
        let line = theme::EDGE_WIDTH;
        self.scene.update(self.edge, IRect::new(0, h - line, w, line), rect(DARK.border, 0.0), true);
    }

    pub fn set_workspaces(&mut self, slots: &[Slot]) {
        while self.labels.len() < slots.len() {
            let empty = self.text.shape("", LABEL);
            let id = self.scene.add(IRect::default(), Paint::Text { text: empty, color: DARK.muted_foreground });
            self.labels.push(id);
        }
        let mut x = theme::SPACE_MD;
        let mut pill = None;
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
            if slot.focused {
                pill = Some(IRect::new(x, CELL_Y, cell_w, theme::BAR_CELL_HEIGHT));
            }
            x += cell_w + theme::SPACE_SM;
        }
        match pill {
            Some(b) => self.scene.update(self.pill, b, rect(DARK.primary, theme::radius_md()), true),
            None => self.scene.set_visible(self.pill, false),
        }
    }

    pub fn set_clock(&mut self, now: &str) {
        self.now = now.to_owned();
        let shaped = self.text.shape(now, LABEL);
        let cell_w = shaped.width + theme::CONTROL_PADDING_X * 2;
        let cell_x = (self.scene.size.w - cell_w) / 2;
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
