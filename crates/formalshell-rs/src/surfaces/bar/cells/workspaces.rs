//! The workspace chips as the R0 spike drew them (Workspaces.qml's model
//! through `Bar/workspaces.js`): each ordinal a cell, the focused one under
//! the travelling pill, and the herdr spinner on the first chip. Spaces'
//! window icons and badges build on this.

use std::time::Instant;

use fs_chrome::bar::workspaces::{self, Slot, SlotOpts};
use vello_cpu::kurbo::Affine;

use crate::motion::{Animated, EMPHASIZED, PULSE_MS};
use crate::scene::IRect;
use crate::services::hyprland::{Window, Workspace};
use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Custom, Env, Ink, Kit, Look, Painter, View};
use crate::text::{self, ShapedText, TextStyle};

/// `workspaces.persistent`'s default: slots 1..n show even when empty.
const PERSISTENT_WORKSPACES: i64 = 5;
const LOADER_CIRCLE: &str = "loader-circle";

/// The focused workspace's fill. Its two edges chase the same chip, the
/// leading pair on `emphasized` and the trailing pair on twice that clock,
/// so a switch stretches one shape across both chips before it lands.
struct Pill {
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

pub struct Workspaces {
    slots: Vec<Slot>,
    /// Each chip's start and extent along the cell.
    chips: Vec<(f64, f64)>,
    vertical: bool,
    pill: Pill,
    spinner: Option<Instant>,
}

impl Default for Workspaces {
    fn default() -> Self {
        let at = |v| Animated::new(v, EMPHASIZED);
        Self {
            slots: Vec::new(),
            chips: Vec::new(),
            vertical: false,
            pill: Pill { shown: false, lead: (at(0.0), at(0.0)), trail: (at(0.0), at(0.0)) },
            spinner: None,
        }
    }
}

fn workspace(w: &Workspace) -> workspaces::Workspace {
    workspaces::Workspace {
        id: w.id.clone(),
        idx: w.idx,
        name: w.name.clone(),
        output: w.output.clone(),
        is_active: w.is_active,
        is_focused: w.is_focused,
        is_urgent: w.is_urgent,
        placeholder: false,
    }
}

fn window(w: &Window) -> workspaces::Window {
    workspaces::Window {
        id: w.id.clone(),
        workspace_id: w.workspace_id.clone(),
        app_id: w.app_id.clone(),
        initial_class: w.initial_class.clone(),
        initial_title: w.initial_title.clone(),
        pid: w.pid,
        is_focused: w.is_focused,
        is_urgent: w.is_urgent,
        is_floating: w.is_floating,
        rect: w.rect.map(|r| fs_chrome::types::Rect {
            x: r.x as f64,
            y: r.y as f64,
            width: r.width as f64,
            height: r.height as f64,
        }),
    }
}

impl Workspaces {
    fn label_style(look: &Look) -> TextStyle {
        look.label(fs_theme::tokens::WEIGHTS.medium as f32)
    }
}

impl Cell for Workspaces {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Hyprland, Topic::Config]
    }

    fn read(&mut self, env: &Env) -> bool {
        let persistent = env.store.config.f64("workspaces.persistent").map_or(PERSISTENT_WORKSPACES, |n| n as i64);
        let c = &env.store.hyprland.compositor;
        let rows: Vec<workspaces::Workspace> = c.workspaces.iter().map(workspace).collect();
        let windows: Vec<workspaces::Window> = c.windows.iter().map(window).collect();
        let slots = workspaces::slots(&rows, &windows, env.output, SlotOpts { persistent, ..SlotOpts::default() });
        let vertical = env.edge.is_vertical();
        let changed = slots != self.slots || vertical != self.vertical;
        self.slots = slots;
        self.vertical = vertical;
        changed
    }

    fn view(&self, _: &Look) -> View {
        let mut v = View::new(Vec::new(), 0.0);
        v.tooltip = String::new();
        v
    }

    fn click(&mut self, _: Button, at: (f64, f64), _: &Env) -> Action {
        let along = if self.vertical { at.1 } else { at.0 };
        self.chips
            .iter()
            .zip(&self.slots)
            .find(|((s, e), _)| along >= *s && along < s + e)
            .map_or(Action::None, |(_, slot)| Action::Workspace(slot.id.clone()))
    }

    fn custom(&mut self) -> Option<&mut dyn Custom> {
        Some(self)
    }
}

