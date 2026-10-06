//! AudioPanel.qml's hero: the default sink with its rail as the master
//! slider and its mute as a `Switch`, one cursor stop. Left and Right step
//! the volume by 5%, Enter and `m` mute. The device, input and app
//! sections land with the PipeWire graph (R3 Task 2).

use super::{Effect, Panel, View};
use crate::services::devices;
use crate::store::Topic;
use crate::ui::{El, Event, What, w};

/// AudioModel.clampDevice's step.
const STEP: f64 = 0.05;

#[derive(Default)]
pub struct Audio;

fn set_volume(fx: &Effect, v: f64) {
    fx.service(move |ctx| devices::run(ctx, devices::Op::Volume(v.clamp(0.0, 1.0))));
}

fn mute(fx: &Effect) {
    fx.service(|ctx| devices::run(ctx, devices::Op::ToggleMute));
}

impl Panel for Audio {
    fn id(&self) -> &'static str {
        "audio"
    }

    fn title(&self, _: &View) -> String {
        "Audio".into()
    }

    fn icon(&self, _: &View) -> String {
        "volume-2".into()
    }

    fn reads(&self) -> &'static [Topic] {
        &[Topic::Devices]
    }

    fn body(&self, v: &View) -> El {
        let s = &v.theme.space;
        let a = &v.store.devices.audio;
        let Some(volume) = a.volume else {
            return w::column(s.section_gap, vec![w::section_label(s, "No devices", None, true)]);
        };
        let volume = volume.clamp(0.0, 1.0);
        let hero = w::hero(
            s,
            w::Hero {
                glyph: if a.muted { "volume-x" } else { "volume-2" }.into(),
                title: if a.name.is_empty() { "Output".into() } else { a.name.clone() },
                meta: if a.muted { "Muted" } else { "Active" }.into(),
                readout: format!("{}%", (volume * 100.0).round()),
                trailing: Some(w::switch(!a.muted).on("mute")),
                rail: Some(volume),
                rail_on: Some("volume".into()),
            },
        )
        .stop("output-slider");
        w::column(s.section_gap, vec![hero])
    }

    fn event(&mut self, ev: &Event, fx: &mut Effect) {
        let volume = fx.store.devices.audio.volume.unwrap_or(0.0);
        match (ev.on.as_str(), &ev.what) {
            ("mute", What::Toggle(_)) => mute(fx),
            ("volume", What::Fraction(f)) => set_volume(fx, *f),
            ("volume", What::Wheel(d)) => set_volume(fx, volume + *d as f64 * STEP),
            _ => {}
        }
    }

    fn activate(&mut self, stop: &str, fx: &mut Effect) {
        if stop == "output-slider" {
            mute(fx);
        }
    }

    fn step(&mut self, stop: &str, direction: i32, fx: &mut Effect) {
        if stop == "output-slider" {
            let volume = fx.store.devices.audio.volume.unwrap_or(0.0);
            set_volume(fx, volume + direction as f64 * STEP);
        }
    }

    fn key(&mut self, stop: Option<&str>, text: &str, fx: &mut Effect) {
        if (text == "m" || text == "M") && stop == Some("output-slider") {
            mute(fx);
        }
    }

    fn steps(&self) -> bool {
        true
    }
}
