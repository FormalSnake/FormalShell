//! `media`, MediaIpc.qml's read of the active source. The controls join
//! with the media panel.

use super::registry::{Function, Target, Type, Value};
use crate::wayland::App;

pub fn target() -> Target<App> {
    Target {
        name: "media",
        functions: vec![Function {
            name: "status",
            params: &[],
            ret: Type::String,
            call: |app, _| Value::Str(app.store.media.status().to_string()),
        }],
    }
}