impl Custom for Workspaces {
    fn measure(&mut self, kit: &mut Kit, vertical: bool) -> f64 {
        let look = kit.look.clone();
        let now = Instant::now();
        self.chips.clear();
        let mut at = 0.0;
        let mut focused = None;
        for slot in &self.slots.clone() {
            let shaped = kit.shape(&slot.label, Self::label_style(&look));
            let extent = if vertical { look.cell_height } else { shaped.width as f64 + look.pad_x * 2.0 };
            self.chips.push((at, extent));
            if slot.is_focused {
                focused = Some((at, at + extent));
            }
            at += extent + look.sm;
        }
        match focused {
            Some((start, end)) if self.pill.shown => {
                let clock = look.emphasized * kit.motion_scale;
                self.pill.lead.0.set(now, start, clock);
                self.pill.lead.1.set(now, end, clock);
                self.pill.trail.0.set(now, start, clock * 2.0);
                self.pill.trail.1.set(now, end, clock * 2.0);
            }
            Some((start, end)) => {
                // Arriving rather than travelling: the pill lands on its chip.
                self.pill.shown = true;
                self.pill.lead.0.jump(start);
                self.pill.trail.0.jump(start);
                self.pill.lead.1.jump(end);
                self.pill.trail.1.jump(end);
            }
            None => self.pill.shown = false,
        }
        (at - look.sm).max(0.0)
    }

    fn draw(&mut self, kit: &mut Kit, p: &mut Painter, rect: IRect, ink: &Ink, now: Instant) {
        let look = kit.look.clone();
        let vertical = self.vertical;
        let chip = |start: f64, extent: f64| {
            if vertical {
                IRect::new(rect.x, rect.y + start.round() as i32, rect.w, extent.round() as i32)
            } else {
                IRect::new(rect.x + start.round() as i32, rect.y, extent.round() as i32, rect.h)
            }
        };
        if self.pill.shown {
            let (from, to) = self.pill.span(now);
            let r = chip(from, to - from);
            p.rect(r, ink.of(look.active_fill), look.radius);
        }
        for (slot, (start, extent)) in self.slots.iter().zip(&self.chips) {
            let shaped = kit.shape(&slot.label, Self::label_style(&look));
            let c = chip(*start, *extent);
            let color = if slot.is_focused { look.on_active } else { ink.dim };
            let x = c.x + (c.w - shaped.width) / 2;
            let y = c.y + (c.h - shaped.line_height()) / 2;
            p.text(&shaped, (x, y), ink.of(color), if slot.is_focused { &[] } else { &ink.glow });
        }
        if let (Some(since), Some((start, extent))) = (self.spinner, self.chips.first().copied()) {
            let c = chip(start, extent);
            let size = look.caption as i32;
            let xxs = look.xxs as i32;
            let badge = IRect::new(c.right() - xxs - size, c.y + xxs, size, size);
            p.rect(badge, ink.of(look.background), size as f32 / 2.0);
            let g = fs_theme::icons::glyph(&look.icon_set, LOADER_CIRCLE);
            let shaped: ShapedText = kit.shape(g.text, TextStyle { family: text::Family::Named(g.family), size: look.caption, weight: 400.0 });
            let (bw, bh) = shaped.box_size();
            let at = (badge.x + (size - bw) / 2, badge.y + (size - bh) / 2);
            let centre = (badge.x as f64 + size as f64 / 2.0, badge.y as f64 + size as f64 / 2.0);
            let elapsed = now.saturating_duration_since(since).as_secs_f64() * 1000.0;
            let turn = (elapsed / PULSE_MS).fract() * std::f64::consts::TAU;
            let spin = Affine::translate(centre) * Affine::rotate(turn) * Affine::translate((-centre.0, -centre.1));
            // The node covers the badge alone, so the damage is the badge.
            let shift = Affine::translate(((at.0 - badge.x) as f64, (at.1 - badge.y) as f64));
            p.text_in(&shaped, badge, spin * shift, p.clip, ink.of(look.foreground), &[]);
        }
    }

    fn animating(&self, now: Instant) -> bool {
        self.spinner.is_some() || self.pill.running(now)
    }

    fn spinner(&mut self, on: bool, now: Instant) {
        match (on, self.spinner) {
            (true, None) => self.spinner = Some(now),
            (false, Some(_)) => self.spinner = None,
            _ => {}
        }
    }
}
