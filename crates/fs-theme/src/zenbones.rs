//! Zenbones (github.com/zenbones-theme/zenbones.nvim) as data, in the same
//! three views `flexoki` carries: theme.json's shadcn roles, the Material
//! roles every matugen template is written against, and the base16 slots a
//! terminal palette is built from. `palette` registers it as a pinned
//! palette, so a wallpaper whose path carries "zenbones" lands on these tones
//! instead of a scheme grown from its pixels.
//!
//! Zenbones has no published ramps: the upstream palette is eight hsluv seeds
//! per mode plus lush derivations (lua/zenbones/palette.lua,
//! specs/{dark,light}.lua). Every hex here was computed from those exact
//! derivations with lush's own arithmetic (h/s/l round to integers between
//! ops), and the computation was verified against the repo's generated kitty
//! port (extras/kitty/zenbones_{dark,light}.conf): all 32 port values and
//! both Visual selections reproduce byte for byte. Tones with no upstream
//! name reuse the spec's own idioms (the surface ladder is CursorLine/
//! NormalFloat/Folded/PmenuSel, containers are the DiffAdd recipe) rather
//! than inventing new colours; each carries its derivation.
//!
//! Hue mapping is zenbones' own terminal port (lua/zenbones/term.lua):
//! red=rose, green=leaf, yellow=wood, blue=water, magenta=blossom, cyan=sky.
//! The scheme has six chromatics, so orange doubles on wood and purple on
//! blossom. Bright ANSI is the same mode's `1` variants, not the other
//! mode's stops (unlike Flexoki, whose ports spend both mode stops).

use crate::flexoki::from_pairs;
use serde_json::{Map, Value};

pub type Tones = [(&'static str, &'static str)];

pub const DARK: [(&str, &str); 29] = [
    ("bg", "#1c1917"),         // hsluv(39,12,9)
    ("surface1", "#25211f"),   // bg.li(4)   CursorLine
    ("surface2", "#302b29"),   // bg.li(10)  NormalFloat/Pmenu
    ("surface3", "#393431"),   // bg.li(14)  Folded
    ("surface4", "#4a433f"),   // bg.li(22)  PmenuSel
    ("bg1", "#403833"),        // bg.sa(4).li(16)  bright black
    ("sel", "#3d4042"),        // fg.de(18).lightness(bg.l+18)  Visual
    ("linenr", "#685f5a"),     // bg.li(35)  LineNr
    ("comment", "#6e6763"),    // bg.li(38).de(24)  Comment
    ("fgdim", "#888f94"),      // fg.da(22)  terminal bright white
    ("fg", "#b4bdc3"),         // hsluv(230,10,76)
    ("fgbright", "#c4cacf"),   // fg.li(20)  Cursor
    ("fgbrighter", "#d3d8db"), // fg.li(40)
    ("rose", "#de6e7c"),
    ("leaf", "#819b69"),
    ("wood", "#b77e64"),
    ("water", "#6099c0"),
    ("blossom", "#b279a7"),
    ("sky", "#66a5ad"),
    ("rose1", "#e8838f"),
    ("leaf1", "#8bae68"),
    ("wood1", "#d68c67"),
    ("water1", "#61abda"),
    ("blossom1", "#cf86c1"),
    ("sky1", "#65b8c1"),
    // DiffAdd recipe: hue.saturation(n).lightness(bg.l+8); n is the spec's
    // own per-hue saturation (water/sky 50, wood 46, rose 30).
    ("waterC", "#1d2c36"),
    ("skyC", "#1c2d2f"),
    ("woodC", "#39251c"),
    ("roseC", "#3e2225"),
];

