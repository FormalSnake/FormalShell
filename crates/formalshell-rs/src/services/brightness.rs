//! BrightnessService.qml: the internal backlight through `brightnessctl -m`
//! and every DDC monitor through `ddcutil`. Nothing polls: the backlight is
//! read when the service starts and after a write, and ddcutil's seconds-slow
//! I2C detection runs only when a consumer asks for the device list (the
//! display panel) or for the DDC rows themselves (overnight).

use std::cell::RefCell;
use std::time::Duration;

use crate::runtime::Ctx;
use crate::services::proc::{self, MISSING, argv};
use crate::store;

const BRIGHTNESSCTL: Duration = Duration::from_secs(5);
/// ddcutil walks every I2C bus; a desk with a few monitors takes several seconds.
const DDCUTIL: Duration = Duration::from_secs(30);

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

/// `ddcutil detect --brief`: each monitor's I2C bus then its DRM connector.
pub fn parse_detect(text: &str) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();
    let mut bus: Option<String> = None;
    for line in text.lines() {
        if let Some(rest) = line.split("I2C bus:").nth(1).and_then(|r| r.trim().strip_prefix("/dev/i2c-")) {
            let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
            if !digits.is_empty() {
                bus = Some(digits);
            }
            continue;
        }
        let Some(rest) = line.split("DRM connector:").nth(1) else { continue };
        let Some(pending) = bus.take() else { continue };
        let name = rest.trim().strip_prefix("card").and_then(|r| r.split_once('-')).map(|(_, n)| n.split_whitespace().next().unwrap_or(""));
        let Some(name) = name.filter(|n| !n.is_empty()) else { continue };
        match out.iter_mut().find(|(c, _)| c == name) {
            Some(slot) => slot.1 = pending,
            None => out.push((name.to_owned(), pending)),
        }
    }
    out
}

/// `ddcutil getvcp 10 --brief`: `VCP 10 C <current> <max>`.
pub fn parse_getvcp(text: &str) -> Option<(i64, i64)> {
    for line in text.lines() {
        let mut t = line.split_whitespace();
        if t.next() == Some("VCP") && t.next() == Some("10") && t.next() == Some("C") {
            let current = t.next()?.parse().ok()?;
            let max = t.next()?.parse().ok()?;
            return Some((current, max));
        }
    }
    None
}

