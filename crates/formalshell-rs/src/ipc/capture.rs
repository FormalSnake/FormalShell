//! `capture`, CaptureIpc.qml: text (OCR) and colour off a slurp selection
//! or a geometry the caller already has, cancel and status.

use super::registry::{Function, Target, Type, Value};
use crate::surfaces::capture as cap;
use crate::wayland::App;

fn text(app: &mut App, _: &[Value]) -> Value {
    Value::Str(cap::grab_start(app, "text", ""))
}

fn color(app: &mut App, _: &[Value]) -> Value {
    Value::Str(cap::grab_start(app, "color", ""))
}

fn text_at(app: &mut App, a: &[Value]) -> Value {
    Value::Str(cap::grab_start(app, "text", a[0].str()))
}

fn color_at(app: &mut App, a: &[Value]) -> Value {
    Value::Str(cap::grab_start(app, "color", a[0].str()))
}

fn cancel(app: &mut App, _: &[Value]) -> Value {
    Value::Str(cap::grab_cancel(app, "cancelled on demand"))
}

fn status(app: &mut App, _: &[Value]) -> Value {
    Value::Str(cap::grab_status(app))
}

pub fn target() -> Target<App> {
    Target {
        name: "capture",
        functions: vec![
            Function { name: "text", params: &[], ret: Type::String, call: text },
            Function { name: "color", params: &[], ret: Type::String, call: color },
            Function { name: "textAt", params: &[("geometry", Type::String)], ret: Type::String, call: text_at },
            Function { name: "colorAt", params: &[("geometry", Type::String)], ret: Type::String, call: color_at },
            Function { name: "cancel", params: &[], ret: Type::String, call: cancel },
            Function { name: "status", params: &[], ret: Type::String, call: status },
        ],
    }
}
