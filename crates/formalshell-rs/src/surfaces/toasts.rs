//! Toasts.qml: the sonner depth stack. One overlay surface the size of the
//! output for as long as anything is popped up, so the collapse and expand
//! reflow moves cards inside a static window rather than resizing a layer
//! surface the compositor would animate against the shell's own motion; the
//! input region is the stack's own rect.
//!
//! Collapsed is the depth stack (the front card, two levels peeking behind
//! it as empty chrome), expanded the plain column, both laid out by
//! fs-info's `toast_stack`. The card is NotificationRow.qml.

use std::collections::{HashMap, HashSet};
use std::time::Instant;

use fs_info::notifications::{self as model, Group, Urgency};
use fs_info::toast_stack::{self, StackParams};
use fs_theme::theme::Theme;
use smithay_client_toolkit::shell::WaylandSurface;
use vello_cpu::kurbo::Rect;

use crate::scene::{IRect, NodeId, Scene};
use crate::services::notifications::now_ms;
use crate::store::Store;
use crate::surface::Surface;
use crate::surfaces::bar::cell::{Kit, Painter};
use crate::ui::{self, El, Ink, Type, Ui, Variant, Weight, w};

const MAX_PEEK_LEVELS: usize = 2;

/// What a click on a card asks for.
pub enum Act {
    None,
    /// The card's X: every member of its group.
    Dismiss(Vec<String>),
    Action(String, String),
    /// The body: the default action when there is one, else the sender's
    /// window, and the toast goes either way.
    Body(Vec<String>),
}

struct Slot {
    nodes: Vec<NodeId>,
    ui: Ui,
    height: f64,
    rect: IRect,
    z: i64,
    members: Vec<String>,
}

pub struct Toasts {
    pub surface: Surface,
    pub scene: Scene,
    slots: HashMap<String, Slot>,
    region: Option<IRect>,
    stack: IRect,
    /// The pointer over the stack: it fans out and every toast in it holds.
    pub hovered: bool,
    pressed: Option<(String, String)>,
}

/// Where the stack hangs: the bar's own edge cleared, `screenPadding` in.
pub struct Insets {
    pub top: f64,
    pub bottom: f64,
    pub left: f64,
    pub right: f64,
}

fn card(theme: &Theme, g: &Group, now: i64) -> El {
    let s = &theme.space;
    let e = &g.entry;
    let critical = e.urgency == Urgency::Critical;
    let rel = model::rel_time(now, e.arrived_at);
    let meta = if g.count > 1 { format!("{rel}  x{}", g.count) } else { rel };
    let glyph = if critical { "triangle-alert" } else { "bell" };
    let header = w::row(
        s.icon_gap,
        vec![
            w::icon(glyph).ink(if critical { Ink::Destructive } else { Ink::Muted }),
            w::section_label(s, &e.app_name, None, false),
            w::caption(meta).mono().fill(),
            w::icon_button("x").on("close"),
        ],
    );
    let mut parts = vec![header, w::text(e.summary.clone()).weight(Weight::Medium).elide().fill()];
    let body = model::sanitize_body(&e.body, &e.app_name, &e.app_icon);
    if !body.is_empty() {
        parts.push(w::text(body).size(Type::BodySmall).ink(Ink::Muted).elide().fill());
    }
    let actions = model::button_actions(e);
    if !actions.is_empty() {
        let buttons = actions.iter().map(|a| w::button(a.label.clone()).variant(Variant::Outline).on(format!("action:{}", a.key))).collect();
        parts.push(w::row(s.sm, buttons).pad(0.0, s.row_gap, 0.0, 0.0));
    }
    w::column(s.row_gap, parts).on("body")
}

impl Toasts {
    pub fn new(surface: Surface, size: (i32, i32)) -> Self {
        Self {
            surface,
            scene: Scene::clear(size.0, size.1),
            slots: HashMap::new(),
            region: None,
            stack: IRect::default(),
            hovered: false,
            pressed: None,
        }
    }

