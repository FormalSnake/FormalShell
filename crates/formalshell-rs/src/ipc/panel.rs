//! `panel`, PanelIpc.qml's verbs over the panels' cards. `open` hangs a
//! card under its cell when the strip has one, and at the strip's end
//! otherwise.

use fs_chrome::bar::{layout, panels};

use super::registry::{Function, Target, Type, Value};
use crate::wayland::{App, PANELS};

fn text(s: impl Into<String>) -> Value {
    Value::Str(s.into())
}

pub fn target() -> Target<App> {
    Target {
        name: "panel",
        functions: vec![
            Function { name: "open", params: &[("name", Type::String)], ret: Type::String, call: open },
            Function { name: "close", params: &[], ret: Type::String, call: close },
            Function { name: "toggle", params: &[("name", Type::String)], ret: Type::String, call: toggle },
            Function { name: "toggleAt", params: &[("n", Type::Int)], ret: Type::String, call: toggle_at },
            Function { name: "state", params: &[], ret: Type::String, call: state },
        ],
    }
}

fn known(name: &str) -> Option<&'static str> {
    PANELS.iter().find(|(n, _)| *n == name).map(|(n, _)| *n)
}

fn open(app: &mut App, args: &[Value]) -> Value {
    let Some(name) = known(args[0].str()) else { return text(format!("error: unknown panel '{}'", args[0].str())) };
    app.set_panel(name, true, None);
    text("ok")
}

fn close(app: &mut App, _: &[Value]) -> Value {
    app.close_panels();
    text("ok")
}

fn toggle(app: &mut App, args: &[Value]) -> Value {
    let Some(name) = known(args[0].str()) else { return text(format!("error: unknown panel '{}'", args[0].str())) };
    let open = app.panel_open() != Some(name);
    app.set_panel(name, open, None);
    text("ok")
}

fn toggle_at(app: &mut App, args: &[Value]) -> Value {
    let n = args[0].int();
    let bar = app.store.config.get("bar").cloned();
    let resolved = layout::resolve(bar.as_ref(), &[]);
    match panels::panel_at(&resolved, n as i64) {
        Some(name) => toggle(app, &[Value::Str(name.into())]),
        None => text(format!("no panel at {n}")),
    }
}

fn state(app: &mut App, _: &[Value]) -> Value {
    text(app.panel_open().unwrap_or(""))
}
