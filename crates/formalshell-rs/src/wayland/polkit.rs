//! The polkit dialog (PolkitDialog.qml): a full-output top-layer surface
//! holding the keyboard while a request is open, the scrim over the desktop
//! and the card at its centre: "Authentication required", the action's
//! message, the identity, the password field and Cancel/Authenticate.

use std::time::Instant;

use fs_theme::color::Rgba;
use smithay_client_toolkit::reexports::client::protocol::wl_surface::WlSurface;
use smithay_client_toolkit::seat::keyboard::{KeyEvent, Keysym};
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::{Anchor, KeyboardInteractivity, Layer, LayerSurface};
use vello_cpu::kurbo::Rect;
use zeroize::Zeroizing;

use super::App;
use super::lock::{LockMsg, field};
use crate::scene::{Bitmap, IRect, NodeId, Scene};
use crate::services::polkit::{self, Cmd, Event};
use crate::surface::Surface;
use crate::surfaces::bar::cell::Painter;
use crate::ui::{self, El, Size, Ui, Variant, boxes, w};

const NAMESPACE: &str = "formalshell:polkit";

pub struct Dialog {
    surface: Surface,
    scene: Scene,
    ui: Ui,
    nodes: Vec<NodeId>,
    avatar_nodes: Vec<NodeId>,
    /// The identity's picture, when it is this session's own account.
    avatar: Option<Bitmap>,
    message: String,
    identity: String,
    prompt: String,
    echo: bool,
    /// Waiting on the helper for a prompt, or on its verdict.
    asked: bool,
    submitted: bool,
    error: bool,
    text: Zeroizing<String>,
    dirty: bool,
}

impl Dialog {
    pub(super) fn set_avatar(&mut self, avatar: Option<Bitmap>) {
        self.avatar = avatar;
        self.dirty = true;
    }
}

/// Text.qml's `WordWrap` for body text: greedy lines no wider than `width`.
fn wrap(text: &str, width: f64, theme: &fs_theme::theme::Theme, kit: &mut crate::surfaces::bar::cell::Kit) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    let mut line = String::new();
    for word in text.split_whitespace() {
        let candidate = if line.is_empty() { word.to_owned() } else { format!("{line} {word}") };
        if !line.is_empty() && ui::measure(&w::text(&candidate), 1.0e6, theme, kit).0 > width {
            lines.push(std::mem::replace(&mut line, word.to_owned()));
        } else {
            line = candidate;
        }
    }
    if !line.is_empty() {
        lines.push(line);
    }
    lines
}

impl App {
    pub(super) fn polkit_event(&mut self, event: Event) {
        match event {
            Event::Begin { message, identity } => {
                let own = !identity.is_empty() && std::env::var("USER").is_ok_and(|u| u == identity);
                let surface = self.compositor.create_surface(&self.qh);
                let layer = self.layer_shell.create_layer_surface(&self.qh, surface, Layer::Top, Some(NAMESPACE), None);
                layer.set_anchor(Anchor::all());
                layer.set_exclusive_zone(-1);
                layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
                layer.commit();
                self.polkit = Some(Dialog {
                    surface: Surface::new("polkit", layer, &self.shm, self.started),
                    scene: Scene::new(1, 1),
                    ui: Ui::new(None),
                    nodes: Vec::new(),
                    avatar_nodes: Vec::new(),
                    avatar: None,
                    message,
                    identity,
                    prompt: String::new(),
                    echo: false,
                    asked: false,
                    submitted: false,
                    error: false,
                    text: field(),
                    dirty: true,
                });
                if own && let (Some(rt), Some(tx)) = (&self.runtime, self.lock.tx.clone()) {
                    let home = std::env::var("HOME").unwrap_or_default();
                    let path = self.store.config.avatar_path(&home);
                    let px = (self.store.theme.theme.space.xxl * 2.0).round() as u32;
                    rt.pool().submit(move || {
                        let _ = tx.send(LockMsg::PolkitAvatar(crate::surfaces::lock::avatar(&path, px)));
                    });
                }
            }
            Event::Prompt { prompt, echo } => {
                if let Some(d) = &mut self.polkit {
                    (d.prompt, d.echo, d.asked, d.submitted, d.dirty) = (prompt, echo, true, false, true);
                }
            }
            Event::Failed => {
                if let Some(d) = &mut self.polkit {
                    (d.error, d.submitted, d.asked, d.dirty) = (true, false, false, true);
                    d.text = field();
                }
            }
            Event::Done => self.polkit = None,
        }
    }

    pub(super) fn polkit_owns(&self, layer: &LayerSurface) -> bool {
        self.polkit.as_ref().is_some_and(|d| d.surface.layer.wl_surface() == layer.wl_surface())
    }

    pub(super) fn polkit_configure(&mut self, width: i32, height: i32) {
        let Some(d) = &mut self.polkit else { return };
        if (d.scene.size.w, d.scene.size.h) != (width, height) {
            d.scene.resize(width, height);
            d.scene.touch(d.scene.size);
        }
        d.surface.configure(width, height);
        d.dirty = true;
    }

    pub(super) fn polkit_frame(&mut self, surface: &WlSurface) -> bool {
        let Some(d) = self.polkit.as_mut().filter(|d| d.surface.layer.wl_surface() == surface) else { return false };
        let s = &mut d.surface;
        (s.frame_pending, s.mapped, s.callbacks) = (false, true, s.callbacks + 1);
        true
    }

