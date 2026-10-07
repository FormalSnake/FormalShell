//! `display` and `hdr`: the Display panel's
//! output controls without the panel, and HDR for a compositor keybind.
//! Each answers "ok" or why nothing was sent.

use fs_system::display::outputs;

use super::registry::{Function, Target, Type, Value};
use crate::services::display;
use crate::services::hyprland::{self, Command};
use crate::wayland::App;

fn text(s: impl Into<String>) -> Value {
    Value::Str(s.into())
}

pub fn target() -> Target<App> {
    Target {
        name: "display",
        functions: vec![
            Function { name: "scale", params: &[("output", Type::String), ("scale", Type::Real)], ret: Type::String, call: scale },
            Function { name: "mirror", params: &[("output", Type::String), ("source", Type::String)], ret: Type::String, call: mirror },
            Function { name: "enable", params: &[("output", Type::String), ("enabled", Type::Bool)], ret: Type::String, call: enable },
        ],
    }
}

pub fn hdr() -> Target<App> {
    Target {
        name: "hdr",
        functions: vec![
            Function { name: "toggle", params: &[], ret: Type::String, call: hdr_toggle },
            Function { name: "enable", params: &[], ret: Type::String, call: hdr_enable },
            Function { name: "disable", params: &[], ret: Type::String, call: hdr_disable },
            Function {
                name: "setOutput",
                params: &[("output", Type::String), ("enabled", Type::Bool)],
                ret: Type::String,
                call: hdr_set_output,
            },
            Function { name: "rule", params: &[("output", Type::String)], ret: Type::String, call: hdr_rule },
            Function { name: "status", params: &[], ret: Type::String, call: hdr_status },
        ],
    }
}

/// None when the change may go out; otherwise the answer.
fn refuse(app: &App, output: &str) -> Option<Value> {
    if !display::config_available() {
        return Some(text("no compositor"));
    }
    if outputs::find_output(&app.store.hyprland.outputs, output).is_none() {
        return Some(text(format!("unknown output: {output}")));
    }
    None
}

fn scale(app: &mut App, args: &[Value]) -> Value {
    let output = args[0].str();
    if let Some(no) = refuse(app, output) {
        return no;
    }
    hyprland::send(Command::SetOutputScale(output.to_owned(), args[1].real()));
    text("ok")
}

/// An empty `source` clears the mirror.
fn mirror(app: &mut App, args: &[Value]) -> Value {
    let output = args[0].str();
    if !display::config_available() {
        return text("mirroring unsupported");
    }
    if let Some(no) = refuse(app, output) {
        return no;
    }
    hyprland::send(Command::SetOutputMirror(output.to_owned(), args[1].str().to_owned()));
    text("ok")
}

fn enable(app: &mut App, args: &[Value]) -> Value {
    let output = args[0].str();
    if let Some(no) = refuse(app, output) {
        return no;
    }
    hyprland::send(Command::SetOutputEnabled(output.to_owned(), args[1].bool()));
    text("ok")
}

fn hdr_toggle(app: &mut App, _: &[Value]) -> Value {
    text(display::hdr_toggle(&app.store))
}

fn hdr_enable(app: &mut App, _: &[Value]) -> Value {
    text(display::hdr_set_all(&app.store, true))
}

fn hdr_disable(app: &mut App, _: &[Value]) -> Value {
    text(display::hdr_set_all(&app.store, false))
}

fn hdr_set_output(app: &mut App, args: &[Value]) -> Value {
    text(display::hdr_set(&app.store, args[0].str(), args[1].bool()))
}

fn hdr_rule(app: &mut App, args: &[Value]) -> Value {
    text(display::hdr_rule(&app.store, args[0].str()))
}

fn hdr_status(app: &mut App, _: &[Value]) -> Value {
    text(display::hdr_status(&app.store))
}
