//! What the display panel and the `display`/`hdr` targets read beside the
//! compositor's own outputs: each output's EDID, the
//! backlight and DDC monitors, and which card drives which connector.
//!
//! The EDIDs are read once per set of connector names, off the hyprland
//! service's own output refresh. The backlight is listed once at start and
//! re-read from every set's own reply. DDC detection is seconds-slow, so it
//! runs only when the panel opens, as does the 5s re-read of the outputs the
//! compositor never announces (a disabled one), for as long as it is open.
//!
//! HDR's choice lives in state.json's `hdr`; [`hdr_set`] and its siblings
//! answer on the UI thread off the store, and [`reconcile`] puts a wanted output back in
//! HDR after a start, a hotplug or a config reload that reset the rules.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::time::Duration;

use async_io::Timer;
use fs_system::display::hdr::{self, Edid, Verdict};
use fs_system::display::outputs::{self, Output};
use fs_system::display::priority;
use fs_system::monitor::gpu;
use serde_json::Value;

use crate::runtime::Ctx;
use crate::services::hyprland::{self, Command};
use crate::services::state::{self, Field};
use crate::store::{self, Store};

/// The display panel's re-read while open.
const REFRESH: Duration = Duration::from_secs(5);

#[derive(Clone, Debug, PartialEq)]
pub struct Brightness {
    /// "backlight" or a DRM connector.
    pub id: String,
    pub label: String,
    pub percent: i64,
    pub max: i64,
}

#[derive(Default)]
pub struct State {
    /// None until the first read answers ("Checking").
    pub edids: Option<HashMap<String, Edid>>,
    pub cards: Vec<gpu::Card>,
    pub backlight: Option<Brightness>,
    pub ddc: Vec<Brightness>,
}

pub enum Diff {
    Edids(HashMap<String, Edid>),
    Cards(Vec<gpu::Card>),
    Backlight(Option<Brightness>),
    Ddc(Vec<Brightness>),
    DdcPercent(String, i64),
}

impl State {
    pub fn apply(&mut self, diff: Diff) -> bool {
        fn set<T: PartialEq>(slot: &mut T, v: T) -> bool {
            let changed = *slot != v;
            *slot = v;
            changed
        }
        match diff {
            Diff::Edids(v) => set(&mut self.edids, Some(v)),
            Diff::Cards(v) => set(&mut self.cards, v),
            Diff::Backlight(v) => set(&mut self.backlight, v),
            Diff::Ddc(v) => set(&mut self.ddc, v),
            Diff::DdcPercent(id, pct) => match self.ddc.iter_mut().find(|d| d.id == id) {
                Some(d) if d.percent != pct => {
                    d.percent = pct;
                    true
                }
                _ => false,
            },
        }
    }

    /// The backlight first, then every DDC monitor, the panel's row order.
    pub fn devices(&self) -> Vec<Brightness> {
        self.backlight.iter().chain(self.ddc.iter()).cloned().collect()
    }

    pub fn verdict(&self, name: &str) -> Verdict {
        match &self.edids {
            None => Verdict { supported: false, reason: "Checking" },
            Some(edids) => hdr::verdict(edids.get(name)),
        }
    }
}

fn publish(ctx: &Ctx, diff: Diff) {
    ctx.publish(store::Diff::Display(diff));
}

thread_local! {
    static EDID_NAMES: RefCell<String> = const { RefCell::new(String::new()) };
    static BACKLIGHT: RefCell<String> = const { RefCell::new(String::new()) };
    static BUSES: RefCell<HashMap<String, String>> = RefCell::new(HashMap::new());
}

pub fn start(ctx: &Ctx) {
    ctx.spawn(backlight(ctx.clone(), vec!["-c".into(), "backlight".into(), "-l".into()]));
}

/// The hyprland service's every output read: a new set of connector names
/// is read off /sys/class/drm.
pub fn outputs_changed(ctx: &Ctx, rows: &[Output]) {
    let mut names: Vec<String> = rows.iter().map(|r| r.name.clone()).collect();
    names.sort();
    let key = names.join("\n");
    if key.is_empty() || EDID_NAMES.with_borrow(|k| *k == key) {
        return;
    }
    EDID_NAMES.with_borrow_mut(|k| *k = key);
    let ctx2 = ctx.clone();
    ctx.spawn(async move {
        if let Some(edids) = ctx2.pool().run(move || read_edids(&names)).await {
            publish(&ctx2, Diff::Edids(edids));
        }
    });
}

