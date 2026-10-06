//! `caffeinate`, CaffeinateIpc.qml: toggle, enable and disable the idle
//! inhibitor, and `status` (`inhibiting` is the surface's own word that the
//! Wayland inhibitor is up, not a restatement of `active`).

use super::registry::{Function, Target, Type, Value};
use crate::wayland::App;

fn toggle(app: &mut App, _: &[Value]) -> Value {
    let on = !app.store.caffeinate.active;
    app.set_caffeinated(on);
    Value::Str("ok".into())
}

fn enable(app: &mut App, _: &[Value]) -> Value {
    app.set_caffeinated(true);
    Value::Str("ok".into())
}

fn disable(app: &mut App, _: &[Value]) -> Value {
    app.set_caffeinated(false);
    Value::Str("ok".into())
}

fn status(app: &mut App, _: &[Value]) -> Value {
    Value::Str(app.store.caffeinate.status())
}

pub fn target() -> Target<App> {
    Target {
        name: "caffeinate",
        functions: vec![
            Function { name: "toggle", params: &[], ret: Type::String, call: toggle },
            Function { name: "enable", params: &[], ret: Type::String, call: enable },
            Function { name: "disable", params: &[], ret: Type::String, call: disable },
            Function { name: "status", params: &[], ret: Type::String, call: status },
        ],
    }
}
