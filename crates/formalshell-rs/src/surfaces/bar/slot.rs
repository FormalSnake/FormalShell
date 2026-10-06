//! One placed cell (Bar.qml's region delegate): the cell, its measure, its
//! presence along the strip and fade, its open mark, its marquee clock and
//! the nodes it last drew. The strip and the chevron's second bar both hold
//! their cells as slots.

use std::time::{Duration, Instant};

use fs_chrome::bar::layout::Entry;
use fs_chrome::types::{Edge, Region};
use fs_theme::color::Rgba;
use fs_theme::style::Glow;

use crate::motion::{Animated, EFFECTS, SPATIAL, SPATIAL_FAST};
use crate::scene::{IRect, NodeId, Scene};
use crate::surfaces::bar::cell::{Cell, Env, Frame, Ink, Kit, Limits, Measured, Painter, View};
use crate::surfaces::bar::cells;

pub struct Slot {
    /// The name `bar.layout` gave it.
    pub name: String,
    pub region: Region,
    pub cell: Box<dyn Cell>,
    pub view: View,
    pub measured: Measured,
    /// What the slot measures to, 0 while its cell is not shown.
    pub natural: f64,
    pub along: Animated,
    fade: Animated,
    /// The free label's budget (`labelBudget`).
    pub budget: f64,
    pub limits: Option<Limits>,
    pub open: bool,
    mark: Animated,
    mark_fade: Animated,
    /// When the marquee's current cycle started, while it overflows.
    marquee: Option<Instant>,
    /// Laid out along the strip, in the owner's scene; empty when the
    /// region's room hid it.
    pub rect: IRect,
    pub clip: IRect,
    nodes: Vec<NodeId>,
    pub dirty: bool,
}

impl Slot {
    pub fn new(entry: &Entry, region_entries: &[Entry]) -> Self {
        Self {
            name: entry.name(),
            region: entry.region,
            cell: cells::build(entry, region_entries),
            view: View::hidden(),
            measured: Measured::default(),
            natural: 0.0,
            along: Animated::new(0.0, SPATIAL),
            fade: Animated::new(0.0, EFFECTS),
            budget: f64::INFINITY,
            limits: None,
            open: false,
            mark: Animated::new(0.0, SPATIAL_FAST),
            mark_fade: Animated::new(0.0, EFFECTS),
            marquee: None,
            rect: IRect::default(),
            clip: IRect::default(),
            nodes: Vec::new(),
            dirty: true,
        }
    }

    /// Re-reads the cell and measures it again. `animate` arms the
    /// presence clocks (held off until the strip has arrived).
    pub fn refresh(&mut self, kit: &mut Kit, env: &Env, band: bool, animate: bool, along_strip: f64, now: Instant) {
        if self.cell.read(env) {
            self.dirty = true;
        }
        let vertical = env.edge.is_vertical();
        self.view = self.cell.view(&kit.look);
        let natural = match self.cell.custom() {
            Some(c) if self.view.shown => c.measure(kit, vertical) + 0.0,
            _ => {
                self.measured = kit.measure(&self.view, vertical, self.budget, band);
                if let Some(free) = &self.measured.free {
                    let rest = self.measured.along - free.extent;
                    self.limits = self.cell.limits(&kit.look, along_strip, rest);
                }
                if self.view.shown { self.measured.along } else { 0.0 }
            }
        };
        let look = &kit.look;
        let scale = kit.motion_scale;
        if natural != self.natural || !animate {
            self.natural = natural;
            if animate && look.motion {
                self.along.set(now, natural, look.spatial * scale);
            } else {
                self.along.jump(natural);
            }
        }
        let fade = if self.view.shown { 1.0 } else { 0.0 };
        if animate && look.motion {
            self.fade.set(now, fade, look.effects * scale);
        } else {
            self.fade.jump(fade);
        }
        self.dirty = true;
    }

    pub fn set_open(&mut self, open: bool, kit: &Kit, now: Instant) {
        if self.cell.set_open(open) {
            self.view = self.cell.view(&kit.look);
            self.dirty = true;
        }
        if open == self.open {
            return;
        }
        self.open = open;
        let t = if open { 1.0 } else { 0.0 };
        let scale = kit.motion_scale;
        self.mark.set(now, t, kit.look.spatial_fast * scale);
        self.mark_fade.set(now, t, kit.look.effects * scale);
        self.dirty = true;
    }

