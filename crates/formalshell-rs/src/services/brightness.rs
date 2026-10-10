//! The internal backlight through `brightnessctl -m`, the OSD's reading.
//! Nothing polls: the backlight is read when the service starts and when the
//! OSD asks. Every brightness write and the DDC monitors are
//! `services::display`'s.

use std::cell::RefCell;
use std::time::Duration;

use crate::runtime::Ctx;
use crate::services::proc::{self, argv};
use crate::store;

const BRIGHTNESSCTL: Duration = Duration::from_secs(5);

#[derive(Clone, Debug, PartialEq)]
pub struct Device {
    /// `backlight` for the internal panel, a DRM connector name for a DDC monitor.
    pub id: String,
    pub label: String,
    pub percent: f64,
    pub max: i64,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct State {
    pub available: bool,
    pub percent: f64,
    pub devices: Vec<Device>,
}

pub struct Diff(pub State);

impl State {
    pub fn apply(&mut self, diff: Diff) -> bool {
        let changed = *self != diff.0;
        *self = diff.0;
        changed
    }
}

/// `brightnessctl -m`'s row: `name,class,current,percent%,max`.
pub fn parse_csv(line: &str) -> Option<(String, f64)> {
    let fields: Vec<&str> = line.split(',').collect();
    if fields.len() < 4 || fields[0].is_empty() {
        return None;
    }
    let digits: String = fields[3].trim().chars().take_while(char::is_ascii_digit).collect();
    Some((fields[0].to_owned(), digits.parse().unwrap_or(0.0)))
}

#[derive(Default)]
struct Local {
    device: String,
    state: State,
    /// A read is out, and another was asked for while it was.
    reading: bool,
    again: bool,
}

thread_local! {
    static LOCAL: RefCell<Local> = RefCell::new(Local::default());
}

fn publish(ctx: &Ctx) {
    let state = LOCAL.with_borrow_mut(|l| {
        let mut devices = Vec::new();
        if !l.device.is_empty() {
            devices.push(Device { id: "backlight".into(), label: "INTERNAL".into(), percent: l.state.percent, max: 100 });
        }
        l.state.available = !l.device.is_empty();
        l.state.devices = devices;
        l.state.clone()
    });
    ctx.publish(store::Diff::Brightness(Diff(state)));
}

/// The first backlight device and its percent, or none without one.
pub async fn backlight() -> Option<(String, f64)> {
    let done = proc::capture(&argv(&["brightnessctl", "-m", "-c", "backlight", "-l"]), BRIGHTNESSCTL).await;
    parse_csv(done.stdout.lines().next()?)
}

pub fn start(ctx: &Ctx) {
    refresh(ctx);
}

/// Reads the backlight again: a keybind's own `brightnessctl set` bypassed
/// this service, so its cached percent is stale until something asks. One
/// read at a time, and one more after it if another call landed meanwhile:
/// a held key fires this at its repeat rate, and reads racing each other
/// could land oldest last and step the OSD backwards.
pub fn refresh(ctx: &Ctx) {
    let first = LOCAL.with_borrow_mut(|l| {
        l.again = l.reading;
        !std::mem::replace(&mut l.reading, true)
    });
    if !first {
        return;
    }
    let ctx = ctx.clone();
    ctx.clone().spawn(async move {
        loop {
            let read = backlight().await;
            let again = LOCAL.with_borrow_mut(|l| {
                match read {
                    Some((device, percent)) => {
                        l.device = device;
                        l.state.percent = percent;
                    }
                    None => {
                        l.device.clear();
                        l.state.percent = 0.0;
                    }
                }
                let again = std::mem::take(&mut l.again);
                l.reading = again;
                again
            });
            publish(&ctx);
            if !again {
                return;
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_backlight_row_is_name_and_percent() {
        assert_eq!(parse_csv("intel_backlight,backlight,4800,43%,11000"), Some(("intel_backlight".into(), 43.0)));
        assert_eq!(parse_csv("a,b"), None);
        assert_eq!(parse_csv(",backlight,1,2%,3"), None);
    }
}
