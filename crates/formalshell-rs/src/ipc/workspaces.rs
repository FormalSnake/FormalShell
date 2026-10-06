//! `workspaces status`, WorkspacesIpc.qml's read of the Spaces cell. `peek`
//! and `close` drive the hover preview, which waits for the window
//! thumbnails (R8); until then the preview block reads as closed.

use serde_json::json;

use super::registry::{Function, Target, Type, Value};
use crate::wayland::App;

pub fn target() -> Target<App> {
    Target { name: "workspaces", functions: vec![Function { name: "status", params: &[], ret: Type::String, call: status }] }
}

fn status(app: &mut App, _: &[Value]) -> Value {
    let Some(cell) = app.bar.workspaces_status() else {
        return Value::Str("error: no workspaces cell on any bar".into());
    };
    let preview = json!({"open": false, "idx": -1, "windows": 0, "captured": 0, "keyboard": false, "miniature": null, "rect": null});
    Value::Str(json!({"output": cell["output"], "slots": cell["slots"], "preview": preview}).to_string())
}
