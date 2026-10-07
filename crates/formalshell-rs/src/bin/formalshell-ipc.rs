//! `formalshell-ipc <call|show|wait|listen|prop> ...`: the command line
//! client for the shell's IPC, printing replies as
//! `crates/formalshell-rs/tests/ipc-golden.jsonl` fixes them and exiting as
//! it exits.

#[path = "../ipc/cli.rs"]
mod cli;
#[path = "../ipc/wire.rs"]
mod wire;

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::process::exit;

fn main() {
    let argv: Vec<String> = std::env::args_os().skip(1).map(|a| a.to_string_lossy().into_owned()).collect();
    let request = match cli::parse(&argv) {
        Ok(request) => request,
        Err(err) => {
            eprint!("{}", err.stderr());
            exit(err.exit);
        }
    };
    let path = wire::socket_path();
    let Ok(mut stream) = UnixStream::connect(&path) else {
        println!("No running instances for \"{}\"", path.display());
        exit(255);
    };
    if let Some(message) = cli::missing(&request) {
        print!("{message}");
        return;
    }
    let mut exchange = || -> std::io::Result<String> {
        stream.write_all(&serde_json::to_vec(&request)?)?;
        stream.shutdown(std::net::Shutdown::Write)?;
        let mut reply = String::new();
        stream.read_to_string(&mut reply)?;
        Ok(reply)
    };
    match exchange() {
        Ok(reply) => {
            print!("{reply}");
            let _ = std::io::stdout().flush();
        }
        Err(err) => {
            eprintln!("formalshell-ipc: {err}");
            exit(255);
        }
    }
}
