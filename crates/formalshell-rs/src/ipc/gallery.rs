//! `gallery`, GalleryIpc.qml's verbs over the dev sheet.

use super::registry::{Function, Target, Type, Value};
use crate::wayland::App;

fn ok() -> Value {
    Value::Str("ok".into())
}

fn open(app: &mut App, _: &[Value]) -> Value {
    app.set_gallery(true);
    ok()
}

fn close(app: &mut App, _: &[Value]) -> Value {
    app.set_gallery(false);
    ok()
}

fn toggle(app: &mut App, _: &[Value]) -> Value {
    let open = !app.gallery_open();
    app.set_gallery(open);
    ok()
}

fn status(app: &mut App, _: &[Value]) -> Value {
    Value::Str(serde_json::json!({ "isOpen": app.gallery_open() }).to_string())
}

pub fn target() -> Target<App> {
    Target {
        name: "gallery",
        functions: vec![
            Function { name: "open", params: &[], ret: Type::String, call: open },
            Function { name: "close", params: &[], ret: Type::String, call: close },
            Function { name: "toggle", params: &[], ret: Type::String, call: toggle },
            Function { name: "status", params: &[], ret: Type::String, call: status },
        ],
    }
}