/// Each EDID read from `/sys/class/drm/card*-<name>/edid`: only a
/// readable node yields an entry, so a connector with none reads "No EDID".
fn read_edids(names: &[String]) -> HashMap<String, Edid> {
    let mut out = HashMap::new();
    let Ok(dir) = std::fs::read_dir("/sys/class/drm") else { return out };
    let entries: Vec<String> = dir.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
    for name in names {
        for entry in &entries {
            let Some((card, connector)) = entry.split_once('-') else { continue };
            if !card.starts_with("card") || connector != name {
                continue;
            }
            if let Ok(bytes) = std::fs::read(format!("/sys/class/drm/{entry}/edid")) {
                let hex: Vec<String> = bytes.iter().map(|b| format!("{b:02x}")).collect();
                out.insert(name.clone(), hdr::parse_edid(&hex.join(" ")));
            }
        }
    }
    out
}

/// The `card|...` and `conn|...` rows read straight
/// off sysfs, for `outputs::output_card_label`.
fn read_cards() -> Vec<gpu::Card> {
    let Ok(dir) = std::fs::read_dir("/sys/class/drm") else { return Vec::new() };
    let mut entries: Vec<String> = dir.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
    entries.sort();
    let read = |p: String| std::fs::read_to_string(p).map(|s| s.trim().to_owned()).unwrap_or_default();
    let link = |p: String| {
        std::fs::read_link(p).ok().and_then(|l| l.file_name().map(|n| n.to_string_lossy().into_owned())).unwrap_or_default()
    };
    let mut text = String::new();
    for e in entries.iter().filter(|e| e.starts_with("card") && !e.contains('-')) {
        let base = format!("/sys/class/drm/{e}/device");
        text.push_str(&format!(
            "card|{e}|{}|{}|{}|{}|{}|\n",
            link(format!("{base}/driver")),
            read(format!("{base}/vendor")),
            read(format!("{base}/device")),
            read(format!("{base}/boot_vga")),
            link(base.clone()),
        ));
    }
    for e in &entries {
        if let Some((card, connector)) = e.split_once('-')
            && card.starts_with("card")
        {
            text.push_str(&format!("conn|{card}|{connector}|{}\n", read(format!("/sys/class/drm/{e}/status"))));
        }
    }
    gpu::parse_cards(&text)
}

async fn output(argv: &[String]) -> Option<(i32, String)> {
    let out = crate::services::proc::command(&argv[0])
        .args(&argv[1..])
        .stderr(async_process::Stdio::null())
        .output()
        .await
        .ok()?;
    Some((out.status.code().unwrap_or(-1), String::from_utf8_lossy(&out.stdout).into_owned()))
}

/// `brightnessctl -m` with `args`; its first CSV row (`name,class,current,
/// percent%,max`) is the backlight now.
async fn backlight(ctx: Ctx, args: Vec<String>) {
    let mut argv = vec!["brightnessctl".to_string(), "-m".to_string()];
    argv.extend(args);
    let text = output(&argv).await.map(|(_, t)| t).unwrap_or_default();
    let line = text.lines().next().unwrap_or("").trim();
    let fields: Vec<&str> = line.split(',').collect();
    let device = if fields.len() >= 4 && !fields[0].is_empty() {
        BACKLIGHT.with_borrow_mut(|b| *b = fields[0].to_owned());
        Some(Brightness {
            id: "backlight".into(),
            label: "INTERNAL".into(),
            percent: fields[3].trim_end_matches('%').parse().unwrap_or(0),
            max: 100,
        })
    } else if line.is_empty() {
        BACKLIGHT.with_borrow_mut(String::clear);
        None
    } else {
        return;
    };
    publish(&ctx, Diff::Backlight(device));
}

