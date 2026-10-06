//! Menu.qml: the launcher. One keyboard-exclusive overlay window over the
//! output, a card budding off the top line (Drawer.qml through `Card`) to
//! rest at 30% of the output's height, three bands split by full-bleed
//! rules: the header (back chip, search field, close), the body (the app
//! grid, the row list or the emoji grid, sections and the empty state) and
//! the footer (where you are, what Enter does). The scrim behind it is two
//! single-pixel surfaces the App owns.
//!
//! The model ([`Model`]) lives as long as the shell, as Menu.qml's instance
//! does: the level and the select request outlive a close. The window
//! ([`Shown`]) exists from an open until its exit has run.
//!
//! Rows come off the store's warm index (`services::menu`); a keystroke
//! re-ranks a few hundred nodes and builds only the rows inside the
//! viewport.

use std::time::Instant;

use fs_chrome::types::Edge;
use fs_menu::model::{self, Mode, SectionCtx};
use fs_menu::nav::{self, Dir, KeyAction, KeyCtx, KeyMode};
use fs_menu::node::{Kind as NodeKind, Node};
use fs_menu::toggles::{self, Snapshot};
use fs_theme::theme::Theme;
use serde_json::{Value, json};
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::KeyboardInteractivity;
use vello_cpu::kurbo::Rect;

use crate::motion::{Animated, Kind as Clock};
use crate::scene::{IRect, NodeId};
use crate::services::menu::{self as index, Ask};
use crate::services::{hyprland, state};
use crate::store::Store;
use crate::surface::Surface;
use crate::surfaces::bar::cell::{Kit, Painter};
use crate::surfaces::card::{Card, Ends};
use crate::ui::{self, El, Ink, Size, Type, Ui, Weight, w};

/// Which view draws the level (`menu status`'s `view`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum View {
    Rows,
    Emoji,
    AppGrid,
}

impl View {
    fn name(self) -> &'static str {
        match self {
            View::Rows => "rows",
            View::Emoji => "emoji",
            View::AppGrid => "appGrid",
        }
    }
}

/// One drawn row or cell's place in the body, in body coordinates.
#[derive(Clone, Copy, Debug, Default)]
struct Slot {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    /// The heading band above a row, part of its height.
    band: f64,
}

/// What the body lays out, recomputed on every resolve.
#[derive(Default)]
struct Layout {
    slots: Vec<Slot>,
    /// The headings: text and the band's top, in body coordinates.
    headings: Vec<(String, f64, f64)>,
    content_h: f64,
    columns: usize,
    cell_w: f64,
    cell_h: f64,
}

pub struct Model {
    pub open: bool,
    pub mode: Mode,
    pub level: Option<String>,
    pub query: String,
    select_prompt: String,
    select_options: Vec<String>,
    select_token: String,
    input_secret: bool,
    // What `resolve` committed.
    pub rows: Vec<Node>,
    sections: Vec<String>,
    pub view: View,
    pub app_count: usize,
    empty: Option<Node>,
    searching: bool,
    key: String,
    // The cursor (M72 T1).
    pub cursor: usize,
    pub cursor_id: String,
    placed: bool,
    want: String,
    pub from_keys: bool,
    travels: bool,
    confirm: String,
    pub scroll: f64,
    layout: Layout,
    body_h: f64,
    /// The rows changed since the window last drew.
    pub dirty: bool,
}

impl Default for Model {
    fn default() -> Self {
        Self {
            open: false,
            mode: Mode::Menu,
            level: None,
            query: String::new(),
            select_prompt: String::new(),
            select_options: Vec::new(),
            select_token: String::new(),
            input_secret: false,
            rows: Vec::new(),
            sections: Vec::new(),
            view: View::AppGrid,
            app_count: 0,
            empty: None,
            searching: false,
            key: String::new(),
            cursor: 0,
            cursor_id: String::new(),
            placed: false,
            want: String::new(),
            from_keys: true,
            travels: false,
            confirm: String::new(),
            scroll: 0.0,
            layout: Layout::default(),
            body_h: 0.0,
            dirty: true,
        }
    }
}

/// What an activation asks of the shell outside the launcher.
pub enum Out {
    None,
    Close,
    /// An in-process `@ipc:` action the App dispatches.
    Internal(String),
}

pub fn snapshot(store: &Store) -> Snapshot {
    toggles::snapshot(Some(&json!({
        "theme.dark": store.state.data.mode == "dark",
        "caffeinate.active": store.caffeinate.active,
        "notifications.dnd": store.state.data.dnd,
    })))
}

impl Model {
    fn key_mode(&self) -> KeyMode {
        match self.mode {
            Mode::Menu => KeyMode::Menu,
            Mode::Select => KeyMode::Select,
            Mode::Input => KeyMode::Input,
        }
    }

    pub fn placeholder(&self, store: &Store) -> String {
        if self.mode != Mode::Menu {
            return self.select_prompt.clone();
        }
        match self.level.as_deref().and_then(|l| store.menu.nodes().get(l)) {
            Some(node) => model::prompt_for(Some(node)),
            None => "Type a command or search...".into(),
        }
    }

    pub fn section_names(&self) -> Vec<String> {
        model::section_names(&self.sections)
    }

    pub fn columns(&self) -> usize {
        match self.view {
            View::Rows => 1,
            _ => self.layout.columns.max(1),
        }
    }

