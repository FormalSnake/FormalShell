//! Hyprland's two sockets: `.socket.sock` answers one request per
//! connection, `.socket2.sock` streams `EVENT>>DATA` lines.

use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

use serde::Deserialize;

fn socket_dir() -> io::Result<PathBuf> {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "XDG_RUNTIME_DIR is not set"))?;
    let sig = std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE")
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "HYPRLAND_INSTANCE_SIGNATURE is not set"))?;
    Ok(PathBuf::from(runtime).join("hypr").join(sig))
}

pub fn request(command: &str) -> io::Result<String> {
    let mut stream = UnixStream::connect(socket_dir()?.join(".socket.sock"))?;
    stream.write_all(command.as_bytes())?;
    let mut out = String::new();
    stream.read_to_string(&mut out)?;
    Ok(out)
}

pub fn events() -> io::Result<UnixStream> {
    let stream = UnixStream::connect(socket_dir()?.join(".socket2.sock"))?;
    stream.set_nonblocking(true)?;
    Ok(stream)
}

/// Splits a byte stream into complete lines, carrying a partial tail over.
#[derive(Default)]
pub struct LineBuffer(Vec<u8>);

impl LineBuffer {
    pub fn feed(&mut self, bytes: &[u8]) -> Vec<String> {
        self.0.extend_from_slice(bytes);
        let mut lines = Vec::new();
        while let Some(at) = self.0.iter().position(|b| *b == b'\n') {
            let line: Vec<u8> = self.0.drain(..=at).collect();
            lines.push(String::from_utf8_lossy(&line[..line.len() - 1]).into_owned());
        }
        lines
    }
}

/// The events after which the workspace strip can look different.
pub fn touches_workspaces(line: &str) -> bool {
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
pub fn slots(persistent: i64) -> io::Result<Vec<Slot>> {
    let workspaces: Vec<RawWorkspace> = serde_json::from_str(&request("j/workspaces")?)?;
    let active: RawActive = serde_json::from_str(&request("j/activeworkspace")?)?;
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
