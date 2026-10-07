//! `nightlight`, NightLightIpc.qml: toggle, enable and disable the
//! wlsunset-backed night light, and `status`.

use super::registry::{Function, Target, Type, Value};
use crate::services::nightlight;
use crate::wayland::App;

fn toggle(_: &mut App, _: &[Value]) -> Value {
    nightlight::toggle();
    Value::Str("ok".into())
}

fn enable(_: &mut App, _: &[Value]) -> Value {
    nightlight::enable();
    Value::Str("ok".into())
}

fn disable(_: &mut App, _: &[Value]) -> Value {
    nightlight::disable();
    Value::Str("ok".into())
}

fn status(app: &mut App, _: &[Value]) -> Value {
    Value::Str(app.store.nightlight.status())
}

pub fn target() -> Target<App> {
    Target {
        name: "nightlight",
        functions: vec![
            Function { name: "toggle", params: &[], ret: Type::String, call: toggle },
            Function { name: "enable", params: &[], ret: Type::String, call: enable },
            Function { name: "disable", params: &[], ret: Type::String, call: disable },
            Function { name: "status", params: &[], ret: Type::String, call: status },
        ],
    }
}
