mod bar;
mod fontconfig;
mod hyprland;
mod render;
mod scene;
mod text;
mod theme;
mod wayland;

use std::io::Read;
use std::time::Duration;

use calloop::generic::Generic;
use calloop::timer::{TimeoutAction, Timer};
use calloop::{EventLoop, Interest, Mode, PostAction};
use chrono::{Local, Timelike};
use smithay_client_toolkit::reexports::calloop_wayland_source::WaylandSource;
use smithay_client_toolkit::reexports::client::Connection;
use smithay_client_toolkit::reexports::client::globals::registry_queue_init;

use wayland::App;

fn clock_text() -> String {
    Local::now().format("%H:%M").to_string()
}

/// Time left until the next wall-clock minute starts.
fn until_next_minute() -> Duration {
    let now = Local::now();
    let into = Duration::new(now.second() as u64, now.nanosecond() % 1_000_000_000);
    Duration::from_secs(60) - into
}

fn refresh_workspaces(app: &mut App) {
    match hyprland::slots(theme::PERSISTENT_WORKSPACES) {
        Ok(slots) => app.bar.set_workspaces(&slots),
        Err(err) => eprintln!("hyprland: workspaces unavailable: {err}"),
    }
}

fn main() {
    let conn = Connection::connect_to_env().expect("no Wayland compositor to connect to");
    let (globals, queue) = registry_queue_init::<App>(&conn).expect("wl_registry");
    let qh = queue.handle();

    let mut event_loop: EventLoop<App> = EventLoop::try_new().expect("event loop");
    let handle = event_loop.handle();
    WaylandSource::new(conn.clone(), queue).insert(handle.clone()).expect("wayland source");

    let mut app = App::new(&globals, &qh);
    app.bar.set_clock(&clock_text());
    refresh_workspaces(&mut app);

    handle
        .insert_source(Timer::from_duration(until_next_minute()), |_, _, app| {
            app.bar.set_clock(&clock_text());
            TimeoutAction::ToDuration(until_next_minute())
        })
        .expect("clock timer");

    match hyprland::events() {
        Ok(stream) => {
            let mut lines = hyprland::LineBuffer::default();
            handle
                .insert_source(Generic::new(stream, Interest::READ, Mode::Level), move |_, stream, app| {
                    let mut buf = [0u8; 4096];
                    let mut changed = false;
                    loop {
                        match (&**stream).read(&mut buf) {
                            Ok(0) => {
                                eprintln!("hyprland: event socket closed");
                                return Ok(PostAction::Remove);
                            }
                            Ok(n) => changed |= lines.feed(&buf[..n]).iter().any(|l| hyprland::touches_workspaces(l)),
                            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                            Err(e) => return Err(e),
                        }
                    }
                    if changed {
                        refresh_workspaces(app);
                    }
                    Ok(PostAction::Continue)
                })
                .expect("hyprland event source");
        }
        Err(err) => eprintln!("hyprland: no event socket: {err}"),
    }

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
