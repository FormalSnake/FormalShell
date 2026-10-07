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

use crate::motion::{Animated, Curve};
use crate::scene::{Bitmap, IRect, NodeId, Scene};
use crate::services::notifications::now_ms;
use crate::store::Store;
use crate::surface::Surface;
use crate::surfaces::bar::cell::{Kit, Painter};
use crate::ui::{self, El, Ink, Type, Ui, Variant, Weight, w};

const MAX_PEEK_LEVELS: usize = 2;

/// How often the relative times ("2m ago") recompute, off their own clock.
pub const REL_EVERY: std::time::Duration = std::time::Duration::from_secs(30);

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
    /// The bubble unfolding off its own top edge on `arrive`; 1 at once
    /// for the row.
    reveal: Animated,
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
    /// Pictures fitted to the icon slot, per entry.
    fitted: HashMap<String, Option<Bitmap>>,
    /// When the relative times were last recomputed.
    pub rel_at: Instant,
}

/// Where the stack hangs: the bar's own edge cleared, `screenPadding` in.
pub struct Insets {
    pub top: f64,
    pub bottom: f64,
    pub left: f64,
    pub right: f64,
}

fn card(theme: &Theme, g: &Group, now: i64, picture: Option<Bitmap>) -> El {
    let s = &theme.space;
    let e = &g.entry;
    let critical = e.urgency == Urgency::Critical;
    let rel = model::rel_time(now, e.arrived_at);
    let meta = if g.count > 1 { format!("{rel}  x{}", g.count) } else { rel };
    let glyph = if critical { "triangle-alert" } else { "bell" };
    let slot = theme.font_size.heading;
    let mark = match picture.filter(|_| !critical) {
        Some(b) => w::picture(Some(b), slot),
        None => w::row(0.0, vec![w::icon(glyph).ink(if critical { Ink::Destructive } else { Ink::Muted })])
            .width(ui::Size::Px(slot))
            .centred(),
    };
    let mark = if e.source == "iphone" { mark.badge("smartphone") } else { mark };
    let header = w::row(
        s.icon_gap,
        vec![
            mark,
            w::section_label(s, &e.app_name, None, false),
            w::caption(meta).mono().fill(),
            w::icon_button("x").on("close"),
        ],
    );
    let mut parts = vec![header, w::para(e.summary.clone(), Type::Body, Weight::Medium, Ink::Fg, 2)];
    let body = model::sanitize_body(&e.body, &e.app_name, &e.app_icon);
    if !body.is_empty() {
        parts.push(w::para(body, Type::BodySmall, Weight::Normal, Ink::Muted, 2));
    }
    let actions = model::button_actions(e);
    if !actions.is_empty() {
        let buttons = actions.iter().map(|a| w::button(a.label.clone()).variant(Variant::Outline).on(format!("action:{}", a.key))).collect();
        parts.push(w::row(s.sm, buttons).pad(0.0, s.row_gap, 0.0, 0.0));
    }
    w::column(s.row_gap, parts).on("body")
}

