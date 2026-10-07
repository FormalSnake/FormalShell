//! The screensaver (Screensaver.qml): one controller deciding when to show,
//! the session's idle state crossed with the live media guard, and one
//! full-output overlay drawing the banner cell by cell. ttfx is the frame
//! source when it is on PATH (its stdout parsed on the service thread),
//! fs-screensaver's built-in effects when it is not. The overlay fades in
//! and out through `wp_alpha_modifier_v1`, so a fade step is a multiplier
//! and a commit, and nothing draws or ticks while it is down.
//!
//! When the overlay unmaps, the end of its fade, the hot corner that fired
//! it is told the action ended (`hot_corner_action_ended`): that is the
//! moment the pointer comes back to a corner it may never have left.

use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::time::{Duration, Instant, SystemTime};

use calloop::RegistrationToken;
use calloop::timer::{TimeoutAction, Timer};
use fs_screensaver::{blocks, effect, ttfx};
use fs_theme::color::Rgba;
use parley::GenericFamily;
use serde_json::json;
use smithay_client_toolkit::reexports::client::protocol::wl_pointer;
use smithay_client_toolkit::reexports::protocols::wp::alpha_modifier::v1::client::wp_alpha_modifier_surface_v1::WpAlphaModifierSurfaceV1;
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::{Anchor, KeyboardInteractivity, Layer};
use vello_cpu::kurbo::Rect;

use super::App;
use crate::motion::{Animated, EFFECTS_SLOW};
use crate::scene::{IRect, NodeId, Paint, Scene};
use crate::services::screensaver as service;
use crate::services::visualizer::Avail;
use crate::surface::{Ignore, Surface};
use crate::text::{Family, ShapedText, TextStyle};

const NAMESPACE: &str = "formalshell:screensaver";
const FRAME_INTERVAL: Duration = Duration::from_millis(90);
/// 18pt at 96dpi, the size omarchy pins every screensaver terminal to; the
/// fit to the screen's width only ever shrinks it.
const BANNER_FONT_SIZE: f64 = 24.0;
const BACKGROUND: Rgba = Rgba { r: 0.0, g: 0.0, b: 0.0, a: 1.0 };
const FOREGROUND: Rgba = Rgba { r: 1.0, g: 1.0, b: 1.0, a: 1.0 };

/// One cell to paint: its column on the canvas, its character, its ink.
type Row = Vec<(i64, char, Rgba)>;

pub struct Overlay {
    surface: Surface,
    fade: WpAlphaModifierSurfaceV1,
    scene: Scene,
    background: Option<NodeId>,
    rows_drawn: Vec<Option<(u64, NodeId)>>,
    size: (i32, i32),
    font_size: f64,
    cell: (f64, f64),
    columns: i64,
    rows: i64,
    glyphs: HashMap<char, ShapedText>,
    multiplier: Option<u32>,
    /// The first pointer position after mapping is a baseline, not a move:
    /// mapping under a still cursor reports one.
    baseline: Option<(f64, f64)>,
}

impl Drop for Overlay {
    fn drop(&mut self) {
        self.fade.destroy();
    }
}

pub struct Saver {
    forced: bool,
    suppressed: bool,
    pub active: bool,
    pinned: i64,
    cycles: u64,
    seed: i64,
    previous: String,
    ttfx_frames: usize,
    run: u64,
    logged_unknown: bool,
    auto_frame: i64,
    /// The rows on screen, ttfx's or the built-in engine's.
    grid: Vec<Row>,
    overlay: Option<Overlay>,
    opacity: Animated,
    hold: Option<RegistrationToken>,
    tick: Option<RegistrationToken>,
    /// `screensaver.lockAfterSeconds`' timer, running only while shown.
    chain: Option<RegistrationToken>,
}

impl Default for Saver {
    fn default() -> Self {
        Self {
            forced: false,
            suppressed: false,
            active: false,
            pinned: -1,
            cycles: 0,
            seed: 0,
            previous: String::new(),
            ttfx_frames: 0,
            run: 0,
            logged_unknown: false,
            auto_frame: 0,
            grid: Vec::new(),
            overlay: None,
            opacity: Animated::new(0.0, EFFECTS_SLOW),
            hold: None,
            tick: None,
            chain: None,
        }
    }
}

fn now_ms() -> i64 {
    SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64)
}

