//! `plugins`: `list` (the resolved manifests), `status`
//! (what loaded, what failed and what the scan warned about) and `reload`
//! (scan again, restart every plugin). Summoning a plugin's panel stays on
//! the `panel` target under its `plugin:<id>` name.

use super::registry::{Function, Target, Type, Value};
use crate::services::plugins;
use crate::wayland::App;

fn list(app: &mut App, _: &[Value]) -> Value {
    Value::Str(app.store.plugins.list().to_string())
}

fn status(app: &mut App, _: &[Value]) -> Value {
    Value::Str(app.store.plugins.status().to_string())
}

fn reload(_: &mut App, _: &[Value]) -> Value {
    plugins::reload();
    Value::Str("ok".into())
}

pub fn target() -> Target<App> {
    Target {
        name: "plugins",
        functions: vec![
            Function { name: "list", params: &[], ret: Type::String, call: list },
            Function { name: "status", params: &[], ret: Type::String, call: status },
            Function { name: "reload", params: &[], ret: Type::String, call: reload },
        ],
    }
}
