//! The `hl.*` Lua each write sends, worded as HyprlandBackend.qml words it.
//! Window ids reach this module as the backend's opaque strings; the
//! `address:0x...` selector is built here and nowhere else.

pub const PARK_WORKSPACE: &str = "special:formalshell-console";
const PARK_NAME: &str = "formalshell-console";

/// DMS's `luaString`: a double-quoted Lua string.
pub fn string(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

/// DMS's `luaValue`: an integer stays bare, anything else is a string.
pub fn value(value: &str) -> String {
    let digits = value.strip_prefix(['-', '+']).unwrap_or(value);
    if !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()) { value.to_owned() } else { string(value) }
}

pub fn selector(id: &str) -> String {
    if id.starts_with("0x") { format!("address:{id}") } else { format!("address:0x{id}") }
}

/// One argv word, single-quoted for the shell `exec_cmd` hands it to.
fn quote_arg(arg: &str) -> String {
    format!("'{}'", arg.replace('\'', "'\\''"))
}

pub fn focus_workspace(id: &str) -> String {
    format!("hl.dsp.focus({{ workspace = {} }})", value(id))
}

pub fn focus_window(id: &str) -> String {
    format!("hl.dsp.focus({{ window = {} }})", string(&selector(id)))
}

pub fn close_window(id: &str) -> String {
    format!("hl.dsp.window.close({})", string(&selector(id)))
}

pub fn spawn(argv: &[String]) -> String {
    let cmd: Vec<String> = argv.iter().map(|a| quote_arg(a)).collect();
    format!("hl.dsp.exec_cmd({})", string(&cmd.join(" ")))
}

pub fn dpms(on: bool) -> String {
    format!("hl.dsp.dpms({{ action = \"{}\" }})", if on { "enable" } else { "disable" })
}

pub fn float_window(id: &str) -> String {
    format!("hl.dsp.window.float({{ window = {}, action = \"set\" }})", string(&selector(id)))
}

pub fn resize_window(id: &str, w: i64, h: i64) -> String {
    format!("hl.dsp.window.resize({{ window = {}, x = {w}, y = {h} }})", string(&selector(id)))
}

pub fn move_window(id: &str, x: i64, y: i64) -> String {
    format!("hl.dsp.window.move({{ window = {}, x = {x}, y = {y} }})", string(&selector(id)))
}

pub fn park_window(id: &str) -> String {
    format!(
        "hl.dsp.window.move({{ window = {}, workspace = {}, follow = false }})",
        string(&selector(id)),
        string(PARK_WORKSPACE)
    )
}

pub fn toggle_special() -> String {
    format!("hl.dsp.workspace.toggle_special({})", string(PARK_NAME))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn worded_as_the_qml_backend() {
        assert_eq!(focus_workspace("2"), "hl.dsp.focus({ workspace = 2 })");
        assert_eq!(focus_workspace("name"), "hl.dsp.focus({ workspace = \"name\" })");
        assert_eq!(focus_window("55d0c1b0"), "hl.dsp.focus({ window = \"address:0x55d0c1b0\" })");
        assert_eq!(close_window("0xab"), "hl.dsp.window.close(\"address:0xab\")");
        assert_eq!(
            spawn(&["foot".into(), "-e".into(), "it's".into()]),
            r#"hl.dsp.exec_cmd("'foot' '-e' 'it'\\''s'")"#
        );
        assert_eq!(dpms(false), "hl.dsp.dpms({ action = \"disable\" })");
        assert_eq!(
            park_window("ab"),
            "hl.dsp.window.move({ window = \"address:0xab\", workspace = \"special:formalshell-console\", follow = false })"
        );
        assert_eq!(toggle_special(), "hl.dsp.workspace.toggle_special(\"formalshell-console\")");
        assert_eq!(value("-3"), "-3");
        assert_eq!(value("+"), "\"+\"");
        assert_eq!(string(r#"a"b\c"#), r#""a\"b\\c""#);
    }
}
