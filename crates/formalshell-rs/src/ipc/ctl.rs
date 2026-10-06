//! The spike's control socket: one line in, one line back. Task 4's
//! `formalshell-ipc` replaces it.

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

pub fn socket_path() -> PathBuf {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    runtime.join("formalshell").join("rs.sock")
}

/// `formalshell-rs ctl <words...>`: the client half.
pub fn client(words: &[String]) -> i32 {
    let run = || -> std::io::Result<String> {
        let mut stream = UnixStream::connect(socket_path())?;
        stream.write_all(format!("{}\n", words.join(" ")).as_bytes())?;
        stream.shutdown(std::net::Shutdown::Write)?;
        let mut reply = String::new();
        stream.read_to_string(&mut reply)?;
        Ok(reply)
    };
    match run() {
        Ok(reply) => {
            print!("{reply}");
            if reply.starts_with("ok") { 0 } else { 1 }
        }
        Err(err) => {
            eprintln!("formalshell-rs ctl: {err}");
            1
        }
    }
}