    fn level_node<'a>(&self, store: &'a Store) -> Option<&'a Node> {
        if self.mode != Mode::Menu {
            return None;
        }
        self.level.as_deref().and_then(|l| store.menu.nodes().get(l))
    }

    pub fn level_name(&self, store: &Store) -> String {
        match self.mode {
            Mode::Select => "Select".into(),
            Mode::Input => "Input".into(),
            Mode::Menu => self.level_node(store).map_or_else(|| "Launcher".into(), |n| n.label.clone()),
        }
    }

    fn level_icon(&self, store: &Store) -> String {
        if self.mode != Mode::Menu {
            return "list".into();
        }
        match self.level_node(store) {
            Some(n) => {
                let i = fs_menu::icons::icon_for(Some(n));
                if i.is_empty() { fs_menu::icons::fallback_for(Some(n)).into() } else { i.into() }
            }
            None => "search".into(),
        }
    }

    /// Menu.qml's `_resolve` and `_levelRows` over the warm index.
    fn resolve_rows(&self, store: &Store) -> (View, Vec<Node>, usize, Option<Node>, bool, String) {
        let menu = self.mode == Mode::Menu;
        let q = self.query.as_str();
        let level = self.level.as_deref();
        let nodes = store.menu.nodes();
        let cond = &store.menu.cond;
        let emoji_q = if menu { fs_menu::providers::emoji_trigger_query(q) } else { None };
        let keys_q = if menu { fs_menu::keybinds::trigger_query(q) } else { None };
        let emoji = menu && (level == Some("emoji") || emoji_q.is_some());
        let route_rows = matches!(level, Some("nix" | "keybinds" | "calc" | "radio.search"));
        let grid_wanted = store.config.bool("menu.appGrid").unwrap_or(true);
        let view = if emoji {
            View::Emoji
        } else if menu && grid_wanted && !route_rows {
            View::AppGrid
        } else {
            View::Rows
        };
        let mut rows: Vec<Node> = match self.mode {
            Mode::Select => {
                let ql = q.to_lowercase();
                self.select_options
                    .iter()
                    .enumerate()
                    .map(|(i, o)| Node::new(format!("select.{i}"), o.clone(), NodeKind::Other("option".into())))
                    .filter(|n| ql.is_empty() || n.label.to_lowercase().contains(&ql))
                    .collect()
            }
            Mode::Input => Vec::new(),
            Mode::Menu if emoji => {
                let uses: Vec<fs_menu::frecency::Record> = serde_json::from_value(store.state.data.emoji_uses.clone()).unwrap_or_default();
                let paste = store.config.bool("clipboard.paste").unwrap_or(true);
                let eq = emoji_q.unwrap_or(q);
                store.menu.emoji.as_ref().map_or_else(Vec::new, |e| e.rows(eq, paste, &uses, None))
            }
            Mode::Menu if level == Some("keybinds") || keys_q.is_some() => {
                let reply = store.menu.binds.as_ref().map(|r| r.as_ref().map(|t| &**t).map_err(|_| ()));
                fs_menu::keybinds::rows_for(reply, keys_q.unwrap_or(q))
            }
            Mode::Menu if q.is_empty() => {
                let gated = level.and_then(|l| nodes.get(l)).is_some_and(|n| !model::is_when_visible(n, cond));
                if gated {
                    vec![model::gated_note_row(&nodes[level.unwrap_or_default()])]
                } else {
                    model::visible_children(nodes, level, cond).into_iter().cloned().collect()
                }
            }
            Mode::Menu => {
                let calc = fs_menu::calc::result_node(q);
                if level == Some("calc") {
                    calc.into_iter().collect()
                } else {
                    let ranked = fs_menu::search::rank(nodes, q, cond, level).into_iter().cloned();
                    calc.into_iter().chain(ranked).collect()
                }
            }
        };
        let mut empty = None;
        let live: Vec<Node> = rows.iter().filter(|r| !(r.kind == NodeKind::Note && r.dim == Some(true))).cloned().collect();
        if live.len() < rows.len() {
            if live.is_empty() {
                empty = rows.first().cloned();
            }
            rows = live;
        }
        if view == View::AppGrid && level.is_none() && q.is_empty() {
            let apps: Vec<Node> = model::visible_children(nodes, Some("apps"), cond)
                .into_iter()
                .filter(|r| r.kind == NodeKind::App)
                .take(fs_theme::tokens::LAUNCHER.root_apps as usize)
                .cloned()
                .collect();
            rows = apps.into_iter().chain(rows).collect();
        }
        let mut app_count = 0;
        if view == View::AppGrid {
            let parts = fs_menu::appgrid::partition(rows);
            rows = parts.rows;
            app_count = parts.app_count;
        }
        let searching = menu && !q.is_empty() && !emoji && !route_rows && keys_q.is_none();
        let key = format!("{:?}\u{1}{}\u{1}{}", self.mode, level.unwrap_or(""), q);
        (view, rows, app_count, empty, searching, key)
    }

    /// `_syncRows`: commits the rows, their headings and the cursor.
    pub fn resolve(&mut self, store: &Store, theme: &Theme, kit: &mut Kit) {
        let (view, rows, app_count, empty, searching, key) = self.resolve_rows(store);
        let fresh = key != self.key;
        let level_label = self.level.as_deref().and_then(|l| store.menu.nodes().get(l)).map(|n| n.label.clone()).unwrap_or_default();
        let sections = model::sections_for(
            &rows,
            &SectionCtx {
                mode: Some(self.mode),
                grid: view == View::Emoji,
                cells: app_count,
                searching,
                level: self.level.as_deref(),
                level_label: &level_label,
                nodes: Some(store.menu.nodes()),
            },
        );
        let view_changed = view != self.view;
        self.rows = rows;
        self.sections = sections;
        self.view = view;
        self.app_count = app_count;
        self.empty = empty;
        self.searching = searching;
        if fresh {
            self.placed = false;
            self.want.clear();
        }
        let ids: Vec<&str> = self.rows.iter().map(|r| r.id.as_str()).collect();
        let index = nav::rederive(&self.want, self.cursor as i64, &ids, fresh, self.placed);
        self.key = key;
        self.layout(theme, kit);
        self.place(index, false);
        if fresh || view_changed {
            self.scroll = 0.0;
            self.follow();
        }
        self.dirty = true;
    }

    fn place(&mut self, index: usize, travels: bool) {
        let valid = index < self.rows.len();
        self.travels = travels;
        self.cursor = if valid { index } else { 0 };
        self.cursor_id = if valid { self.rows[index].id.clone() } else { String::new() };
    }

    /// The body's slots: AppGridView.qml's cells and tail, RowListView.qml's
    /// rows, EmojiGridView.qml's tiles.
    fn layout(&mut self, theme: &Theme, kit: &mut Kit) {
        let s = &theme.space;
        let width = theme.space.popup_width_menu - s.panel_padding * 2.0;
        let inset = s.lg;
        let gutter = s.sm;
        let heading_h = ui::measure(&w::section_label(s, "Ag", None, true), width, theme, kit).1;
        let mut out = Layout::default();
        let mut y = inset;
        let band_of = |section: &str, first: bool| -> f64 {
            if section.is_empty() { 0.0 } else { (if first { 0.0 } else { s.section_gap }) + heading_h + s.row_gap }
        };
        let heading = |i: usize, secs: &[String]| -> String {
            let band = secs.get(i).cloned().unwrap_or_default();
            let prev = if i > 0 { secs.get(i - 1).cloned().unwrap_or_default() } else { String::new() };
            if band == prev { String::new() } else { band }
        };
        match self.view {
            View::AppGrid | View::Emoji => {
                let (cells, min_cell) = if self.view == View::AppGrid {
                    (self.app_count, s.control_height * 4.0)
                } else {
                    (self.rows.len(), 0.0)
                };
                let columns = if self.view == View::Emoji {
                    fs_theme::tokens::LAUNCHER.emoji_columns as usize
                } else {
                    fs_menu::appgrid::columns_for(width, min_cell)
                };
                let cell_w = width / columns.max(1) as f64;
                let name_h = ui::measure(&w::label("Ag"), width, theme, kit).1;
                let cell_h = if self.view == View::AppGrid {
                    s.control_height * 2.0 + s.row_gap + name_h + s.control_padding_y * 2.0 + gutter * 2.0
                } else {
                    cell_w
                };
                let heading_text = if self.view == View::AppGrid && cells > 0 { self.sections.first().cloned().unwrap_or_default() } else { String::new() };
                if !heading_text.is_empty() {
                    out.headings.push((heading_text, y, gutter));
                    y += heading_h + s.row_gap;
                }
                for i in 0..cells {
                    let (r, c) = (i / columns.max(1), i % columns.max(1));
                    out.slots.push(Slot { x: c as f64 * cell_w, y: y + r as f64 * cell_h, w: cell_w, h: cell_h, band: 0.0 });
                }
                y += cells.div_ceil(columns.max(1)) as f64 * cell_h;
                out.columns = columns;
                out.cell_w = cell_w;
                out.cell_h = cell_h;
                for i in cells..self.rows.len() {
                    let h_text = heading(i, &self.sections);
                    let band = band_of(&h_text, i == 0);
                    if !h_text.is_empty() {
                        out.headings.push((h_text, y + band - heading_h - s.row_gap, 0.0));
                    }
                    let row_h = row_height(&self.rows[i], theme, kit);
                    out.slots.push(Slot { x: gutter, y, w: width - gutter * 2.0, h: band + row_h, band });
                    y += band + row_h;
                }
            }
            View::Rows => {
                out.columns = 1;
                let side = s.sm;
                for i in 0..self.rows.len() {
                    let h_text = heading(i, &self.sections);
                    let band = band_of(&h_text, i == 0);
                    if !h_text.is_empty() {
                        out.headings.push((h_text, y + band - heading_h - s.row_gap, 0.0));
                    }
                    let row_h = row_height(&self.rows[i], theme, kit);
                    out.slots.push(Slot { x: side, y, w: width - side * 2.0, h: band + row_h, band });
                    y += band + row_h;
                }
            }
        }
        out.content_h = y + inset;
        self.layout = out;
    }

    /// cursor.js `follow`: the smallest scroll that shows the cursor's slot.
    fn follow(&mut self) {
        let Some(slot) = self.layout.slots.get(self.cursor) else {
            self.scroll = 0.0;
            return;
        };
        let (top, h) = (slot.y + slot.band, slot.h - slot.band);
        let view = self.body_h;
        let mut next = self.scroll;
        // The grid's own heading rides with its first row.
        let top = if self.view != View::Rows && self.cursor < self.cells() && self.cursor < self.layout.columns { 0.0 } else { top };
        if top < next {
            next = top;
        } else if top + h > next + view {
            next = top + h - view;
        }
        let max = (self.layout.content_h - view).max(0.0);
        self.scroll = next.clamp(0.0, max);
    }

    fn cells(&self) -> usize {
        match self.view {
            View::AppGrid => self.app_count,
            View::Emoji => self.rows.len(),
            View::Rows => 0,
        }
    }

    /// `_moveCursor`.
    pub fn move_cursor(&mut self, dir: Dir) {
        let n = self.rows.len();
        if n == 0 {
            return;
        }
        let page = self.page_step();
        let next = nav::step(self.cursor, dir, n, self.cells(), self.columns(), page);
        self.place(next.index, next.travels);
        self.placed = true;
        self.want = self.cursor_id.clone();
        self.confirm.clear();
        self.from_keys = true;
        self.follow();
        self.dirty = true;
    }

    fn page_step(&self) -> usize {
        let h = self.body_h;
        if self.view != View::Rows && self.cursor < self.cells() {
            return ((h / self.layout.cell_h.max(1.0)).floor() as usize).max(1) * self.columns();
        }
        1usize.max((h / 32.0).floor() as usize)
    }

    /// A wheel notch: the view scrolls a row (a grid row of cells) and the
    /// cursor stays where it is.
    pub fn wheel(&mut self, notches: i32) {
        let step = if self.view == View::Rows { 32.0 } else { self.layout.cell_h.max(1.0) };
        let max = (self.layout.content_h - self.body_h).max(0.0);
        let next = (self.scroll + notches as f64 * step).clamp(0.0, max);
        if next != self.scroll {
            self.scroll = next;
            self.travels = true;
            self.dirty = true;
        }
    }

    /// The pointer named a row.
    pub fn set_cursor(&mut self, index: usize) {
        if index == self.cursor {
            return;
        }
        self.place(index, false);
        self.placed = true;
        self.want = self.cursor_id.clone();
        self.confirm.clear();
        self.from_keys = false;
        self.dirty = true;
    }

    pub fn view_cursor(&self) -> Value {
        let k = self.view.name();
        let Some(slot) = self.layout.slots.get(self.cursor).filter(|_| self.cursor < self.rows.len()) else {
            return json!({"view": k, "index": -1, "id": ""});
        };
        let top = (slot.y + slot.band - self.scroll).round() as i64;
        let bottom = (slot.y + slot.h - self.scroll).round() as i64;
        json!({
            "view": k, "index": self.cursor, "id": self.rows[self.cursor].id,
            "top": top, "bottom": bottom, "viewport": self.body_h.round() as i64,
        })
    }

    pub fn status(&self, store: &Store) -> Value {
        let checked: Vec<&str> = {
            let snap = snapshot(store);
            self.rows
                .iter()
                .filter(|n| toggles::checked_for(Some(n), Some(&snap), Some(&store.menu.checked)))
                .map(|n| n.id.as_str())
                .collect()
        };
        let cells: Vec<&str> = match self.view {
            View::AppGrid => self.rows[..self.app_count].iter().map(|r| r.id.as_str()).collect(),
            _ => self.rows.iter().map(|r| r.id.as_str()).collect(),
        };
        let drawn: Vec<Value> = match self.view {
            View::AppGrid => self.rows[..self.app_count].iter().map(|r| json!({"id": r.id, "label": r.label})).collect(),
            View::Rows => self.rows.iter().map(|r| json!({"id": r.id, "label": r.label})).collect(),
            View::Emoji => Vec::new(),
        };
        json!({
            "isOpen": self.open,
            "level": self.level,
            "scrollTop": self.scroll.round() as i64,
            "placeholder": self.placeholder(store),
            "sections": self.section_names(),
            "view": self.view.name(),
            "columns": self.columns(),
            "cursor": self.cursor,
            "cursorId": self.cursor_id,
            "empty": self.empty.as_ref().map_or("", |n| n.id.as_str()),
            "mode": match self.mode { Mode::Menu => "menu", Mode::Select => "select", Mode::Input => "input" },
            "viewCursor": self.view_cursor(),
            "rows": self.rows.len(),
            "cells": cells,
            "ids": self.rows.iter().map(|r| r.id.as_str()).collect::<Vec<_>>(),
            "checked": checked,
            "drawn": drawn,
        })
    }

    /// `_resolveRoute`.
    fn resolve_route(store: &Store, route: &str) -> Option<String> {
        let nodes = store.menu.nodes();
        if nodes.contains_key(route) {
            return Some(route.to_owned());
        }
        nodes.values().find(|n| n.aliases.iter().any(|a| a == route)).map(|n| n.id.clone())
    }

    /// `open(route)`: a fresh session on `route`'s level, or a `:`-led
    /// prefill at the root.
    pub fn open(&mut self, store: &Store, route: Option<&str>) {
        self.abandon_select();
        self.ask_fresh(store);
        let route = route.filter(|r| !r.is_empty());
        let prefill = route.filter(|r| r.starts_with(':')).unwrap_or("").to_owned();
        let mut target = None;
        if prefill.is_empty()
            && let Some(id) = route.and_then(|r| Self::resolve_route(store, r))
            && let Some(node) = store.menu.nodes().get(&id)
        {
            target = match node.kind {
                NodeKind::Submenu | NodeKind::Provider => Some(node.id.clone()),
                NodeKind::Link => Some(node.target.clone().filter(|t| store.menu.nodes().contains_key(t)).unwrap_or(node.id.clone())),
                _ => None,
            };
        }
        self.enter_level(store, target);
        self.query = prefill;
        self.open = true;
        self.key.clear();
    }

    /// What every open asks the service for: the conditions, the binds and
    /// the apps, each landing as its own diff.
    fn ask_fresh(&self, store: &Store) {
        let conds: Vec<(String, String, bool)> = store
            .menu
            .nodes()
            .values()
            .flat_map(|n| {
                let when = n.when.clone().filter(|c| !toggles::is_state_condition(c)).map(|c| (n.id.clone(), c, true));
                let checked = n.checked.clone().filter(|c| !toggles::is_state_condition(c)).map(|c| (n.id.clone(), c, false));
                when.into_iter().chain(checked)
            })
            .collect();
        index::ask(Ask::Conds(conds));
        index::ask(Ask::Binds);
        index::ask(Ask::Apps(launches(store)));
    }

    pub fn open_select(&mut self, prompt: &str, options: Vec<String>, token: &str) {
        self.begin_selection();
        self.mode = Mode::Select;
        self.select_prompt = prompt.into();
        self.select_options = options;
        self.select_token = token.into();
        self.confirm.clear();
        self.query.clear();
        self.open = true;
        self.key.clear();
    }

    pub fn open_input(&mut self, prompt: &str, token: &str, secret: bool) {
        self.begin_selection();
        self.mode = Mode::Input;
        self.input_secret = secret;
        self.select_prompt = prompt.into();
        self.select_options.clear();
        self.select_token = token.into();
        self.confirm.clear();
        self.query.clear();
        self.open = true;
        self.key.clear();
    }

    pub fn close(&mut self) {
        self.abandon_select();
        self.open = false;
        self.confirm.clear();
    }

    fn write_selection(&mut self, payload: Value) {
        let token = payload.get("token").cloned().unwrap_or(Value::Null);
        let filed = if self.input_secret { json!({"token": token, "cancelled": true, "secret": true}) } else { payload };
        let path = selection_path();
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(&path, filed.to_string());
        if self.input_secret {
            self.query.clear();
            self.input_secret = false;
        }
    }

    fn abandon_select(&mut self) {
        if self.mode != Mode::Menu {
            let token = self.select_token.clone();
            self.write_selection(json!({"token": token, "cancelled": true}));
            self.mode = Mode::Menu;
        }
    }

    fn begin_selection(&mut self) {
        let pending = self.mode != Mode::Menu;
        self.abandon_select();
        if !pending {
            let _ = std::fs::remove_file(selection_path());
        }
    }

    fn complete_select(&mut self, value: &str) {
        let token = self.select_token.clone();
        self.write_selection(json!({"token": token, "value": value}));
        self.mode = Mode::Menu;
        self.close();
    }

    fn enter_level(&mut self, store: &Store, id: Option<String>) {
        self.level = id;
        self.confirm.clear();
        self.from_keys = true;
        self.query.clear();
        if self.level.as_deref() == Some("emoji") && store.menu.emoji.is_none() {
            index::ask(Ask::Emoji);
        }
    }

    fn pop(&mut self, store: &Store) -> Out {
        let Some(level) = self.level.clone() else { return Out::Close };
        let parent = store.menu.nodes().get(&level).and_then(|n| n.parent_id.clone());
        self.enter_level(store, parent);
        Out::None
    }

    pub fn set_query(&mut self, store: &Store, text: &str) {
        self.query = text.into();
        self.confirm.clear();
        if self.mode == Mode::Menu && fs_menu::providers::emoji_trigger_query(text).is_some() && store.menu.emoji.is_none() {
            index::ask(Ask::Emoji);
        }
    }

    /// `_activateRow`.
    pub fn activate(&mut self, store: &Store, index: usize) -> Out {
        let Some(node) = self.rows.get(index).cloned() else { return Out::None };
        match node.kind {
            NodeKind::Other(ref k) if k == "option" => {
                self.complete_select(&node.label);
                Out::Close
            }
            NodeKind::Action => {
                if node.confirm == Some(true) && self.confirm != node.id {
                    self.confirm = node.id.clone();
                    self.dirty = true;
                    return Out::None;
                }
                let out = run_action(node.action.as_deref().unwrap_or(""));
                if node.id.starts_with("emoji.") {
                    let uses: Vec<fs_menu::frecency::Record> = serde_json::from_value(store.state.data.emoji_uses.clone()).unwrap_or_default();
                    let next = fs_menu::frecency::record(&uses, &node.id, now_ms(), None);
                    state::set(vec![state::Field::EmojiUses(serde_json::to_value(next).unwrap_or_default())]);
                }
                if node.keep_open == Some(true) {
                    self.confirm.clear();
                    return out;
                }
                match out {
                    Out::Internal(name) => {
                        self.close();
                        Out::Internal(name)
                    }
                    _ => {
                        self.close();
                        Out::Close
                    }
                }
            }
            NodeKind::App => {
                let Some(entry) = node.entry.clone() else { return Out::None };
                let windows: Vec<fs_menu::appmatch::Window> = store
                    .hyprland
                    .compositor
                    .windows
                    .iter()
                    .map(|w| fs_menu::appmatch::Window { id: w.id.clone(), app_id: w.app_id.clone(), ..Default::default() })
                    .collect();
                let matches = fs_menu::appmatch::match_windows(Some(&entry), &windows);
                let target = fs_menu::appmatch::next_window(&matches, &store.hyprland.compositor.focused_window_id);
                if !target.is_empty() {
                    hyprland::focus_window(&target);
                } else if let Some(argv) = index::launch_argv(&store.menu, &entry.id) {
                    hyprland::spawn(&argv);
                }
                record_launch(store, &entry.id);
                self.close();
                Out::Close
            }
            NodeKind::Submenu | NodeKind::Provider => {
                self.enter_level(store, Some(node.id.clone()));
                Out::None
            }
            NodeKind::Link => {
                let to = node.target.clone().filter(|t| store.menu.nodes().contains_key(t)).unwrap_or(node.id.clone());
                self.enter_level(store, Some(to));
                Out::None
            }
            _ => Out::None,
        }
    }

    /// `_activateRowAlternate`: a row's own alternate, else Enter.
    pub fn activate_alternate(&mut self, store: &Store, index: usize) -> Out {
        let Some(node) = self.rows.get(index).cloned() else { return Out::None };
        if let Some(alt) = node.alternate.as_deref() {
            let out = run_action(alt);
            if node.keep_open != Some(true) {
                self.close();
                return if matches!(out, Out::Internal(_)) { out } else { Out::Close };
            }
            return out;
        }
        self.activate(store, index)
    }

    /// One key, through Menu/nav.js's `keyAction`, or into the field.
    pub fn key(&mut self, store: &Store, key: nav::Key, mods: nav::Modifiers, repeat: bool, text: Option<&str>) -> Out {
        let ctx = KeyCtx {
            mode: self.key_mode(),
            query: !self.query.is_empty(),
            grid: self.view != View::Rows,
            app_view: false,
            scrollable: false,
            variants: false,
        };
        let action = nav::key_action(key, mods, repeat, &ctx);
        let out = match action {
            KeyAction::Pass => {
                match (key, text) {
                    (nav::Key::Backspace, _) => {
                        let mut q = self.query.clone();
                        if mods.ctrl {
                            let t = q.trim_end().len();
                            q.truncate(q[..t].rfind(char::is_whitespace).map_or(0, |i| i + 1));
                        } else {
                            q.pop();
                        }
                        self.set_query(store, &q);
                    }
                    (_, Some(t)) if !mods.ctrl && !mods.alt => {
                        let q = format!("{}{t}", self.query);
                        self.set_query(store, &q);
                    }
                    _ => return Out::None,
                }
                Out::None
            }
            KeyAction::Up => self.dir(Dir::Up),
            KeyAction::Down => self.dir(Dir::Down),
            KeyAction::Left => self.dir(Dir::Left),
            KeyAction::Right => self.dir(Dir::Right),
            KeyAction::PageUp => self.dir(Dir::PageUp),
            KeyAction::PageDown => self.dir(Dir::PageDown),
            KeyAction::Home => self.dir(Dir::Home),
            KeyAction::End => self.dir(Dir::End),
            KeyAction::Activate => self.activate(store, self.cursor),
            KeyAction::ActivateAlternate => self.activate_alternate(store, self.cursor),
            KeyAction::Submit => {
                let q = self.query.clone();
                self.complete_select(&q);
                Out::Close
            }
            KeyAction::Clear => {
                self.set_query(store, "");
                Out::None
            }
            KeyAction::Pop => self.pop(store),
            KeyAction::Close => {
                self.close();
                Out::Close
            }
            _ => Out::None,
        };
        self.dirty = true;
        out
    }

    fn dir(&mut self, d: Dir) -> Out {
        self.move_cursor(d);
        Out::None
    }

    /// `debug query`: the live tree ranked, whether or not the window is up.
    pub fn query(&self, store: &Store, q: &str) -> Value {
        if let Some(eq) = fs_menu::providers::emoji_trigger_query(q) {
            let Some(index) = &store.menu.emoji else {
                index::ask(Ask::Emoji);
                return json!([]);
            };
            return Value::Array(index.rows(eq, true, &[], None).iter().map(|n| json!({"id": n.id, "label": n.label, "icon": n.icon, "kind": n.kind.as_str()})).collect());
        }
        if let Some(kq) = fs_menu::keybinds::trigger_query(q) {
            index::ask(Ask::Binds);
            let reply = store.menu.binds.as_ref().map(|r| r.as_ref().map(|t| &**t).map_err(|_| ()));
            return Value::Array(
                fs_menu::keybinds::rows_for(reply, kq)
                    .iter()
                    .map(|n| json!({"id": n.id, "label": n.label, "desc": n.desc.clone().unwrap_or_default(), "kind": n.kind.as_str()}))
                    .collect(),
            );
        }
        let nodes = store.menu.nodes();
        let snap = snapshot(store);
        let mut rows: Vec<Value> = fs_menu::search::rank(nodes, q, &store.menu.cond, self.level.as_deref())
            .into_iter()
            .map(|n| {
                json!({
                    "id": n.id, "label": n.label, "kind": n.kind.as_str(), "iconSource": n.icon_source,
                    "checked": toggles::checked_for(Some(n), Some(&snap), Some(&store.menu.checked)),
                    "section": model::search_section_of(Some(nodes), n),
                })
            })
            .collect();
        if let Some(calc) = fs_menu::calc::result_node(q) {
            rows.insert(0, json!({"id": calc.id, "label": calc.label, "kind": calc.kind.as_str(), "section": model::search_section_of(Some(nodes), &calc)}));
        }
        Value::Array(rows)
    }
}

