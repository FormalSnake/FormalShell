//! `debug`, DebugIpc.qml's verbs as far as this shell can answer them, and
//! the R0 spike's animation switches (`r0*`) until real targets replace
//! them.

use fs_chrome::types::Edge;
use serde_json::json;

use super::registry::{Function, Target, Type, Value};
use crate::scene::IRect;
use crate::theme;
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

/// Only what this shell holds, keyed and ordered as DebugIpc.qml's dump:
/// the compositor block, the settings, the strip, its join and the chrome
/// numbers. Every other key waits for the service behind it.
fn dump(app: &mut App, _: &[Value]) -> Value {
    let h = &app.store.hyprland;
    let c = &h.compositor;
    let edge = app.bar.edge();
    let thickness = crate::surfaces::bar::thickness(edge);
    let inset = |e: Edge| if e == edge { thickness } else { 0 };
    let rect = |r: IRect| json!({"x": r.x, "y": r.y, "width": r.w, "height": r.h});
    let reach = theme::radius_xl() as i32;
    let screen = app.bar_output_name();
    let join = match app.debug_join() {
        Some((x, width)) => json!({"edge": edge.as_str(), "x": x, "width": width, "reach": reach, "screen": screen}),
        None => serde_json::Value::Null,
    };
    let [first, second] = app.bar.line_rects();
    let dump = json!({
        "compositor": "hyprland",
        "available": c.available,
        "workspaces": c.workspaces,
        "windows": c.windows,
        "focusedWindowId": c.focused_window_id,
        "heldFocusedWindowId": h.held_focused_window_id(),
        "focusedWorkspaceId": c.focused_workspace_id,
        "fullscreenOutputs": c.fullscreen_outputs,
        "configLoaded": app.store.config.settings(),
        "bar": [{"screen": screen, "edge": edge.as_str(), "line": [rect(first), rect(second)], "paint": null}],
        "join": join,
        "theme": {
            "radius": theme::RADIUS_BASE as i32,
            "radiusXl": reach,
            "borderWidth": theme::EDGE_WIDTH,
            "barPosition": edge.as_str(),
            "edgeInset": {
                "top": inset(Edge::Top),
                "bottom": inset(Edge::Bottom),
                "left": inset(Edge::Left),
                "right": inset(Edge::Right),
            },
        },
    });
    text(dump.to_string())
}

fn join(app: &mut App, args: &[Value]) -> Value {
    let (edge, x, width) = (args[0].str(), args[1].int(), args[2].int());
    if !["top", "bottom", "left", "right"].contains(&edge) {
        return text(format!("error: unknown edge '{edge}' (top|bottom|left|right)"));
    }
    if width <= 0 {
        return text("error: width must be positive");
    }
    // A join on an edge the strip is not on has no line to open, as under
    // QML with no bar on that edge.
    app.set_debug_join((edge == app.bar.edge().as_str()).then_some((x, width)));
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
    app.bar.motion_scale = app.motion_scale;
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