/// NotificationBubble.qml, elementary's bubble: the picture in a
/// `controlHeight` slot beside the words, a semibold summary, and the close
/// button only while the pointer is over the bubble.
fn bubble(theme: &Theme, g: &Group, now: i64, picture: Option<Bitmap>, hovered: bool) -> El {
    let s = &theme.space;
    let e = &g.entry;
    let critical = e.urgency == Urgency::Critical;
    let rel = model::rel_time(now, e.arrived_at);
    let meta = if g.count > 1 { format!("{rel}  x{}", g.count) } else { rel };
    let slot = s.control_height;
    let mark = match picture.filter(|_| !critical) {
        Some(b) => w::picture(Some(b), slot),
        None => w::row(
            0.0,
            vec![w::icon(if critical { "triangle-alert" } else { "bell" })
                .size(Type::Heading)
                .ink(if critical { Ink::Destructive } else { Ink::Muted })],
        )
        .width(ui::Size::Px(slot))
        .centred(),
    };
    let mark = if e.source == "iphone" { mark.badge("smartphone") } else { mark };
    let mut head = vec![w::section_label(s, &e.app_name, None, false), w::caption(meta).mono().fill()];
    head.push(if hovered { w::icon_button("x").on("close") } else { w::space(s.control_height) });
    let mut words = vec![w::row(s.icon_gap, head), w::para(e.summary.clone(), Type::Body, Weight::Semibold, Ink::Fg, 2)];
    let body = model::sanitize_body(&e.body, &e.app_name, &e.app_icon);
    if !body.is_empty() {
        words.push(w::para(body, Type::BodySmall, Weight::Normal, Ink::Muted, 2));
    }
    let actions = model::button_actions(e);
    if !actions.is_empty() {
        let buttons = actions.iter().map(|a| w::button(a.label.clone()).variant(Variant::Outline).on(format!("action:{}", a.key))).collect();
        words.push(w::row(s.sm, buttons).pad(0.0, s.row_gap, 0.0, 0.0));
    }
    w::row(s.md, vec![mark, w::column(s.row_gap, words).fill()]).top().on("body")
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
            fitted: HashMap::new(),
            rel_at: Instant::now(),
        }
    }

    pub fn expanded(&self, store: &Store) -> bool {
        self.hovered || store.notifications.stack_expanded
    }

    pub fn draw(&mut self, store: &Store, theme: &Theme, kit: &mut Kit, insets: &Insets, scale: f64, now: Instant) {
        let is_bubble = theme.habit("notification").and_then(|v| v.as_str()) == Some("bubble");
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

        let width = if is_bubble { s.popup_width_bubble } else { s.popup_width_narrow };
        let clock = now_ms();
        let size = theme.font_size.heading.round() as u32;
        self.fitted.retain(|id, _| n.icons.contains_key(id));
        let mut cards: HashMap<&String, El> = HashMap::new();
        for (k, g) in &by_key {
            let pic = n.icons.get(&g.id).and_then(|raw| {
                self.fitted.entry(g.id.clone()).or_insert_with(|| raw.bitmap(size)).clone()
            });
            let el = if is_bubble {
                let hovered = self.slots.get(k.as_str()).is_some_and(|sl| sl.ui.hover.is_some());
                bubble(theme, g, clock, pic, hovered)
            } else {
                card(theme, g, clock, pic)
            };
            cards.insert(k, el);
        }
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
            let slot = self.slots.entry(k.clone()).or_insert_with(|| {
                let motion = theme.motion();
                let mut reveal = Animated::new(0.0, Curve::from_table(&motion.arrive_curve));
                if is_bubble {
                    reveal.set(now, 1.0, motion.arrive * scale);
                } else {
                    reveal.jump(1.0);
                }
                Slot { nodes: Vec::new(), ui: Ui::new(None), height: h, rect, z: g.z, members: Vec::new(), reveal }
            });
            slot.z = g.z;
            slot.height = h;
            slot.rect = rect;
            slot.members = by_key[k].member_ids.clone();
            let radius = theme.box_radius(&b, rect.h as f64);
            let shown = IRect::new(rect.x, rect.y, rect.w, (rect.h as f64 * slot.reveal.value(now).clamp(0.0, 1.0)).round() as i32);
            // The box opens out with the unfold, so its cast opens with it
            // rather than being cut to the card's own rect.
            let reach = fs_theme::style::geometry::cast_pad(&b.casts).ceil() as i32;
            let around = IRect::new(rect.x - reach, rect.y - reach, rect.w + reach * 2, shown.h + reach * 2);
            let mut p = Painter::new(&mut self.scene, &mut slot.nodes, Some(around)).after(anchor);
            ui::boxes::paint(&mut p, shown, &b, radius, 1.0, 0.0);
            p.finish();
            anchor = slot.nodes.last().copied().or(anchor);
            if g.content_visible {
                slot.ui.motion_scale = 1.0;
                let pad = s.panel_padding;
                let inner = Rect::new(rect.x as f64 + pad, rect.y as f64 + pad, (rect.x + rect.w) as f64 - pad, (rect.y + rect.h) as f64 - pad);
                slot.ui.draw(&cards[k], inner, Some(shown), 1.0, theme, kit, &mut self.scene, now);
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

    pub fn animating(&self, now: Instant) -> bool {
        !self.surface.mapped || self.slots.values().any(|s| s.reveal.running(now))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::theme::getter;
    use crate::ui::el::Kind;
    use serde_json::json;

    fn group(source: &str, body: &str) -> Group {
        let entry = model::Entry {
            source: source.into(),
            app_name: "Messages".into(),
            summary: "hello".into(),
            body: body.into(),
            ..Default::default()
        };
        Group { entry, count: 1, member_ids: Vec::new() }
    }

    fn walk(el: &El, f: &mut dyn FnMut(&El)) {
        f(el);
        if let Kind::Column { children, .. } | Kind::Row { children, .. } = &el.kind {
            children.iter().for_each(|c| walk(c, f));
        }
    }

    fn theme() -> Theme {
        Theme::resolve(getter(json!({})), &fs_theme::palette::fallback("dark"))
    }

    #[test]
    fn a_card_mirrored_off_the_phone_carries_the_source_mark() {
        let theme = theme();
        for (source, marked) in [("iphone", true), ("", false)] {
            let mut badges = 0;
            walk(&card(&theme, &group(source, ""), 0, None), &mut |e| badges += usize::from(e.badge.is_some()));
            assert_eq!(badges, usize::from(marked), "source {source:?}");
            let mut badges = 0;
            walk(&bubble(&theme, &group(source, ""), 0, None, false), &mut |e| badges += usize::from(e.badge.is_some()));
            assert_eq!(badges, usize::from(marked), "bubble, source {source:?}");
        }
    }

    #[test]
    fn the_summary_and_the_body_wrap_to_two_lines() {
        let theme = theme();
        let mut wrapped = Vec::new();
        walk(&card(&theme, &group("", "some body"), 0, None), &mut |e| {
            if let Kind::Para { lines, .. } = &e.kind {
                wrapped.push(*lines);
            }
        });
        assert_eq!(wrapped, vec![2, 2]);
    }
}