#[derive(Default)]
struct Local {
    device: String,
    state: State,
    /// The DDC rows, in the order detection found them, and their buses.
    ddc: Vec<(Device, String)>,
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
        devices.extend(l.ddc.iter().map(|(d, _)| d.clone()));
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

async fn write_backlight(device: &str, arg: &str) -> Option<(String, f64)> {
    let done = proc::capture(&argv(&["brightnessctl", "-m", "-d", device, "set", arg]), BRIGHTNESSCTL).await;
    parse_csv(done.stdout.trim())
}

/// Every DDC monitor: connector and bus, as detection found them. Empty
/// without ddcutil.
pub async fn ddc_detect() -> Vec<(String, String)> {
    let done = proc::capture(&argv(&["ddcutil", "--skip-ddc-checks", "detect", "--brief"]), DDCUTIL).await;
    if done.code == MISSING { Vec::new() } else { parse_detect(&done.stdout) }
}

pub async fn ddc_read(bus: &str) -> Option<(i64, i64)> {
    let done = proc::capture(&argv(&["ddcutil", "--bus", bus, "--skip-ddc-checks", "getvcp", "10", "--brief"]), DDCUTIL).await;
    parse_getvcp(&done.stdout)
}

/// `--noverify`: setvcp never reads back, so a write is one round trip.
pub async fn ddc_write(bus: &str, raw: i64) {
    let _ = proc::capture(&argv(&["ddcutil", "--bus", bus, "--skip-ddc-checks", "--noverify", "setvcp", "10", &raw.to_string()]), DDCUTIL).await;
}

/// Never a literal 0 over DDC: some panels treat VCP 10 = 0 as off, not dim.
pub fn ddc_raw(percent: f64, max: i64) -> i64 {
    (percent.round().max(1.0) * max as f64 / 100.0).round() as i64
}

#[derive(Clone, Debug, PartialEq)]
pub struct DdcRow {
    pub connector: String,
    pub bus: String,
    pub percent: f64,
    pub max: i64,
}

/// Detection then one read per monitor, one bus at a time (ddcutil on
/// several at once only contends on the same I2C bus).
pub async fn ddc_rows() -> Vec<DdcRow> {
    let mut rows = Vec::new();
    for (connector, bus) in ddc_detect().await {
        if let Some((current, max)) = ddc_read(&bus).await {
            let percent = if max > 0 { (current as f64 * 100.0 / max as f64).round() } else { 0.0 };
            rows.push(DdcRow { connector, bus, percent, max });
        }
    }
    rows
}

pub fn start(ctx: &Ctx) {
    refresh(ctx);
}

/// Reads the backlight again: a keybind's own `brightnessctl set` bypassed
/// this service, so its cached percent is stale until something asks.
pub fn refresh(ctx: &Ctx) {
    let ctx = ctx.clone();
    ctx.clone().spawn(async move {
        let read = backlight().await;
        LOCAL.with_borrow_mut(|l| match read {
            Some((device, percent)) => {
                l.device = device;
                l.state.percent = percent;
            }
            None => {
                l.device.clear();
                l.state.percent = 0.0;
            }
        });
        publish(&ctx);
    });
}

/// The backlight again and a fresh DDC detection, each monitor appearing
/// as its own read lands. The display panel's call.
#[allow(dead_code)]
pub fn refresh_devices(ctx: &Ctx) {
    refresh(ctx);
    let ctx = ctx.clone();
    ctx.clone().spawn(async move {
        let found = ddc_detect().await;
        LOCAL.with_borrow_mut(|l| l.ddc.clear());
        publish(&ctx);
        for (connector, bus) in found {
            if let Some((current, max)) = ddc_read(&bus).await {
                let percent = if max > 0 { (current as f64 * 100.0 / max as f64).round() } else { 0.0 };
                let device = Device { id: connector.clone(), label: connector, percent, max };
                LOCAL.with_borrow_mut(|l| l.ddc.push((device, bus)));
                publish(&ctx);
            }
        }
    });
}

/// `id` is `backlight` or a DDC connector; the display panel's call.
#[allow(dead_code)]
pub fn set_device_percent(ctx: &Ctx, id: &str, percent: f64) {
    let clamped = percent.round().clamp(0.0, 100.0);
    if id == "backlight" {
        let ctx = ctx.clone();
        let device = LOCAL.with_borrow(|l| l.device.clone());
        if device.is_empty() {
            return;
        }
        ctx.clone().spawn(async move {
            if let Some((_, percent)) = write_backlight(&device, &format!("{}%", clamped as i64)).await {
                LOCAL.with_borrow_mut(|l| l.state.percent = percent);
                publish(&ctx);
            }
        });
        return;
    }
    let Some((device, bus)) = LOCAL.with_borrow(|l| l.ddc.iter().find(|(d, _)| d.id == id).cloned()) else { return };
    let target = clamped.max(1.0);
    LOCAL.with_borrow_mut(|l| {
        if let Some((d, _)) = l.ddc.iter_mut().find(|(d, _)| d.id == id) {
            d.percent = target;
        }
    });
    publish(ctx);
    ctx.spawn(async move { ddc_write(&bus, ddc_raw(target, device.max)).await });
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

    #[test]
    fn detection_pairs_each_bus_with_the_connector_after_it() {
        let text = "Display 1\n   I2C bus:  /dev/i2c-5\n   DRM connector:           card1-DP-1\n   Monitor:  DEL:X\n\nDisplay 2\n   I2C bus:  /dev/i2c-7\n   DRM connector:           card1-HDMI-A-2\n\nInvalid display\n   I2C bus:  /dev/i2c-9\n";
        assert_eq!(parse_detect(text), vec![("DP-1".into(), "5".into()), ("HDMI-A-2".into(), "7".into())]);
    }

    #[test]
    fn getvcp_brief_reads_current_and_max() {
        assert_eq!(parse_getvcp("VCP 10 C 37 100\n"), Some((37, 100)));
        assert_eq!(parse_getvcp("VCP 10 SNC x00\n"), None);
    }

    #[test]
    fn ddc_never_writes_zero() {
        assert_eq!(ddc_raw(0.0, 100), 1);
        assert_eq!(ddc_raw(50.0, 255), 128);
    }
}
