//! The compositor backend, BackendBase.qml's contract on Hyprland's two raw
//! sockets: `.socket.sock` answers one request per connection,
//! `.socket2.sock` streams `EVENT>>DATA` lines. Every write is an `hl.*`
//! Lua call, a dispatcher sent as `dispatch` and a monitor rule as `eval`.
//!
//! An event only marks the model dirty; one refresh re-reads it, so a burst
//! of events in one turn costs one round of requests.

// The whole contract lands here at once; its callers are the bar cells,
// panels and launcher routes R2 onward ports.
#![allow(dead_code)]

mod lua;
pub mod model;

use std::cell::RefCell;
use std::collections::HashSet;
use std::io;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::OnceLock;
use std::time::Duration;

use async_io::{Async, Timer};
use futures_lite::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, StreamExt, io::BufReader};
use fs_system::compositor::keyboard::{self, Layout};
use fs_system::display::outputs::{self, Color, Output, RuleOverrides};

use crate::runtime::Ctx;
use crate::store;
pub use model::{Snapshot, Window, Workspace};

/// The wait before the next attempt at a socket that is gone, doubling up
/// to the ceiling while it stays gone.
const RETRY_FIRST: Duration = Duration::from_millis(250);
const RETRY_MAX: Duration = Duration::from_secs(5);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OutputsState {
    Unknown,
    Ok,
    Failed,
}

impl OutputsState {
    pub fn as_str(self) -> &'static str {
        match self {
            OutputsState::Unknown => "unknown",
            OutputsState::Ok => "ok",
            OutputsState::Failed => "failed",
        }
    }
}

pub struct State {
    pub compositor: Snapshot,
    /// The last window the compositor reported focused, for focus.js's hold.
    pub remembered_focused_id: String,
    pub outputs: Vec<Output>,
    pub outputs_state: OutputsState,
    pub keyboard: Layout,
    /// False until the first answer (or failure) of the layout query, so a
    /// cell can tell "not asked yet" from "cannot be asked".
    pub keyboard_answered: bool,
    /// Counts `configreloaded`, the contract's `configReloaded` signal.
    pub config_reloads: u64,
}

impl Default for State {
    fn default() -> Self {
        Self {
            compositor: Snapshot::default(),
            remembered_focused_id: String::new(),
            outputs: Vec::new(),
            outputs_state: OutputsState::Unknown,
            keyboard: keyboard::unavailable(),
            keyboard_answered: false,
            config_reloads: 0,
        }
    }
}

pub enum Diff {
    Compositor(Snapshot),
    Outputs(Vec<Output>, OutputsState),
    Keyboard(Layout),
    ConfigReloaded,
}

impl State {
    pub fn apply(&mut self, diff: Diff) -> bool {
        match diff {
            Diff::Compositor(snapshot) => {
                if self.compositor == snapshot {
                    return false;
                }
                if !snapshot.focused_window_id.is_empty() {
                    self.remembered_focused_id = snapshot.focused_window_id.clone();
                }
                self.compositor = snapshot;
            }
            Diff::Outputs(rows, state) => {
                if self.outputs == rows && self.outputs_state == state {
                    return false;
                }
                (self.outputs, self.outputs_state) = (rows, state);
            }
            Diff::Keyboard(layout) => {
                let first = !std::mem::replace(&mut self.keyboard_answered, true);
                if self.keyboard == layout && !first {
                    return false;
                }
                self.keyboard = layout;
            }
            Diff::ConfigReloaded => self.config_reloads += 1,
        }
        true
    }

    pub fn held_focused_window_id(&self) -> String {
        let c = &self.compositor;
        model::held_focus(&c.focused_window_id, &self.remembered_focused_id, &c.windows, &c.focused_workspace_id)
    }

    pub fn window(&self, id: &str) -> Option<&Window> {
        self.compositor.windows.iter().find(|w| w.id == id)
    }
}

/// The writes, queued from any thread and run in order on the service
/// thread against the backend's own latest model.
pub enum Command {
    Dispatch(String),
    FloatWindow(String),
    PlaceFloatingWindow { id: String, x: f64, y: f64, width: f64, height: f64 },
    ParkWindow(String),
    UnparkWindow(String),
    RefreshWindows,
    RefreshOutputs,
    SetOutputEnabled(String, bool),
    SetOutputScale(String, f64),
    SetOutputMirror(String, String),
    SetOutputColor(String, Color),
}