    /// The dialog's keys while it holds the keyboard.
    pub(super) fn polkit_key(&mut self, event: &KeyEvent) -> bool {
        let Some(d) = &mut self.polkit else { return false };
        let enabled = d.asked && !d.submitted;
        match event.keysym {
            Keysym::Escape => {
                d.text = field();
                polkit::send(Cmd::Cancel);
            }
            Keysym::Return | Keysym::KP_Enter if enabled => {
                (d.submitted, d.error) = (true, false);
                let answer = std::mem::replace(&mut d.text, field());
                polkit::send(Cmd::Submit(answer));
            }
            Keysym::BackSpace if enabled => {
                d.text.pop();
            }
            _ if enabled => {
                if let Some(t) = event.utf8.as_deref().filter(|t| t.chars().all(|c| c as u32 >= 0x20 && c != '\u{7f}')) {
                    d.text.push_str(t);
                }
            }
            _ => {}
        }
        d.dirty = true;
        true
    }

    pub(super) fn present_polkit(&mut self) {
        let Some(d) = &mut self.polkit else { return };
        if !d.dirty || !d.surface.configured {
            return;
        }
        d.dirty = false;
        let theme = &self.store.theme.theme;
        let kit = &mut self.bar.kit;
        let s = &theme.space;
        let (w, h) = (d.scene.size.w, d.scene.size.h);
        let inner = s.popup_width_narrow;
        let enabled = d.asked && !d.submitted;
        let shown = if d.echo { d.text.to_string() } else { "\u{2022}".repeat(d.text.chars().count()) };
        let placeholder = if d.submitted {
            "Checking".to_owned()
        } else if d.prompt.trim().is_empty() {
            "Enter Password".to_owned()
        } else {
            d.prompt.trim().to_owned()
        };
        let mut rows: Vec<El> = vec![w::section_label(s, "Authentication required", None, false)];
        rows.push(w::column(0.0, wrap(&d.message, inner, theme, kit).into_iter().map(w::text).collect()));
        // Avatar.qml's slot: the picture goes in over the space the row
        // leaves for it.
        let avatar = d.avatar.as_ref().map(|b| b.pixmap.width() as f64);
        let mut avatar_row = None;
        if !d.identity.is_empty() {
            let name = w::value(&d.identity).elide();
            let line = match avatar {
                Some(size) => {
                    // The name sits centred on the picture's own height.
                    let h = ui::measure(&name, inner, theme, kit).1;
                    let v = ((size - h) / 2.0).max(0.0);
                    w::row(s.icon_gap, vec![w::space(size), name.fill().pad(0.0, v, 0.0, v)])
                }
                None => name,
            };
            avatar_row = Some(rows.len());
            rows.push(w::column(s.row_gap, vec![w::section_label(s, "Identity", None, false), line]));
        }
        rows.push(w::input(&shown, &placeholder, enabled, d.error.then_some("Wrong password")).width(Size::Px(inner)).enabled(enabled));
        let cancel = w::button("Cancel").variant(Variant::Outline);
        let auth = w::button("Authenticate").enabled(enabled);
        let buttons = w::row(s.control_gap, vec![cancel, auth]);
        let (buttons_w, _) = ui::measure(&buttons, inner, theme, kit);
        rows.push(w::row(0.0, vec![w::space((inner - buttons_w).max(0.0)), buttons]));
        let heights: Vec<f64> = rows.iter().map(|r| ui::measure(r, inner, theme, kit).1).collect();
        let body = w::column(s.section_gap, rows).width(Size::Px(inner));
        let (_, body_h) = ui::measure(&body, inner, theme, kit);
        let card_w = inner + s.panel_padding * 2.0;
        let card_h = body_h + s.panel_padding * 2.0;
        let card = IRect::new(((w as f64 - card_w) / 2.0).round() as i32, ((h as f64 - card_h) / 2.0).round() as i32, card_w.round() as i32, card_h.round() as i32);

        let scrim = theme.box_style("scrim", None).fill.a;
        let style = theme.box_style("card", None);
        let radius = theme.box_radius(&style, card.h as f64);
        let mut p = Painter::new(&mut d.scene, &mut d.nodes, None);
        p.rect(IRect::new(0, 0, w, h), Rgba { r: 0.0, g: 0.0, b: 0.0, a: scrim }, 0.0);
        boxes::paint(&mut p, card, &style, radius, 1.0, 0.0);
        let last = p.last();
        p.finish();
        d.ui.anchor = last;
        let (x, y) = (card.x as f64 + s.panel_padding, card.y as f64 + s.panel_padding);
        if let (Some(i), Some(b)) = (avatar_row, d.avatar.as_ref()) {
            // Under the Identity label and its gap, centred on the row.
            let label_h = ui::measure(&w::section_label(s, "Identity", None, false), inner, theme, kit).1;
            let above: f64 = heights[..i].iter().map(|h| h + s.section_gap).sum();
            let side = b.pixmap.width() as f64;
            let line_h = (heights[i] - label_h - s.row_gap).max(side);
            let at = (x.round() as i32, (y + above + label_h + s.row_gap + (line_h - side) / 2.0).round() as i32);
            let mut p = Painter::new(&mut d.scene, &mut d.avatar_nodes, None).after(last);
            p.image(b, at, 1.0);
            let after = p.last();
            p.finish();
            d.ui.anchor = after;
        } else {
            let p = Painter::new(&mut d.scene, &mut d.avatar_nodes, None);
            p.finish();
        }
        d.ui.draw(&body, Rect::new(x, y, x + inner, y + body_h), None, 1.0, theme, kit, &mut d.scene, Instant::now());
        let qh = self.qh.clone();
        d.surface.present(&mut d.scene, false, &qh);
    }
}