pub const LIGHT: [(&str, &str); 29] = [
    ("bg", "#f0edec"),       // hsluv(39,12,94)
    ("surface1", "#e9e4e2"), // bg.da(3)   CursorLine
    ("surface2", "#ddd6d3"), // bg.da(8)   NormalFloat
    ("surface3", "#dad3cf"), // bg.da(10)  Pmenu
    ("surface4", "#c4b6af"), // bg.da(20)  PmenuSel
    ("bg1", "#cfc1ba"),      // bg.sa(4).da(16)  bright black
    ("sel", "#cbd9e3"),      // fg.lightness(bg.l-8)  Visual
    ("linenr", "#a4968f"),   // bg.da(33)  LineNr
    ("comment", "#948985"),  // bg.da(38).de(28)  Comment
    ("fgdim", "#4f5e68"),    // fg.li(22)  terminal bright white
    ("fg", "#2c363c"),       // hsluv(230,30,22)
    ("fg1s", "#3e4b53"),     // fg.li(11)  spec fg1
    ("fg2s", "#44525b"),     // fg.li(15)  spec fg2
    ("rose", "#a8334c"),
    ("leaf", "#4f6c31"),
    ("wood", "#944927"),
    ("water", "#286486"),
    ("blossom", "#88507d"),
    ("sky", "#3b8992"),
    ("rose1", "#94253e"),
    ("leaf1", "#3f5a22"),
    ("wood1", "#803d1c"),
    ("water1", "#1d5573"),
    ("blossom1", "#7b3b70"),
    ("sky1", "#2b747c"),
    // DiffAdd recipe, lightness bg.l-6 (water/sky 30, wood 46, rose 40).
    ("waterC", "#d4dee7"),
    ("skyC", "#c3e2e7"),
    ("woodC", "#edd8d4"),
    ("roseC", "#ebd8da"),
];

/// Material's `*_fixed` family is mode-independent by definition, so it is
/// derived once from the light-mode hue seeds: fixed is
/// saturation(30).lightness(85), on_fixed lightness(15), on_fixed_variant
/// lightness(35); fixed_dim is the dark-mode stop (Material's own shape:
/// a dim accent that works on the fixed pastel).
pub const FIXED: [(&str, [(&str, &str); 4]); 3] = [
    (
        "water",
        [
            ("fixed", "#cad6e2"),
            ("dim", "#6099c0"),
            ("on", "#0c2838"),
            ("onVariant", "#225775"),
        ],
    ),
    (
        "sky",
        [
            ("fixed", "#b6dbe0"),
            ("dim", "#66a5ad"),
            ("on", "#0d2a2d"),
            ("onVariant", "#245a60"),
        ],
    ),
    (
        "wood",
        [
            ("fixed", "#e3d1cd"),
            ("dim", "#b77e64"),
            ("on", "#3f1c0b"),
            ("onVariant", "#824021"),
        ],
    ),
];

/// What a pinned run hands `matugen color hex` in place of the image: water
/// (the blue), zenbones' de-facto accent. Only seeds the roles no rewrite
/// covers, same as Flexoki's SOURCE.
pub const SOURCE: &str = "#6099c0";

/// The tone table for a mode; anything but "light" is dark.
pub fn tones(mode: &str) -> &'static Tones {
    if mode == "light" { &LIGHT } else { &DARK }
}

/// One tone of a table; panics on a key the table lacks.
pub fn tone(t: &Tones, key: &str) -> &'static str {
    t.iter()
        .find(|(k, _)| *k == key)
        .map(|(_, v)| *v)
        .unwrap_or_else(|| panic!("zenbones: no tone {key}"))
}

fn fixed(hue: &str, key: &str) -> &'static str {
    FIXED
        .iter()
        .find(|(n, _)| *n == hue)
        .and_then(|(_, f)| f.iter().find(|(k, _)| *k == key))
        .map(|(_, v)| *v)
        .unwrap_or_else(|| panic!("zenbones: no fixed {hue}.{key}"))
}

/// theme.json's shadcn roles. The surface ladder fills the neutral slots,
/// water is `primary` and `ring`, rose destructive, wood warning, and
/// chart1..5 walk the chromatics.
pub fn shadcn(mode: &str) -> Map<String, Value> {
    let t = tones(mode);
    let g = |k: &str| tone(t, k);
    let on_accent = g("bg");
    from_pairs(&[
        ("mode", if mode == "light" { "light" } else { "dark" }),
        ("background", g("bg")),
        ("foreground", g("fg")),
        ("card", g("surface1")),
        ("cardForeground", g("fg")),
        ("popover", g("surface2")),
        ("popoverForeground", g("fg")),
        ("primary", g("water")),
        ("primaryForeground", on_accent),
        ("secondary", g("surface2")),
        ("secondaryForeground", g("fg")),
        ("muted", g("surface2")),
        ("mutedForeground", g("fgdim")),
        (
            "accent",
            if mode == "light" {
                g("surface3")
            } else {
                g("surface4")
            },
        ),
        ("accentForeground", g("fg")),
        ("destructive", g("rose")),
        ("destructiveForeground", on_accent),
        ("warning", g("wood")),
        ("warningForeground", on_accent),
        ("border", g("bg1")),
        ("input", g("bg1")),
        ("ring", g("water")),
        ("chart1", g("water")),
        ("chart2", g("sky")),
        ("chart3", g("wood")),
        ("chart4", g("leaf")),
        ("chart5", g("blossom")),
    ])
}