fn now_ms() -> f64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0.0, |d| d.as_millis() as f64)
}

pub fn launches(store: &Store) -> Vec<fs_menu::frecency::Record> {
    serde_json::from_value(store.state.data.app_launches.clone()).unwrap_or_default()
}

fn record_launch(store: &Store, id: &str) {
    let next = fs_menu::frecency::record(&launches(store), id, now_ms(), None);
    state::set(vec![state::Field::AppLaunches(serde_json::to_value(next).unwrap_or_default())]);
}

/// `_runAction`: `@ipc:` stays in process, anything else is a shell
/// command spawned through the compositor.
fn run_action(action: &str) -> Out {
    if let Some(name) = action.strip_prefix("@ipc:") {
        return Out::Internal(name.to_owned());
    }
    if !action.is_empty() {
        index::ask(Ask::Spawn(index::ipc_command(action)));
    }
    Out::None
}

pub fn selection_path() -> std::path::PathBuf {
    state::state_path().with_file_name("menu-selection.txt")
}

fn row_height(node: &Node, theme: &Theme, kit: &mut Kit) -> f64 {
    let s = &theme.space;
    if node.emoji_only {
        let h = ui::measure(&w::text("Ag").size(Type::Display), 100.0, theme, kit).1;
        return h + s.control_padding_y * 2.0;
    }
    s.control_height
}