/// `ddcutil detect --brief`: each `I2C bus: /dev/i2c-N` followed by its
/// `DRM connector: cardM-<name>`.
fn parse_detect(text: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut bus: Option<String> = None;
    for line in text.lines() {
        if let Some(rest) = line.split_once("I2C bus:").map(|(_, r)| r.trim())
            && let Some(n) = rest.strip_prefix("/dev/i2c-")
            && !n.is_empty()
            && n.bytes().all(|b| b.is_ascii_digit())
        {
            bus = Some(n.to_owned());
            continue;
        }
        if let Some(rest) = line.split_once("DRM connector:").map(|(_, r)| r.trim())
            && let Some((card, connector)) = rest.split_whitespace().next().unwrap_or("").split_once('-')
            && card.starts_with("card")
            && let Some(b) = bus.take()
        {
            out.push((connector.to_owned(), b));
        }
    }
    out
}

/// `VCP 10 C <current> <max>`, getvcp's brief answer.
fn parse_vcp(text: &str) -> Option<(i64, i64)> {
    let words: Vec<&str> = text.split_whitespace().collect();
    words.windows(5).find(|w| w[0] == "VCP" && w[1] == "10" && w[2] == "C").and_then(|w| Some((w[3].parse().ok()?, w[4].parse().ok()?)))
}

async fn detect(ctx: Ctx) {
    let argv: Vec<String> = ["ddcutil", "--skip-ddc-checks", "detect", "--brief"].map(String::from).into();
    let found = match output(&argv).await {
        Some((_, text)) => parse_detect(&text),
        None => Vec::new(),
    };
    BUSES.with_borrow_mut(|b| *b = found.iter().cloned().collect());
    let mut rows = Vec::new();
    publish(&ctx, Diff::Ddc(rows.clone()));
    // One bus at a time: they share the I2C controller.
    for (connector, bus) in found {
        let argv: Vec<String> = ["ddcutil", "--bus", &bus, "--skip-ddc-checks", "getvcp", "10", "--brief"].map(String::from).into();
        if let Some((current, max)) = output(&argv).await.and_then(|(_, t)| parse_vcp(&t)) {
            let percent = if max > 0 { (current as f64 * 100.0 / max as f64).round() as i64 } else { 0 };
            rows.push(Brightness { id: connector.clone(), label: connector, percent, max });
            publish(&ctx, Diff::Ddc(rows.clone()));
        }
    }
}

/// Sets a device's brightness percent. `max` is the DDC row's own.
pub fn set_percent(ctx: &Ctx, id: &str, percent: f64, max: i64) {
    let pct = percent.round().clamp(0.0, 100.0) as i64;
    if id == "backlight" {
        let device = BACKLIGHT.with_borrow(Clone::clone);
        if device.is_empty() {
            return;
        }
        ctx.spawn(backlight(ctx.clone(), vec!["-d".into(), device, "set".into(), format!("{pct}%")]));
        return;
    }
    let Some(bus) = BUSES.with_borrow(|b| b.get(id).cloned()) else { return };
    // Some panels take VCP 10 at 0 as off rather than dim.
    let target = pct.max(1);
    let raw = (target as f64 * max as f64 / 100.0).round() as i64;
    let argv: Vec<String> =
        ["ddcutil", "--bus", &bus, "--skip-ddc-checks", "--noverify", "setvcp", "10", &raw.to_string()].map(String::from).into();
    ctx.spawn(async move {
        let _ = output(&argv).await;
    });
    // --noverify reads nothing back, so the row takes the value it asked for.
    publish(ctx, Diff::DdcPercent(id.to_owned(), target));
}

/// While the panel is open: the outputs read now and every 5s, the
/// backlight, the DDC monitors and the cards once.
pub async fn run(ctx: Ctx) {
    ctx.spawn(backlight(ctx.clone(), vec!["-c".into(), "backlight".into(), "-l".into()]));
    ctx.spawn(detect(ctx.clone()));
    if let Some(cards) = ctx.pool().run(read_cards).await {
        publish(&ctx, Diff::Cards(cards));
    }
    loop {
        hyprland::send(Command::RefreshOutputs);
        Timer::after(REFRESH).await;
    }
}

// HDR, answered on the UI thread.

