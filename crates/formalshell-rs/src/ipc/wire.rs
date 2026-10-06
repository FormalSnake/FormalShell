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


pub fn socket_path() -> PathBuf {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    runtime.join("formalshell").join("ipc.sock")
}