/// The window: the card, its surface and the three bands' widgets.
pub struct Shown {
    pub card: Card,
    pub surface: Surface,
    head: Ui,
    body: Ui,
    foot: Ui,
    rules: Vec<NodeId>,
    pub output: (f64, f64),
    pub line_at: f64,
    scale: f64,
    pub wake: Option<Instant>,
    region: Option<IRect>,
    pub open: bool,
    /// The card's top, settled: the scroll's own animation.
    scroll: Animated,
}

impl Shown {
    pub fn new(theme: &Theme, surface: Surface, output: (f64, f64), line_at: f64, ends: Ends, scale: f64, cast: bool) -> Self {
        let rest = Rect::new(0.0, line_at, 0.0, line_at);
        let mut card = Card::build(theme, "card", Edge::Top, (output.0 as i32, output.1 as i32), line_at, rest, scale, cast, true);
        card.ends = ends;
        card.deform_amount = 0.1;
        let top = card.top_node();
        Self {
            card,
            surface,
            head: Ui::new(Some(top)),
            body: Ui::new(Some(top)),
            foot: Ui::new(Some(top)),
            rules: Vec::new(),
            output,
            line_at,
            scale,
            wake: None,
            region: None,
            open: true,
            scroll: Animated::new(0.0, Clock::SpatialFast.curve()),
        }
    }

