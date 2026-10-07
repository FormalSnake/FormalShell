//! OvernightService.qml: the machine left compiling while its owner sleeps.
//! Screens to 1%, every LED the shell may touch off, the Aura zones dark,
//! and a Performance profile dropped to Balanced (power-saver would also
//! pin the CPU's energy preference and drag a long build out).
//!
//! Everything changed is recorded in state.json's `overnight` before or as
//! it lands, so disable restores it even after a restart: `{ profile,
//! backlight, ddc, leds, aura }`, backlight -1 with no backlight to dim.
//! The UI decides enable or disable off the store's record; the work runs
//! here, on the service thread.
//!
//! DDC monitors are detected and read through the brightness service's
//! ddcutil helpers; `ddc` records each one's percent before it is dimmed,
//! keyed by connector, and disable puts those back.

use std::cell::RefCell;

use fs_system::overnight::{self, AURA_ZONES, SCREEN_PERCENT};
use fs_upower::{PowerProfiles, Profile};
use serde_json::{Map, Value, json};

use crate::runtime::Ctx;
use crate::services::brightness;
use crate::services::state::{self, Field};

thread_local! {
    /// The record this thread last wrote while active, for the merges the
    /// LED listing and the Aura probe make once they finish.
    static RECORD: RefCell<Option<Map<String, Value>>> = const { RefCell::new(None) };
}

/// Quickshell's `PowerProfile` enum numbers, what the record has always held.
fn profile_number(p: Profile) -> i64 {
    match p {
        Profile::PowerSaver => 0,
        Profile::Balanced => 1,
        Profile::Performance => 2,
    }
}

fn profile_of(n: i64) -> Option<Profile> {
    match n {
        0 => Some(Profile::PowerSaver),
        1 => Some(Profile::Balanced),
        2 => Some(Profile::Performance),
        _ => None,
    }
}

fn write(record: Option<Map<String, Value>>) {
    state::set(vec![Field::Overnight(record.clone().map_or(Value::Null, Value::Object))]);
    RECORD.with_borrow_mut(|r| *r = record);
}

/// Merges one key into the stored record; nothing once disabled.
fn record(key: &str, value: Value) {
    let next = RECORD.with_borrow(|r| {
        r.clone().map(|mut m| {
            m.insert(key.into(), value);
            m
        })
    });
    if next.is_some() {
        write(next);
    }
}

async fn output(argv: &[&str]) -> Option<(i32, String)> {
    let out = async_process::Command::new(argv[0]).args(&argv[1..]).stderr(async_process::Stdio::null()).output().await.ok()?;
    Some((out.status.code().unwrap_or(-1), String::from_utf8_lossy(&out.stdout).into_owned()))
}

/// BrightnessService.qml's backlight: `brightnessctl -m -c backlight -l`'s
/// first row, name and percent.
async fn backlight() -> Option<(String, i64)> {
    let (_, text) = output(&["brightnessctl", "-m", "-c", "backlight", "-l"]).await?;
    let line = text.lines().next()?;
    let fields: Vec<&str> = line.split(',').collect();
    if fields.len() < 4 || fields[0].is_empty() {
        return None;
    }
    let percent = fields[3].trim().trim_end_matches('%').parse().unwrap_or(0);
    Some((fields[0].to_owned(), percent))
}

async fn set_backlight(device: &str, percent: i64) {
    let arg = format!("{}%", percent.clamp(0, 100));
    let _ = output(&["brightnessctl", "-m", "-d", device, "set", &arg]).await;
}

async fn profiles() -> Option<PowerProfiles> {
    let conn = zbus::Connection::system().await.ok()?;
    PowerProfiles::connect(&conn).await.ok()
}

const LED_LIST: &str = "for d in /sys/class/leds/*; do printf '%s\\t%s\\t%s\\n' \"${d##*/}\" \"$(cat \"$d/trigger\" 2>/dev/null)\" \"$(cat \"$d/brightness\" 2>/dev/null)\"; done";
const LED_OFF: &str = "for n; do brightnessctl -q -d \"$n\" set 0; done";
const LED_RESTORE: &str = "while [ $# -ge 2 ]; do brightnessctl -q -d \"$1\" set \"$2\"; shift 2; done";
// `asusctl aura power <zone>` with no flags clears every power state for the
// zone, which is off. Exit 3 is this script's own "no asusctl".
const AURA_OFF: &str = "command -v asusctl >/dev/null || exit 3; for z; do asusctl aura power \"$z\" >/dev/null 2>&1; done; exit 0";
// The states the host's asus-aura unit sets at boot (sleep left off, so the
// zones stay dark while suspended).
const AURA_ON: &str = "for z; do asusctl aura power \"$z\" --boot --awake --shutdown >/dev/null 2>&1; done; exit 0";

