//! `headset`: `dismiss` takes the connect card down, which is what its
//! Escape bind runs; "none" when no card was up.

use super::registry::{Function, Target, Type, Value};
use crate::wayland::App;

fn dismiss(app: &mut App, _: &[Value]) -> Value {
    Value::Str(if app.headset_escape() { "ok" } else { "none" }.into())
}

pub fn target() -> Target<App> {
    Target { name: "headset", functions: vec![Function { name: "dismiss", params: &[], ret: Type::String, call: dismiss }] }
}