static COMMANDS: OnceLock<async_channel::Sender<Command>> = OnceLock::new();

/// Dropped when the service has not started, as a write to a backend with
/// no compositor is in the QML shell.
pub fn send(command: Command) {
    if let Some(tx) = COMMANDS.get() {
        let _ = tx.try_send(command);
    }
}

pub fn focus_workspace(id: &str) {
    send(Command::Dispatch(lua::focus_workspace(id)));
}

/// By `idx`, for a persistent slot Hyprland has no workspace for yet: its
/// `workspace` dispatcher creates one.
pub fn focus_workspace_at(idx: i64) {
    if idx >= 1 {
        focus_workspace(&idx.to_string());
    }
}

pub fn focus_window(id: &str) {
    send(Command::Dispatch(lua::focus_window(id)));
}

pub fn close_window(id: &str) {
    send(Command::Dispatch(lua::close_window(id)));
}

pub fn spawn(argv: &[String]) {
    send(Command::Dispatch(lua::spawn(argv)));
}

pub fn power_off_monitors() {
    send(Command::Dispatch(lua::dpms(false)));
}

pub fn power_on_monitors() {
    send(Command::Dispatch(lua::dpms(true)));
}

/// On the special workspace and not on screen, or on another workspace than
/// the focused one. A window the backend has never heard of counts as
/// parked, so a console toggle asks for it to be brought here.
pub fn is_window_parked(state: &State, id: &str) -> bool {
    let c = &state.compositor;
    match state.window(id) {
        None => true,
        Some(w) if w.workspace_id.parse::<i64>().is_ok_and(|n| n < 0) => c.special_shown != lua::PARK_WORKSPACE,
        Some(w) => w.workspace_id != c.focused_workspace_id,
    }
}

fn socket_dir() -> io::Result<PathBuf> {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "XDG_RUNTIME_DIR is not set"))?;
    let sig = std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE")
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "HYPRLAND_INSTANCE_SIGNATURE is not set"))?;
    Ok(PathBuf::from(runtime).join("hypr").join(sig))
}

pub async fn request(command: &str) -> io::Result<String> {
    let mut stream = Async::<UnixStream>::connect(socket_dir()?.join(".socket.sock")).await?;
    stream.write_all(command.as_bytes()).await?;
    let mut out = String::new();
    stream.read_to_string(&mut out).await?;
    Ok(out)
}

/// What the tasks share, all on the one service thread.
#[derive(Default)]
struct Backend {
    snapshot: Snapshot,
    order: Vec<String>,
    urgent: HashSet<String>,
    outputs: Vec<Output>,
    keyboard: Option<Layout>,
}

type Shared = Rc<RefCell<Backend>>;

pub async fn run(ctx: Ctx) {
    if let Err(err) = socket_dir() {
        eprintln!("hyprland: {err}");
        return;
    }
    let shared: Shared = Rc::default();
    let (dirty_tx, dirty_rx) = async_channel::bounded::<()>(1);
    let (tx, rx) = async_channel::unbounded();
    let _ = COMMANDS.set(tx);

    ctx.spawn(refresher(ctx.clone(), shared.clone(), dirty_rx));
    ctx.spawn(commands(ctx.clone(), shared.clone(), rx, dirty_tx.clone()));
    events(ctx, shared, dirty_tx).await;
}

