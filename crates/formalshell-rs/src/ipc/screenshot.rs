//! `screenshot`: full, region and the picker's pick,
//! its headless keys and status, the editor, and cancel.

use super::registry::{Function, Target, Type, Value};
use crate::surfaces::capture as cap;
use crate::wayland::App;

const PROCESSING: (&str, Type) = ("processing", Type::String);

fn full(app: &mut App, a: &[Value]) -> Value {
    Value::Str(cap::shot_start(app, false, a[0].str()))
}

fn region(app: &mut App, a: &[Value]) -> Value {
    Value::Str(cap::shot_start(app, true, a[0].str()))
}

fn cancel(app: &mut App, _: &[Value]) -> Value {
    Value::Str(cap::shot_cancel(app, "cancelled on demand"))
}

fn pick(app: &mut App, a: &[Value]) -> Value {
    Value::Str(cap::shot_pick(app, a[0].str(), a[1].str()))
}

fn key(app: &mut App, a: &[Value]) -> Value {
    Value::Str(cap::picker_key(app, a[0].str()))
}

fn picker_status(app: &mut App, _: &[Value]) -> Value {
    Value::Str(cap::picker_status(app))
}

fn edit(app: &mut App, a: &[Value]) -> Value {
    let path = if a[0].str().is_empty() { app.capture.shot.last_path.clone() } else { a[0].str().to_owned() };
    Value::Str(cap::shot_edit(app, &path))
}

fn status(app: &mut App, _: &[Value]) -> Value {
    Value::Str(cap::shot_status(app))
}

pub fn target() -> Target<App> {
    Target {
        name: "screenshot",
        functions: vec![
            Function { name: "full", params: &[PROCESSING], ret: Type::String, call: full },
            Function { name: "region", params: &[PROCESSING], ret: Type::String, call: region },
            Function { name: "cancel", params: &[], ret: Type::String, call: cancel },
            Function { name: "pick", params: &[("mode", Type::String), PROCESSING], ret: Type::String, call: pick },
            Function { name: "key", params: &[("name", Type::String)], ret: Type::String, call: key },
            Function { name: "pickerStatus", params: &[], ret: Type::String, call: picker_status },
            Function { name: "edit", params: &[("path", Type::String)], ret: Type::String, call: edit },
            Function { name: "status", params: &[], ret: Type::String, call: status },
        ],
    }
}
