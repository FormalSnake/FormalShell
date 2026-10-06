//! `airplay`, AirplayIpc.qml: a headless drive path for the receiver. No other
//! verb: UxPlay takes no remote command, and `airplay.enable` and
//! `airplay.name` are settings.json keys the shell only ever reads.

use super::registry::{Function, Target, Type, Value};
use crate::wayland::App;

pub fn target() -> Target<App> {
    Target {
        name: "airplay",
        functions: vec![Function {
            name: "status",
            params: &[],
            ret: Type::String,
            call: |app, _| Value::Str(app.store.media.airplay.status().to_string()),
        }],
    }
}
