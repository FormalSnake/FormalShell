//! `screensaver`: start, stop, status, the frame pin a
//! recorder steps through, and `frameInfo`, whose `cycles` is its last key
//! on purpose (the rig greps `"cycles":0}`).

use super::registry::{Function, Target, Type, Value};
use crate::wayland::App;

fn text(s: impl Into<String>) -> Value {
    Value::Str(s.into())
}

fn start(app: &mut App, _: &[Value]) -> Value {
    app.saver_start();
    text("ok")
}

fn stop(app: &mut App, _: &[Value]) -> Value {
    app.saver_stop();
    text("ok")
}

fn status(app: &mut App, _: &[Value]) -> Value {
    text(app.saver_status())
}

fn frame(app: &mut App, args: &[Value]) -> Value {
    if !app.saver_active() {
        return text("error: screensaver not active");
    }
    let n = args[0].int();
    if n < 0 {
        return text("error: frame must be >= 0");
    }
    app.saver_pin(i64::from(n));
    text("ok")
}

fn frame_info(app: &mut App, _: &[Value]) -> Value {
    text(app.saver_frame_info())
}

pub fn target() -> Target<App> {
    Target {
        name: "screensaver",
        functions: vec![
            Function { name: "start", params: &[], ret: Type::String, call: start },
            Function { name: "stop", params: &[], ret: Type::String, call: stop },
            Function { name: "status", params: &[], ret: Type::String, call: status },
            Function { name: "frame", params: &[("n", Type::Int)], ret: Type::String, call: frame },
            Function { name: "frameInfo", params: &[], ret: Type::String, call: frame_info },
        ],
    }
}
