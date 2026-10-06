//! A child a service runs once and reads whole: argv in, exit code and
//! stdout out. A missing binary reads as exit 127, the way `sh -c 'command
//! -v x || exit 127'` reports it, so a poll has one failure vocabulary.

use std::io::ErrorKind;
use std::time::Duration;

use async_io::Timer;
use futures_lite::{AsyncReadExt, FutureExt};

pub const MISSING: i32 = 127;
pub const TIMED_OUT: i32 = 124;

pub struct Done {
    pub code: i32,
    pub stdout: String,
}

pub fn argv(parts: &[&str]) -> Vec<String> {
    parts.iter().map(|p| (*p).to_owned()).collect()
}

/// Dropping the future kills the child.
pub async fn capture(argv: &[String], timeout: Duration) -> Done {
    let Some((program, args)) = argv.split_first() else { return Done { code: MISSING, stdout: String::new() } };
    let child = async_process::Command::new(program)
        .args(args)
        .stdin(async_process::Stdio::null())
        .stdout(async_process::Stdio::piped())
        .stderr(async_process::Stdio::null())
        .kill_on_drop(true)
        .spawn();
    let mut child = match child {
        Ok(child) => child,
        Err(err) => {
            let code = if err.kind() == ErrorKind::NotFound { MISSING } else { -1 };
            return Done { code, stdout: String::new() };
        }
    };
    let mut stdout = child.stdout.take();
    let run = async {
        let mut raw = Vec::new();
        if let Some(out) = stdout.as_mut() {
            let _ = out.read_to_end(&mut raw).await;
        }
        let code = child.status().await.ok().and_then(|s| s.code()).unwrap_or(-1);
        Done { code, stdout: String::from_utf8_lossy(&raw).into_owned() }
    };
    let expired = async {
        Timer::after(timeout).await;
        Done { code: TIMED_OUT, stdout: String::new() }
    };
    run.or(expired).await
}
