//! `localsend`, LocalsendIpc.qml: the receiver's and the last scan's
//! state, a scan, and one file sent to a peer the last scan found.

use super::registry::{Function, Target, Type, Value};
use crate::services::localsend::{self, Cmd, Payload};
use crate::wayland::App;

fn text(s: impl Into<String>) -> Value {
    Value::Str(s.into())
}

fn status(app: &mut App, _: &[Value]) -> Value {
    text(app.store.localsend.status())
}

fn peers(app: &mut App, _: &[Value]) -> Value {
    text(app.store.localsend.peers_json())
}

fn scan(app: &mut App, _: &[Value]) -> Value {
    if !app.store.localsend.installed {
        return text("error: localsend-cli is not installed");
    }
    localsend::command(Cmd::Scan { force: true });
    text("ok")
}

fn send(app: &mut App, a: &[Value]) -> Value {
    let name = a[0].str();
    let Some(peer) = fs_devices::localsend::resolve_peer(&app.store.localsend.peers, name).cloned() else {
        let body = format!("'{name}' is not in the last scan, rescan and try again");
        app.store.notifications.notify("LOCALSEND FAILED", &body, fs_info::notifications::Urgency::Critical);
        crate::surfaces::changed(app, crate::store::Topic::Notifications);
        return text(format!("error: unknown peer '{name}'"));
    };
    localsend::command(Cmd::Send { peer, payload: Payload::Path(a[1].str().to_owned()) });
    text("ok")
}

pub fn target() -> Target<App> {
    Target {
        name: "localsend",
        functions: vec![
            Function { name: "status", params: &[], ret: Type::String, call: status },
            Function { name: "peers", params: &[], ret: Type::String, call: peers },
            Function { name: "scan", params: &[], ret: Type::String, call: scan },
            Function { name: "send", params: &[("peer", Type::String), ("path", Type::String)], ret: Type::String, call: send },
        ],
    }
}
