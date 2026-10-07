//! Hot corners (Surfaces/HotCorners/HotCorners.qml): one `hotCorners.size`
//! square of nothing per active corner per output, on the Top layer so the
//! screensaver and the lock plate cover it once fired. The arming rules are
//! fs-chrome's `arm`; this file feeds them real enters, leaves and the end
//! of each action.
//!
//! An action ends when its covering surface unmaps, and whether the cursor
//! is still in the corner then is asked of the compositor (`j/cursorpos`):
//! hover cannot say, since the covering surface held the pointer until that
//! moment.

use std::collections::HashMap;
use std::time::{Duration, SystemTime};

use calloop::RegistrationToken;
use calloop::timer::{TimeoutAction, Timer};
use fs_chrome::hot_corners::arm::{self, ArmState};
use fs_chrome::hot_corners::corners::{self, Action, Corner};
use smithay_client_toolkit::reexports::client::protocol::wl_surface::WlSurface;
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::{Anchor, KeyboardInteractivity, Layer};

use super::App;
use crate::services::hotcorners::Diff;
use crate::services::hyprland;
use crate::store;
use crate::surface::PixelSurface;

const NAMESPACE: &str = "formalshell:hotcorner";

struct Window {
    output: String,
    corner: Corner,
    action: Action,
    surface: PixelSurface,
    arm: ArmState,
    dwell: Option<RegistrationToken>,
}

#[derive(Default)]
pub struct HotCorners {
    windows: Vec<Window>,
    /// What the windows were built from: (output, corner, action, size).
    built: Vec<(String, Corner, String, i64)>,
    delay_ms: i64,
    size: i64,
    ended_at: HashMap<String, i64>,
}

fn now_ms() -> i64 {
    SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64)
}

fn anchor(corner: Corner) -> Anchor {
    let e = corners::edges(corner);
    let mut a = Anchor::empty();
    for (on, side) in [(e.top, Anchor::TOP), (e.bottom, Anchor::BOTTOM), (e.left, Anchor::LEFT), (e.right, Anchor::RIGHT)] {
        if on {
            a |= side;
        }
    }
    a
}

impl App {
    fn hotcorner_action_active(&self, action: &Action) -> bool {
        match action {
            Action::Screensaver => self.saver.active || self.saver_mapped(),
            _ => false,
        }
    }

    /// The corners the config, the outputs and fullscreen want, rebuilt
    /// whole when that set changes; each new window adopts what its action
    /// is doing right now.
    pub fn hotcorners_sync(&mut self) {
        let config = corners::resolve(self.store.config.get("hotCorners"));
        if !self.store.config.loaded {
            return;
        }
        let covered = &self.store.hyprland.compositor.fullscreen_outputs;
        let screens: Vec<String> = self
            .outputs
            .outputs()
            .filter_map(|o| self.outputs.info(&o).and_then(|i| i.name))
            .filter(|name| !covered.contains(name))
            .collect();
        let want: Vec<(String, Corner, String, i64)> = corners::windows(&config, &screens)
            .into_iter()
            .map(|w| (w.screen, w.corner, w.action.as_str().to_owned(), config.size))
            .collect();
        self.hotcorners.delay_ms = config.delay_ms;
        if want == self.hotcorners.built {
            return;
        }
        for w in &config.warnings {
            eprintln!("hotcorners: {w}");
        }
        for w in self.hotcorners.windows.drain(..) {
            if let (Some(t), Some(h)) = (w.dwell, &self.handle) {
                h.remove(t);
            }
        }
        let now = now_ms();
        let outputs: Vec<_> = self.outputs.outputs().collect();
        let mut windows = Vec::new();
        for w in corners::windows(&config, &screens) {
            let output = outputs.iter().find(|o| self.outputs.info(o).and_then(|i| i.name).as_deref() == Some(w.screen.as_str()));
            let surface = self.compositor.create_surface(&self.qh);
            let layer = self.layer_shell.create_layer_surface(&self.qh, surface, Layer::Top, Some(NAMESPACE), output);
            layer.set_anchor(anchor(w.corner));
            layer.set_size(config.size as u32, config.size as u32);
            layer.set_exclusive_zone(-1);
            layer.set_keyboard_interactivity(KeyboardInteractivity::None);
            layer.commit();
            let running = self.hotcorner_action_active(&w.action);
            let ended = self.hotcorners.ended_at.get(w.action.as_str()).copied().unwrap_or(0);
            windows.push(Window {
                output: w.screen,
                corner: w.corner,
                arm: arm::adopt(now, running, ended),
                action: w.action,
                surface: PixelSurface::new("hotcorner", layer, &self.pixels, &self.qh, self.started),
                dwell: None,
            });
        }
        self.hotcorners.windows = windows;
        self.hotcorners.built = want;
        self.hotcorners.size = config.size;
    }

    fn hotcorner_index(&self, surface: &WlSurface) -> Option<usize> {
        self.hotcorners.windows.iter().position(|w| w.surface.layer.wl_surface() == surface)
    }

    pub(super) fn hotcorner_owns(&self, surface: &WlSurface) -> bool {
        self.hotcorner_index(surface).is_some()
    }

    pub(super) fn hotcorner_configure(&mut self, surface: &WlSurface, width: i32, height: i32) {
        if let Some(i) = self.hotcorner_index(surface) {
            self.hotcorners.windows[i].surface.configure(width.max(1), height.max(1));
        }
    }

