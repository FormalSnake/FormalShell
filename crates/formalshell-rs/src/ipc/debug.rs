//! `debug`, DebugIpc.qml's verbs as far as this shell can answer them, and
//! the R0 spike's animation switches (`r0*`) until real targets replace
//! them.

use super::registry::{Function, Target, Type, Value};
use crate::wayland::App;

fn text(s: impl Into<String>) -> Value {
    Value::Str(s.into())
}

fn ok() -> Value {
    text("ok")
}

pub fn target() -> Target<App> {
    Target {
        name: "debug",
        functions: vec![
            Function { name: "dump", params: &[], ret: Type::String, call: dump },
            Function {
                name: "join",
                params: &[("edge", Type::String), ("x", Type::Int), ("width", Type::Int)],
                ret: Type::String,
                call: join,
            },
            Function { name: "joinClear", params: &[], ret: Type::String, call: join_clear },
            Function { name: "motionScale", params: &[("percent", Type::Int)], ret: Type::String, call: motion_scale },
            // No launcher yet: DebugIpc.qml's own answer with no menu instance.
            Function { name: "query", params: &[("q", Type::String)], ret: Type::String, call: |_, _| text("[]") },
            Function { name: "r0Spinner", params: &[("on", Type::Bool)], ret: Type::String, call: r0_spinner },
            Function { name: "r0Panel", params: &[("action", Type::String)], ret: Type::String, call: r0_panel },
            Function { name: "r0Scrim", params: &[("on", Type::Bool)], ret: Type::String, call: r0_scrim },
            Function { name: "r0Cast", params: &[("on", Type::Bool)], ret: Type::String, call: r0_cast },
        ],
    }
}

/// Only what this shell holds: the join on its one top strip and the
/// chrome numbers it draws with, keyed and ordered as DebugIpc.qml's dump.
/// Every other key waits for the service behind it.
fn dump(app: &mut App, _: &[Value]) -> Value {
    let theme = app.theme();
    let reach = theme.radii.xl;
    let (radius, border, inset) = (theme.radius, theme.border_width, theme.space.bar_cell_height + theme.space.bar_margin * 2.0);
    let join = match app.debug_join() {
        Some((x, width)) => format!(r#"{{"edge":"top","x":{x},"width":{width},"reach":{reach}}}"#),
        None => "null".into(),
    };
    text(format!(
        r#"{{"join":{join},"theme":{{"radius":{},"radiusXl":{reach},"borderWidth":{},"barPosition":"top","edgeInset":{}}}}}"#,
        radius,
        border,
        inset,
    ))
}

fn join(app: &mut App, args: &[Value]) -> Value {
    let (edge, x, width) = (args[0].str(), args[1].int(), args[2].int());
    if !["top", "bottom", "left", "right"].contains(&edge) {
        return text(format!("error: unknown edge '{edge}' (top|bottom|left|right)"));
    }
    if width <= 0 {
        return text("error: width must be positive");
    }
    // The strip only exists on the top edge, so a join on any other has
    // no line to open, as under QML with no bar on that edge.
    app.set_debug_join((edge == "top").then_some((x, width)));
    ok()
}

fn join_clear(app: &mut App, _: &[Value]) -> Value {
    app.set_debug_join(None);
    ok()
}

fn motion_scale(app: &mut App, args: &[Value]) -> Value {
    let percent = args[0].int();
    if !(1..=5000).contains(&percent) {
        return text("error: percent must be 1..5000");
    }
    app.motion_scale = percent as f64 / 100.0;
    ok()
}

fn r0_spinner(app: &mut App, args: &[Value]) -> Value {
    app.bar.set_spinner(std::time::Instant::now(), args[0].bool());
    ok()
}

fn r0_panel(app: &mut App, args: &[Value]) -> Value {
    let open = match args[0].str() {
        "open" => true,
        "close" => false,
        "toggle" => !app.panel_open(),
        other => return text(format!("error: unknown action '{other}' (open|close|toggle)")),
    };
    app.set_panel(std::time::Instant::now(), open);
    ok()
}

fn r0_scrim(app: &mut App, args: &[Value]) -> Value {
    app.set_scrim(std::time::Instant::now(), args[0].bool());
    ok()
}

fn r0_cast(app: &mut App, args: &[Value]) -> Value {
    app.cast = args[0].bool();
    ok()
}