    pub fn finished(&self, now: Instant) -> bool {
        self.surface.mapped && self.card.finished(now)
    }

    pub fn animating(&self, now: Instant) -> bool {
        self.card.animating(now) || self.scroll.running(now) || self.wake.is_some_and(|w| w <= now)
    }

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

    fn metrics(theme: &Theme, m: &Model, output_h: f64) -> (f64, f64, f64) {
        let s = &theme.space;
        let band = s.control_height + s.panel_padding * 2.0 + theme.border_width;
        let chrome = band * 2.0;
        let cap = if output_h > 0.0 { output_h * fs_theme::tokens::LAUNCHER.height_share } else { s.popup_height_menu };
        let body = if m.mode == Mode::Input { 0.0 } else { (s.popup_height_menu.min(cap) - chrome).max(0.0) };
        (band, chrome, body)
    }

    /// Lays the card out and draws the three bands.
    pub fn layout(&mut self, m: &mut Model, store: &Store, theme: &Theme, kit: &mut Kit, now: Instant) {
        let s = theme.space.clone();
        let (_, chrome, body_h) = Self::metrics(theme, m, self.output.1);
        if (m.body_h - body_h).abs() > 0.5 {
            m.body_h = body_h;
            m.follow();
        }
        let (w_, h_) = (s.popup_width_menu, chrome + body_h);
        let x = ((self.output.0 - w_) / 2.0).round();
        let pad = s.panel_padding;
        let max_top = self.output.1 - h_ - pad;
        let y = if max_top < pad { pad } else { (self.output.1 * 0.3).clamp(pad, max_top) }.round();
        let rest = Rect::new(x, y, x + w_, y + h_);
        if rest != self.card.rest() {
            self.card.set_rect(rest, rest);
            if !self.card.animating(now) || !self.surface.mapped {
                self.card.tick(now);
            }
        }
        let target = m.scroll;
        if (self.scroll.target() - target).abs() > 0.5 {
            if m.travels { self.scroll.set(now, target, Clock::SpatialFast.ms(theme) * self.scale) } else { self.scroll.jump(target) }
        }
        self.draw(m, store, theme, kit, now, body_h);
    }