/// The event stream, reconnected for as long as the shell runs: a Hyprland
/// that restarts its socket comes back to a full re-read.
async fn events(ctx: Ctx, shared: Shared, dirty: async_channel::Sender<()>) {
    let mut wait = RETRY_FIRST;
    let mut connected_once = false;
    loop {
        let stream = match socket_dir() {
            Ok(dir) => Async::<UnixStream>::connect(dir.join(".socket2.sock")).await,
            Err(err) => Err(err),
        };
        let stream = match stream {
            Ok(stream) => stream,
            Err(err) => {
                if wait == RETRY_FIRST {
                    eprintln!("hyprland: no event socket: {err}");
                }
                Timer::after(wait).await;
                wait = (wait * 2).min(RETRY_MAX);
                continue;
            }
        };
        if connected_once {
            eprintln!("hyprland: event socket reconnected");
        }
        connected_once = true;
        wait = RETRY_FIRST;
        let _ = dirty.try_send(());
        refresh_outputs(&ctx, &shared).await;
        refresh_keyboard(&ctx, &shared).await;

        let mut lines = BufReader::new(stream).lines();
        while let Some(line) = lines.next().await {
            let Ok(line) = line else { break };
            let (name, data) = line.split_once(">>").unwrap_or((line.as_str(), ""));
            match name {
                "urgent" => {
                    if let Some(id) = model::address_id(data) {
                        shared.borrow_mut().urgent.insert(id);
                    }
                }
                "activelayout" => {
                    let next = shared.borrow().keyboard.as_ref().map(|k| keyboard::apply_active_layout(k, data));
                    if let Some(layout) = next {
                        shared.borrow_mut().keyboard = Some(layout.clone());
                        ctx.publish(store::Diff::Hyprland(Diff::Keyboard(layout)));
                    }
                }
                "configreloaded" => {
                    ctx.publish(store::Diff::Hyprland(Diff::ConfigReloaded));
                    refresh_outputs(&ctx, &shared).await;
                    refresh_keyboard(&ctx, &shared).await;
                }
                "monitoradded" | "monitoraddedv2" | "monitorremoved" | "monitorremovedv2" => {
                    refresh_outputs(&ctx, &shared).await;
                }
                _ => {}
            }
            if !model::ignores(name) {
                let _ = dirty.try_send(());
            }
        }
        eprintln!("hyprland: event socket closed");
        // Gone until it answers again: the honest unavailable state, not
        // the last model it reported.
        shared.borrow_mut().snapshot = Snapshot::default();
        ctx.publish(store::Diff::Hyprland(Diff::Compositor(Snapshot::default())));
    }
}

async fn refresher(ctx: Ctx, shared: Shared, dirty: async_channel::Receiver<()>) {
    while dirty.recv().await.is_ok() {
        refresh_compositor(&ctx, &shared).await;
    }
}

async fn refresh_compositor(ctx: &Ctx, shared: &Shared) {
    let read = async {
        let monitors = request("j/monitors").await?;
        let workspaces = request("j/workspaces").await?;
        let clients = request("j/clients").await?;
        let active = request("j/activewindow").await?;
        io::Result::Ok((monitors, workspaces, clients, active))
    };
    let (monitors, workspaces, clients, active) = match read.await {
        Ok(answers) => answers,
        Err(err) => {
            eprintln!("hyprland: refresh: {err}");
            return;
        }
    };
    let snapshot = {
        let mut b = shared.borrow_mut();
        let mut snapshot = model::snapshot(&monitors, &workspaces, &clients, &active, &b.urgent);
        snapshot.windows = model::keep_order(&mut b.order, snapshot.windows);
        let live: HashSet<&str> = snapshot.windows.iter().filter(|w| w.is_urgent).map(|w| w.id.as_str()).collect();
        b.urgent.retain(|id| live.contains(id.as_str()));
        b.snapshot = snapshot.clone();
        snapshot
    };
    ctx.publish(store::Diff::Hyprland(Diff::Compositor(snapshot)));
}

/// `monitors all`: the only enumeration that lists a disabled output, which
/// is the one the display panel needs to switch back on.
async fn refresh_outputs(ctx: &Ctx, shared: &Shared) {
    let (rows, state) = match request("j/monitors all").await {
        Ok(text) => (outputs::parse_hyprland_outputs(&text), OutputsState::Ok),
        Err(err) => {
            eprintln!("hyprland: outputs: {err}");
            (Vec::new(), OutputsState::Failed)
        }
    };
    crate::services::display::outputs_changed(ctx, &rows);
    shared.borrow_mut().outputs = rows.clone();
    ctx.publish(store::Diff::Hyprland(Diff::Outputs(rows, state)));
}

async fn refresh_keyboard(ctx: &Ctx, shared: &Shared) {
    let layout = match request("j/devices").await {
        Ok(text) => keyboard::parse_hyprland_layouts(&text),
        Err(_) => keyboard::unavailable(),
    };
    shared.borrow_mut().keyboard = Some(layout.clone());
    ctx.publish(store::Diff::Hyprland(Diff::Keyboard(layout)));
}

async fn dispatch(lua: &str) {
    report("dispatch", request(&format!("dispatch {lua}")).await);
}

