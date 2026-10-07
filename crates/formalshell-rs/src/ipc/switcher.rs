//! `switcher`, SwitcherIpc.qml: the whole summon path for the window
//! switcher. `switcher.enabled: false` answers every verb with the error
//! string rather than accepting a call that would do nothing.

use super::registry::{Function, Target, Type, Value};
use crate::wayland::App;
use crate::wayland::switcher::OFF;

fn guard(app: &App) -> Option<Value> {
    (!app.switcher_enabled()).then(|| Value::Str(OFF.into()))
}

fn next(app: &mut App, _: &[Value]) -> Value {
    guard(app).unwrap_or_else(|| {
        app.switcher_step(1);
        Value::Str("ok".into())
    })
}

fn prev(app: &mut App, _: &[Value]) -> Value {
    guard(app).unwrap_or_else(|| {
        app.switcher_step(-1);
        Value::Str("ok".into())
    })
}

fn commit(app: &mut App, _: &[Value]) -> Value {
    guard(app).unwrap_or_else(|| Value::Str(if app.switcher_commit() { "ok" } else { "error: nothing to commit" }.into()))
}

fn cancel(app: &mut App, _: &[Value]) -> Value {
    guard(app).unwrap_or_else(|| {
        app.switcher_close();
        Value::Str("ok".into())
    })
}

fn state(app: &mut App, _: &[Value]) -> Value {
    guard(app).unwrap_or_else(|| Value::Str(app.switcher_state()))
}

pub fn target() -> Target<App> {
    Target {
        name: "switcher",
        functions: vec![
            Function { name: "next", params: &[], ret: Type::String, call: next },
            Function { name: "prev", params: &[], ret: Type::String, call: prev },
            Function { name: "commit", params: &[], ret: Type::String, call: commit },
            Function { name: "cancel", params: &[], ret: Type::String, call: cancel },
            Function { name: "state", params: &[], ret: Type::String, call: state },
        ],
    }
}
