mod fontconfig;
mod ipc;
mod motion;
mod render;
mod runtime;
mod scene;
mod services;
mod store;
mod surface;
mod surfaces;
mod text;
mod ui;
mod wayland;

use std::time::{Instant, SystemTime};

use calloop::EventLoop;
use calloop::channel::{self, Event};
use smithay_client_toolkit::reexports::calloop_wayland_source::WaylandSource;
use smithay_client_toolkit::reexports::client::Connection;
use smithay_client_toolkit::reexports::client::globals::registry_queue_init;

use runtime::{Msg, Publisher, Runtime};
use wayland::App;

fn main() {
    // Every `t=` in the log counts from here; this line puts that zero on the
    // wall clock, so a cold start reads against the launcher's own stamp.
    let started = Instant::now();
    let epoch = SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap_or_default();
    eprintln!("start epoch_us={}", epoch.as_micros());

    let conn = Connection::connect_to_env().expect("no Wayland compositor to connect to");
    let (globals, queue) = registry_queue_init::<App>(&conn).expect("wl_registry");
    let qh = queue.handle();

    let mut event_loop: EventLoop<'static, App> = EventLoop::try_new().expect("event loop");
    let handle = event_loop.handle();
    WaylandSource::new(conn.clone(), queue).insert(handle.clone()).expect("wayland source");

    let mut app = App::new(&globals, &qh, started);

    let (sender, inbox) = channel::channel::<Msg>();
    handle
        .insert_source(inbox, |event, _, app| {
            if let Event::Msg(msg) = event {
                app.receive(msg);
            }
        })
        .expect("runtime channel");
    let runtime = Runtime::start(Publisher::new(sender), |ctx| {
        services::start(ctx);
        ipc::start(ctx);
    });
    app.runtime = Some(runtime);
    app.set_handle(handle.clone());

    let signal = event_loop.get_signal();
    let ended = event_loop.run(None, &mut app, |app| {
        app.present();
        if app.exit {
            signal.stop();
        }
    });
    app.report_exit();
    if let Err(err) = ended {
        eprintln!("event loop: {err}");
    }
}
