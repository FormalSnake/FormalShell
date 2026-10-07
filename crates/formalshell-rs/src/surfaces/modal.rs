//! A modal card (Drawer.qml on the top edge with Scrim.qml under it): the
//! card budding off the top line on its own full-output surface, which
//! holds the keyboard while open, and the two single-pixel scrim surfaces
//! riding its pose: the band over the top line's own inset, which fades in
//! only as the card lets go of the line (`1 - attach`), and the rest of the
//! output. The launcher and the polkit dialog are both one of these; the
//! owner lays its content out in `card.content` under `card.clip`.

use std::time::Instant;

use fs_chrome::types::Edge;
use fs_theme::theme::Theme;
use smithay_client_toolkit::reexports::client::QueueHandle;
use smithay_client_toolkit::reexports::client::protocol::wl_surface::WlSurface;
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::KeyboardInteractivity;
use vello_cpu::kurbo::Rect;

use crate::scene::IRect;
use crate::surface::{PixelSurface, Surface};
use crate::surfaces::card::{Card, Ends};
use crate::wayland::App;

/// Which of a modal's three surfaces an event is for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Part {
    Card,
    Band,
    Dim,
}

pub struct Modal {
    pub card: Card,
    pub surface: Surface,
    band: Option<PixelSurface>,
    dim: PixelSurface,
    /// The `scrim` role's fill alpha over its plain black.
    tone: f64,
    pub open: bool,
    region: Option<IRect>,
}

impl Modal {
    /// The card rests on the line until its owner places it.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        theme: &Theme,
        surface: Surface,
        band: Option<PixelSurface>,
        dim: PixelSurface,
        output: (f64, f64),
        line_at: f64,
        ends: Ends,
        scale: f64,
        cast: bool,
        deform_amount: f64,
    ) -> Self {
        let rest = Rect::new(0.0, line_at, 0.0, line_at);
        let mut card = Card::build(theme, "card", Edge::Top, (output.0 as i32, output.1 as i32), line_at, rest, scale, cast, true);
        card.ends = ends;
        card.deform_amount = deform_amount;
        let tone = f64::from(theme.box_style("scrim", None).fill.a);
        Self { card, surface, band, dim, tone, open: true, region: None }
    }

    /// Moves the card's resting rect; an idle card lands there at once.
    pub fn place(&mut self, rest: Rect, now: Instant) {
        if rest != self.card.rest() {
            self.card.set_rect(rest, rest);
            if !self.card.animating(now) || !self.surface.mapped {
                self.card.tick(now);
            }
        }
    }

    pub fn finished(&self, now: Instant) -> bool {
        self.surface.mapped && self.card.finished(now)
    }

    pub fn animating(&self, now: Instant) -> bool {
        self.card.animating(now)
    }

    /// Closes on the card's own clock and lets the keyboard go.
    pub fn close(&mut self, now: Instant) {
        if !self.open {
            return;
        }
        self.open = false;
        self.card.set_open(now, false);
        self.surface.layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        self.surface.layer.commit();
    }

    /// Input everywhere while open, nowhere once closing.
    pub fn sync_region(&mut self, compositor: &smithay_client_toolkit::compositor::CompositorState) {
        let want = if self.open { self.card.scene.size } else { IRect::default() };
        if self.region == Some(want) {
            return;
        }
        self.region = Some(want);
        if let Ok(region) = smithay_client_toolkit::compositor::Region::new(compositor) {
            if !want.is_empty() {
                region.add(want.x, want.y, want.w, want.h);
            }
            self.surface.layer.set_input_region(Some(region.wl_region()));
        }
    }

    /// The card's frame, then the scrim on the card's own pose.
    pub fn present(&mut self, animating: bool, now: Instant, qh: &QueueHandle<App>) {
        self.surface.present(&mut self.card.scene, animating, qh);
        let pose = self.card.pose(now);
        let attach = self.card.attach(now);
        if let Some(b) = &mut self.band {
            b.present(self.tone * pose * (1.0 - attach), animating, qh);
        }
        self.dim.present(self.tone * pose, animating, qh);
    }

    pub fn part(&self, surface: &WlSurface) -> Option<Part> {
        if self.surface.layer.wl_surface() == surface {
            Some(Part::Card)
        } else if self.dim.layer.wl_surface() == surface {
            Some(Part::Dim)
        } else if self.band.as_ref().is_some_and(|b| b.layer.wl_surface() == surface) {
            Some(Part::Band)
        } else {
            None
        }
    }

    /// A frame callback; true when it was the card's, which has stepped.
    pub fn frame(&mut self, part: Part, now: Instant) -> bool {
        match part {
            Part::Card => {
                let s = &mut self.surface;
                s.landed(now);
                if s.mapped {
                    self.card.tick(now);
                } else {
                    s.mapped = true;
                    self.card.mapped(now);
                }
                true
            }
            Part::Band | Part::Dim => {
                let s = if part == Part::Band { self.band.as_mut() } else { Some(&mut self.dim) };
                if let Some(s) = s {
                    (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
                }
                false
            }
        }
    }

    pub fn configure(&mut self, part: Part, width: i32, height: i32) {
        match part {
            Part::Card => {
                let size = self.card.scene.size;
                self.surface.configure(size.w, size.h);
            }
            Part::Band => {
                if let Some(b) = &mut self.band {
                    b.configure(width, height);
                }
            }
            Part::Dim => self.dim.configure(width, height),
        }
    }

    pub fn on_card(&self, x: f64, y: f64) -> bool {
        let r = self.card.live_rect();
        x >= r.x as f64 && x < r.right() as f64 && y >= r.y as f64 && y < r.bottom() as f64
    }

    pub fn joins(&self) -> impl Iterator<Item = (Edge, f64, f64, f64)> + '_ {
        self.card.joins.iter().map(|j| (j.edge, j.x, j.width, j.reach))
    }
}
