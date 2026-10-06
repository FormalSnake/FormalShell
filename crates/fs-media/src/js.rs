//! The few JavaScript built-ins whose edge cases the ported code relies on.

use std::sync::LazyLock;

use percent_encoding::{AsciiSet, NON_ALPHANUMERIC, utf8_percent_encode};
use regex::Regex;
use serde_json::Value;

// encodeURIComponent leaves A-Z a-z 0-9 - _ . ! ~ * ' ( ) alone.
const URI_COMPONENT: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'-')
    .remove(b'_')
    .remove(b'.')
    .remove(b'!')
    .remove(b'~')
    .remove(b'*')
    .remove(b'\'')
    .remove(b'(')
    .remove(b')');

pub fn encode_uri_component(s: &str) -> String {
    utf8_percent_encode(s, URI_COMPONENT).to_string()
}

static FLOAT_PREFIX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^[\s\u{feff}]*([+-]?(?:Infinity|[0-9]+\.?[0-9]*(?:[eE][+-]?[0-9]+)?|\.[0-9]+(?:[eE][+-]?[0-9]+)?))")
        .unwrap()
});

/// `parseFloat`: the longest numeric prefix, NaN when there is none.
pub fn parse_float(s: &str) -> f64 {
    let Some(m) = FLOAT_PREFIX.captures(s) else {
        return f64::NAN;
    };
    let text = &m[1];
    let (sign, body) = match text.strip_prefix('-') {
        Some(rest) => (-1.0, rest),
        None => (1.0, text.strip_prefix('+').unwrap_or(text)),
    };
    if body == "Infinity" {
        return sign * f64::INFINITY;
    }
    body.parse::<f64>().map(|v| sign * v).unwrap_or(f64::NAN)
}

/// `Number(s)` for a string: whitespace trimmed, empty is 0, 0x/0o/0b
/// prefixes honoured, anything unparsable NaN.
pub fn number_from_str(s: &str) -> f64 {
    let t = s.trim();
    if t.is_empty() {
        return 0.0;
    }
    for (prefix, radix) in [
        ("0x", 16),
        ("0X", 16),
        ("0o", 8),
        ("0O", 8),
        ("0b", 2),
        ("0B", 2),
    ] {
        if let Some(rest) = t.strip_prefix(prefix) {
            return u64::from_str_radix(rest, radix)
                .map(|v| v as f64)
                .unwrap_or(f64::NAN);
        }
    }
    match t {
        "Infinity" | "+Infinity" => return f64::INFINITY,
        "-Infinity" => return f64::NEG_INFINITY,
        _ => {}
    }
    // Rust also accepts "inf" and "nan"; JS does not.
    if t.chars()
        .any(|c| c.is_ascii_alphabetic() && !matches!(c, 'e' | 'E'))
    {
        return f64::NAN;
    }
    t.parse::<f64>().unwrap_or(f64::NAN)
}

/// `s.slice(0, n)` counted in UTF-16 units. A cut that would split a
/// surrogate pair drops the pair instead of leaving half of it.
pub fn slice_utf16(s: &str, n: usize) -> &str {
    let mut units = 0;
    for (i, c) in s.char_indices() {
        units += c.len_utf16();
        if units > n {
            return &s[..i];
        }
    }
    s
}

/// `s.length`.
pub fn utf16_len(s: &str) -> usize {
    s.encode_utf16().count()
}

/// JS's `\s`: WhiteSpace and LineTerminator, which includes U+FEFF and leaves
/// out the U+0085 that `char::is_whitespace` has.
pub fn is_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n' | '\u{b}' | '\u{c}' | '\r' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200a}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202f}'
                | '\u{205f}'
                | '\u{3000}'
                | '\u{feff}'
    )
}

/// `String.prototype.trim`.
pub fn trim(s: &str) -> &str {
    s.trim_matches(is_space)
}

/// `Math.round`: halves go toward +Infinity, where `f64::round` goes away from
/// zero.
pub fn math_round(x: f64) -> f64 {
    let f = x.floor();
    if x - f >= 0.5 { f + 1.0 } else { f }
}

/// `parseInt(s, 10)`: optional whitespace and sign, then the leading digits;
/// NaN when there are none.
pub fn parse_int(s: &str) -> f64 {
    let t = s.trim_start_matches(|c: char| c.is_whitespace() || c == '\u{feff}');
    let (sign, rest) = match t.strip_prefix('-') {
        Some(r) => (-1.0, r),
        None => (1.0, t.strip_prefix('+').unwrap_or(t)),
    };
    let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
    if digits.is_empty() {
        return f64::NAN;
    }
    sign * digits.parse::<f64>().unwrap_or(f64::NAN)
}

/// `String(v)` for a parsed JSON value.
pub fn to_js_string(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Null => "null".into(),
        Value::Array(a) => a
            .iter()
            .map(|e| {
                if e.is_null() {
                    String::new()
                } else {
                    to_js_string(e)
                }
            })
            .collect::<Vec<_>>()
            .join(","),
        Value::Object(_) => "[object Object]".into(),
    }
}

/// `parseInt(s, 10)` for a string of ASCII digits, saturating instead of
/// losing precision past u64.
pub fn parse_digits(s: &str) -> u64 {
    s.parse::<u64>().unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uri_component_matches_js() {
        assert_eq!(
            encode_uri_component("Tyler, The Creator"),
            "Tyler%2C%20The%20Creator"
        );
        assert_eq!(
            encode_uri_component("a-b_c.d!e~f*g'h(i)"),
            "a-b_c.d!e~f*g'h(i)"
        );
        assert_eq!(encode_uri_component("é"), "%C3%A9");
    }

    #[test]
    fn parse_float_takes_the_numeric_prefix() {
        assert_eq!(parse_float("12abc"), 12.0);
        assert_eq!(parse_float("  -1.5e2x"), -150.0);
        assert_eq!(parse_float(".5"), 0.5);
        assert_eq!(parse_float("5."), 5.0);
        assert!(parse_float("abc").is_nan());
        assert!(parse_float("").is_nan());
    }
}
