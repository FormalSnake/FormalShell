//! `~/.config/hypr/formalshell-chrome.lua` (`shell/Theme/chrome.js`): the
//! window rounding, whether the compositor blurs behind the shell, and the
//! gaps, frame and cast the table's `window` role asks for. Not a matugen
//! template, since none of it comes from the wallpaper.
//!
//! Every value is clamped to the range Hyprland's own option carries
//! (src/config/values/ConfigValues.cpp, 0.56): a value outside one fails the
//! whole `hl.config` call rather than one key.

use serde_json::{Map, Value};

use crate::style;
use crate::tokens::{js_number, js_round};

/// What ThemeEngine hands the renderer: the two settings scalars as written
/// and the `window` role's two states straight off the live table.
#[derive(Clone, Debug, Default)]
pub struct Chrome {
    pub rounding: Option<Value>,
    pub blur: Option<Value>,
    pub window: Option<Map<String, Value>>,
    pub window_inactive: Option<Map<String, Value>>,
}

impl Chrome {
    pub fn from_table(table: &Value, rounding: Value, blur: Value) -> Self {
        Self {
            rounding: Some(rounding),
            blur: Some(blur),
            window: style::entry(table, "window", Some("rest")),
            window_inactive: style::entry(table, "window", Some("inactive")),
        }
    }
}

/// Hyprland's `rounding` is a non-negative int. NaN falls through to 0.
fn rounding(value: Option<&Value>) -> i64 {
    let n = js_round(js_number(value));
    if n > 0.0 { n as i64 } else { 0 }
}

/// Anything but the boolean true is false: a stray string on a bool option
/// is rejected.
fn blur(value: Option<&Value>) -> bool {
    matches!(value, Some(Value::Bool(true)))
}

fn int(value: Option<&Value>, min: i64, max: i64, fallback: i64) -> i64 {
    let n = js_round(js_number(value));
    if !n.is_finite() {
        return fallback;
    }
    (n as i64).clamp(min, max)
}

fn byte(alpha: Option<&Value>) -> String {
    let a = js_number(alpha);
    if !a.is_finite() {
        return "ff".to_owned();
    }
    format!("{:02x}", js_round(a.clamp(0.0, 1.0) * 255.0) as u8)
}

/// A literal renders as Hyprland's `rgba(RRGGBBAA)`; anything else is a
/// palette role and renders as its name, a key into
/// formalshell-colors.lua's table, so the wallpaper keeps moving it. A role
/// therefore arrives at whatever alpha the palette gave it.
fn color(name: Option<&Value>, alpha: Option<&Value>) -> String {
    let name = match name {
        None | Some(Value::Null) => return "rgba(00000000)".to_owned(),
        Some(Value::String(s)) => s.as_str(),
        Some(other) => return other.to_string(),
    };
    if name == "transparent" {
        return "rgba(00000000)".to_owned();
    }
    match style::literal(name) {
        Some(lit) => format!("rgba({}{})", lit.trim_start_matches('#'), byte(alpha)),
        None => name.to_owned(),
    }
}

fn field<'a>(map: Option<&'a Value>, key: &str) -> Option<&'a Value> {
    map.and_then(|m| m.get(key))
}