/// Monitor rules are config calls rather than dispatchers; `hyprctl eval`
/// is the documented way in under a Lua config.
async fn eval(ctx: &Ctx, lua: &str) {
    let lua = lua.to_owned();
    let out = ctx.pool().run(move || std::process::Command::new("hyprctl").args(["eval", &lua]).output()).await;
    let answer = match out {
        Some(Ok(out)) if out.status.success() => Ok(String::from_utf8_lossy(&out.stdout).into_owned()),
        Some(Ok(out)) => Ok(String::from_utf8_lossy(&out.stderr).into_owned()),
        Some(Err(err)) => Err(err),
        None => Err(io::Error::other("the blocking pool is gone")),
    };
    report("eval", answer);
}

fn report(what: &str, answer: io::Result<String>) {
    match answer {
        Ok(text) if text.trim() == "ok" => {}
        Ok(text) => eprintln!("hyprland: {what}: {}", text.trim()),
        Err(err) => eprintln!("hyprland: {what}: {err}"),
    }
}

async fn commands(
    ctx: Ctx,
    shared: Shared,
    rx: async_channel::Receiver<Command>,
    dirty: async_channel::Sender<()>,
) {
    while let Ok(command) = rx.recv().await {
        match command {
            Command::Dispatch(lua) => dispatch(&lua).await,
            Command::FloatWindow(id) => {
                let floating = shared.borrow().snapshot.windows.iter().any(|w| w.id == id && w.is_floating);
                if !floating {
                    dispatch(&lua::float_window(&id)).await;
                }
            }
            Command::PlaceFloatingWindow { id, x, y, width, height } => {
                let (w, h) = ((width.round() as i64).max(1), (height.round() as i64).max(1));
                dispatch(&lua::resize_window(&id, w, h)).await;
                dispatch(&lua::move_window(&id, x.round() as i64, y.round() as i64)).await;
            }
            Command::ParkWindow(id) => park(&ctx, &shared, &id, false).await,
            Command::UnparkWindow(id) => park(&ctx, &shared, &id, true).await,
            Command::RefreshWindows => {
                let _ = dirty.try_send(());
            }
            Command::RefreshOutputs => refresh_outputs(&ctx, &shared).await,
            Command::SetOutputEnabled(name, enabled) => {
                eval(&ctx, &outputs::hyprland_enabled_lua(&name, enabled)).await;
                refresh_outputs(&ctx, &shared).await;
            }
            Command::SetOutputScale(name, scale) => {
                let row = outputs::find_output(&shared.borrow().outputs, &name).cloned();
                if let Some(row) = row {
                    let overrides = RuleOverrides { scale: Some(scale), mirror_of: None };
                    eval(&ctx, &outputs::hyprland_rule_lua(&outputs::hyprland_monitor_rule(&row, &overrides))).await;
                    refresh_outputs(&ctx, &shared).await;
                }
            }
            Command::SetOutputMirror(name, source) => {
                let row = outputs::find_output(&shared.borrow().outputs, &name).cloned();
                if let Some(row) = row {
                    let overrides = RuleOverrides { scale: None, mirror_of: Some(source) };
                    eval(&ctx, &outputs::hyprland_rule_lua(&outputs::hyprland_monitor_rule(&row, &overrides))).await;
                    refresh_outputs(&ctx, &shared).await;
                }
            }
            Command::SetOutputColor(name, color) => {
                let row = outputs::find_output(&shared.borrow().outputs, &name).cloned();
                if let Some(row) = row.filter(|r| r.enabled) {
                    eval(&ctx, &outputs::hyprland_rule_lua(&outputs::hyprland_color_rule(&row, &color))).await;
                    refresh_outputs(&ctx, &shared).await;
                }
            }
        }
    }
}

/// The console lives on its special workspace for good; showing it is the
/// compositor's own toggle of that workspace. `show` false parks it.
async fn park(ctx: &Ctx, shared: &Shared, id: &str, show: bool) {
    let on_special = shared
        .borrow()
        .snapshot
        .windows
        .iter()
        .any(|w| w.id == id && w.workspace_id.parse::<i64>().is_ok_and(|n| n < 0));
    if !on_special {
        dispatch(&lua::park_window(id)).await;
    }
    let shown = shared.borrow().snapshot.special_shown == lua::PARK_WORKSPACE;
    if shown != show {
        dispatch(&lua::toggle_special()).await;
        refresh_compositor(ctx, shared).await;
    }
}
