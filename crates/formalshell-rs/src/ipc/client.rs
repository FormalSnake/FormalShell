//! The command line IPC client, shared by `formalshell-ipc` and
//! `formalshell ipc`: parse the words, send one request to the running
//! shell, print its reply verbatim.

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;

use super::{cli, wire};

/// Quickshell's `qs ipc` options, which the hyprland binds still pass. A
/// shell here is one per Wayland display, picked off `WAYLAND_DISPLAY`
/// (`wire::client_socket_path`), so the flags are read off and dropped.
///
/// Flags taking a value: `-p/--path`, `-c/--config`, `-i/--id`, `--pid`.
pub fn strip_instance_flags(argv: &[String]) -> Vec<String> {
    let mut i = 0;
    while i < argv.len() {
        match argv[i].as_str() {
            "--any-display" | "--newest" => {}
            "-p" | "--path" | "-c" | "--config" | "-i" | "--id" | "--pid" => i += 1,
            a if ["--path=", "--config=", "--id=", "--pid="].iter().any(|p| a.starts_with(p)) => {}
            _ => break,
        }
        i += 1;
    }
    argv[i.min(argv.len())..].to_vec()
}

/// Runs one client invocation and returns the process exit code.
pub fn run(argv: &[String]) -> i32 {
    let request = match cli::parse(&strip_instance_flags(argv)) {
        Ok(request) => request,
        Err(err) => {
            eprint!("{}", err.stderr());
            return err.exit;
        }
    };
    let path = wire::client_socket_path();
    let Ok(mut stream) = UnixStream::connect(&path) else {
        println!("No running instances for \"{}\"", path.display());
        return 255;
    };
    if let Some(message) = cli::missing(&request) {
        print!("{message}");
        return 0;
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
            0
        }
        Err(err) => {
            eprintln!("formalshell-ipc: {err}");
            255
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(words: &[&str]) -> Vec<String> {
        words.iter().map(|w| w.to_string()).collect()
    }

    #[test]
    fn host_form_drops_instance_flags() {
        let got = strip_instance_flags(&v(&["--any-display", "call", "menu", "toggle"]));
        assert_eq!(got, v(&["call", "menu", "toggle"]));
    }

    #[test]
    fn valued_flags_take_their_value() {
        let got = strip_instance_flags(&v(&["-p", "/x/shell", "--newest", "-i", "abc", "--pid=7", "call", "a", "b"]));
        assert_eq!(got, v(&["call", "a", "b"]));
    }

    #[test]
    fn flags_after_the_subcommand_are_left_alone() {
        let got = strip_instance_flags(&v(&["call", "a", "b", "--any-display"]));
        assert_eq!(got, v(&["call", "a", "b", "--any-display"]));
    }

    #[test]
    fn nothing_but_flags_leaves_nothing() {
        assert!(strip_instance_flags(&v(&["--any-display"])).is_empty());
    }
}
