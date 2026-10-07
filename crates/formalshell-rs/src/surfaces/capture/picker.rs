//! The region picker's selection model: the candidate
//! rectangles, the toolbar, the cursor and its moves, and the status the
//! `screenshot pickerStatus` verb reports. The surface and its drawing are
//! in `draw`; the freeze, the commit and the teardown are the owner's.

use std::collections::BTreeMap;

use serde_json::{Value, json};

use crate::scene::Bitmap;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct R {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

impl R {
    pub fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x && x < self.x + self.w && y >= self.y && y < self.y + self.h
    }

    pub fn json(&self) -> Value {
        json!({"x": js(self.x), "y": js(self.y), "width": js(self.w), "height": js(self.h)})
    }
}

/// A whole number serialises as JSON.stringify writes it, without `.0`.
fn js(v: f64) -> Value {
    if v.fract() == 0.0 && v.abs() < 9.0e15 { json!(v as i64) } else { json!(v) }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EntryKind {
    Output,
    Window,
    Drag,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub kind: EntryKind,
    pub label: String,
    pub sublabel: String,
    pub window_id: String,
    pub rect: Option<R>,
}

/// A screen: logical position and size.
#[derive(Clone, Debug, PartialEq)]
pub struct Screen {
    pub name: String,
    pub rect: R,
}

pub struct Tool {
    pub action: &'static str,
    pub mode: &'static str,
    pub icon: &'static str,
    pub label: &'static str,
}

pub const TOOLS: [Tool; 6] = [
    Tool { action: "shot", mode: "fullscreen", icon: "monitor", label: "Screen" },
    Tool { action: "shot", mode: "windows", icon: "app-window", label: "Window" },
    Tool { action: "shot", mode: "smart", icon: "crop", label: "Region" },
    Tool { action: "record", mode: "fullscreen", icon: "monitor", label: "Screen" },
    Tool { action: "record", mode: "windows", icon: "app-window", label: "Window" },
    Tool { action: "record", mode: "smart", icon: "crop", label: "Region" },
];

/// The candidate sets, rebuilt from the compositor's model on every read
/// so they never go stale.
#[derive(Clone, Debug, Default)]
pub struct Cands {
    pub outputs: Vec<Entry>,
    pub with_rect: Vec<Entry>,
    pub without_rect: Vec<Entry>,
    pub focused_output: String,
}

impl Cands {
    pub fn new(screens: &[Screen], windows: &[crate::services::hyprland::model::Window], focused_output: &str) -> Self {
        let outputs = screens
            .iter()
            .map(|s| Entry { kind: EntryKind::Output, label: s.name.clone(), sublabel: String::new(), window_id: String::new(), rect: Some(s.rect) })
            .collect();
        let mut seen = std::collections::HashSet::new();
        let (mut with_rect, mut without_rect) = (Vec::new(), Vec::new());
        for w in windows {
            let label = [&w.title, &w.app_id].into_iter().find(|s| !s.is_empty()).cloned().unwrap_or_else(|| "(untitled)".into());
            let rect = w.rect.map(|r| R { x: r.x as f64, y: r.y as f64, w: r.width as f64, h: r.height as f64 });
            let entry = Entry { kind: EntryKind::Window, label, sublabel: w.app_id.clone(), window_id: w.id.clone(), rect };
            match rect {
                None => without_rect.push(entry),
                Some(r) => {
                    if seen.insert(format!("{},{} {}x{}", r.x, r.y, r.w, r.h)) {
                        with_rect.push(entry);
                    }
                }
            }
        }
        with_rect.sort_by(|a, b| {
            let (a, b) = (a.rect.unwrap(), b.rect.unwrap());
            (a.y, a.x).partial_cmp(&(b.y, b.x)).unwrap_or(std::cmp::Ordering::Equal)
        });
        without_rect.sort_by(|a, b| a.label.cmp(&b.label));
        Self { outputs, with_rect, without_rect, focused_output: focused_output.to_owned() }
    }

    pub fn focused_output_rect(&self) -> Option<&Entry> {
        self.outputs.iter().find(|o| o.label == self.focused_output).or(self.outputs.first())
    }

    pub fn output_name_for(&self, r: R) -> String {
        let (cx, cy) = (r.x + r.w / 2.0, r.y + r.h / 2.0);
        self.outputs.iter().find(|o| o.rect.is_some_and(|o| o.contains(cx, cy))).map(|o| o.label.clone()).unwrap_or_default()
    }
}

pub struct Picker {
    pub mode: String,
    pub action: String,
    pub open: bool,
    /// Output name to its frozen frame.
    pub frames: BTreeMap<String, Option<Bitmap>>,
    pub pending_freezes: usize,
    pub last_freeze_error: String,
    pub capturing: bool,
    pub drag: Option<R>,
    pub hover: Option<Entry>,
    pub cursor: i32,
    /// The run a freeze, a settle or a teardown belongs to.
    pub generation: u64,
}

impl Default for Picker {
    fn default() -> Self {
        Self {
            mode: "smart".into(),
            action: "shot".into(),
            open: false,
            frames: BTreeMap::new(),
            pending_freezes: 0,
            last_freeze_error: String::new(),
            capturing: false,
            drag: None,
            hover: None,
            cursor: -1,
            generation: 0,
        }
    }
}

impl Picker {
    pub fn recording(&self) -> bool {
        self.action == "record"
    }

    pub fn tool_index(&self) -> i32 {
        let mode = if self.mode == "region" { "smart" } else { self.mode.as_str() };
        TOOLS.iter().position(|t| t.action == self.action && t.mode == mode).map_or(-1, |i| i as i32)
    }

    pub fn hint_rects(&self, c: &Cands) -> Vec<Entry> {
        match self.mode.as_str() {
            "region" => Vec::new(),
            "windows" => c.with_rect.clone(),
            "fullscreen" => c.outputs.clone(),
            _ => c.outputs.iter().chain(&c.with_rect).cloned().collect(),
        }
    }

    pub fn selectable(&self, c: &Cands) -> Vec<Entry> {
        match self.mode.as_str() {
            "region" => Vec::new(),
            "fullscreen" => c.outputs.clone(),
            "windows" => c.with_rect.clone(),
            _ => c.with_rect.iter().chain(&c.outputs).cloned().collect(),
        }
    }

    pub fn named_shown(&self, c: &Cands) -> bool {
        !c.without_rect.is_empty() && (self.mode == "windows" || self.mode == "smart")
    }

    pub fn current(&self, c: &Cands) -> Option<Entry> {
        if let Some(d) = self.drag {
            return Some(Entry { kind: EntryKind::Drag, label: String::new(), sublabel: String::new(), window_id: String::new(), rect: Some(d) });
        }
        let sel = self.selectable(c);
        if self.cursor >= 0 && (self.cursor as usize) < sel.len() {
            return Some(sel[self.cursor as usize].clone());
        }
        self.hover.clone()
    }

    /// The smallest hinted box under a point, the first on a tie.
    pub fn resolve_at(&self, c: &Cands, x: f64, y: f64) -> Option<Entry> {
        let mut best: Option<Entry> = None;
        let mut best_area = 0.0;
        for cand in self.hint_rects(c) {
            let Some(r) = cand.rect else { continue };
            if !r.contains(x, y) {
                continue;
            }
            let area = r.w * r.h;
            if best.is_none() || area < best_area {
                best_area = area;
                best = Some(cand);
            }
        }
        best
    }

    pub fn move_cursor(&mut self, c: &Cands, delta: i32) {
        let sel = self.selectable(c);
        let n = sel.len() as i32;
        if n == 0 {
            return;
        }
        if self.cursor < 0 {
            let at = self
                .hover
                .as_ref()
                .and_then(|h| sel.iter().position(|e| e.window_id == h.window_id && e.label == h.label))
                .map_or(-1, |i| i as i32);
            self.cursor = if at >= 0 { at } else if delta > 0 { 0 } else { n - 1 };
            return;
        }
        self.cursor = (self.cursor + delta + n) % n;
    }

    pub fn move_spatial(&mut self, c: &Cands, direction: &str) {
        let from = self.current(c);
        let Some(from_rect) = from.as_ref().and_then(|f| f.rect) else {
            self.move_cursor(c, if direction == "up" || direction == "left" { -1 } else { 1 });
            return;
        };
        let (ox, oy) = (from_rect.x + from_rect.w / 2.0, from_rect.y + from_rect.h / 2.0);
        let mut best = -1i32;
        let mut best_score = 0.0;
        for (i, entry) in self.selectable(c).iter().enumerate() {
            let Some(r) = entry.rect else { continue };
            if Some(entry) == from.as_ref() {
                continue;
            }
            let (cx, cy) = (r.x + r.w / 2.0, r.y + r.h / 2.0);
            let (primary, perp) = match direction {
                "left" => (ox - cx, cy - oy),
                "right" => (cx - ox, cy - oy),
                "up" => (oy - cy, cx - ox),
                _ => (cy - oy, cx - ox),
            };
            if primary <= 0.0 {
                continue;
            }
            let score = primary + perp.abs() * 2.0;
            if best < 0 || score < best_score {
                best = i as i32;
                best_score = score;
            }
        }
        if best >= 0 {
            self.cursor = best;
        }
    }

    /// Selects a toolbar cell; the caller has checked the picker is open.
    pub fn set_tool(&mut self, c: &Cands, index: i32) -> String {
        if !self.open {
            return "error: picker not open".into();
        }
        if index < 0 || index as usize >= TOOLS.len() {
            return format!("error: unknown tool {index}");
        }
        let tool = &TOOLS[index as usize];
        self.action = tool.action.into();
        self.mode = tool.mode.into();
        self.drag = None;
        self.hover = None;
        self.cursor = -1;
        if tool.mode == "fullscreen" {
            let focused = c.focused_output_rect().map(|o| o.label.clone());
            let at = focused.and_then(|f| self.selectable(c).iter().position(|e| e.label == f));
            self.cursor = at.map_or(0, |i| i as i32);
        } else if tool.mode == "windows" && !self.selectable(c).is_empty() {
            self.cursor = 0;
        }
        "ok".into()
    }

    pub fn status(&self, c: &Cands, runtime_dir: &str, screens: usize) -> Value {
        let current = self.current(c);
        json!({
            "open": self.open,
            "mode": self.mode,
            "action": self.action,
            "tool": self.tool_index(),
            "drawableWindows": c.with_rect.len(),
            "namedWindows": c.without_rect.len(),
            "cursor": self.cursor,
            "selection": current.as_ref().and_then(|e| e.rect).map_or(Value::Null, |r| r.json()),
            "selectionLabel": current.map(|e| e.label).unwrap_or_default(),
            "capturing": self.capturing,
            "pendingFreezes": self.pending_freezes,
            "frames": self.frames.values().filter(|f| f.is_some()).count(),
            "screens": screens,
            "runtimeDir": runtime_dir,
            "lastFreezeError": self.last_freeze_error,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::hyprland::model::{Rect, Window};

    fn win(id: &str, title: &str, rect: Option<(i64, i64, i64, i64)>) -> Window {
        Window {
            id: id.into(),
            title: title.into(),
            app_id: format!("app.{id}"),
            rect: rect.map(|(x, y, width, height)| Rect { x, y, width, height }),
            ..Default::default()
        }
    }

    fn cands() -> Cands {
        let screens = [Screen { name: "DP-1".into(), rect: R { x: 0.0, y: 0.0, w: 1920.0, h: 1080.0 } }];
        let windows = [
            win("b", "Right", Some((960, 40, 960, 1040))),
            win("a", "Left", Some((0, 40, 960, 1040))),
            win("dup", "Dup", Some((0, 40, 960, 1040))),
            win("c", "Tabbed", None),
        ];
        Cands::new(&screens, &windows, "DP-1")
    }

    #[test]
    fn windows_sort_in_reading_order_and_duplicates_collapse() {
        let c = cands();
        let labels: Vec<_> = c.with_rect.iter().map(|e| e.label.as_str()).collect();
        assert_eq!(labels, ["Left", "Right"]);
        assert_eq!(c.without_rect.len(), 1);
    }

    #[test]
    fn tab_walks_windows_then_outputs() {
        let c = cands();
        let mut p = Picker { open: true, ..Default::default() };
        p.move_cursor(&c, 1);
        assert_eq!(p.cursor, 0);
        p.move_cursor(&c, 1);
        p.move_cursor(&c, 1);
        assert_eq!(p.current(&c).unwrap().label, "DP-1");
        p.move_cursor(&c, 1);
        assert_eq!(p.cursor, 0);
    }

    #[test]
    fn the_smallest_box_wins_under_the_pointer() {
        let c = cands();
        let p = Picker::default();
        assert_eq!(p.resolve_at(&c, 100.0, 100.0).unwrap().label, "Left");
        assert_eq!(p.resolve_at(&c, 100.0, 10.0).unwrap().label, "DP-1");
    }

    #[test]
    fn screen_tool_preselects_the_focused_output() {
        let c = cands();
        let mut p = Picker { open: true, ..Default::default() };
        assert_eq!(p.set_tool(&c, 3), "ok");
        assert_eq!((p.action.as_str(), p.mode.as_str(), p.tool_index(), p.cursor), ("record", "fullscreen", 3, 0));
        assert_eq!(p.set_tool(&c, 7), "error: unknown tool 7");
    }

    #[test]
    fn right_takes_the_nearest_centre_ahead() {
        let c = cands();
        let mut p = Picker { open: true, cursor: 0, ..Default::default() };
        p.move_spatial(&c, "right");
        assert_eq!(p.current(&c).unwrap().label, "DP-1");
        p.move_spatial(&c, "right");
        assert_eq!(p.current(&c).unwrap().label, "Right");
    }
}