    pub fn expanded(&self, store: &Store) -> bool {
        self.hovered || store.notifications.stack_expanded
    }

    pub fn draw(&mut self, store: &Store, theme: &Theme, kit: &mut Kit, insets: &Insets, now: Instant) {
        let s = &theme.space;
        let n = &store.notifications;
        let spec = model::position_spec(store.config.str("notifications.position"));
        let groups = model::group_entries(&n.model.popups);
        let by_key: HashMap<String, &Group> = groups.iter().map(|g| (model::group_key(g), g)).collect();
        let mut chronological: Vec<&Group> = groups.iter().collect();
        chronological.sort_by_key(|g| g.arrived_at);
        let stack_order: Vec<String> = model::stack_order(&groups).iter().map(|g| model::group_key(g)).collect();
        let mut column: Vec<String> = chronological.iter().map(|g| model::group_key(g)).collect();
        if spec.newest_first {
            column.reverse();
        }
        self.slots.retain(|k, slot| {
            let keep = by_key.contains_key(k);
            if !keep {
                for id in slot.nodes.drain(..) {
                    self.scene.remove(id);
                }
                slot.ui.hide(&mut self.scene);
            }
            keep
        });

        let width = s.popup_width_narrow;
        let clock = now_ms();
        let cards: HashMap<&String, El> = by_key.iter().map(|(k, g)| (k, card(theme, g, clock))).collect();
        let mut heights = HashMap::new();
        for (k, el) in &cards {
            let inner = ui::measure(el, width - s.panel_padding * 2.0, theme, kit).1;
            heights.insert((*k).clone(), inner + s.panel_padding * 2.0);
        }
        let layout = toast_stack::layout(&StackParams {
            frame_width: width,
            peek_inset: s.lg,
            peek_offset: s.sm,
            max_peek_levels: MAX_PEEK_LEVELS,
            gap: s.panel_padding,
            top: spec.top,
            heights: heights.clone(),
            collapsed: stack_order.iter().cloned().map(Some).collect(),
            expanded: column.iter().cloned().map(Some).collect(),
        });
        let expanded = self.expanded(store);
        let (sw, sh) = (self.scene.size.w as f64, self.scene.size.h as f64);
        let max_h = (sh - insets.top - insets.bottom - s.screen_padding * 2.0).max(0.0);
        let stack_h = max_h.min(if expanded { layout.expanded_height } else { layout.collapsed_height });
        let x0 = if spec.left { insets.left + s.screen_padding } else { sw - insets.right - s.screen_padding - width };
        let y0 = if spec.top { insets.top + s.screen_padding } else { sh - insets.bottom - s.screen_padding - stack_h };
        self.stack = if by_key.is_empty() {
            IRect::default()
        } else {
            IRect::new(x0.round() as i32, y0.round() as i32, width.round() as i32, stack_h.round() as i32)
        };

        // Back to front, so the front card's chrome covers the peeks.
        let mut order: Vec<(&String, toast_stack::Geom)> = stack_order
            .iter()
            .filter_map(|k| {
                let slot = layout.by_key.get(k)?;
                let g = if expanded { slot.expanded.or(slot.collapsed) } else { slot.collapsed };
                Some((k, g?))
            })
            .collect();
        order.sort_by_key(|(_, g)| g.z);
        let mut anchor: Option<NodeId> = None;
        for (k, g) in order {
            let critical = by_key[k].urgency == Urgency::Critical;
            let b = theme.box_style("notification", Some(if critical { "critical" } else { "rest" }));
            let h = heights[k];
            let rect = IRect::new((x0 + g.x).round() as i32, (y0 + g.y).round() as i32, g.width.round() as i32, h.round() as i32);
            let slot = self.slots.entry(k.clone()).or_insert_with(|| Slot {
                nodes: Vec::new(),
                ui: Ui::new(None),
                height: h,
                rect,
                z: g.z,
                members: Vec::new(),
            });
            slot.z = g.z;
            slot.height = h;
            slot.rect = rect;
            slot.members = by_key[k].member_ids.clone();
            let radius = theme.box_radius(&b, rect.h as f64);
            let mut p = Painter::new(&mut self.scene, &mut slot.nodes, None).after(anchor);
            ui::boxes::paint(&mut p, rect, &b, radius, 1.0, 0.0);
            p.finish();
            anchor = slot.nodes.last().copied().or(anchor);
            if g.content_visible {
                slot.ui.motion_scale = 1.0;
                let pad = s.panel_padding;
                let inner = Rect::new(rect.x as f64 + pad, rect.y as f64 + pad, (rect.x + rect.w) as f64 - pad, (rect.y + rect.h) as f64 - pad);
                slot.ui.draw(&cards[k], inner, Some(rect), 1.0, theme, kit, &mut self.scene, now);
            } else {
                slot.ui.hide(&mut self.scene);
            }
        }
    }

