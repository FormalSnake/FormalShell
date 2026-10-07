//! `monitor`, MonitorIpc.qml's `status`, `gpu`, `processes`, `kill` and
//! `restart`. A reply is whatever the last tick left, never a wait for a
//! fresh one; each read also asks for the poll for a grace period (QML's
//! subscribe/unsubscribe pulse), so a caller with no monitor cell on the bar
//! finds data on its next call. A signal answers that it was sent, and its
//! own exit status lands in the next `processes` reply's `lastAction`.
//! `launch` and `mode` join with the launcher's monitor view.

use super::registry::{Function, Target, Type, Value};
use crate::services::info::monitor::now_ms;
use crate::services::info::procs;
use crate::services::wants::{self, Source};
use crate::wayland::App;

fn status(app: &mut App, _: &[Value]) -> Value {
    wants::pulse(Source::Monitor);
    Value::Str(app.store.info.monitor.status(now_ms()).to_string())
}

fn gpu(app: &mut App, _: &[Value]) -> Value {
    wants::pulse(Source::Monitor);
    Value::Str(app.store.info.monitor.gpu(now_ms()).to_string())
}

fn processes(app: &mut App, args: &[Value]) -> Value {
    wants::pulse(Source::Processes);
    Value::Str(app.store.info.procs.report(args[0].str(), now_ms()).to_string())
}

fn signal(app: &mut App, args: &[Value]) -> Value {
    Value::Str(match procs::begin_signal(args[0].str(), args[1].str()) {
        Ok((n, sig)) => {
            if let Some(rt) = &app.runtime {
                rt.service(move |ctx| procs::run_signal(ctx, n, sig));
            }
            format!("ok: {sig} sent to {n}")
        }
        Err(e) => e,
    })
}

fn restart(app: &mut App, args: &[Value]) -> Value {
    let pid = args[0].str();
    let kernel = fs_system::monitor::procs::parse_pid(pid).and_then(|n| app.store.info.procs.row(n)).is_some_and(|r| r.kernel);
    Value::Str(match procs::begin_restart(pid, kernel) {
        Ok(n) => {
            if let Some(rt) = &app.runtime {
                rt.service(move |ctx| procs::run_restart(ctx, n));
            }
            format!("ok: restarting {n}")
        }
        Err(e) => e,
    })
}

pub fn target() -> Target<App> {
    Target {
        name: "monitor",
        functions: vec![
            Function { name: "status", params: &[], ret: Type::String, call: status },
            Function { name: "processes", params: &[("query", Type::String)], ret: Type::String, call: processes },
            Function { name: "kill", params: &[("pid", Type::String), ("signal", Type::String)], ret: Type::String, call: signal },
            Function { name: "restart", params: &[("pid", Type::String)], ret: Type::String, call: restart },
            Function { name: "gpu", params: &[], ret: Type::String, call: gpu },
        ],
    }
}