/// Whether output config can be sent: a compositor to talk to.
pub fn config_available() -> bool {
    std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some()
}

fn rows(store: &Store) -> &[Output] {
    &store.hyprland.outputs
}

/// The SDR level while HDR is on; at 1.0 SDR windows read dim next to the
/// panel's HDR white.
fn on_color(store: &Store) -> outputs::Color {
    hdr::on_color(
        store.config.f64("display.hdr.sdrBrightness").unwrap_or(1.2),
        store.config.f64("display.hdr.sdrSaturation").unwrap_or(1.0),
    )
}

pub fn hdr_supported(store: &Store, name: &str) -> bool {
    outputs::find_output(rows(store), name).is_some() && store.display.verdict(name).supported
}

pub fn hdr_reason(store: &Store, name: &str) -> &'static str {
    if outputs::find_output(rows(store), name).is_none() {
        return "";
    }
    store.display.verdict(name).reason
}

pub fn hdr_on(store: &Store, name: &str) -> bool {
    hdr::is_on(outputs::find_output(rows(store), name))
}

fn apply(name: &str, color: outputs::Color) {
    hyprland::send(Command::SetOutputColor(name.to_owned(), color));
}

/// Sets HDR on an output: "ok" or why nothing was done.
pub fn hdr_set(store: &Store, name: &str, on: bool) -> String {
    if !config_available() {
        return "no compositor".into();
    }
    let Some(row) = outputs::find_output(rows(store), name) else {
        return format!("unknown output: {name}");
    };
    if !row.enabled {
        return format!("{name} is disabled");
    }
    if on && !hdr_supported(store, name) {
        return format!("HDR unavailable on {name}: {}", hdr_reason(store, name));
    }
    let saved = &store.state.data.hdr;
    let wanted = hdr::state_of(saved);
    let prior_value = wanted.get(name).and_then(|w| w.get("prior")).cloned().filter(|p| p.is_object());
    if on {
        let prior = match &prior_value {
            Some(p) => hdr::off_color(p),
            None => hdr::prior_of(row),
        };
        state::set(vec![Field::Hdr(Value::Object(hdr::with_output(saved, name, &prior)))]);
        TRIED.with_borrow_mut(|t| t.insert(name.to_owned()));
        apply(name, on_color(store));
    } else {
        state::set(vec![Field::Hdr(Value::Object(hdr::without_output(saved, name)))]);
        if hdr::is_on(Some(row)) {
            let prior = prior_value.unwrap_or_else(|| prior_json(&hdr::prior_of(row)));
            apply(name, hdr::off_color(&prior));
        }
    }
    "ok".into()
}

fn prior_json(c: &outputs::Color) -> Value {
    serde_json::json!({ "cm": c.cm, "bitdepth": c.bitdepth, "sdrbrightness": c.sdrbrightness, "sdrsaturation": c.sdrsaturation })
}

fn supported_names(store: &Store) -> Vec<String> {
    rows(store).iter().filter(|r| r.enabled && hdr_supported(store, &r.name)).map(|r| r.name.clone()).collect()
}

/// Every output that can do HDR together; an error when none can.
pub fn hdr_set_all(store: &Store, on: bool) -> String {
    let names = supported_names(store);
    if names.is_empty() {
        return if on { "no output supports HDR".into() } else { "ok".into() };
    }
    for name in &names {
        hdr_set(store, name, on);
    }
    "ok".into()
}

pub fn hdr_toggle(store: &Store) -> String {
    let names = supported_names(store);
    if names.is_empty() {
        return "no output supports HDR".into();
    }
    let any_on = names.iter().any(|n| hdr_on(store, n));
    hdr_set_all(store, !any_on)
}

fn js(s: &str) -> String {
    serde_json::to_string(s).unwrap_or_default()
}

/// Any output showing HDR now (HdrService.active).
pub fn hdr_active(store: &Store) -> bool {
    rows(store).iter().any(|r| hdr::is_on(Some(r)))
}