    /// The extent the strip lays this slot out at this frame.
    pub fn extent(&self, now: Instant) -> f64 {
        self.along.value(now).max(0.0)
    }

    pub fn present(&self) -> bool {
        self.natural > 0.0
    }

    pub fn free_natural(&self) -> f64 {
        self.measured.free.as_ref().map_or(0.0, |f| f.natural)
    }

    pub fn free_extent(&self) -> f64 {
        self.measured.free.as_ref().map_or(0.0, |f| f.extent)
    }

    fn overflowing(&self, kit: &Kit, visible: bool) -> bool {
        kit.look.motion && visible && self.measured.free.as_ref().is_some_and(|f| f.overflow && f.extent > 0.0)
    }

    pub fn scrolling(&self, kit: &Kit, visible: bool) -> bool {
        self.overflowing(kit, visible)
    }

    /// The marquee's scroll this frame, or none while it holds or fits.
    fn scroll(&mut self, kit: &Kit, visible: bool, now: Instant) -> Option<f64> {
        if !self.overflowing(kit, visible) {
            self.marquee = None;
            return None;
        }
        let start = *self.marquee.get_or_insert(now);
        let free = self.measured.free.as_ref()?;
        let look = &kit.look;
        let run = free.loop_width / look.marquee_px * 1000.0;
        let cycle = look.marquee_hold + run;
        let t = now.saturating_duration_since(start).as_secs_f64() * 1000.0 % cycle;
        (t >= look.marquee_hold).then(|| (t - look.marquee_hold) / 1000.0 * look.marquee_px)
    }

    /// When the marquee next starts to move, while it is holding.
    pub fn wake(&self, kit: &Kit, visible: bool, now: Instant) -> Option<Instant> {
        let start = self.marquee.filter(|_| self.overflowing(kit, visible))?;
        let free = self.measured.free.as_ref()?;
        let look = &kit.look;
        let cycle = look.marquee_hold + free.loop_width / look.marquee_px * 1000.0;
        let t = now.saturating_duration_since(start).as_secs_f64() * 1000.0 % cycle;
        (t < look.marquee_hold).then(|| now + Duration::from_secs_f64((look.marquee_hold - t) / 1000.0))
    }

    pub fn animating(&mut self, kit: &Kit, visible: bool, now: Instant) -> bool {
        let custom = self.cell.custom().is_some_and(|c| c.animating(now));
        custom
            || self.along.running(now)
            || self.fade.running(now)
            || self.mark.running(now)
            || self.mark_fade.running(now)
            || self.scroll(kit, visible, now).is_some()
    }

    pub fn hide(&mut self, scene: &mut Scene) {
        for id in &self.nodes {
            scene.set_visible(*id, false);
        }
        self.rect = IRect::default();
    }

    /// Draws the slot at `rect` under `clip`.
    #[allow(clippy::too_many_arguments)]
    pub fn paint(
        &mut self,
        kit: &mut Kit,
        scene: &mut Scene,
        edge: Edge,
        hovered: bool,
        band: Option<(Rgba, &[Glow<Rgba>])>,
        alpha: f32,
        visible: bool,
        now: Instant,
    ) {
        let rect = self.rect;
        let fade = self.fade.value(now).clamp(0.0, 1.0) as f32 * alpha;
        let scroll = self.scroll(kit, visible, now);
        let mut p = Painter::new(scene, &mut self.nodes, Some(self.clip.intersect(&rect)));
        if rect.is_empty() || fade <= 0.0 {
            p.finish();
            return;
        }
        let frame = Frame {
            rect,
            edge,
            hovered: hovered && self.view.interactive,
            open: (self.mark.value(now), self.mark_fade.value(now).clamp(0.0, 1.0)),
            alpha: fade,
            band,
            scroll,
        };
        match self.cell.custom() {
            Some(custom) => {
                kit.draw_box(&mut p, self.view.tone, &frame);
                let ink = Ink::resolve(&kit.look, self.view.tone, band, fade);
                custom.draw(kit, &mut p, rect, &ink, now);
            }
            None => kit.draw(&self.view, &self.measured, &mut p, &frame),
        }
        p.finish();
        self.dirty = false;
    }
}
