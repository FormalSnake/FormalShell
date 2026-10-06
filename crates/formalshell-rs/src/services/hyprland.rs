//! Hyprland's two sockets: `.socket.sock` answers one request per
//! connection, `.socket2.sock` streams `EVENT>>DATA` lines. Task 5 grows
//! this into the full backend; for now it keeps the bar's workspace slots.

use std::io;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

use async_io::Async;
use futures_lite::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, StreamExt, io::BufReader};
use serde::Deserialize;

use crate::runtime::Ctx;
use crate::store;
use crate::theme;

#[derive(Default)]
pub struct State {
    pub slots: Vec<Slot>,
}

pub enum Diff {
    Slots(Vec<Slot>),
}

impl State {
    pub fn apply(&mut self, diff: Diff) -> bool {
        let Diff::Slots(slots) = diff;
        if self.slots == slots {
            return false;
        }
        self.slots = slots;
        true
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

async fn publish_slots(ctx: &Ctx) {
    match slots(theme::PERSISTENT_WORKSPACES).await {
        Ok(slots) => ctx.publish(store::Diff::Hyprland(Diff::Slots(slots))),
        Err(err) => eprintln!("hyprland: workspaces unavailable: {err}"),
    }
}

pub async fn run(ctx: Ctx) {
    publish_slots(&ctx).await;
    let stream = match socket_dir() {
        Ok(dir) => Async::<UnixStream>::connect(dir.join(".socket2.sock")).await,
        Err(err) => Err(err),
    };
    let stream = match stream {
        Ok(stream) => stream,
        Err(err) => {
            eprintln!("hyprland: no event socket: {err}");
            return;
        }
    };
    let mut lines = BufReader::new(stream).lines();
    while let Some(line) = lines.next().await {
        match line {
            Ok(line) if touches_workspaces(&line) => publish_slots(&ctx).await,
            Ok(_) => {}
            Err(err) => {
                eprintln!("hyprland: event socket: {err}");
                return;
            }
        }
    }
    eprintln!("hyprland: event socket closed");
}

/// The events after which the workspace strip can look different.
fn touches_workspaces(line: &str) -> bool {
    let name = line.split(">>").next().unwrap_or("");
    matches!(
        name,
        "workspace" | "workspacev2" | "focusedmon" | "focusedmonv2" | "createworkspace"
            | "createworkspacev2" | "destroyworkspace" | "destroyworkspacev2" | "moveworkspace"
            | "moveworkspacev2" | "renameworkspace" | "openwindow" | "closewindow" | "movewindow"
            | "movewindowv2" | "urgent"
    )
}

#[derive(Deserialize)]
struct RawWorkspace {
    id: i64,
    windows: i64,
}

#[derive(Deserialize)]
struct RawActive {
    id: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Slot {
    pub idx: i64,
    pub focused: bool,
}

/// `Bar/workspaces.js`'s `visibleModel` for one output: occupied, focused,
/// or one of the persistent slots 1..n (a placeholder when Hyprland has no
/// such workspace yet). Special workspaces carry negative ids and stay off.
async fn slots(persistent: i64) -> io::Result<Vec<Slot>> {
    let workspaces: Vec<RawWorkspace> = serde_json::from_str(&request("j/workspaces").await?)?;
    let active: RawActive = serde_json::from_str(&request("j/activeworkspace").await?)?;
    let mut idxs: Vec<i64> = workspaces
        .iter()
        .filter(|w| w.id > 0 && (w.windows > 0 || w.id == active.id || w.id <= persistent))
        .map(|w| w.id)
        .collect();
    for n in 1..=persistent {
        if !idxs.contains(&n) {
            idxs.push(n);
        }
    }
    idxs.sort_unstable();
    Ok(idxs.into_iter().map(|idx| Slot { idx, focused: idx == active.id }).collect())
}
