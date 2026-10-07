//! A modal card (Drawer.qml on the top edge with Scrim.qml under it): the
//! card budding off the top line on its own full-output surface, which
//! holds the keyboard while open, and the two single-pixel scrim surfaces
//! riding its pose: the band over the top line's own inset, which fades in
//! only as the card lets go of the line (`1 - attach`), and the rest of the
//! output. The launcher, the polkit dialog and the radio atlas are each one
//! of these; the owner lays its content out in `card.content` under
//! `card.clip`.

use std::time::Instant;

use fs_chrome::types::Edge;
use fs_theme::theme::Theme;
use smithay_client_toolkit::reexports::client::QueueHandle;
use smithay_client_toolkit::reexports::client::protocol::wl_surface::WlSurface;
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::KeyboardInteractivity;
use vello_cpu::kurbo::Rect;

use smithay_client_toolkit::reexports::protocols::wp::alpha_modifier::v1::client::wp_alpha_modifier_surface_v1::WpAlphaModifierSurfaceV1;

use crate::scene::{IRect, NodeId, Paint, Scene};
use crate::surface::{PixelSurface, Role, Sub, Surface};
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
    /// The owner's content, when it draws on a layer of its own rather
    /// than in the card's scene.
    pub layer: Option<Layer>,
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
        Self { card, surface, band, dim, tone, open: true, region: None, layer: None }
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

    /// The card's frame, then the scrim on the card's own pose. The scrim
    /// asks for frames only while the card itself moves, never for the
    /// owner's content.
    pub fn present(&mut self, animating: bool, now: Instant, qh: &QueueHandle<App>) {
        let layered = self.layer.as_mut().is_some_and(|l| l.present(&self.card, !self.card.animating(now), qh));
        let before = self.surface.commits();
        self.surface.present(&mut self.card.scene, animating, qh);
        // A subsurface's state lands with its parent's next commit.
        if layered && self.surface.commits() == before {
            self.surface.layer.commit();
        }
        let pose = self.card.pose(now);
        let attach = self.card.attach(now);
        let moving = self.card.animating(now);
        if let Some(b) = &mut self.band {
            b.present(self.tone * pose * (1.0 - attach), moving, qh);
        }
        self.dim.present(self.tone * pose, moving, qh);
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

/// The owner's content on a synchronized subsurface of the card, drawn
/// where the card rests: its motion moves and fades the layer in the
/// compositor (`wl_subsurface.set_position`, `wp_alpha_modifier`), so a
/// frame of the card's motion draws only the card's own frame. Only while
/// the content crosses the line does the owner lay it out again, cut to
/// what shows.
pub struct Layer {
    pub scene: Scene,
    pub surface: Surface<Sub>,
    fade: WpAlphaModifierSurfaceV1,
    pub top: NodeId,
    /// What the compositor last got: the layer's offset and multiplier.
    shown: Option<(i32, i32, u32)>,
}

impl Layer {
    pub fn new(surface: Surface<Sub>, fade: WpAlphaModifierSurfaceV1, size: (i32, i32)) -> Self {
        let mut scene = Scene::clear(size.0, size.1);
        let top = scene.add(IRect::default(), Paint::Shape { fill: None, strokes: Vec::new() });
        scene.set_visible(top, false);
        Self { scene, surface, fade, top, shown: None }
    }

    /// The card's offset since its content was laid out where it rests.
    /// Once the card has settled it is none: the content rect may have
    /// moved on before the card next steps.
    fn shift(card: &Card, settled: bool) -> (i32, i32) {
        let (now, rest) = (card.content.0, card.content_rest());
        if settled { (0, 0) } else { (now.x - rest.x, now.y - rest.y) }
    }

    /// The part of the content that shows this frame, in the layer's own
    /// coordinates: the resting rect cut to the card's clip.
    pub fn crop(card: &Card, settled: bool) -> IRect {
        let rest = card.content_rest();
        let (dx, dy) = Self::shift(card, settled);
        let now = IRect::new(rest.x + dx, rest.y + dy, rest.w, rest.h);
        let shown = card.clip.intersect(&now);
        IRect::new(shown.x - dx, shown.y - dy, shown.w, shown.h)
    }

    /// The layer's draw, then its offset and fade off the card's pose. True
    /// when anything reached the subsurface, which only shows once the
    /// card commits too.
    fn present(&mut self, card: &Card, settled: bool, qh: &QueueHandle<App>) -> bool {
        let before = self.surface.commits();
        self.surface.present(&mut self.scene, false, qh);
        let (dx, dy) = Self::shift(card, settled);
        let alpha = if Self::crop(card, settled).is_empty() { 0.0 } else { card.content.1.clamp(0.0, 1.0) };
        let want = (dx, dy, (f64::from(alpha) * f64::from(u32::MAX)).round() as u32);
        if self.shown == Some(want) {
            return self.surface.commits() != before;
        }
        self.shown = Some(want);
        self.surface.layer.sub.set_position(dx, dy);
        self.fade.set_multiplier(want.2);
        self.surface.layer.role_commit();
        true
    }

    /// The layer gone, its pool, buffers and canvas kept for the next one.
    pub fn keep(self) -> crate::surface::Kept {
        self.fade.destroy();
        self.surface.keep()
    }

    /// From the card's surface coordinates to the layer's, for a pointer.
    pub fn offset(card: &Card, settled: bool) -> (f64, f64) {
        let (dx, dy) = Self::shift(card, settled);
        (f64::from(dx), f64::from(dy))
    }
}

