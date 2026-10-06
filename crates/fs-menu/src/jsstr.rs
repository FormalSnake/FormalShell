//! The few string operations whose JavaScript semantics differ from Rust's
//! in ways that reach the UI: `trim`, `\s`, and UTF-16 lengths.

/// ECMAScript `WhiteSpace` and `LineTerminator`: Rust's `char::is_whitespace`
/// plus U+FEFF, minus U+0085.
pub fn is_space(c: char) -> bool {
    (c.is_whitespace() && c != '\u{85}') || c == '\u{FEFF}'
}

/// `String.prototype.trim`.
pub fn trim(s: &str) -> &str {
    s.trim_matches(is_space)
}

/// `text.trim().replace(/\s+/g, " ")`.
pub fn collapse_spaces(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_run = false;
    for c in trim(s).chars() {
        if is_space(c) {
            if !in_run {
                out.push(' ');
            }
            in_run = true;
        } else {
            in_run = false;
            out.push(c);
        }
    }
    out
}

/// `s.length`.
pub fn utf16_len(s: &str) -> usize {
    s.encode_utf16().count()
}

/// `s.slice(0, units)`. A cut through a surrogate pair leaves a replacement
/// character where JavaScript would leave a lone surrogate.
pub fn utf16_prefix(s: &str, units: usize) -> String {
    let prefix: Vec<u16> = s.encode_utf16().take(units).collect();
    String::from_utf16_lossy(&prefix)
}