pub fn hyprland_chrome(chrome: &Chrome) -> String {
    let focused = chrome.window.clone().map(Value::Object);
    let backdrop = chrome.window_inactive.clone().map(Value::Object);
    let border = field(focused.as_ref(), "border");
    let cast = field(focused.as_ref(), "shadow");
    let backdrop_cast = field(backdrop.as_ref(), "shadow");
    let offset = field(cast, "offset");

    let gaps_in = int(field(focused.as_ref(), "gapsIn"), 0, 100, 4);
    let gaps_out = int(field(focused.as_ref(), "gapsOut"), 0, 100, 8);
    let border_size = int(field(border, "width"), 0, 20, 1);
    let border_color = color(field(border, "color"), field(border, "alpha"));
    let enabled = blur(field(cast, "enabled"));
    let range = int(field(cast, "range"), 0, 100, 4);
    let power = int(field(cast, "renderPower"), 1, 4, 3);
    let ox = int(offset.and_then(|o| o.get(0)), -250, 250, 0);
    let oy = int(offset.and_then(|o| o.get(1)), -250, 250, 0);
    let shadow_color = color(field(cast, "color"), field(cast, "alpha"));
    let backdrop_color = color(field(backdrop_cast, "color"), field(backdrop_cast, "alpha"));

    format!(
        "-- Written by the shell (ThemeEngine) into ~/.config/hypr/formalshell-chrome.lua\n\
         -- on every theme.radius/theme.blur/theme.preset change, for a hyprland.lua\n\
         -- that reads it back with `dofile`. The shell asks Hyprland to reload after\n\
         -- each write.\n\
         return {{\n  \
         rounding = {},\n  \
         blur = {},\n  \
         gapsIn = {gaps_in},\n  \
         gapsOut = {gaps_out},\n  \
         borderSize = {border_size},\n  \
         borderColor = \"{border_color}\",\n  \
         shadow = {enabled},\n  \
         shadowRange = {range},\n  \
         shadowPower = {power},\n  \
         shadowOffset = {{ {ox}, {oy} }},\n  \
         shadowColor = \"{shadow_color}\",\n  \
         shadowInactiveColor = \"{backdrop_color}\",\n\
         }}\n",
        rounding(chrome.rounding.as_ref()),
        blur(chrome.blur.as_ref()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tables;
    use serde_json::json;

    fn chrome_for(table: &Value, rounding: Value, blur: Value) -> Chrome {
        Chrome::from_table(table, rounding, blur)
    }

    fn raw(v: Value) -> Chrome {
        let o = |k: &str| v.get(k).and_then(Value::as_object).cloned();
        Chrome { rounding: v.get("rounding").cloned(), blur: v.get("blur").cloned(), window: o("window"), window_inactive: o("windowInactive") }
    }

    /// The table alone, with the file's own header dropped.
    fn body(text: &str) -> String {
        text.trim().lines().filter(|l| !l.starts_with("--")).collect::<Vec<_>>().join("\n")
    }

    #[allow(clippy::too_many_arguments)]
    fn expected(
        rounding: i64,
        blur: &str,
        gaps: (i64, i64),
        border_size: i64,
        border_color: &str,
        shadow: &str,
        range: i64,
        power: i64,
        offset: &str,
        shadow_color: &str,
        inactive: &str,
    ) -> String {
        format!(
            "return {{\n  rounding = {rounding},\n  blur = {blur},\n  gapsIn = {},\n  gapsOut = {},\n  borderSize = {border_size},\n  borderColor = {border_color},\n  shadow = {shadow},\n  shadowRange = {range},\n  shadowPower = {power},\n  shadowOffset = {offset},\n  shadowColor = {shadow_color},\n  shadowInactiveColor = {inactive},\n}}",
            gaps.0, gaps.1
        )
    }

    #[test]
    fn the_shipped_table_renders_the_shipped_chrome() {
        let out = hyprland_chrome(&chrome_for(tables::metamorphosis(), json!(10), json!(true)));
        let lines: Vec<&str> = out.trim().lines().collect();
        for line in &lines[..4] {
            assert!(line.starts_with("--"));
        }
        assert_eq!(
            body(&out),
            expected(10, "true", (4, 8), 1, "\"primary\"", "false", 4, 3, "{ 0, 0 }", "\"rgba(000000ed)\"", "\"rgba(000000ed)\"")
        );
    }

    #[test]
    fn retro_squares_the_corners_and_keeps_the_window_chrome() {
        assert_eq!(
            body(&hyprland_chrome(&chrome_for(tables::metamorphosis(), json!(0), json!(false)))),
            expected(0, "false", (4, 8), 1, "\"primary\"", "false", 4, 3, "{ 0, 0 }", "\"rgba(000000ed)\"", "\"rgba(000000ed)\"")
        );
    }

    #[test]
    fn the_pantheon_table_renders_elementarys_window() {
        assert_eq!(
            body(&hyprland_chrome(&chrome_for(tables::pantheon(), json!(6), json!(true)))),
            expected(6, "true", (4, 6), 1, "\"border\"", "true", 24, 3, "{ 0, 6 }", "\"rgba(00000059)\"", "\"rgba(00000040)\"")
        );
    }

    #[test]
    fn rounding_is_a_non_negative_int() {
        let t = tables::metamorphosis();
        assert!(hyprland_chrome(&chrome_for(t, json!(10.6), json!(false))).contains("rounding = 11,"));
        assert!(hyprland_chrome(&chrome_for(t, json!(-4), json!(false))).contains("rounding = 0,"));
        assert!(hyprland_chrome(&chrome_for(t, json!("square"), json!(false))).contains("rounding = 0,"));
    }

    #[test]
    fn blur_is_a_real_bool() {
        let t = tables::metamorphosis();
        assert!(hyprland_chrome(&chrome_for(t, json!(0), json!("yes"))).contains("blur = false,"));
        let mut absent = chrome_for(t, json!(0), Value::Null);
        absent.blur = None;
        assert!(hyprland_chrome(&absent).contains("blur = false,"));
    }

    #[test]
    fn the_window_values_are_clamped_to_hyprlands_own_ranges() {
        let wild = raw(json!({
            "rounding": 0,
            "blur": false,
            "window": {
                "border": { "color": "primary", "width": 99 },
                "shadow": { "enabled": "on", "range": 4000, "renderPower": 9, "offset": [-999, "down"], "color": "black", "alpha": 4 }
            },
            "windowInactive": { "shadow": { "color": "black", "alpha": -1 } }
        }));
        assert_eq!(
            body(&hyprland_chrome(&wild)),
            expected(0, "false", (4, 8), 20, "\"primary\"", "false", 100, 4, "{ -250, 0 }", "\"rgba(000000ff)\"", "\"rgba(00000000)\"")
        );

        let thin = raw(json!({
            "rounding": 0,
            "blur": false,
            "window": {
                "border": { "color": "border", "width": -3 },
                "shadow": { "enabled": true, "range": "wide", "renderPower": 0, "offset": [], "color": "white", "alpha": 0.5 }
            },
            "windowInactive": {}
        }));
        assert_eq!(
            body(&hyprland_chrome(&thin)),
            expected(0, "false", (4, 8), 0, "\"border\"", "true", 4, 1, "{ 0, 0 }", "\"rgba(ffffff80)\"", "\"rgba(00000000)\"")
        );
    }

    #[test]
    fn a_table_with_no_window_role_still_renders_every_key() {
        assert_eq!(
            body(&hyprland_chrome(&raw(json!({ "rounding": 10, "blur": true })))),
            expected(10, "true", (4, 8), 1, "\"rgba(00000000)\"", "false", 4, 3, "{ 0, 0 }", "\"rgba(00000000)\"", "\"rgba(00000000)\"")
        );
    }

    #[test]
    fn each_table_publishes_its_own_gaps() {
        let shadcn = hyprland_chrome(&chrome_for(tables::metamorphosis(), json!(10), json!(true)));
        assert!(shadcn.contains("gapsIn = 4,\n"));
        assert!(shadcn.contains("gapsOut = 8,\n"));
        let pantheon = hyprland_chrome(&chrome_for(tables::pantheon(), json!(6), json!(true)));
        assert!(pantheon.contains("gapsOut = 6,\n"));
    }

    #[test]
    fn the_gaps_are_clamped_and_fall_back() {
        let bare = raw(json!({ "rounding": 0, "blur": false, "window": {}, "windowInactive": {} }));
        assert!(hyprland_chrome(&bare).contains("gapsIn = 4,\n"));
        assert!(hyprland_chrome(&bare).contains("gapsOut = 8,\n"));

        let wild = raw(json!({ "rounding": 0, "blur": false, "window": { "gapsIn": -5, "gapsOut": 4000 }, "windowInactive": {} }));
        assert!(hyprland_chrome(&wild).contains("gapsIn = 0,\n"));
        assert!(hyprland_chrome(&wild).contains("gapsOut = 100,\n"));
    }
}