    pub(super) fn hotcorner_frame(&mut self, surface: &WlSurface) {
        if let Some(i) = self.hotcorner_index(surface) {
            let s = &mut self.hotcorners.windows[i].surface;
            (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
        }
    }

    pub(super) fn hotcorner_closed(&mut self, surface: &WlSurface) {
        if let Some(i) = self.hotcorner_index(surface) {
            let w = self.hotcorners.windows.remove(i);
            if let (Some(t), Some(h)) = (w.dwell, &self.handle) {
                h.remove(t);
            }
        }
    }

    pub(super) fn present_hotcorners(&mut self) {
        let qh = self.qh.clone();
        for w in &mut self.hotcorners.windows {
            w.surface.present(0.0, false, &qh);
        }
    }

    pub(super) fn hotcorner_enter(&mut self, surface: &WlSurface) {
        let Some(i) = self.hotcorner_index(surface) else { return };
        let now = now_ms();
        let w = &mut self.hotcorners.windows[i];
        let armed = arm::is_armed(w.arm, now);
        w.arm = arm::on_enter(w.arm, now);
        let action = w.action.clone();
        if armed && !self.hotcorner_action_active(&action) {
            self.hotcorner_dwell(i);
        }
    }

    pub(super) fn hotcorner_leave(&mut self, surface: &WlSurface) {
        let Some(i) = self.hotcorner_index(surface) else { return };
        let w = &mut self.hotcorners.windows[i];
        if let (Some(t), Some(h)) = (w.dwell.take(), &self.handle) {
            h.remove(t);
        }
        w.arm = arm::on_exit(w.arm);
    }

    /// A click on a 4px corner is deliberate: it fires outright.
    pub(super) fn hotcorner_press(&mut self, surface: &WlSurface) {
        if let Some(i) = self.hotcorner_index(surface) {
            self.hotcorner_fire(i);
        }
    }

    fn hotcorner_dwell(&mut self, i: usize) {
        let Some(handle) = &self.handle else { return };
        let delay = Duration::from_millis(self.hotcorners.delay_ms.max(0) as u64);
        let surface = self.hotcorners.windows[i].surface.layer.wl_surface().clone();
        let token = handle.insert_source(Timer::from_duration(delay), move |_, _, app: &mut App| {
            if let Some(i) = app.hotcorner_index(&surface) {
                app.hotcorners.windows[i].dwell = None;
                app.hotcorner_fire(i);
            }
            TimeoutAction::Drop
        });
        self.hotcorners.windows[i].dwell = token.ok();
    }

    fn hotcorner_fire(&mut self, i: usize) {
        let now = now_ms();
        let w = &mut self.hotcorners.windows[i];
        if let (Some(t), Some(h)) = (w.dwell.take(), &self.handle) {
            h.remove(t);
        }
        let reports = arm::reports_end(&w.action, false);
        w.arm = arm::on_fire(w.arm, now, reports);
        let action = w.action.clone();
        eprintln!("hotcorners: {} fired {}", w.corner.name(), action.as_str());
        if self.hotcorner_action_active(&action) {
            return;
        }
        if !reports {
            self.hotcorners.ended_at.insert(action.as_str().to_owned(), now);
        }
        match action {
            Action::Screensaver => self.saver_start(),
            Action::Lock => eprintln!("hotcorners: lock has no surface in this shell yet"),
            Action::Launcher(a) => eprintln!("hotcorners: launcher action {a} has no launcher in this shell yet"),
            Action::None => {}
        }
    }

    /// `action`'s covering surface is gone. The cursor is asked for where
    /// it is now, and each of the action's corners hears the end with it.
    pub fn hotcorner_action_ended(&mut self, action: &str) {
        let at = now_ms();
        self.hotcorners.ended_at.insert(action.to_owned(), at);
        let action = action.to_owned();
        let Some(rt) = &self.runtime else { return };
        rt.service(move |ctx| {
            let task_ctx = ctx.clone();
            ctx.spawn(async move {
                let cursor = hyprland::request("j/cursorpos").await.ok().and_then(|text| {
                    let v: serde_json::Value = serde_json::from_str(&text).ok()?;
                    Some((v.get("x")?.as_f64()?, v.get("y")?.as_f64()?))
                });
                task_ctx.publish(store::Diff::HotCorners(Diff::Ended(action, at, cursor)));
            });
        });
    }

    /// An unknown cursor counts as still in the corner: no leave is
    /// invented, so only a real one re-arms it.
    pub fn hotcorners_changed(&mut self) {
        let Some((action, at, cursor)) = self.store.hotcorners.ended.take() else { return };
        let size = self.hotcorners.size as f64;
        let boxes: HashMap<String, (f64, f64, f64, f64)> = self
            .outputs
            .outputs()
            .filter_map(|o| self.outputs.info(&o))
            .filter_map(|i| {
                let (x, y) = i.logical_position.unwrap_or((0, 0));
                let (w, h) = i.logical_size?;
                Some((i.name?, (f64::from(x), f64::from(y), f64::from(w), f64::from(h))))
            })
            .collect();
        for w in &mut self.hotcorners.windows {
            if w.action.as_str() != action {
                continue;
            }
            let inside = match (cursor, boxes.get(&w.output)) {
                (Some((cx, cy)), Some(&(x, y, ow, oh))) => {
                    let e = corners::edges(w.corner);
                    let left = if e.left { x } else { x + ow - size };
                    let top = if e.top { y } else { y + oh - size };
                    cx >= left && cx < left + size && cy >= top && cy < top + size
                }
                _ => true,
            };
            w.arm = arm::on_action_end(w.arm, at, inside);
            eprintln!("hotcorners: {} {action} ended, cursor {cursor:?} in corner {inside}", w.corner.name());
        }
    }
}