    #[allow(clippy::too_many_arguments)]
    fn draw(&mut self, m: &Model, store: &Store, theme: &Theme, kit: &mut Kit, now: Instant, body_h: f64) {
        let (frame, alpha) = self.card.content;
        let clip = self.card.clip;
        let s = theme.space.clone();
        let pad = s.panel_padding;
        let (fx, fy, fw) = (frame.x as f64, frame.y as f64, frame.w as f64);
        let inner_w = (fw - pad * 2.0).max(0.0);
        let side = s.sm;
        self.wake = None;
        let scene = &mut self.card.scene;
        self.head.motion_scale = self.scale;
        self.body.motion_scale = self.scale;
        self.foot.motion_scale = self.scale;

        // The header band.
        let head_rect = Rect::new(fx + pad, fy + pad, fx + pad + inner_w, fy + pad + s.control_height);
        let head = header(m, store, theme, kit, inner_w);
        let d = self.head.draw(&head, head_rect, Some(clip), alpha, theme, kit, scene, now);
        if d.animating {
            self.wake = Some(now);
        }
        let bw = theme.border_width.round().max(1.0) as i32;
        let rule_top = (fy + pad + s.control_height + pad).round() as i32;
        let body_top = rule_top as f64 + theme.border_width;
        let sep = theme.box_style("separator", None).fill;
        let sep = sep.with_alpha(sep.a * alpha);

        // The body.
        let viewport = IRect::new((fx + pad).round() as i32, body_top.round() as i32, inner_w.round() as i32, body_h.round() as i32);
        let body_clip = viewport.intersect(&clip);
        let scroll = self.scroll.value(now);
        let body = if body_h > 0.0 { body_el(m, store, theme, kit, scroll, body_h) } else { w::space(0.0) };
        self.body.halo_owned = false;
        self.body.cursor = None;
        let origin = (fx + pad, body_top - scroll);
        let d = self.body.draw(&body, Rect::new(origin.0, origin.1, origin.0 + inner_w, origin.1 + m.layout.content_h), Some(body_clip), alpha, theme, kit, scene, now);
        if d.animating {
            self.wake = Some(now);
        }
        let _ = side;

        // The footer band.
        let foot_rule = (body_top + body_h).round() as i32;
        let foot_top = if body_h > 0.0 { foot_rule as f64 + theme.border_width + pad } else { body_top + pad };
        let foot = footer(m, store, theme);
        let d = self.foot.draw(&foot, Rect::new(fx + pad + side, foot_top, fx + pad + inner_w - side, foot_top + s.control_height), Some(clip), alpha, theme, kit, scene, now);
        if d.animating {
            self.wake = Some(now);
        }

        let mut p = Painter::new(scene, &mut self.rules, Some(clip));
        p.rect(IRect::new(frame.x, rule_top, frame.w, bw), sep, 0.0);
        if body_h > 0.0 {
            p.rect(IRect::new(frame.x, foot_rule, frame.w, bw), sep, 0.0);
        }
        p.finish();
    }

