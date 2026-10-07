//! IPC. The socket is served on the service thread, which reads each
//! request off its client and hands it to the UI thread as a
//! [`Msg::Call`]; [`dispatch`] answers it there, where the store and the
//! surfaces live. A slow or silent client only ever stalls its own task.
//!
//! Each target is one module returning a [`registry::Target`], listed in
//! [`registry`]; `formalshell-ipc` (`src/bin/formalshell-ipc.rs`) is the
//! client.

mod airplay;
mod bluetooth;
mod bar;
mod caffeinate;
mod calendar;
mod capture;
mod clipboard;
mod console;
#[cfg(test)]
mod cli;
mod debug;
mod display;
mod earbuds;
mod gallery;
mod iphone;
mod lights;
mod localsend;
mod lock;
#[cfg(test)]
mod golden;
mod media;
mod menu;
mod mirror;
mod notifications;
mod overnight;
mod monitor;
mod network;
mod nightlight;
mod osd;
mod panel;
mod picker;
mod plugins;
mod radio;
mod record;
mod screensaver;
mod switcher;
pub mod registry;
mod screenshot;
mod theme;
mod tray;
mod visualizer;
pub mod wire;
mod workspaces;

use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::OnceLock;

use async_io::Async;
use futures_lite::{AsyncReadExt, AsyncWriteExt};

pub use wire::Request;

use crate::runtime::{Ctx, Msg};
use crate::wayland::App;
use registry::Registry;

/// The most of one request the server reads.
const MAX_REQUEST: u64 = 1 << 20;

fn registry() ->&'static Registry<App> {
    static REGISTRY: OnceLock<Registry<App>> = OnceLock::new();
    REGISTRY.get_or_init(|| Registry {
        targets: vec![
            debug::target(),
            theme::target(),
            theme::wallpaper(),
            bar::target(),
            panel::target(),
            media::target(),
            radio::target(),
            airplay::target(),
            bluetooth::target(),
            visualizer::target(),
            tray::target(),
            overnight::target(),
            earbuds::target(),
            display::target(),
            display::hdr(),
            workspaces::target(),
            monitor::target(),
            network::target(),
            plugins::target(),
            caffeinate::target(),
            gallery::target(),
            lock::target(),
            menu::target(),
            calendar::target(),
            iphone::target(),
            console::target(),
            screensaver::target(),
            screenshot::target(),
            capture::target(),
            record::target(),
            notifications::target(),
            notifications::reminder(),
            osd::target(),
            nightlight::target(),
            lights::target(),
            switcher::target(),
            clipboard::target(),
            picker::target(),
            localsend::target(),
            mirror::target(),
        ],
    })
}

pub fn dispatch(app: &mut App, request: &Request) -> String {
    registry().answer(app, request)
}

pub fn start(ctx: &Ctx) {
    monitor::warm();
    ctx.spawn(serve(ctx.clone()));
}

async fn serve(ctx: Ctx) {
    let path = wire::socket_path();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    // A socket that still answers belongs to another running shell; one
    // that refuses is a dead shell's leftover.
    if UnixStream::connect(&path).is_ok() {
        eprintln!("ipc: another shell already answers on {}", path.display());
        return;
    }
    let _ = std::fs::remove_file(&path);
    let listener = match Async::<UnixListener>::bind(&path) {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("ipc: cannot listen on {}: {err}", path.display());
            return;
        }
    };
    loop {
        match listener.accept().await {
            Ok((stream, _)) => ctx.spawn(answer(ctx.clone(), stream)),
            Err(err) => eprintln!("ipc: accept: {err}"),
        }
    }
}

/// The client writes its request and shuts its half down, so the read
/// ends at EOF.
async fn answer(ctx: Ctx, mut stream: Async<UnixStream>) {
    let mut bytes = Vec::new();
    if (&mut stream).take(MAX_REQUEST).read_to_end(&mut bytes).await.is_err() {
        return;
    }
    let Ok(request) = serde_json::from_slice::<Request>(&bytes) else { return };
    let (tx, rx) = async_channel::bounded(1);
    ctx.publisher().send(Msg::Call(request, tx));
    if let Ok(reply) = rx.recv().await {
        let _ = stream.write_all(reply.as_bytes()).await;
    }
}
