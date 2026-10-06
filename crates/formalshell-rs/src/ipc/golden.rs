//! `tests/ipc-golden.jsonl`, recorded off the built `qs` by
//! `dev/ipc-golden.sh`, replayed through the client's parsing and the
//! registry against the same stub handlers that script serves.

use serde::Deserialize;

use super::cli;
use super::registry::{Function, Registry, Target, Type, Value};
use super::wire::Request;

#[derive(Deserialize)]
struct Case {
    argv: Vec<String>,
    live: bool,
    stdout: String,
    stderr: String,
    exit: i32,
}

fn s(v: impl Into<String>) -> Value {
    Value::Str(v.into())
}

/// How a JS string concatenation prints a number.
fn js_number(v: f64) -> String {
    if v.is_nan() {
        "NaN".into()
    } else if v.is_infinite() {
        if v > 0.0 { "Infinity".into() } else { "-Infinity".into() }
    } else {
        v.to_string()
    }
}

const fn f(name: &'static str, params: &'static [(&'static str, Type)], ret: Type, call: fn(&mut (), &[Value]) -> Value) -> Function<()> {
    Function { name, params, ret, call }
}

const STR: (&str, Type) = ("a", Type::String);

/// dev/ipc-golden.sh's shell.qml, function for function.
fn stub() -> Registry<()> {
    Registry {
        targets: vec![
            Target {
                name: "debug",
                functions: vec![
                    f("dump", &[], Type::String, |_, _| s("{}")),
                    f("join", &[("edge", Type::String), ("x", Type::Int), ("width", Type::Int)], Type::String, |_, a| {
                        s(format!("join {} {} {}", a[0].str(), a[1].int(), a[2].int()))
                    }),
                    f("joinClear", &[], Type::String, |_, _| s("ok")),
                    f("motionScale", &[("percent", Type::Int)], Type::String, |_, a| s(format!("ms {}", a[0].int()))),
                    f("query", &[("q", Type::String)], Type::String, |_, a| {
                        s(serde_json::to_string(&[a[0].str()]).unwrap())
                    }),
                ],
            },
            Target {
                name: "theme",
                functions: vec![
                    f("retheme", &[], Type::String, |_, _| s("ok")),
                    f("mode", &[("m", Type::String)], Type::String, |_, a| s(format!("mode {}", a[0].str()))),
                    f("status", &[], Type::String, |_, _| s("{}")),
                ],
            },
            Target {
                name: "wallpaper",
                functions: vec![
                    f("set", &[("path", Type::String)], Type::String, |_, a| s(format!("set {}", a[0].str()))),
                    f("get", &[], Type::String, |_, _| s("")),
                ],
            },
            Target {
                name: "bar",
                functions: vec![
                    f("chevron", &[("action", Type::String)], Type::String, |_, a| s(format!("chevron {}", a[0].str()))),
                    f("chevronAt", &[("action", Type::String), ("region", Type::String)], Type::String, |_, a| {
                        s(format!("chevronAt {} {}", a[0].str(), a[1].str()))
                    }),
                    f("room", &[], Type::String, |_, _| s("[]")),
                    f("paint", &[], Type::String, |_, _| s("[]")),
                ],
            },
            Target {
                name: "panel",
                functions: vec![
                    f("open", &[("name", Type::String)], Type::String, |_, a| s(format!("open {}", a[0].str()))),
                    f("close", &[], Type::String, |_, _| s("ok")),
                    f("toggle", &[("name", Type::String)], Type::String, |_, a| s(format!("toggle {}", a[0].str()))),
                    f("toggleAt", &[("n", Type::Int)], Type::String, |_, a| s(format!("toggleAt {}", a[0].int()))),
                    f("state", &[], Type::String, |_, _| s("")),
                ],
            },
            Target { name: "media", functions: vec![f("status", &[], Type::String, |_, _| s("{}"))] },
            Target {
                name: "overnight",
                functions: vec![
                    f("toggle", &[], Type::String, |_, _| s("ok")),
                    f("enable", &[], Type::String, |_, _| s("ok")),
                    f("disable", &[], Type::String, |_, _| s("ok")),
                    f("status", &[], Type::String, |_, _| s("{}")),
                ],
            },
            Target {
                name: "earbuds",
                functions: vec![
                    f("status", &[], Type::String, |_, _| s("{}")),
                    f("devices", &[], Type::String, |_, _| s("[]")),
                    f("select", &[("key", Type::String)], Type::String, |_, a| s(format!("select {}", a[0].str()))),
                    f("set", &[("control", Type::String), ("value", Type::String)], Type::String, |_, a| {
                        s(format!("set {} {}", a[0].str(), a[1].str()))
                    }),
                ],
            },
            Target {
                name: "probe",
                functions: vec![
                    f("s", &[STR], Type::String, |_, a| s(format!("[{}]", a[0].str()))),
                    f("ss", &[STR, ("b", Type::String)], Type::String, |_, a| {
                        s(format!("[{}][{}]", a[0].str(), a[1].str()))
                    }),
                    f("sss", &[STR, ("b", Type::String), ("c", Type::String)], Type::String, |_, a| {
                        s(format!("[{}][{}][{}]", a[0].str(), a[1].str(), a[2].str()))
                    }),
                    f("i", &[("a", Type::Int)], Type::String, |_, a| s(a[0].int().to_string())),
                    f("b", &[("a", Type::Bool)], Type::String, |_, a| s(a[0].bool().to_string())),
                    f("r", &[("a", Type::Real)], Type::String, |_, a| s(js_number(if let Value::Real(r) = a[0] { r } else { 0.0 }))),
                    f("ri", &[("a", Type::Real)], Type::Real, |_, a| a[0].clone()),
                    f("ii", &[("a", Type::Int)], Type::Int, |_, a| a[0].clone()),
                    f("bb", &[("a", Type::Bool)], Type::Bool, |_, a| a[0].clone()),
                    f("v", &[], Type::Void, |_, _| Value::Void),
                    f("empty", &[], Type::String, |_, _| s("")),
                    f("nl", &[], Type::String, |_, _| s("a\nb\n")),
                    f("show", &[], Type::String, |_, _| s("probe-show")),
                    f("call", &[], Type::String, |_, _| s("probe-call")),
                ],
            },
        ],
    }
}

/// stdout, stderr and the exit code, as formalshell-ipc would leave them.
fn run(registry: &Registry<()>, argv: &[String], live: bool) -> (String, String, i32, bool) {
    let request = match cli::parse(argv) {
        Ok(request) => request,
        Err(err) => return (String::new(), err.stderr(), err.exit, false),
    };
    if !live {
        return ("No running instances for \"\"\n".into(), String::new(), 255, false);
    }
    let listing = matches!(request, Request::Show { .. });
    if let Some(message) = cli::missing(&request) {
        return (message.into(), String::new(), 0, listing);
    }
    (registry.answer(&mut (), &request), String::new(), 0, listing)
}

/// The quoted path is the instance's own, so only the words around it are
/// held.
fn no_instance(text: &str) -> bool {
    text.starts_with("No running instances for \"") && text.ends_with("\"\n")
}

/// qs lists targets and functions out of a hash; the set is what holds.
fn sorted(text: &str) -> Vec<&str> {
    let mut lines: Vec<&str> = text.lines().collect();
    lines.sort();
    lines
}

#[test]
fn matches_qs_ipc() {
    let registry = stub();
    let cases: Vec<Case> = include_str!("../../tests/ipc-golden.jsonl")
        .lines()
        .map(|line| serde_json::from_str(line).expect("a golden line"))
        .collect();
    assert!(cases.len() > 100, "only {} golden cases", cases.len());
    for case in &cases {
        let (stdout, stderr, exit, listing) = run(&registry, &case.argv, case.live);
        let what = format!("{:?} live={}", case.argv, case.live);
        assert_eq!(exit, case.exit, "exit code of {what}");
        assert_eq!(stderr, case.stderr, "stderr of {what}");
        if !case.live {
            assert!(no_instance(&stdout) && no_instance(&case.stdout), "stdout of {what}: {stdout:?}");
        } else if listing {
            assert_eq!(sorted(&stdout), sorted(&case.stdout), "stdout of {what}");
        } else {
            assert_eq!(stdout, case.stdout, "stdout of {what}");
        }
    }
}

/// Each real target declares every one of its QML handler's functions
/// exactly as the stub above does.
#[test]
fn signatures_match_qml() {
    let stub = stub();
    for real in [
        super::debug::target(),
        super::theme::target(),
        super::theme::wallpaper(),
        super::bar::target(),
        super::panel::target(),
        super::media::target(),
        super::overnight::target(),
        super::earbuds::target(),
    ] {
        let defs: Vec<String> = real.functions.iter().map(|f| f.definition()).collect();
        let qml = stub.targets.iter().find(|t| t.name == real.name).expect("a stub target");
        for function in &qml.functions {
            assert!(defs.contains(&function.definition()), "{} lacks {}", real.name, function.definition());
        }
    }
}