/// base16 over the same tones: the gray ramp walks bg, surface2, Visual,
/// Comment, dim fg, fg, then the spec's own brighter/darker fg steps, accents
/// sit in the canonical slots (0F takes wood, the scheme's brown).
pub fn base16(mode: &str) -> Map<String, Value> {
    let light = mode == "light";
    let t = tones(mode);
    let g = |k: &str| tone(t, k);
    from_pairs(&[
        ("base00", g("bg")),
        ("base01", g("surface2")),
        ("base02", g("sel")),
        ("base03", g("comment")),
        ("base04", g("fgdim")),
        ("base05", g("fg")),
        ("base06", if light { g("fg1s") } else { g("fgbright") }),
        ("base07", if light { g("fg2s") } else { g("fgbrighter") }),
        ("base08", g("rose")),
        ("base09", g("wood")),
        ("base0A", g("wood")),
        ("base0B", g("leaf")),
        ("base0C", g("sky")),
        ("base0D", g("water")),
        ("base0E", g("blossom")),
        ("base0F", g("wood")),
    ])
}

/// Every role matugen emits under `colors.*`, each carrying a zenbones tone.
/// The accents follow the shadcn view: water primary, sky secondary, wood
/// tertiary (the warning colour), rose error. outline is the LineNr tone and
/// outline_variant the bright black, so hairlines stay subtler than dividers
/// in both modes; ANSI 8 (a template reads it off outline) lands on LineNr
/// gray rather than the port's bright black, the one deliberate deviation
/// from the kitty port.
///
/// The eight hue names and their `_alt` twins ride along for terminal
/// templates, exactly like `flexoki`; `_alt` is the mode's own bright
/// variant, which is what zenbones' ports spend on ANSI 9-14.
pub fn material_roles(mode: &str) -> Map<String, Value> {
    let dark = mode != "light";
    let t = tones(mode);
    let other = tones(if dark { "light" } else { "dark" });
    let g = |k: &str| tone(t, k);

    let mut roles = Map::new();
    let mut put = |k: &str, v: &str| {
        roles.insert(k.to_string(), Value::String(v.to_string()));
    };

    put("source_color", SOURCE);
    put("surface_tint", g("water"));

    for (role, hue, container) in [
        ("primary", "water", "waterC"),
        ("secondary", "sky", "skyC"),
        ("tertiary", "wood", "woodC"),
    ] {
        put(role, g(hue));
        put(&format!("on_{role}"), g("bg"));
        put(&format!("{role}_container"), g(container));
        put(&format!("on_{role}_container"), g(&format!("{hue}1")));
        if role == "primary" {
            put("inverse_primary", tone(other, hue));
        }
        put(&format!("{role}_fixed"), fixed(hue, "fixed"));
        put(&format!("{role}_fixed_dim"), fixed(hue, "dim"));
        put(&format!("on_{role}_fixed"), fixed(hue, "on"));
        put(&format!("on_{role}_fixed_variant"), fixed(hue, "onVariant"));
    }

    put("error", g("rose"));
    put("on_error", g("bg"));
    put("error_container", g("roseC"));
    put("on_error_container", g("rose1"));

    put("background", g("bg"));
    put("on_background", g("fg"));
    put("surface", g("bg"));
    put("on_surface", g("fg"));
    put("surface_dim", if dark { g("bg") } else { g("surface3") });
    put("surface_bright", if dark { g("surface4") } else { g("bg") });
    put("surface_container_lowest", g("bg"));
    put("surface_container_low", g("surface1"));
    put("surface_container", g("surface2"));
    put("surface_container_high", g("surface3"));
    put("surface_container_highest", g("surface4"));
    put("surface_variant", g("surface2"));
    put("on_surface_variant", g("fgdim"));
    put("inverse_surface", g("fg"));
    put("inverse_on_surface", g("bg"));

    put("outline", g("linenr"));
    put("outline_variant", g("bg1"));
    put("scrim", tone(&DARK, "bg"));
    put("shadow", tone(&DARK, "bg"));

    for (name, tone_name) in [
        ("red", "rose"),
        ("orange", "wood"),
        ("yellow", "wood"),
        ("green", "leaf"),
        ("cyan", "sky"),
        ("blue", "water"),
        ("purple", "blossom"),
        ("magenta", "blossom"),
    ] {
        put(name, g(tone_name));
        put(&format!("{name}_alt"), g(&format!("{tone_name}1")));
    }
    roles
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::matugen;
    use crate::palette;
    use std::collections::HashSet;

    fn s<'a>(m: &'a Map<String, Value>, k: &str) -> &'a str {
        m.get(k)
            .and_then(Value::as_str)
            .unwrap_or_else(|| panic!("missing {k}"))
    }

    fn pin() -> &'static palette::Pin {
        palette::pinned_palette("zenbones").unwrap()
    }

    /// matugen 4.1.0's own role list, same as the flexoki test: a role
    /// missing from material_roles() is a template expression a pinned run
    /// would leave on matugen's own scheme.
    const MATUGEN_ROLES: [&str; 50] = [
        "background",
        "error",
        "error_container",
        "inverse_on_surface",
        "inverse_primary",
        "inverse_surface",
        "on_background",
        "on_error",
        "on_error_container",
        "on_primary",
        "on_primary_container",
        "on_primary_fixed",
        "on_primary_fixed_variant",
        "on_secondary",
        "on_secondary_container",
        "on_secondary_fixed",
        "on_secondary_fixed_variant",
        "on_surface",
        "on_surface_variant",
        "on_tertiary",
        "on_tertiary_container",
        "on_tertiary_fixed",
        "on_tertiary_fixed_variant",
        "outline",
        "outline_variant",
        "primary",
        "primary_container",
        "primary_fixed",
        "primary_fixed_dim",
        "scrim",
        "secondary",
        "secondary_container",
        "secondary_fixed",
        "secondary_fixed_dim",
        "shadow",
        "source_color",
        "surface",
        "surface_bright",
        "surface_container",
        "surface_container_high",
        "surface_container_highest",
        "surface_container_low",
        "surface_container_lowest",
        "surface_dim",
        "surface_tint",
        "surface_variant",
        "tertiary",
        "tertiary_container",
        "tertiary_fixed",
        "tertiary_fixed_dim",
    ];

    fn is_hex(v: &str) -> bool {
        v.len() == 7
            && v.starts_with('#')
            && v[1..]
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    }

    #[test]
    fn material_roles_cover_matugen() {
        for mode in ["dark", "light"] {
            let roles = material_roles(mode);
            for role in MATUGEN_ROLES {
                let v = roles.get(role).and_then(Value::as_str);
                assert!(v.is_some(), "{mode} is missing {role}");
                assert!(is_hex(v.unwrap()), "{mode}.{role} is not a hex");
            }
        }
    }

    /// Every value has to come off the tone table, or a pinned run ships a
    /// tone zenbones does not have.
    #[test]
    fn every_value_is_on_the_tone_table() {
        let mut known: HashSet<&str> = HashSet::new();
        for mode in ["dark", "light"] {
            for (_, v) in tones(mode) {
                known.insert(v);
            }
        }
        for (_, f) in FIXED {
            for (_, v) in f {
                known.insert(v);
            }
        }
        for mode in ["dark", "light"] {
            for (role, v) in material_roles(mode) {
                let v = v.as_str().unwrap();
                assert!(known.contains(v), "{mode}.{role} is off-table: {v}");
            }
            for (slot, v) in base16(mode) {
                let v = v.as_str().unwrap();
                assert!(known.contains(v), "{mode}.{slot} is off-table: {v}");
            }
        }
    }

    #[test]
    fn source_is_dark_water() {
        assert_eq!(SOURCE, tone(&DARK, "water"));
    }

    /// Zenbones has six chromatics, so the eight hue names double up: orange
    /// rides wood and purple rides blossom. `_alt` is the mode's own bright
    /// variant, which is what zenbones' terminal ports spend on ANSI 9-14
    /// (unlike Flexoki, whose _alt is the other mode's stop).
    #[test]
    fn hue_roles() {
        for mode in ["dark", "light"] {
            let roles = material_roles(mode);
            let t = tones(mode);
            assert_eq!(s(&roles, "green"), tone(t, "leaf"));
            assert_eq!(s(&roles, "green_alt"), tone(t, "leaf1"));
            assert_eq!(s(&roles, "blue"), tone(t, "water"));
            assert_eq!(s(&roles, "blue_alt"), tone(t, "water1"));
            assert_eq!(s(&roles, "orange"), s(&roles, "yellow"));
            assert_eq!(s(&roles, "purple"), s(&roles, "magenta"));
        }
    }

    /// The shell's own palette and the templates read one table: primary is
    /// water, destructive rose, warning wood, in both directions.
    #[test]
    fn shadcn_matches_material() {
        for mode in ["dark", "light"] {
            let sh = shadcn(mode);
            let roles = material_roles(mode);
            assert_eq!(s(&sh, "primary"), s(&roles, "primary"));
            assert_eq!(s(&sh, "background"), s(&roles, "surface"));
            assert_eq!(s(&sh, "foreground"), s(&roles, "on_surface"));
            assert_eq!(s(&sh, "destructive"), s(&roles, "error"));
            assert_eq!(s(&sh, "warning"), s(&roles, "tertiary"));
            assert_eq!(s(&sh, "mutedForeground"), s(&roles, "on_surface_variant"));
            assert_eq!(s(&sh, "border"), s(&roles, "outline_variant"));
        }
        let pin = palette::pinned_palette("/walls/Zenbones-forest.png").unwrap();
        assert_eq!(pin.name, "zenbones");
        assert_eq!(
            s(&pin.shadcn("dark"), "primary"),
            s(&shadcn("dark"), "primary")
        );
        assert_eq!(pin.source, "6099C0");
    }

    /// The upstream kitty port (extras/kitty/zenbones_{dark,light}.conf),
    /// slot for slot as a terminal template renders them: the mode's own hue
    /// stops for ANSI 1-6, the same mode's bright variants for 9-14, and the
    /// dark scheme for black and bright white in both modes. Slots 7, 8 and
    /// 15 deviate from the port on purpose: the template reads them off
    /// on_surface_variant, outline and on_surface.dark, which land on the dim
    /// fg, LineNr gray and full fg (the port's own 7/15 are inverted, its
    /// bright white darker than white, and its 8 is the bright black this
    /// table spends on outline_variant instead).
    #[test]
    fn ansi_ramp_matches_the_zenbones_port() {
        let hues = ["red", "green", "yellow", "blue", "magenta", "cyan"];
        let expected: [(&str, [&str; 16]); 2] = [
            (
                "dark",
                [
                    "#1c1917", "#de6e7c", "#819b69", "#b77e64", "#6099c0", "#b279a7", "#66a5ad",
                    "#888f94", "#685f5a", "#e8838f", "#8bae68", "#d68c67", "#61abda", "#cf86c1",
                    "#65b8c1", "#b4bdc3",
                ],
            ),
            (
                "light",
                [
                    "#1c1917", "#a8334c", "#4f6c31", "#944927", "#286486", "#88507d", "#3b8992",
                    "#4f5e68", "#a4968f", "#94253e", "#3f5a22", "#803d1c", "#1d5573", "#7b3b70",
                    "#2b747c", "#b4bdc3",
                ],
            ),
        ];
        for (mode, want) in expected {
            let roles = material_roles(mode);
            let dark = material_roles("dark");
            let mut ramp: Vec<&str> = vec![s(&dark, "surface")];
            for h in hues {
                ramp.push(s(&roles, h));
            }
            ramp.push(s(&roles, "on_surface_variant"));
            ramp.push(s(&roles, "outline"));
            for h in hues {
                ramp.push(s(&roles, &format!("{h}_alt")));
            }
            ramp.push(s(&dark, "on_surface"));
            for i in 0..16 {
                assert_eq!(ramp[i], want[i], "{mode} ANSI {i}");
            }
        }
    }

    #[test]
    fn substitute_uses_zenbones_tables() {
        let out = matugen::substitute_pinned(
            "a={{colors.surface.default.hex}}\n\
             b={{ colors.primary.default.hex_stripped }}\n\
             e={{base16.base0B.default.hex}}\n",
            "dark",
            pin(),
        );
        assert_eq!(out.substituted, 3);
        assert_eq!(out.skipped.len(), 0);
        assert!(out.text.contains("a=#1c1917"));
        assert!(out.text.contains("b=6099c0"));
        assert!(out.text.contains("e=#819b69"));
    }
}
