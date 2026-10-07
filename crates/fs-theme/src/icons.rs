//! Icons by name: the Lucide and Nerd tables picked
//! by `theme.icons`, and the distro logos the launcher draws whatever the set.
//! The tables are generated files, read as data.

use std::collections::HashMap;
use std::sync::OnceLock;

const LUCIDE: &str = include_str!("../icons/lucide.js");
const NERD: &str = include_str!("../icons/nerd.js");
const DISTRO: &str = include_str!("../icons/distro.js");

/// The family Lucide's glyphs are drawn in.
pub const LUCIDE_FAMILY: &str = "lucide";
/// The font-logos range Nerd Fonts embeds; the distro marks and the `nerd`
/// set both resolve in it.
pub const SYMBOLS_FAMILY: &str = "Symbols Nerd Font";
/// The generic Tux, for a Linux the logo table does not name.
pub const TUX: &str = "\u{F31A}";

/// A glyph and the family it is drawn in.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Glyph {
    pub text: &'static str,
    pub family: &'static str,
}

struct Table {
    glyphs: HashMap<&'static str, &'static str>,
    family: &'static str,
}

/// `"name": "\u{XXXX}"` pairs, one per line, as the generators write them.
fn parse(source: &'static str) -> HashMap<&'static str, &'static str> {
    let mut out = HashMap::new();
    for line in source.lines() {
        let line = line.trim();
        let Some(rest) = line.strip_prefix('"') else { continue };
        let Some((name, rest)) = rest.split_once('"') else { continue };
        let Some(start) = rest.find("\"\\u{") else { continue };
        let code = &rest[start + 4..];
        let Some(end) = code.find('}') else { continue };
        let Some(c) = u32::from_str_radix(&code[..end], 16).ok().and_then(char::from_u32) else { continue };
        let text: &'static str = Box::leak(c.to_string().into_boxed_str());
        out.entry(name).or_insert(text);
    }
    out
}

fn lucide() -> &'static Table {
    static T: OnceLock<Table> = OnceLock::new();
    T.get_or_init(|| Table { glyphs: parse(LUCIDE), family: LUCIDE_FAMILY })
}

fn nerd() -> &'static Table {
    static T: OnceLock<Table> = OnceLock::new();
    T.get_or_init(|| Table { glyphs: parse(NERD), family: SYMBOLS_FAMILY })
}

fn distro() -> &'static HashMap<&'static str, &'static str> {
    static T: OnceLock<HashMap<&'static str, &'static str>> = OnceLock::new();
    T.get_or_init(|| parse(DISTRO))
}

/// `Icons.glyph(set, name)`: an unknown set reads as `lucide`, and a name
/// missing from the set is that set's own `circle-help`.
pub fn glyph(set: &str, name: &str) -> Glyph {
    let table = if set == "nerd" { nerd() } else { lucide() };
    let text = table.glyphs.get(name).or_else(|| table.glyphs.get("circle-help")).copied().unwrap_or("?");
    Glyph { text, family: table.family }
}

/// The real logo for an os-release `ID`, or none.
pub fn distro_logo(id: &str) -> Option<&'static str> {
    distro().get(id.trim().to_lowercase().as_str()).copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tables_parse() {
        assert!(lucide().glyphs.len() > 1500);
        assert!(nerd().glyphs.len() > 100);
        assert_eq!(glyph("lucide", "bell").text, "\u{E059}");
        assert_eq!(glyph("nerd", "bell").text, "\u{F009A}");
        assert_eq!(glyph("nope", "no-such-icon"), glyph("lucide", "circle-help"));
        assert_eq!(distro_logo("NixOS"), Some("\u{F313}"));
        assert_eq!(distro_logo("plan9"), None);
    }
}
