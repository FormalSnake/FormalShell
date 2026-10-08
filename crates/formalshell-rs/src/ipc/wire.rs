//! What `formalshell-ipc` sends the shell: one JSON request, written before
//! the client shuts its half down. The reply is the text the client prints
//! on stdout, verbatim.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub enum Request {
    Call { target: String, function: String, args: Vec<String> },
    Show { target: String, name: String },
    Signal { target: String, signal: String },
    Prop { target: String, property: String },
}


/// One socket per Wayland display, like the instance lock: a nested
/// session's shell shares `XDG_RUNTIME_DIR` with the session it runs in,
/// and a socket keyed on that alone hands its calls to the outer shell.
pub fn socket_path() -> PathBuf {
    socket_dir().join(format!("ipc-{}.sock", display_key()))
}

/// The socket a client should reach. With no `WAYLAND_DISPLAY` (an ssh
/// shell, a cron job) it is whichever shell's socket was bound last.
pub fn client_socket_path() -> PathBuf {
    if std::env::var_os("WAYLAND_DISPLAY").is_some() {
        return socket_path();
    }
    let newest = std::fs::read_dir(socket_dir()).ok().and_then(|dir| {
        dir.flatten()
            .filter(|e| e.file_name().to_string_lossy().starts_with("ipc-"))
            .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
            .max()
            .map(|(_, path)| path)
    });
    newest.unwrap_or_else(socket_path)
}

fn socket_dir() -> PathBuf {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    runtime.join("formalshell")
}

fn display_key() -> String {
    std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "default".into()).replace('/', "_")
}