    pub fn sync_region(&mut self, compositor: &smithay_client_toolkit::compositor::CompositorState) {
        if self.region == Some(self.stack) {
            return;
        }
        self.region = Some(self.stack);
        if let Ok(region) = smithay_client_toolkit::compositor::Region::new(compositor) {
            if !self.stack.is_empty() {
                region.add(self.stack.x, self.stack.y, self.stack.w, self.stack.h);
            }
            self.surface.layer.set_input_region(Some(region.wl_region()));
        }
    }

    fn contains(r: IRect, x: f64, y: f64) -> bool {
        let (x, y) = (x.floor() as i32, y.floor() as i32);
        x >= r.x && x < r.right() && y >= r.y && y < r.bottom()
    }

    /// The card under a point, front first, and what in it.
    fn hit(&self, x: f64, y: f64) -> Option<(String, String)> {
        let mut over: Vec<(&String, &Slot)> = self.slots.iter().filter(|(_, s)| Self::contains(s.rect, x, y)).collect();
        over.sort_by_key(|(_, s)| std::cmp::Reverse(s.z));
        let (k, slot) = over.into_iter().next()?;
        let on = slot.ui.hit(x, y).and_then(|h| h.on.clone()).unwrap_or_else(|| "body".into());
        Some((k.clone(), on))
    }

    /// True when what the pointer is over changed.
    pub fn pointer(&mut self, at: Option<(f64, f64)>) -> bool {
        let inside = at.is_some_and(|(x, y)| Self::contains(self.stack, x, y));
        let mut moved = inside != self.hovered;
        self.hovered = inside;
        for slot in self.slots.values_mut() {
            let hover = at.and_then(|(x, y)| slot.ui.hit(x, y)).map(|h| h.path.clone());
            if slot.ui.hover != hover {
                slot.ui.hover = hover;
                moved = true;
            }
        }
        moved
    }

    /// Members of every group on screen, which hold while the stack is
    /// expanded.
    pub fn members(&self) -> HashSet<String> {
        self.slots.values().flat_map(|s| s.members.iter().cloned()).collect()
    }

    pub fn press(&mut self, x: f64, y: f64) {
        self.pressed = self.hit(x, y);
    }

    pub fn release(&mut self, x: f64, y: f64) -> Act {
        let Some(pressed) = self.pressed.take() else { return Act::None };
        if self.hit(x, y).as_ref() != Some(&pressed) {
            return Act::None;
        }
        let (key, on) = pressed;
        let Some(slot) = self.slots.get(&key) else { return Act::None };
        let members = slot.members.clone();
        match on.as_str() {
            "close" => Act::Dismiss(members),
            "body" => Act::Body(members),
            a => match a.strip_prefix("action:") {
                Some(k) => Act::Action(members.last().cloned().unwrap_or_default(), k.to_owned()),
                None => Act::None,
            },
        }
    }

    pub fn animating(&self, _now: Instant) -> bool {
        !self.surface.mapped
    }
}