/// `{ active, outputs: [{ name, supported, reason, on, wanted, cm }] }`, in
/// this key order.
pub fn hdr_status(store: &Store) -> String {
    let wanted = hdr::state_of(&store.state.data.hdr);
    let active = rows(store).iter().any(|r| hdr::is_on(Some(r)));
    let outputs: Vec<String> = rows(store)
        .iter()
        .map(|r| {
            let v = store.display.verdict(&r.name);
            format!(
                "{{\"name\":{},\"supported\":{},\"reason\":{},\"on\":{},\"wanted\":{},\"cm\":{}}}",
                js(&r.name),
                v.supported,
                js(v.reason),
                hdr::is_on(Some(r)),
                wanted.contains_key(&r.name),
                js(&r.cm)
            )
        })
        .collect();
    format!("{{\"active\":{active},\"outputs\":[{}]}}", outputs.join(","))
}

/// The rule `hdr_set` would send for `name`, unsent: `{ rule, lua }`, the
/// rule's numbers as numbers the way outputs.js builds it.
pub fn hdr_rule(store: &Store, name: &str) -> String {
    let Some(row) = outputs::find_output(rows(store), name) else {
        return format!("unknown output: {name}");
    };
    let r = outputs::hyprland_color_rule(row, &on_color(store));
    let rule = format!(
        "{{\"output\":{},\"mode\":{},\"position\":{},\"scale\":{},\"transform\":{},\"vrr\":{},\"bitdepth\":{},\"cm\":{},\"sdrbrightness\":{},\"sdrsaturation\":{},\"mirror\":{}}}",
        js(&r.output),
        js(&r.mode),
        js(&r.position),
        r.scale,
        r.transform,
        r.vrr,
        r.bitdepth,
        js(&r.cm),
        r.sdrbrightness,
        r.sdrsaturation,
        js(&r.mirror)
    );
    format!("{{\"rule\":{rule},\"lua\":{}}}", js(&outputs::hyprland_rule_lua(&r)))
}

thread_local! {
    /// Outputs re-applied since the last reset, so an apply Hyprland ignores
    /// is not retried on every refresh.
    static TRIED: RefCell<HashSet<String>> = RefCell::new(HashSet::new());
    static RELOADS: RefCell<u64> = const { RefCell::new(0) };
}

/// Puts a wanted output back in HDR, run whenever the outputs, the verdicts or
/// state.json move.
pub fn reconcile(store: &Store) {
    if !store.state.loaded {
        return;
    }
    let reloads = store.hyprland.config_reloads;
    TRIED.with_borrow_mut(|tried| {
        if RELOADS.with_borrow(|r| *r != reloads) {
            RELOADS.with_borrow_mut(|r| *r = reloads);
            tried.clear();
        }
        tried.retain(|n| outputs::find_output(rows(store), n).is_some());
    });
    let verdicts: HashMap<String, Verdict> = rows(store).iter().map(|r| (r.name.clone(), store.display.verdict(&r.name))).collect();
    let pending = TRIED.with_borrow(|tried| hdr::pending_reapply(&store.state.data.hdr, rows(store), &verdicts, tried));
    for name in pending {
        TRIED.with_borrow_mut(|t| t.insert(name.clone()));
        apply(&name, on_color(store));
    }
}

/// The main output among the lit outputs.
pub fn main_output(store: &Store) -> String {
    let names: Vec<String> = rows(store).iter().filter(|r| r.enabled).map(|r| r.name.clone()).collect();
    let prio = store.config.get("display.outputPriority").cloned().unwrap_or(Value::Array(Vec::new()));
    priority::resolve_main_output(&names, &priority::priority_list(&prio), &store.hyprland.compositor.focused_output_name, "")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detect_pairs_bus_and_connector() {
        let text = "Display 1\n   I2C bus:  /dev/i2c-5\n   DRM connector:  card1-DP-1\n   Monitor: X\n\nInvalid display\n   I2C bus: /dev/i2c-7\n";
        assert_eq!(parse_detect(text), vec![("DP-1".to_string(), "5".to_string())]);
    }

    #[test]
    fn vcp_brief() {
        assert_eq!(parse_vcp("VCP 10 C 40 100\n"), Some((40, 100)));
        assert_eq!(parse_vcp("VCP 10 ERR\n"), None);
    }
}
