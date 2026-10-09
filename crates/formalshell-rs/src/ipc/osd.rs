//! `osd`: the bottom pill from outside. It shows itself on a
//! volume change and on `display brightnessStep`; this covers brightness set
//! by something else (it catches the cached backlight percent up and shows
//! it), media text, close and state.

use super::registry::{Function, Target, Type, Value};
use crate::services::brightness;
use crate::surfaces::osd::Kind;
use crate::wayland::App;

fn text(s: impl Into<String>) -> Value {
    Value::Str(s.into())
}

fn volume(app: &mut App, _: &[Value]) -> Value {
    app.osd_show(Kind::Volume, "");
    text("ok")
}

fn show_brightness(app: &mut App, _: &[Value]) -> Value {
    if let Some(rt) = &app.runtime {
        rt.service(brightness::refresh);
    }
    app.osd_brightness_read();
    app.osd_show(Kind::Brightness, "");
    text("ok")
}

fn media(app: &mut App, a: &[Value]) -> Value {
    app.osd_show(Kind::Media, a[0].str());
    text("ok")
}

fn close(app: &mut App, _: &[Value]) -> Value {
    app.osd_close();
    text("ok")
}

fn state(app: &mut App, _: &[Value]) -> Value {
    text(app.osd_state())
}

pub fn target() -> Target<App> {
    Target {
        name: "osd",
        functions: vec![
            Function { name: "volume", params: &[], ret: Type::String, call: volume },
            Function { name: "brightness", params: &[], ret: Type::String, call: show_brightness },
            Function { name: "media", params: &[("text", Type::String)], ret: Type::String, call: media },
            Function { name: "close", params: &[], ret: Type::String, call: close },
            Function { name: "state", params: &[], ret: Type::String, call: state },
        ],
    }
}