    /// What is under the pointer: a body row or cell, a header or footer
    /// control.
    pub fn hit(&self, x: f64, y: f64) -> Option<crate::ui::Hit> {
        self.body.hit(x, y).or_else(|| self.head.hit(x, y)).or_else(|| self.foot.hit(x, y)).cloned()
    }

    pub fn on_card(&self, x: f64, y: f64) -> bool {
        let r = self.card.live_rect();
        x >= r.x as f64 && x < r.right() as f64 && y >= r.y as f64 && y < r.bottom() as f64
    }

    pub fn set_hover(&mut self, path: Option<String>) -> bool {
        let changed = self.body.hover != path;
        self.body.hover = path.clone();
        self.head.hover = path.clone();
        self.foot.hover = path;
        changed
    }
}

fn header(m: &Model, store: &Store, theme: &Theme, kit: &mut Kit, width: f64) -> El {
    let s = &theme.space;
    let mut parts = Vec::new();
    let in_level = m.mode == Mode::Menu && m.level.is_some();
    if in_level {
        parts.push(w::space(s.sm));
        parts.push(w::icon_text_button(m.level_icon(store), m.level_name(store)).variant(ui::Variant::Outline).tip("Back").on("back"));
        parts.push(w::space(s.icon_gap));
    } else {
        parts.push(w::space(s.sm + s.control_padding_x));
    }
    let shown = if m.mode == Mode::Input && m.input_secret { "\u{2022}".repeat(m.query.chars().count()) } else { m.query.clone() };
    let field = if shown.is_empty() {
        w::text(m.placeholder(store)).size(Type::Subtitle).ink(Ink::Muted).elide()
    } else {
        w::text(shown.clone()).size(Type::Subtitle).elide()
    };
    let text_w = if shown.is_empty() { 0.0 } else { ui::measure(&w::text(shown).size(Type::Subtitle), width, theme, kit).0 };
    let line = ui::measure(&w::text("Ag").size(Type::Subtitle), width, theme, kit).1;
    let caret = w::swatch(theme.colors.get("foreground"), theme.border_width.max(1.0), line, 0.0);
    let caret = El { kind: match caret.kind { ui::el::Kind::Swatch { color, w, h, radius, .. } => ui::el::Kind::Swatch { color, w, h, radius, border: false }, k => k }, ..caret };
    if shown_is_empty(m) {
        parts.push(caret);
        parts.push(field.pad_start(0.0));
    } else {
        parts.push(field.width(Size::Px(text_w)));
        parts.push(caret);
        parts.push(w::space(0.0).fill());
    }
    parts.push(w::space(s.icon_gap));
    parts.push(w::icon_button("x").tip("Close").on("close"));
    parts.push(w::space(s.sm));
    w::row(0.0, parts).fill()
}

fn shown_is_empty(m: &Model) -> bool {
    m.query.is_empty()
}

fn footer(m: &Model, store: &Store, theme: &Theme) -> El {
    let s = &theme.space;
    let node = m.rows.get(m.cursor);
    let bar = fs_menu::actions::action_bar(&fs_menu::actions::ActionCtx {
        mode: m.mode,
        node,
        at_root: m.level.is_none(),
        confirming: !m.confirm.is_empty() && node.is_some_and(|n| n.id == m.confirm),
        alternate_label: node.and_then(|n| n.alternate_label.as_deref()).unwrap_or(""),
        ..Default::default()
    });
    let name = if m.view == View::Emoji {
        node.map(|n| {
            let l = n.label.to_lowercase();
            let mut c = l.chars();
            c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
        })
        .unwrap_or_else(|| m.level_name(store))
    } else {
        m.level_name(store)
    };
    let mut parts = vec![
        w::space(s.control_padding_x),
        w::icon(m.level_icon(store)).ink(Ink::Muted),
        w::space(s.icon_gap),
        w::text(name).size(Type::BodySmall).ink(Ink::Muted).elide(),
    ];
    let mut actions = Vec::new();
    if let Some(p) = &bar.primary {
        actions.push(w::row(0.0, vec![w::button(p.label.clone()).variant(ui::Variant::Ghost).on("primary"), w::chord_keys(s, &p.keys)]));
    }
    for h in &bar.hints {
        actions.push(w::row(s.sm, vec![w::text(h.label.clone()).size(Type::BodySmall).ink(Ink::Muted), w::chord_keys(s, &h.keys)]));
    }
    parts.push(w::row(s.xxl, actions));
    parts.push(w::space(s.control_padding_x));
    w::row(0.0, parts).fill()
}

