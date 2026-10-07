//! NetworkPanel.qml: a hero for the connected network, the throughput the
//! last speed test measured, the wired devices, one row per Wi-Fi network
//! (connected, then known, then by signal), the inline passphrase prompt a
//! secured network nobody knows opens, and the speed test footer.
//!
//! The panel holds the scanner while it is open; its close ends a running
//! speed test (`network::Hold`).

use fs_devices::network::speedtest;

use super::{Edit, Effect, Panel, View};
use crate::services::devices::{self, network as net};
use crate::store::Topic;
use crate::ui::{El, Event, Ink, Type, Variant, Weight, What, w};

/// The mask AuthPrompt.qml and the passphrase field draw.
const MASK: char = '\u{25CF}';

#[derive(Clone, Copy, PartialEq, Eq)]
enum Field {
    Identity,
    Password,
}

#[derive(Default)]
pub struct Network {
    hold: Option<net::Hold>,
    /// The SSID whose prompt is open.
    prompt: Option<String>,
    identity: String,
    password: String,
    field: Option<Field>,
}

fn row_key(ssid: &str) -> String {
    format!("wifi:{ssid}")
}

impl Network {
    fn state<'a>(fx: &'a Effect) -> &'a net::Network {
        &fx.store.devices.network
    }

    fn open_prompt(&mut self, ssid: &str, enterprise: bool) {
        if self.prompt.as_deref() != Some(ssid) {
            self.identity.clear();
            self.password.clear();
        }
        self.prompt = Some(ssid.to_owned());
        self.field = Some(if enterprise { Field::Identity } else { Field::Password });
    }

    fn cancel_prompt(&mut self) {
        self.prompt = None;
        self.identity.clear();
        self.password.clear();
        self.field = None;
    }

    /// `_activateWifiRow` and WifiService.activate.
    fn activate_row(&mut self, ssid: &str, fx: &mut Effect) {
        let n = Self::state(fx);
        if n.action.is_some() || self.prompt.as_deref() == Some(ssid) {
            return;
        }
        let Some(row) = n.row(ssid).cloned() else { return };
        let ssid = ssid.to_owned();
        if row.connected {
            fx.service(move |ctx| net::disconnect(ctx, ssid));
            return;
        }
        let retype = n.failure.as_ref().is_some_and(|f| f.ssid == ssid && f.secret);
        if retype || (row.secured && !row.known) {
            self.open_prompt(&ssid, row.enterprise);
            return;
        }
        fx.service(move |ctx| net::connect(ctx, ssid, net::Secret::Saved));
    }

    /// `_submitPassword`.
    fn submit(&mut self, fx: &mut Effect) {
        let n = Self::state(fx);
        let Some(ssid) = self.prompt.clone() else { return };
        if n.action.is_some() || self.password.is_empty() {
            return;
        }
        let Some(row) = n.row(&ssid) else { return };
        let secret = if row.enterprise {
            if self.identity.is_empty() {
                self.field = Some(Field::Identity);
                return;
            }
            net::Secret::Eap { identity: self.identity.clone(), password: self.password.clone() }
        } else {
            net::Secret::Psk(self.password.clone())
        };
        fx.service(move |ctx| net::connect(ctx, ssid, secret));
    }

    fn forget(&self, ssid: &str, fx: &mut Effect) {
        let n = Self::state(fx);
        if n.action.is_some() || !n.row(ssid).is_some_and(|r| r.known && !r.connected) {
            return;
        }
        let ssid = ssid.to_owned();
        fx.service(move |ctx| net::forget(ctx, ssid));
    }

    fn speed(fx: &mut Effect) {
        if !Self::state(fx).speed.running() {
            fx.service(|ctx| {
                net::speed_start(ctx);
            });
        }
    }

    /// The prompt shows while its network has not connected.
    fn prompt_for<'a>(&self, n: &'a net::Network) -> Option<&'a net::Row> {
        let ssid = self.prompt.as_deref()?;
        n.row(ssid).filter(|r| !r.connected)
    }

    fn wifi_row(&self, v: &View, r: &net::Row) -> El {
        let s = &v.theme.space;
        let n = &v.store.devices.network;
        let key = row_key(&r.ssid);
        let mine = |ssid: &str| ssid == r.ssid;
        let status = match (&n.action, &n.failure) {
            (Some((kind, ssid)), _) if mine(ssid) => Some((
                match kind {
                    net::ActionKind::Connect => "Connecting",
                    net::ActionKind::Disconnect => "Disconnecting",
                    net::ActionKind::Forget => "Forgetting",
                }
                .to_owned(),
                false,
            )),
            (_, Some(f)) if mine(&f.ssid) => Some((f.text.clone(), true)),
            _ => None,
        };
        let failed = status.as_ref().is_some_and(|(_, f)| *f);
        let name = if r.ssid.is_empty() { w::label("Hidden network").ink(Ink::Muted) } else { w::label(r.ssid.clone()) };
        let mut top = vec![w::icon("wifi"), name.elide(), w::value(format!("{}%", (r.signal * 100.0).round()))];
        // Forget reveals on the row the pointer or the keyboard is on.
        if r.known && !r.connected && v.cursor == Some(key.as_str()) && n.action.is_none() {
            top.push(w::icon("trash").ink(Ink::Dim).on(format!("forget:{}", r.ssid)).tip("Forget"));
        }
        if r.secured {
            top.push(w::icon("lock").ink(Ink::Dim));
        }
        if r.connected {
            top.push(w::icon("check").ink(Ink::Primary));
        }
        let mut parts = vec![w::row(s.icon_gap, top).fill()];
        if let Some((text, failed)) = status {
            parts.push(w::section_label(s, &text, None, false).ink(if failed { Ink::Destructive } else { Ink::Dim }));
        }
        if self.prompt_for(n).is_some_and(|p| p.ssid == r.ssid) {
            let mut fields = Vec::new();
            if r.enterprise {
                fields.push(w::input(&self.identity, "Identity (user@domain)", self.field == Some(Field::Identity), None).key("identity"));
            }
            let masked: String = std::iter::repeat_n(MASK, self.password.chars().count()).collect();
            let error = n.failure.as_ref().filter(|f| failed && mine(&f.ssid)).map(|f| f.text.as_str());
            fields.push(w::input(&masked, "Passphrase", self.field == Some(Field::Password), error).key("passphrase"));
            parts.push(w::column(s.xs, fields));
        }
        w::cell(w::column(s.xs, parts).fill()).ghost().interactive().stop(key).on(format!("row:{}", r.ssid))
    }

    fn throughput(&self, v: &View) -> El {
        let s = &v.theme.space;
        let st = &v.store.devices.network.speed;
        let rate = |live: bool, live_v: f64, result: f64| {
            if live {
                speedtest::format_mbps(live_v)
            } else if result > 0.0 {
                speedtest::format_mbps(result)
            } else {
                "--".into()
            }
        };
        let down = rate(st.phase == net::Phase::Down, st.down.live_mbps, st.down_result);
        let up = rate(st.phase == net::Phase::Up, st.up.live_mbps, st.up_result);
        let half = |label: &str, glyph: &str, value: String| {
            w::column(
                s.xxs,
                vec![
                    w::section_label(s, label, None, false),
                    w::row(s.icon_gap, vec![w::icon(glyph).ink(Ink::Dim), w::text(format!("{value} Mbps")).mono().weight(Weight::Medium)]),
                ],
            )
            .fill()
        };
        let mut inner = vec![w::row(s.section_gap, vec![half("Download", "download", down), half("Upload", "upload", up)]).fill()];
        let status = if !st.error.is_empty() {
            Some(st.error.clone())
        } else {
            match st.phase {
                net::Phase::Resolving => Some("Resolving interface".into()),
                net::Phase::Down => Some("Measuring down".into()),
                net::Phase::Up => Some("Measuring up".into()),
                _ => None,
            }
        };
        if let Some(t) = status {
            let ink = if st.error.is_empty() { Ink::Dim } else { Ink::Destructive };
            inner.push(w::section_label(s, &t, None, false).ink(ink));
        }
        w::column(s.row_gap, vec![w::section_label(s, "Throughput", None, true), w::cell(w::column(s.xs, inner).fill()).ghost()])
    }

    /// The share row and its code, then the password row while a network
    /// is connected.
    fn share(&self, v: &View) -> El {
        let s = &v.theme.space;
        let n = &v.store.devices.network;
        let open = n.qr != net::Qr::Closed;
        let toggle_row = |glyph: &str, label: &str, state: &str, on: bool| {
            w::row(
                s.icon_gap,
                vec![
                    w::icon(glyph),
                    w::label(label).elide(),
                    w::section_label(s, state, None, false).ink(if on { Ink::Primary } else { Ink::Dim }),
                ],
            )
            .fill()
        };
        let mut parts =
            vec![w::cell(toggle_row("share-2", "Share network", if open { "Hide QR" } else { "QR" }, open)).interactive().stop("share").on("share")];
        match &n.qr {
            net::Qr::Generating => parts.push(w::section_label(s, "Generating", None, true)),
            net::Qr::Failed(e) => parts.push(w::section_label(s, e, None, true)),
            net::Qr::Shown(rows) => parts.push(w::cell(w::matrix(rows.clone()))),
            net::Qr::Closed => {}
        }
        if n.ssid.is_some() {
            let shown = n.reveal != net::Reveal::Idle;
            let mut inner = vec![toggle_row("lock", "Password", if shown { "Hide" } else { "Show" }, shown)];
            match &n.reveal {
                net::Reveal::Idle => {
                    let mask: String = std::iter::repeat_n(MASK, 12).collect();
                    inner.push(w::text(mask).mono().ink(Ink::Muted));
                }
                net::Reveal::Shown(secret) => inner.push(w::text(secret.clone()).mono()),
                net::Reveal::Reading => inner.push(w::section_label(s, "Reading", None, false).ink(Ink::Dim)),
                net::Reveal::Failed(e) => inner.push(w::section_label(s, e, None, false).ink(Ink::Destructive)),
            }
            parts.push(w::cell(w::column(s.xs, inner).fill()).interactive().stop("password").on("password"));
        }
        w::column(s.row_gap, parts)
    }

    fn footer(&self, v: &View) -> El {
        let s = &v.theme.space;
        let st = &v.store.devices.network.speed;
        let running = st.running();
        let down = if st.phase == net::Phase::Down {
            speedtest::format_mbps(st.down.live_mbps)
        } else if st.down_result > 0.0 {
            speedtest::format_mbps(st.down_result)
        } else {
            "--".into()
        };
        let button = w::icon_text_button("zap", if running { "Running" } else { "Speed test" })
            .variant(Variant::Outline)
            .enabled(!running)
            .stop("speedtest")
            .on("speedtest");
        let result = w::row(
            s.xs,
            vec![
                w::text(down).mono().size(Type::Display).weight(Weight::Semibold),
                w::section_label(s, "Mbps", None, false).mono(),
            ],
        );
        w::row(0.0, vec![button, w::space(0.0).fill(), result]).fill()
    }
}