fn sh(script: &str, args: &[String]) -> Vec<String> {
    let mut argv = vec!["sh".to_owned(), "-c".to_owned(), script.to_owned(), "sh".to_owned()];
    argv.extend(args.iter().cloned());
    argv
}

async fn run(argv: Vec<String>) -> Option<(i32, String)> {
    let refs: Vec<&str> = argv.iter().map(String::as_str).collect();
    output(&refs).await
}

pub fn enable(ctx: &Ctx) {
    // A second enable that reached here before the store saw the first.
    if RECORD.with_borrow(Option::is_some) {
        return;
    }
    RECORD.with_borrow_mut(|r| *r = Some(Map::new()));
    ctx.spawn(async {
        let profiles = profiles().await;
        let active = match &profiles {
            Some(p) => p.state().await.ok().map(|s| s.active),
            None => None,
        };
        let light = backlight().await;
        let mut rec = Map::new();
        if let Some(p) = active {
            rec.insert("profile".into(), json!(profile_number(p)));
        }
        rec.insert("backlight".into(), json!(light.as_ref().map_or(-1, |(_, pct)| *pct)));
        rec.insert("ddc".into(), json!({}));
        rec.insert("leds".into(), json!({}));
        rec.insert("aura".into(), json!(false));
        if RECORD.with_borrow(Option::is_none) {
            return;
        }
        write(Some(rec));
        if let (Some(p), Some(Profile::Performance)) = (&profiles, active) {
            let _ = p.set_active(Profile::Balanced).await;
        }
        if let Some((device, _)) = &light {
            set_backlight(device, SCREEN_PERCENT).await;
        }
        let zones: Vec<String> = AURA_ZONES.iter().map(|z| z.to_string()).collect();
        let leds = async {
            let Some((_, text)) = run(sh(LED_LIST, &[])).await else { return };
            let leds = overnight::parse_leds(&text);
            if leds.is_empty() || RECORD.with_borrow(Option::is_none) {
                return;
            }
            let snapshot: Map<String, Value> = overnight::led_snapshot(&leds).into_iter().map(|(n, b)| (n, json!(b))).collect();
            record("leds", Value::Object(snapshot));
            let names: Vec<String> = leds.into_iter().map(|l| l.name).collect();
            let _ = run(sh(LED_OFF, &names)).await;
        };
        let aura = async {
            if let Some((0, _)) = run(sh(AURA_OFF, &zones)).await {
                record("aura", json!(true));
            }
        };
        // Each monitor lands in the record before it is dimmed, so a restart
        // mid-walk still knows what to put back.
        let ddc = async {
            let mut dimmed = Map::new();
            for row in brightness::ddc_rows().await {
                if RECORD.with_borrow(Option::is_none) {
                    return;
                }
                if row.percent > SCREEN_PERCENT as f64 {
                    dimmed.insert(row.connector, json!(row.percent));
                    record("ddc", Value::Object(dimmed.clone()));
                    brightness::ddc_write(&row.bus, brightness::ddc_raw(SCREEN_PERCENT as f64, row.max)).await;
                }
            }
        };
        futures_lite::future::zip(futures_lite::future::zip(leds, aura), ddc).await;
    });
}

/// `snap`: the record state.json holds, which is what gets put back.
pub fn disable(ctx: &Ctx, snap: Value) {
    write(None);
    ctx.spawn(async move {
        if let Some(want) = snap.get("profile").and_then(Value::as_i64).and_then(profile_of)
            && let Some(p) = profiles().await
            && p.state().await.is_ok_and(|s| s.active != want)
        {
            let _ = p.set_active(want).await;
        }
        let level = snap.get("backlight").and_then(Value::as_f64).unwrap_or(-1.0);
        if level >= 0.0
            && let Some((device, _)) = backlight().await
        {
            set_backlight(&device, level.round() as i64).await;
        }
        let leds: Vec<(String, Value)> = match snap.get("leds") {
            Some(Value::Object(m)) => m.iter().map(|(k, v)| (k.clone(), v.clone())).collect(),
            _ => Vec::new(),
        };
        let restore = overnight::restore_args(&leds);
        if snap.get("aura") == Some(&Value::Bool(true)) {
            let zones: Vec<String> = AURA_ZONES.iter().map(|z| z.to_string()).collect();
            let _ = run(sh(AURA_ON, &zones)).await;
        }
        if !restore.is_empty() {
            let _ = run(sh(LED_RESTORE, &restore)).await;
        }
        if let Some(Value::Object(ddc)) = snap.get("ddc")
            && !ddc.is_empty()
        {
            let buses = brightness::ddc_detect().await;
            for (connector, percent) in ddc {
                let Some(percent) = percent.as_f64() else { continue };
                let Some((_, bus)) = buses.iter().find(|(c, _)| c == connector) else { continue };
                if let Some((_, max)) = brightness::ddc_read(bus).await {
                    brightness::ddc_write(bus, brightness::ddc_raw(percent, max)).await;
                }
            }
        }
    });
}
