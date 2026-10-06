//! IPC. The transport runs on the service thread and hands each call to
//! the UI thread as a [`Msg::Call`]; [`dispatch`] answers it there, where
//! the store and the surfaces live.
//!
//! Until Task 4 lands the `formalshell-ipc` contract, the transport is R0's
//! `ctl` socket and the only verbs are the spike's (`App::command`). Task 4
//! replaces [`serve`] and [`ctl`] and registers each target in [`dispatch`].

pub mod ctl;

use std::os::unix::net::UnixListener;

use async_io::Async;
use futures_lite::{AsyncReadExt, AsyncWriteExt};

use crate::runtime::{Ctx, Msg};
use crate::wayland::App;

pub struct Call {
    pub words: Vec<String>,
}

pub fn dispatch(app: &mut App, call: &Call) -> String {
    app.command(&call.words)
}

pub fn start(ctx: &Ctx) {
    ctx.spawn(serve(ctx.clone()));
}

async fn serve(ctx: Ctx) {
    let path = ctl::socket_path();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::remove_file(&path);
    let listener = match Async::<UnixListener>::bind(&path) {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("ctl: no control socket: {err}");
            return;
        }
    };
    loop {
        match listener.accept().await {
            Ok((stream, _)) => ctx.spawn(answer(ctx.clone(), stream)),
            Err(err) => eprintln!("ctl: accept: {err}"),
        }
    }
}

/// The client writes its line and shuts its half down, so the read ends
/// at EOF; a client that never does only stalls its own task.
async fn answer(ctx: Ctx, mut stream: Async<std::os::unix::net::UnixStream>) {
    let mut line = String::new();
    let reply = match stream.read_to_string(&mut line).await {
        Ok(_) => {
            let (tx, rx) = async_channel::bounded(1);
            let words = line.split_whitespace().map(str::to_owned).collect();
            ctx.publisher().send(Msg::Call(Call { words }, tx));
            rx.recv().await.unwrap_or_else(|_| "error: shell is exiting\n".into())
        }
        Err(err) => format!("error: {err}\n"),
    };
    let _ = stream.write_all(reply.as_bytes()).await;
}
