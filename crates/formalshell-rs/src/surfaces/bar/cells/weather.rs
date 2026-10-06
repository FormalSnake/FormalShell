//! WeatherWidget.qml before its first reading: the thermometer in the meta
//! ink. The forecast fetch fills it in with the weather panel.

use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Env, Look, Part, View};

pub struct Weather;

impl Cell for Weather {
    fn reads(&self) -> &'static [Topic] {
        &[]
    }

    fn read(&mut self, _: &Env) -> bool {
        false
    }

    fn view(&self, look: &Look) -> View {
        View::new(vec![Part::Icon { name: "thermometer".into(), dim: true, dot: false }], look.xs)
            .panel("weather")
            .tooltip("WEATHER / UNAVAILABLE / RIGHT REFRESH")
    }

    fn click(&mut self, button: Button, _: (f64, f64), _: &Env) -> Action {
        match button {
            Button::Right => Action::None,
            _ => Action::Panel("weather"),
        }
    }
}