impl Panel for Network {
    fn id(&self) -> &'static str {
        "network"
    }

    fn title(&self, _: &View) -> String {
        "Wi-Fi".into()
    }

    fn icon(&self, _: &View) -> String {
        "wifi".into()
    }

    fn reads(&self) -> &'static [Topic] {
        &[Topic::Devices]
    }

    fn actions(&self, v: &View) -> Vec<El> {
        let n = &v.store.devices.network;
        vec![
            w::switch(n.wifi_enabled).on("radio"),
            w::icon_button("refresh-cw").enabled(n.wifi_device.is_some()).tip("Rescan").on("rescan").key("rescan"),
        ]
    }

    fn body(&self, v: &View) -> El {
        let s = &v.theme.space;
        let n = &v.store.devices.network;
        let mut parts = Vec::new();
        if let Some((iface, mac)) = &n.wifi_device {
            let connected = n.ssid.as_ref();
            let meta = match connected {
                None if n.wifi_enabled => "Disconnected".to_owned(),
                None => "Radio off".to_owned(),
                Some(_) if !mac.is_empty() => mac.clone(),
                Some(_) => "Connected".to_owned(),
            };
            let mono = connected.is_some() && !mac.is_empty();
            parts.push(w::hero_with(
                s,
                w::Hero {
                    glyph: if connected.is_some() { "wifi" } else { "wifi-off" }.into(),
                    title: connected.map_or_else(|| iface.clone(), |(ssid, _)| ssid.clone()),
                    meta,
                    readout: String::new(),
                    trailing: connected.map(|(_, signal)| w::value(format!("signal {signal}%"))),
                    rail: None,
                    rail_on: None,
                },
                mono,
                Type::Display,
                None,
            ));
        }
        parts.push(self.throughput(v));
        if n.wired_rows.is_empty() && n.wifi_device.is_none() {
            parts.push(w::section_label(s, "No devices", None, true));
        }
        if !n.wired_rows.is_empty() {
            let rows = n
                .wired_rows
                .iter()
                .map(|d| {
                    let mut r = vec![w::icon("globe"), w::label(d.name.clone()).elide()];
                    if d.connected {
                        r.push(w::icon("check").ink(Ink::Primary));
                    }
                    w::cell(w::row(s.icon_gap, r).fill()).ghost()
                })
                .collect();
            parts.push(w::section(s, "Wired", Some(n.wired_rows.len()), rows));
        }
        if n.wifi_device.is_some() {
            let mut rows: Vec<El> = n.rows.iter().map(|r| self.wifi_row(v, r)).collect();
            if rows.is_empty() {
                rows.push(w::section_label(s, if n.wifi_enabled { "Scanning" } else { "Radio off" }, None, true));
            }
            parts.push(w::section(s, "Networks", Some(n.rows.len()), rows));
            parts.push(self.share(v));
        }
        parts.push(w::separator());
        parts.push(self.footer(v));
        w::column(s.section_gap, parts)
    }

    fn opened(&mut self) {
        self.hold = Some(net::Hold::new());
    }

    fn closed(&mut self) {
        self.hold = None;
        self.cancel_prompt();
    }

    fn editing(&self) -> bool {
        self.prompt.is_some()
    }

    fn edit(&mut self, e: Edit, fx: &mut Effect) {
        let enterprise = self.prompt.as_deref().and_then(|p| Self::state(fx).row(p)).is_some_and(|r| r.enterprise);
        if self.prompt_for(Self::state(fx)).is_none() {
            self.cancel_prompt();
            return;
        }
        let field = self.field.unwrap_or(Field::Password);
        let text = if field == Field::Identity { &mut self.identity } else { &mut self.password };
        match e {
            Edit::Insert(t) => text.push_str(&t),
            Edit::Back => {
                text.pop();
            }
            Edit::Tab if enterprise => {
                self.field = Some(if field == Field::Identity { Field::Password } else { Field::Identity });
            }
            Edit::Tab => {}
            Edit::Submit if field == Field::Identity => self.field = Some(Field::Password),
            Edit::Submit => self.submit(fx),
            Edit::Cancel => self.cancel_prompt(),
        }
    }

    fn event(&mut self, ev: &Event, fx: &mut Effect) {
        match (ev.on.as_str(), &ev.what) {
            ("radio", What::Toggle(on)) => {
                let on = *on;
                fx.service(move |ctx| devices::run(ctx, devices::Op::Wifi(on)));
            }
            ("rescan", What::Click) => fx.service(|ctx| devices::run(ctx, devices::Op::Rescan)),
            ("speedtest", What::Click) => Self::speed(fx),
            ("share", What::Click) => fx.service(net::qr_toggle),
            ("password", What::Click) => fx.service(net::reveal_toggle),
            (on, What::Click) => {
                if let Some(ssid) = on.strip_prefix("row:") {
                    self.activate_row(ssid, fx);
                } else if let Some(ssid) = on.strip_prefix("forget:") {
                    self.forget(ssid, fx);
                }
            }
            _ => {}
        }
    }

    fn activate(&mut self, stop: &str, fx: &mut Effect) {
        if stop == "speedtest" {
            Self::speed(fx);
        } else if stop == "share" {
            fx.service(net::qr_toggle);
        } else if stop == "password" {
            fx.service(net::reveal_toggle);
        } else if let Some(ssid) = stop.strip_prefix("wifi:") {
            self.activate_row(ssid, fx);
        }
    }

    fn delete(&mut self, stop: &str, fx: &mut Effect) {
        if let Some(ssid) = stop.strip_prefix("wifi:") {
            self.forget(ssid, fx);
        }
    }
}
