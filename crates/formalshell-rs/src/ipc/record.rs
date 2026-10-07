//! `record`, RecordIpc.qml: thin over `surfaces::capture::record`, so a
//! keybind, a menu row and the smoke rig all drive one implementation.

use super::registry::{Function, Target, Type, Value};
use crate::surfaces::capture::record as rec;
use crate::wayland::App;

const SCOPE: (&str, Type) = ("scope", Type::String);
const AUDIO: (&str, Type) = ("audio", Type::String);

fn start(app: &mut App, a: &[Value]) -> Value {
    Value::Str(rec::start(app, a[0].str(), a[1].str(), None))
}

fn start_capped(app: &mut App, a: &[Value]) -> Value {
    Value::Str(rec::start(app, a[0].str(), a[1].str(), Some(a[2].str())))
}

fn start_at(app: &mut App, a: &[Value]) -> Value {
    Value::Str(rec::start_at(app, a[0].str(), "", "region", a[1].str(), None))
}

fn stop(app: &mut App, _: &[Value]) -> Value {
    Value::Str(rec::stop(app))
}

fn toggle(app: &mut App, a: &[Value]) -> Value {
    Value::Str(rec::toggle(app, a[0].str(), a[1].str()))
}

fn gif(app: &mut App, a: &[Value]) -> Value {
    Value::Str(rec::gif(app, a[0].str()))
}

fn status(app: &mut App, _: &[Value]) -> Value {
    Value::Str(rec::status(app))
}

pub fn target() -> Target<App> {
    Target {
        name: "record",
        functions: vec![
            Function { name: "start", params: &[SCOPE, AUDIO], ret: Type::String, call: start },
            Function { name: "startCapped", params: &[SCOPE, AUDIO, ("maxHeight", Type::String)], ret: Type::String, call: start_capped },
            Function { name: "startAt", params: &[("geometry", Type::String), AUDIO], ret: Type::String, call: start_at },
            Function { name: "stop", params: &[], ret: Type::String, call: stop },
            Function { name: "toggle", params: &[SCOPE, AUDIO], ret: Type::String, call: toggle },
            Function { name: "gif", params: &[("path", Type::String)], ret: Type::String, call: gif },
            Function { name: "status", params: &[], ret: Type::String, call: status },
        ],
    }
}
