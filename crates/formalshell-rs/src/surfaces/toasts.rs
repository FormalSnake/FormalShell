//! The sonner depth stack. One overlay surface the size of the
//! output for as long as anything is popped up, so the collapse and expand
//! reflow moves cards inside a static window rather than resizing a layer
//! surface the compositor would animate against the shell's own motion; the
//! input region is the stack's own rect.
//!
//! Collapsed is the depth stack (the front card, two levels peeking behind
//! it as empty chrome), expanded the plain column, both laid out by
//! fs-info's `toast_stack`.
//!
//! Each group keeps its slot across draws, so a card retargets rather than
//! snaps: x, y, width and height ride the table's `restack` clock (y behind
//! its rank's share of `restack.stagger`), presence rides `arrive` in and
//! `restack` out, and a row slides in from past its screen edge under the
//! velocity deform. A group that left keeps its slot, its card and its last
//! place while it fades.

use std::collections::{HashMap, HashSet};
use std::time::Instant;

use fs_info::notifications::{self as model, Group, Urgency};
use fs_info::toast_stack::{self, StackParams};
use fs_theme::theme::Theme;
use smithay_client_toolkit::shell::WaylandSurface;
use vello_cpu::kurbo::{Affine, Rect};

use crate::motion::{Animated, Curve, Deform, DeformEdge, EFFECTS};
use crate::scene::{Bitmap, IRect, NodeId, Scene};
use crate::services::notifications::now_ms;
use crate::store::Store;
use crate::surface::Surface;
use crate::surfaces::bar::cell::{Kit, Painter};
use crate::ui::{self, El, Ink, Type, Ui, Variant, Weight, w};

const MAX_PEEK_LEVELS: usize = 2;

/// The default deform `amount`.
const DEFORM_AMOUNT: f64 = 0.15;

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
    /// The card as it last drew, kept for the fade of a group that left.
    el: El,
    critical: bool,
    /// Where it is drawn this frame, for the pointer.
    rect: IRect,
    z: i64,
    members: Vec<String>,
    x: Animated,
    y: Animated,
    width: Animated,
    height: Animated,
    /// 0 off the stack, 1 shown: opacity, and the row's slide.
    presence: Animated,
    /// The card's words over the peek level's bare chrome.
    content: Animated,
    /// The bubble unfolding off its own top edge on `arrive`; 1 at once
    /// for the row.
    reveal: Animated,
    /// The group is gone and the card is fading where it was.
    departing: bool,
    deform: Deform,
    deform_running: bool,
    last_tick: Option<Instant>,
    /// The card's own widgets still crossfading (a button's ink).
    ui_animating: bool,
}

impl Slot {
    fn moving(&self, now: Instant) -> bool {
        [&self.x, &self.y, &self.width, &self.height, &self.presence].iter().any(|a| a.running(now))
    }

    fn animating(&self, now: Instant) -> bool {
        self.moving(now) || self.content.running(now) || self.reveal.running(now) || !self.deform.at_rest || self.ui_animating
    }

    /// Faded out and no longer anything to draw.
    fn gone(&self, now: Instant) -> bool {
        self.departing && !self.presence.running(now)
    }
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
    /// The last draw ran with a clock still running.
    pub was_animating: bool,
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

/// Elementary's bubble: the picture in a
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
            was_animating: false,
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

        let motion = theme.motion();
        let restack = (motion.restack * scale, Curve::from_table(&motion.restack_curve));
        let arrive = (motion.arrive * scale, Curve::from_table(&motion.arrive_curve));
        let effects = motion.families.effects * scale;

        // A group that left fades where it was; one back before its fade
        // ended takes its slot again.
        for (k, slot) in self.slots.iter_mut() {
            let live = by_key.contains_key(k);
            if !live && !slot.departing {
                slot.departing = true;
                slot.presence.set_on(now, 0.0, restack.0, restack.1);
            } else if live && slot.departing {
                slot.departing = false;
                slot.presence.set_on(now, 1.0, arrive.0, arrive.1);
            }
        }
        let gone: Vec<String> = self.slots.iter().filter(|(_, sl)| sl.gone(now)).map(|(k, _)| k.clone()).collect();
        for k in gone {
            if let Some(mut slot) = self.slots.remove(&k) {
                for id in slot.nodes.drain(..) {
                    // Damages where the deform last put it, past its bounds.
                    self.scene.set_transform(id, Affine::IDENTITY);
                    self.scene.remove(id);
                }
                slot.ui.hide(&mut self.scene);
            }
        }

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

