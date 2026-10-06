//! The spike's control socket: one line in, one line back. R1 replaces it
//! with the real IPC server.

use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::time::Duration;

pub fn socket_path() -> PathBuf {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    runtime.join("formalshell").join("rs.sock")
}

pub fn listen() -> std::io::Result<UnixListener> {
    let path = socket_path();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path)?;
    listener.set_nonblocking(true)?;
    Ok(listener)
}

/// Reads one request off a fresh connection. The client writes its line
/// and shuts its half down, so this never waits on the loop for long.
pub fn read_request(stream: &mut UnixStream) -> std::io::Result<String> {
    stream.set_nonblocking(false)?;
    stream.set_read_timeout(Some(Duration::from_millis(200)))?;
    let mut line = String::new();
    stream.read_to_string(&mut line)?;
    Ok(line)
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
