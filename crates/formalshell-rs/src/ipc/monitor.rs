//! `monitor`, MonitorIpc.qml's `status` and `gpu`. A reply is whatever the
//! last tick left, never a wait for a fresh one; each call also asks for
//! the poll for a grace period (QML's subscribe/unsubscribe pulse), so a
//! caller with no monitor cell on the bar finds data on its next call.
//! The process table, launch and mode verbs join with the launcher's
//! monitor view.

use super::registry::{Function, Target, Type, Value};
use crate::services::info::monitor::now_ms;
use crate::services::wants::{self, Source};
use crate::wayland::App;

fn status(app: &mut App, _: &[Value]) -> Value {
    wants::pulse(Source::Monitor);
    Value::Str(app.store.info.monitor.status(now_ms()).to_string())
}

fn gpu(app: &mut App, _: &[Value]) -> Value {
    wants::pulse(Source::Monitor);
    Value::Str(app.store.info.monitor.gpu(now_ms()).to_string())
}

pub fn target() -> Target<App> {
    Target {
        name: "monitor",
        functions: vec![
            Function { name: "status", params: &[], ret: Type::String, call: status },
            Function { name: "gpu", params: &[], ret: Type::String, call: gpu },
        ],
    }
}
