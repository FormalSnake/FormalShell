//! `mirror`: the launcher's camera route opened, closed and
//! stepped, and what it shows.

use super::registry::{Function, Target, Type, Value};
use crate::surfaces::launcher::MIRROR_ROUTE;
use crate::wayland::App;

fn text(s: impl Into<String>) -> Value {
    Value::Str(s.into())
}

fn toggle(app: &mut App, _: &[Value]) -> Value {
    if app.mirror_showing() {
        app.menu_close();
    } else {
        app.menu_open(Some(MIRROR_ROUTE));
    }
    text("ok")
}

fn open(app: &mut App, _: &[Value]) -> Value {
    app.menu_open(Some(MIRROR_ROUTE));
    text("ok")
}

fn close(app: &mut App, _: &[Value]) -> Value {
    if app.mirror_showing() {
        app.menu_close();
    }
    text("ok")
}

fn step(app: &mut App, delta: i64) -> Value {
    if app.mirror_cycle(delta) { text("ok") } else { text("error: mirror is not showing") }
}

fn next(app: &mut App, _: &[Value]) -> Value {
    step(app, 1)
}

fn previous(app: &mut App, _: &[Value]) -> Value {
    step(app, -1)
}

fn status(app: &mut App, _: &[Value]) -> Value {
    text(app.mirror_status())
}

pub fn target() -> Target<App> {
    Target {
        name: "mirror",
        functions: vec![
            Function { name: "toggle", params: &[], ret: Type::String, call: toggle },
            Function { name: "open", params: &[], ret: Type::String, call: open },
            Function { name: "close", params: &[], ret: Type::String, call: close },
            Function { name: "next", params: &[], ret: Type::String, call: next },
            Function { name: "previous", params: &[], ret: Type::String, call: previous },
            Function { name: "status", params: &[], ret: Type::String, call: status },
        ],
    }
}