/// The body's widgets for the slots inside the viewport, the rest as room.
fn body_el(m: &Model, store: &Store, theme: &Theme, kit: &mut Kit, scroll: f64, view_h: f64) -> El {
    let s = &theme.space;
    let lay = &m.layout;
    if m.rows.is_empty() {
        let title = match &m.empty {
            Some(n) => n.label.clone(),
            None if m.mode == Mode::Input => String::new(),
            None if !m.query.is_empty() => format!("No results for \u{201C}{}\u{201D}", m.query),
            None => "No results".into(),
        };
        let mut col = vec![w::space((view_h / 2.0 - s.control_height).max(0.0)), w::text(title).ink(Ink::Muted).centred()];
        if let Some(d) = m.empty.as_ref().and_then(|n| n.desc.clone()).filter(|d| !d.is_empty()) {
            col.push(w::caption(d).mono().centred());
        }
        return w::column(s.row_gap, col);
    }
    let lo = scroll - view_h * 0.5;
    let hi = scroll + view_h * 1.5;
    let visible = |y: f64, h: f64| y + h >= lo && y <= hi;
    let snap = snapshot(store);
    let mut items: Vec<(f64, f64, El)> = Vec::new();
    for (text, y, x) in &lay.headings {
        let h = ui::measure(&w::section_label(s, text, None, true), 400.0, theme, kit).1;
        if visible(*y, h) {
            items.push((*y, h, w::section_label(s, text, None, true).pad_start(s.control_padding_x + x)));
        }
    }
    let cells = m.cells();
    for (i, slot) in lay.slots.iter().enumerate() {
        if !visible(slot.y, slot.h) {
            continue;
        }
        let row = &m.rows[i];
        let selected = i == m.cursor;
        let el = if i < cells && m.view == View::AppGrid {
            let gutter = s.sm;
            let image = store.menu.icons.get(&row.icon_source).cloned().flatten();
            let pic = if image.is_some() {
                w::picture(image, s.control_height * 2.0)
            } else {
                El::new(ui::el::Kind::Icon { name: "layout-grid".into(), size: Type::DisplayLarge, ink: Ink::Dim })
                    .width(Size::Px(s.control_height * 2.0))
            };
            let content = w::column(s.row_gap, vec![pic.centred(), w::label(row.label.clone()).elide().hug().centred()]);
            w::cell(content)
                .ghost()
                .selected(selected)
                .interactive()
                .cell_state(|st| st.cursor = selected && m.from_keys)
                .on(format!("row:{i}"))
                .key(format!("c:{}", row.id))
                .width(Size::Px(slot.w))
                .pad(gutter, gutter, gutter, gutter)
        } else if i < cells {
            let glyph = w::text(row.icon.clone()).size(Type::Display).centred();
            w::cell(w::column(0.0, vec![glyph]))
                .ghost()
                .selected(selected)
                .interactive()
                .cell_state(|st| st.cursor = selected && m.from_keys)
                .on(format!("row:{i}"))
                .key(format!("e:{}", row.id))
                .width(Size::Px(slot.w))
        } else {
            let checked = toggles::checked_for(Some(row), Some(&snap), Some(&store.menu.checked));
            menu_row(m, row, i, selected, checked, theme).width(Size::Px(slot.w))
        };
        items.push((slot.y + slot.band, slot.h - slot.band, el.pad_start(0.0)));
    }
    // Absolutely placed by stacking: a column of rows, each a row of what
    // shares its top.
    items.sort_by(|a, b| a.0.total_cmp(&b.0));
    let mut col: Vec<El> = Vec::new();
    let mut y = 0.0;
    let mut i = 0;
    while i < items.len() {
        let top = items[i].0;
        let mut line = Vec::new();
        let mut h: f64 = 0.0;
        let mut x = 0.0;
        while i < items.len() && (items[i].0 - top).abs() < 0.5 {
            let (_, ih, el) = items.remove(i);
            let slot_x = slot_x_of(m, &el);
            if slot_x > x {
                line.push(w::space(slot_x - x));
                x = slot_x;
            }
            x += match el.width { Size::Px(px) => px, _ => 0.0 };
            line.push(el);
            h = h.max(ih);
        }
        if top > y {
            col.push(w::space(top - y));
        }
        col.push(w::row(0.0, line).top());
        y = top + h;
    }
    col.push(w::space((lay.content_h - y).max(0.0)));
    w::column(0.0, col)
}

/// Where an item sits across the body, off its key.
fn slot_x_of(m: &Model, el: &El) -> f64 {
    let Some(key) = &el.key else { return 0.0 };
    let id = key.split_once(':').map_or("", |(_, id)| id);
    m.rows.iter().position(|r| r.id == id).and_then(|i| m.layout.slots.get(i)).map_or(0.0, |s| s.x)
}

/// MenuRow.qml.
fn menu_row(m: &Model, row: &Node, i: usize, selected: bool, checked: bool, theme: &Theme) -> El {
    let s = &theme.space;
    let confirming = !m.confirm.is_empty() && m.confirm == row.id;
    let mut lead = Vec::new();
    let glyph = fs_menu::icons::icon_for(Some(row));
    let drawn = if !glyph.is_empty() {
        glyph.to_owned()
    } else if row.icon_source.is_empty() && !row.icon.is_empty() {
        fs_menu::icons::fallback_for(Some(row)).to_owned()
    } else {
        String::new()
    };
    if !drawn.is_empty() {
        lead.push(w::icon(drawn));
    }
    let label = if confirming { format!("Confirm {}?", row.label) } else { row.label.clone() };
    let mut name = w::label(label).elide();
    if row.dim == Some(true) {
        name = name.ink(Ink::Dim);
    }
    if row.emoji_only {
        name = name.size(Type::Display);
    }
    lead.push(name);
    if let Some(desc) = row.desc.clone().filter(|d| !d.is_empty()) {
        lead.push(w::text(desc).size(Type::BodySmall).ink(Ink::Dim).elide());
    }
    let mut trail = Vec::new();
    let chord = fs_menu::actions::chord_keys_for(Some(row));
    let accessory = fs_menu::actions::accessory_for(Some(row));
    if !chord.is_empty() {
        trail.push(w::chord_keys(s, &chord));
    } else if !accessory.is_empty() {
        let word = row.meta.as_deref().unwrap_or("").is_empty() && matches!(row.kind, NodeKind::App | NodeKind::Action);
        let a = w::caption(accessory).ink(Ink::Dim);
        trail.push(if word { a } else { a.mono() });
    }
    if checked && !confirming {
        trail.push(w::icon("check"));
    }
    let mut parts = vec![w::row(s.icon_gap, lead).fill()];
    if !trail.is_empty() {
        parts.push(w::row(s.icon_gap, trail));
    }
    let _ = Weight::Medium;
    w::cell(w::row(s.control_padding_x, parts).fill())
        .ghost()
        .selected(selected)
        .interactive()
        .cell_state(|st| st.destructive = confirming)
        .on(format!("row:{i}"))
        .key(format!("r:{}", row.id))
}
