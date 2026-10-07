//! `picker`, PickerIpc.qml: the wallpaper route summoned, the generic image
//! selector opened on a directory, and `choose` doing what Enter on a cell
//! does.

use super::registry::{Function, Target, Type, Value};
use crate::wayland::App;

fn text(s: impl Into<String>) -> Value {
    Value::Str(s.into())
}

fn summon(app: &mut App, _: &[Value]) -> Value {
    app.picker_summon();
    text("ok")
}

fn select(app: &mut App, a: &[Value]) -> Value {
    app.picker_select(a[0].str(), a[1].str());
    text("ok")
}

fn choose(app: &mut App, a: &[Value]) -> Value {
    app.resolve_launcher();
    if app.picker_choose(a[0].str()) {
        text("ok")
    } else {
        text("error: not on the picker route, or path not in the current listing")
    }
}

fn variant(app: &mut App, a: &[Value]) -> Value {
    let name = a[0].str();
    if name != "dark" && name != "light" {
        return text("error: variant must be dark or light");
    }
    if app.picker_variant(name == "light") {
        text("ok")
    } else {
        text("error: not on the picker route, or the listing has no Dark/Light variants")
    }
}

fn close(app: &mut App, _: &[Value]) -> Value {
    app.menu_close();
    text("ok")
}

fn status(app: &mut App, _: &[Value]) -> Value {
    text(app.launcher.picker_status(&app.store).to_string())
}

pub fn target() -> Target<App> {
    Target {
        name: "picker",
        functions: vec![
            Function { name: "summon", params: &[], ret: Type::String, call: summon },
            Function { name: "select", params: &[("directory", Type::String), ("token", Type::String)], ret: Type::String, call: select },
            Function { name: "choose", params: &[("path", Type::String)], ret: Type::String, call: choose },
            Function { name: "variant", params: &[("name", Type::String)], ret: Type::String, call: variant },
            Function { name: "close", params: &[], ret: Type::String, call: close },
            Function { name: "status", params: &[], ret: Type::String, call: status },
        ],
    }
}