        // The restack's window shared out over the cards still live, each
        // waiting its own rank's share.
        let stagger = (motion.restack_stagger * scale / by_key.len().max(1) as f64).round();
        for k in &stack_order {
            let Some(geom) = layout.by_key.get(k) else { continue };
            let Some(g) = (if expanded { geom.expanded.or(geom.collapsed) } else { geom.collapsed }) else { continue };
            let h = heights[k];
            let (gx, gy) = (x0 + g.x, y0 + g.y);
            let content = if g.content_visible { 1.0 } else { 0.0 };
            let slot = self.slots.entry(k.clone()).or_insert_with(|| {
                let mut reveal = Animated::new(0.0, arrive.1);
                if is_bubble {
                    reveal.set(now, 1.0, arrive.0);
                } else {
                    reveal.jump(1.0);
                }
                let mut presence = Animated::new(0.0, arrive.1);
                presence.set(now, 1.0, arrive.0);
                Slot {
                    nodes: Vec::new(),
                    ui: Ui::new(None),
                    el: cards[k].clone(),
                    critical: false,
                    rect: IRect::default(),
                    z: g.z,
                    members: Vec::new(),
                    x: Animated::new(gx, restack.1),
                    y: Animated::new(gy, restack.1),
                    width: Animated::new(g.width, restack.1),
                    height: Animated::new(h, restack.1),
                    presence,
                    content: Animated::new(content, EFFECTS),
                    reveal,
                    departing: false,
                    deform: Deform::new(),
                    deform_running: false,
                    last_tick: None,
                    ui_animating: false,
                }
            });
            slot.x.set(now, gx, restack.0);
            slot.y.set_after(now, gy, restack.0, stagger * g.rank as f64);
            slot.width.set(now, g.width, restack.0);
            // A card still arriving takes its content in the frame it is
            // measured in, so nothing grows and slides at once.
            if slot.presence.running(now) {
                slot.height.jump(h);
            } else {
                slot.height.set(now, h, restack.0);
            }
            slot.content.set(now, content, effects);
            slot.z = g.z;
            slot.el = cards[k].clone();
            slot.critical = by_key[k].urgency == Urgency::Critical;
            slot.members = by_key[k].member_ids.clone();
        }

        // Back to front, so the front card's chrome covers the peeks.
        let mut order: Vec<(i64, String)> = self.slots.iter().map(|(k, sl)| (sl.z, k.clone())).collect();
        order.sort();
        let mut anchor: Option<NodeId> = None;
        let edge = if spec.right { DeformEdge::Right } else { DeformEdge::Left };
        for (_, k) in order {
            let slot = self.slots.get_mut(&k).expect("ordered from the map");
            let b = theme.box_style("notification", Some(if slot.critical { "critical" } else { "rest" }));
            let presence = slot.presence.value(now);
            let w = slot.width.value(now);
            // A row travels its own width plus the gap it sits in, in from
            // past the anchored edge; a bubble unfolds where it lands.
            let slide = if is_bubble { 0.0 } else { (1.0 - presence) * (w + s.screen_padding) * f64::from(spec.slide_sign) };
            let (fx, fy, fh) = (slot.x.value(now) + slide, slot.y.value(now), slot.height.value(now));

            let dt = slot.last_tick.map_or(0.0, |t| now.saturating_duration_since(t).as_secs_f64());
            slot.last_tick = Some(now);
            let running = !is_bubble && theme.motion_enabled && (slot.moving(now) || !slot.deform.at_rest);
            if running {
                if !slot.deform_running {
                    slot.deform.unsample();
                }
                slot.deform.step_at(dt, (fx, fy, w, fh), DEFORM_AMOUNT, edge);
            }
            slot.deform_running = running;
            let pivot = (if edge == DeformEdge::Right { fx + w } else { fx }, fy + fh / 2.0);
            let matrix = slot.deform.about(pivot);

            let rect = IRect::new(fx.round() as i32, fy.round() as i32, w.round() as i32, fh.round() as i32);
            slot.rect = rect;
            let alpha = presence.clamp(0.0, 1.0) as f32;
            let radius = theme.box_radius(&b, rect.h as f64);
            let shown = IRect::new(rect.x, rect.y, rect.w, (rect.h as f64 * slot.reveal.value(now).clamp(0.0, 1.0)).round() as i32);
            // The box opens out with the unfold, so its cast opens with it
            // rather than being cut to the card's own rect.
            let reach = fs_theme::style::geometry::cast_pad(&b.casts).ceil() as i32;
            let around = IRect::new(rect.x - reach, rect.y - reach, rect.w + reach * 2, shown.h + reach * 2);
            // The painter compares against an untransformed node, and the
            // deform goes back on once it has laid the box out.
            for id in &slot.nodes {
                self.scene.set_transform(*id, Affine::IDENTITY);
            }
            let mut p = Painter::new(&mut self.scene, &mut slot.nodes, Some(around)).after(anchor);
            ui::boxes::paint(&mut p, shown, &b, radius, alpha, 0.0);
            p.finish();
            for id in &slot.nodes {
                self.scene.set_transform(*id, matrix);
            }
            anchor = slot.nodes.last().copied().or(anchor);
            let content = slot.content.value(now).clamp(0.0, 1.0) as f32 * alpha;
            if content > 0.0 {
                slot.ui.motion_scale = 1.0;
                let pad = s.panel_padding;
                // Laid out at the card's own width, so a peek level's words
                // never reflow while its chrome narrows.
                let inner = Rect::new(fx + pad, fy + pad, fx + width - pad, fy + fh - pad);
                slot.ui_animating = slot.ui.draw(&slot.el, inner, Some(shown), content, theme, kit, &mut self.scene, now).animating;
            } else {
                slot.ui_animating = false;
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
        let mut over: Vec<(&String, &Slot)> =
            self.slots.iter().filter(|(_, s)| !s.departing && Self::contains(s.rect, x, y)).collect();
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
        self.slots.values().filter(|s| !s.departing).flat_map(|s| s.members.iter().cloned()).collect()
    }

    /// Any card on the stack, a group that left included until its fade
    /// has run.
    pub fn holds_cards(&self) -> bool {
        !self.slots.is_empty()
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
        !self.surface.mapped || self.slots.values().any(|s| s.animating(now))
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