fn row_hash(row: &Row) -> u64 {
    let mut h = std::collections::hash_map::DefaultHasher::new();
    for (col, ch, ink) in row {
        (col, ch, ink.r.to_bits(), ink.g.to_bits(), ink.b.to_bits(), ink.a.to_bits()).hash(&mut h);
    }
    h.finish()
}

fn ink(color: &str) -> Rgba {
    Rgba::parse(color).unwrap_or(FOREGROUND)
}

impl App {
    fn saver_requested_effect(&self) -> String {
        self.store.config.str("screensaver.effect").unwrap_or("random").to_owned()
    }

    fn saver_hold_seconds(&self) -> f64 {
        self.store.config.f64("screensaver.holdSeconds").unwrap_or(4.0)
    }

    fn saver_guard(&self) -> bool {
        self.store.config.bool("screensaver.guardMediaPlayback").unwrap_or(true)
    }

    fn saver_ttfx(&self) -> bool {
        self.store.screensaver.ttfx == Avail::Available
    }

    pub fn saver_engine(&self) -> &'static str {
        if self.saver_ttfx() { "ttfx" } else { "builtin" }
    }

    fn media_playing(&self) -> bool {
        self.store.media.active().is_some_and(|a| a.playing)
    }

    pub fn saver_effect(&self) -> String {
        let s = &self.saver;
        let requested = self.saver_requested_effect();
        if self.saver_ttfx() {
            ttfx::reroll_effect_name(&requested, &s.previous, s.seed)
        } else {
            effect::reroll_effect_name(&requested, &s.previous, s.seed)
        }
    }

    fn saver_banner(&self) -> effect::Banner {
        effect::parse_banner(self.store.screensaver.banner.as_ref().map_or("", |(_, t)| t.as_str()))
    }

    fn saver_convergence(&self) -> i64 {
        if self.saver_ttfx() {
            self.saver.ttfx_frames as i64
        } else {
            effect::convergence_frame(&self.saver_effect(), &self.saver_banner())
        }
    }

    pub fn saver_status(&self) -> String {
        let c = &self.store.caffeinate;
        json!({
            "active": self.saver.active,
            "isIdle": c.idle,
            "guardMediaPlayback": self.saver_guard(),
            "mediaPlaying": self.media_playing(),
            "caffeinated": c.active,
        })
        .to_string()
    }

    pub fn saver_frame_info(&self) -> String {
        json!({
            "engine": self.saver_engine(),
            "effect": self.saver_effect(),
            "convergenceFrame": self.saver_convergence(),
            "cycles": self.saver.cycles,
        })
        .to_string()
    }

    pub fn saver_active(&self) -> bool {
        self.saver.active
    }

    pub fn saver_start(&mut self) {
        self.saver.forced = true;
        self.saver_update();
    }

    pub fn saver_stop(&mut self) {
        self.saver.forced = false;
        self.saver.suppressed = true;
        self.saver_update();
    }

    pub fn saver_pin(&mut self, frame: i64) {
        self.saver_cancel_hold();
        self.saver.pinned = frame;
        if self.saver_ttfx() {
            self.saver_start_run();
        } else {
            self.saver_paint_builtin();
        }
    }

    /// The banner follows `screensaver.asciiPath`, read off the loop.
    pub fn saver_config(&mut self) {
        let configured = self.store.config.str("screensaver.asciiPath").unwrap_or("").to_owned();
        if let Some(rt) = &self.runtime {
            rt.service(move |ctx| service::load_banner(ctx, configured));
        }
        self.saver_update();
    }

    /// Real activity clears a dismissal's suppression; idle, the media
    /// guard and caffeinate decide the rest, live.
    pub fn saver_idle_changed(&mut self) {
        if !self.store.caffeinate.idle {
            self.saver.suppressed = false;
        }
        self.saver_update();
    }

    pub fn saver_update(&mut self) {
        let c = &self.store.caffeinate;
        let auto = c.idle && !self.saver.suppressed && (!self.saver_guard() || !self.media_playing()) && !c.active;
        let active = self.saver.forced || auto;
        if active == self.saver.active {
            return;
        }
        self.saver.active = active;
        self.saver_cancel_hold();
        let now = Instant::now();
        let reveal = self.saver_reveal_ms();
        if active {
            let s = &mut self.saver;
            s.previous.clear();
            s.cycles = 0;
            s.ttfx_frames = 0;
            s.seed = now_ms();
            s.auto_frame = 0;
            s.grid.clear();
            let requested = self.saver_requested_effect();
            let known = if self.saver_ttfx() { ttfx::is_known_effect(&requested) } else { effect::is_known_effect(&requested) };
            if requested != "random" && !known && !self.saver.logged_unknown {
                eprintln!("screensaver: unknown screensaver.effect '{requested}', falling back to random");
                self.saver.logged_unknown = true;
            }
            if self.saver.overlay.is_none() {
                self.saver_map();
            }
            if let Some(o) = &mut self.saver.overlay {
                o.baseline = None;
                o.surface.layer.set_keyboard_interactivity(KeyboardInteractivity::OnDemand);
                o.surface.layer.commit();
            }
            self.saver.opacity.set(now, 1.0, reveal);
            self.saver_paint();
        } else {
            self.saver.pinned = effect::next_pinned_frame(false, self.saver.pinned);
            self.saver.opacity.set(now, 0.0, reveal);
            if let Some(o) = &mut self.saver.overlay {
                o.surface.layer.set_keyboard_interactivity(KeyboardInteractivity::None);
                o.surface.layer.commit();
            }
        }
        self.saver_start_run();
        self.saver_arm_tick();
        self.saver_arm_chain();
    }

    /// Continued inactivity under the screensaver chains into the lock; 0
    /// (the default) leaves it off.
    fn saver_arm_chain(&mut self) {
        if let (Some(t), Some(h)) = (self.saver.chain.take(), &self.handle) {
            h.remove(t);
        }
        let seconds = self.store.config.f64("screensaver.lockAfterSeconds").unwrap_or(0.0);
        if !self.saver.active || seconds <= 0.0 {
            return;
        }
        let Some(handle) = &self.handle else { return };
        let token = handle.insert_source(Timer::from_duration(Duration::from_secs_f64(seconds)), |_, _, app: &mut App| {
            app.saver.chain = None;
            if app.saver.active {
                let _ = app.lock();
            }
            TimeoutAction::Drop
        });
        self.saver.chain = token.ok();
    }

    fn saver_reveal_ms(&self) -> f64 {
        let theme = &self.store.theme.theme;
        if !theme.motion_enabled {
            return 0.0;
        }
        theme.motion().families.reveal * self.motion_scale
    }

    fn saver_map(&mut self) {
        let surface = self.compositor.create_surface(&self.qh);
        let layer = self.layer_shell.create_layer_surface(&self.qh, surface, Layer::Overlay, Some(NAMESPACE), None);
        layer.set_anchor(Anchor::all());
        layer.set_size(0, 0);
        layer.set_exclusive_zone(-1);
        layer.set_keyboard_interactivity(KeyboardInteractivity::OnDemand);
        layer.commit();
        let fade = self.pixels.alpha.get_surface(layer.wl_surface(), &self.qh, Ignore);
        let mut surface = Surface::new("screensaver", layer, &self.shm, self.started);
        surface.wait_map = true;
        self.saver.overlay = Some(Overlay {
            surface,
            fade,
            scene: Scene::new(1, 1),
            background: None,
            rows_drawn: Vec::new(),
            size: (0, 0),
            font_size: BANNER_FONT_SIZE,
            cell: (1.0, 1.0),
            columns: 0,
            rows: 0,
            glyphs: HashMap::new(),
            multiplier: None,
            baseline: None,
        });
    }

    pub(super) fn saver_mapped(&self) -> bool {
        self.saver.overlay.is_some()
    }

    pub(super) fn saver_owns(&self, surface: &smithay_client_toolkit::reexports::client::protocol::wl_surface::WlSurface) -> bool {
        self.saver.overlay.as_ref().is_some_and(|o| o.surface.layer.wl_surface() == surface)
    }

    /// The canvas measured in cells of the mono font at the size that fits
    /// the banner, as Screensaver.qml's `metric` text measures it.
    pub(super) fn saver_configure(&mut self, width: i32, height: i32) {
        let banner = self.saver_banner();
        let Some(o) = &mut self.saver.overlay else { return };
        if width <= 0 || height <= 0 {
            return;
        }
        let style = |size: f64| TextStyle { family: Family::Generic(GenericFamily::Monospace), size: size as f32, weight: 400.0, tracking: 0.0 };
        let metric = self.bar.kit.text.shape("MMMMMMMMMM", style(100.0));
        let advance = f64::from(metric.width) / 1000.0;
        let line = f64::from(metric.ascent + metric.descent) / 100.0;
        let fit = if banner.width > 0 && advance > 0.0 {
            f64::from(width) / ((banner.width as f64 + 4.0) * advance)
        } else {
            BANNER_FONT_SIZE
        };
        let font_size = BANNER_FONT_SIZE.min(fit).max(8.0);
        let cell = ((font_size * advance).max(1.0), (font_size * line).max(1.0));
        let changed = o.size != (width, height) || o.font_size != font_size;
        o.size = (width, height);
        o.font_size = font_size;
        o.cell = cell;
        o.columns = ((f64::from(width) / cell.0).floor() as i64).max(1);
        o.rows = ((f64::from(height) / cell.1).floor() as i64).max(1);
        o.surface.configure(width, height);
        if changed {
            o.scene = Scene::new(width, height);
            o.background = Some(o.scene.add(IRect::new(0, 0, width, height), Paint::Rect { fill: BACKGROUND, radius: 0.0 }));
            o.rows_drawn.clear();
            o.glyphs.clear();
            self.saver_start_run();
            self.saver_paint();
        }
    }

    pub(super) fn saver_closed(&mut self) {
        self.saver.overlay = None;
    }

    pub(super) fn saver_frame_callback(&mut self) {
        let Some(o) = &mut self.saver.overlay else { return };
        let s = &mut o.surface;
        (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
    }

    /// Restarts ttfx for the canvas, effect and seed in force, or stops it.
    fn saver_start_run(&mut self) {
        let size = self.saver.overlay.as_ref().map(|o| (o.columns, o.rows));
        let Some(rt) = &self.runtime else { return };
        let Some((columns, rows)) = size.filter(|(c, r)| *c > 0 && *r > 0 && self.saver.active && self.saver_ttfx()) else {
            rt.service(service::stop);
            return;
        };
        self.saver.run += 1;
        let pinned = (self.saver.pinned >= 0).then_some(self.saver.pinned as usize);
        let opts = ttfx::Opts {
            banner_path: self.store.screensaver.banner.as_ref().map_or_else(service::bundled_banner, |(p, _)| p.clone()),
            columns: columns as u32,
            rows: rows as u32,
            effect: self.saver_effect(),
            frame_rate: if pinned.is_some() { 0 } else { self.store.config.f64("screensaver.frameRate").unwrap_or(120.0) as u32 },
            background: "#000000".into(),
            seed: self.saver.seed + self.saver.cycles as i64,
        };
        let run = self.saver.run;
        rt.service(move |ctx| service::start(ctx, run, opts, pinned));
    }

    /// A frame or an end from the run on screen; anything older is ignored.
    pub fn saver_changed(&mut self) {
        let run = self.saver.run;
        if let Some((r, _, _)) = &self.store.screensaver.frame
            && *r == run
            && self.saver.active
        {
            let (_, _, frame) = self.store.screensaver.frame.take().expect("frame");
            self.saver.grid = frame
                .iter()
                .map(|runs| {
                    runs.iter()
                        .flat_map(|r| {
                            let ink = if r.color.is_empty() { FOREGROUND } else { ink(&r.color) };
                            r.text.chars().enumerate().map(move |(i, ch)| ((r.col + i) as i64, ch, ink))
                        })
                        .collect()
                })
                .collect();
            self.saver_paint();
        }
        if let Some(end) = self.store.screensaver.ended.take().filter(|e| e.run == run) {
            if end.code != 0 {
                eprintln!("screensaver: ttfx exited {}, falling back to the builtin effects", end.code);
                self.store.screensaver.ttfx = Avail::Missing;
                self.saver.grid.clear();
                self.saver_start_run();
                self.saver_arm_tick();
                self.saver_paint();
            } else if self.saver.pinned >= 0 {
                self.saver.ttfx_frames = end.frames;
            } else if self.saver.active {
                self.saver_arm_hold();
            }
        }
    }

    fn saver_cancel_hold(&mut self) {
        if let (Some(t), Some(h)) = (self.saver.hold.take(), &self.handle) {
            h.remove(t);
        }
    }

    /// The shared hold between one converged effect and the next.
    fn saver_arm_hold(&mut self) {
        self.saver_cancel_hold();
        let Some(handle) = &self.handle else { return };
        let ms = (self.saver_hold_seconds() * 1000.0).max(1.0);
        let token = handle.insert_source(Timer::from_duration(Duration::from_secs_f64(ms / 1000.0)), |_, _, app: &mut App| {
            app.saver.hold = None;
            app.saver_reroll();
            TimeoutAction::Drop
        });
        self.saver.hold = token.ok();
    }

    fn saver_reroll(&mut self) {
        self.saver.previous = self.saver_effect();
        self.saver.seed = now_ms();
        self.saver.cycles += 1;
        self.saver.auto_frame = 0;
        self.saver.grid.clear();
        self.saver_start_run();
        self.saver_paint();
    }

    /// The built-in engine's own clock, running only while it animates.
    fn saver_arm_tick(&mut self) {
        let want = !self.saver_ttfx() && effect::auto_timer_should_run(self.saver.active, self.saver.pinned);
        match (want, self.saver.tick.is_some()) {
            (true, false) => {
                let Some(handle) = &self.handle else { return };
                let token = handle.insert_source(Timer::from_duration(FRAME_INTERVAL), |_, _, app: &mut App| {
                    if !(!app.saver_ttfx() && effect::auto_timer_should_run(app.saver.active, app.saver.pinned)) {
                        app.saver.tick = None;
                        return TimeoutAction::Drop;
                    }
                    app.saver.auto_frame += 1;
                    let reroll_at = app.saver_convergence() + effect::hold_frames(app.saver_hold_seconds(), FRAME_INTERVAL.as_millis() as f64);
                    if app.saver.auto_frame >= reroll_at {
                        app.saver_reroll();
                    } else {
                        app.saver_paint();
                    }
                    TimeoutAction::ToDuration(FRAME_INTERVAL)
                });
                self.saver.tick = token.ok();
            }
            (false, true) => {
                if let (Some(t), Some(h)) = (self.saver.tick.take(), &self.handle) {
                    h.remove(t);
                }
            }
            _ => {}
        }
    }

    fn saver_paint_builtin(&mut self) {
        let Some(o) = &self.saver.overlay else { return };
        let (columns, rows) = (o.columns, o.rows);
        let banner = self.saver_banner();
        let frame = effect::resolve_render_frame(self.saver.pinned, self.saver.auto_frame);
        let grid = effect::frame_state(&self.saver_effect(), frame, &banner);
        let primary = self.store.theme.theme.colors.get("primary");
        let col0 = (columns - banner.width as i64).div_euclid(2);
        let row0 = (rows - banner.height as i64).div_euclid(2);
        let mut out: Vec<Row> = vec![Vec::new(); rows.max(0) as usize];
        for (r, cells) in grid.iter().enumerate() {
            let Some(row) = usize::try_from(row0 + r as i64).ok().and_then(|i| out.get_mut(i)) else { continue };
            for (c, cell) in cells.iter().enumerate() {
                if cell.opacity > 0.0 {
                    row.push((col0 + c as i64, cell.ch, primary.with_alpha(primary.a * cell.opacity as f32)));
                }
            }
        }
        self.saver.grid = out;
        self.saver_draw();
    }

    fn saver_paint(&mut self) {
        if self.saver_ttfx() { self.saver_draw() } else { self.saver_paint_builtin() }
    }

    /// Each row is one node, rebuilt only when its cells changed. Block
    /// elements are the cell fraction their codepoint names, never a glyph
    /// (blocks.rs has why); edges snap to whole pixels so two blocks meeting
    /// leave no seam. Glyphs sit at their own column so nothing accumulates.
    fn saver_draw(&mut self) {
        let Some(o) = &mut self.saver.overlay else { return };
        if o.size.0 <= 0 {
            return;
        }
        let (cw, ch) = o.cell;
        let font = o.font_size as f32;
        let rows = o.rows.max(0) as usize;
        o.rows_drawn.resize(rows.max(o.rows_drawn.len()), None);
        let empty = Vec::new();
        for r in 0..o.rows_drawn.len() {
            let row = if r < rows { self.saver.grid.get(r).unwrap_or(&empty) } else { &empty };
            let hash = row_hash(row);
            if o.rows_drawn[r].as_ref().is_some_and(|(h, _)| *h == hash) {
                continue;
            }
            if let Some((_, id)) = o.rows_drawn[r].take() {
                o.scene.remove(id);
            }
            if row.is_empty() {
                continue;
            }
            let mut rects = Vec::new();
            let mut glyphs = Vec::new();
            let mut i = 0;
            while i < row.len() {
                let (col, c, ink) = row[i];
                if c == ' ' {
                    i += 1;
                    continue;
                }
                match blocks::rects_for(c as u32) {
                    None => {
                        let shaped = o.glyphs.entry(c).or_insert_with(|| {
                            let style = TextStyle { family: Family::Generic(GenericFamily::Monospace), size: font, weight: 400.0, tracking: 0.0 };
                            self.bar.kit.text.shape(&c.to_string(), style)
                        });
                        for g in &shaped.glyphs {
                            glyphs.push((g.path.clone(), col as f64 * cw + f64::from(g.x), r as f64 * ch + f64::from(g.y), ink));
                        }
                        i += 1;
                    }
                    Some(cell_rects) => {
                        let mut span = 1;
                        if blocks::is_full_cell(Some(&cell_rects)) {
                            while i + span < row.len() && row[i + span].1 == c && row[i + span].2 == ink && row[i + span].0 == col + span as i64 {
                                span += 1;
                            }
                        }
                        for rc in &cell_rects {
                            let x0 = ((col as f64 + rc.x) * cw).round();
                            let x1 = ((col as f64 + span as f64 - 1.0 + rc.x + rc.w) * cw).round();
                            let y0 = ((r as f64 + rc.y) * ch).round();
                            let y1 = ((r as f64 + rc.y + rc.h) * ch).round();
                            let fill = ink.with_alpha(ink.a * rc.alpha as f32);
                            rects.push((Rect::new(x0, y0, x0 + (x1 - x0).max(1.0), y0 + (y1 - y0).max(1.0)), fill));
                        }
                        i += span;
                    }
                }
            }
            let top = (r as f64 * ch).floor() as i32 - 2;
            let bounds = IRect::new(0, top, o.size.0, (ch.ceil() as i32) + 4);
            let id = o.scene.add(bounds, Paint::Cells { rects, glyphs });
            o.rows_drawn[r] = Some((hash, id));
        }
    }

    /// Fade, then unmap; the unmap is the action's end for its hot corner.
    pub(super) fn present_saver(&mut self, now: Instant) {
        let alpha = self.saver.opacity.value(now).clamp(0.0, 1.0);
        let fading = self.saver.opacity.running(now);
        let Some(mapped) = self.saver.overlay.as_ref().map(|o| o.surface.mapped) else { return };
        if !self.saver.active && !fading && mapped {
            self.saver.overlay = None;
            self.log("screensaver unmapped");
            self.hot_corner_action_ended("screensaver");
            return;
        }
        let Some(o) = &mut self.saver.overlay else { return };
        let multiplier = (alpha * f64::from(u32::MAX)).round() as u32;
        if o.multiplier != Some(multiplier) && !o.surface.frame_pending {
            o.fade.set_multiplier(multiplier);
            o.multiplier = Some(multiplier);
        }
        let qh = self.qh.clone();
        o.surface.present(&mut o.scene, fading || !self.saver.active, &qh);
    }

    pub(super) fn saver_pointer(&mut self, kind: SaverInput) {
        if !self.saver.active {
            return;
        }
        let Some(o) = &mut self.saver.overlay else { return };
        match kind {
            SaverInput::Enter(pointer, serial, at) => {
                pointer.set_cursor(serial, None, 0, 0);
                if o.baseline.is_none() {
                    o.baseline = Some(at);
                }
            }
            SaverInput::Motion(at) => match o.baseline {
                None => o.baseline = Some(at),
                Some(b) if b == at => {}
                Some(_) => self.saver_stop(),
            },
            SaverInput::Press | SaverInput::Key => self.saver_stop(),
        }
    }
}

pub enum SaverInput {
    Enter(wl_pointer::WlPointer, u32, (f64, f64)),
    Motion((f64, f64)),
    Press,
    Key,
}
