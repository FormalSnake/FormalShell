//! The few JavaScript coercions the ported modules lean on, so warning text
//! built from an arbitrary settings value reads the same as it did in QML.

use serde_json::Value;

/// `Math.round`: halves go up, also below zero.
pub fn round(x: f64) -> f64 {
    (x + 0.5).floor()
}

/// The `\s` class of a JS regex and of `String.prototype.trim`.
pub fn is_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n' | '\u{000B}' | '\u{000C}' | '\r' | ' ' | '\u{00A0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200A}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202F}'
                | '\u{205F}'
                | '\u{3000}'
                | '\u{FEFF}'
    )
}

/// `String(number)`.
pub fn number_string(n: f64) -> String {
    if n.is_nan() {
        return "NaN".into();
    }
    if n.is_infinite() {
        return if n > 0.0 { "Infinity" } else { "-Infinity" }.into();
    }
    if n == 0.0 {
        return "0".into();
    }
    let abs = n.abs();
    if !(1e-6..1e21).contains(&abs) {
        let s = format!("{n:e}");
        return match s.split_once('e') {
            Some((m, e)) if !e.starts_with('-') => format!("{m}e+{e}"),
            _ => s,
        };
    }
    format!("{n}")
}

/// `String(value)` for a parsed JSON value.
pub fn string(v: &Value) -> String {
    match v {
        Value::Null => "null".into(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => match (n.as_i64(), n.as_u64()) {
            (Some(i), _) => i.to_string(),
            (_, Some(u)) => u.to_string(),
            _ => number_string(n.as_f64().unwrap_or(f64::NAN)),
        },
        Value::String(s) => s.clone(),
        Value::Array(a) => a
            .iter()
            .map(|e| {
                if e.is_null() {
                    String::new()
                } else {
                    string(e)
                }
            })
            .collect::<Vec<_>>()
            .join(","),
        Value::Object(_) => "[object Object]".into(),
    }
}

/// `String(value)` where the value may be absent, which JS prints as `undefined`.
pub fn string_opt(v: Option<&Value>) -> String {
    v.map_or_else(|| "undefined".into(), string)
}

fn string_number(s: &str) -> f64 {
    let t = s.trim_matches(is_space);
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
        if let Some(digits) = t.strip_prefix(prefix) {
            return u64::from_str_radix(digits, radix).map_or(f64::NAN, |n| n as f64);
        }
    }
    match t {
        "Infinity" | "+Infinity" => return f64::INFINITY,
        "-Infinity" => return f64::NEG_INFINITY,
        _ => {}
    }
    if !t
        .chars()
        .all(|c| c.is_ascii_digit() || matches!(c, '+' | '-' | '.' | 'e' | 'E'))
    {
        return f64::NAN;
    }
    t.parse::<f64>().unwrap_or(f64::NAN)
}

/// `Number(value)`.
pub fn to_number(v: &Value) -> f64 {
    match v {
        Value::Null => 0.0,
        Value::Bool(b) => f64::from(u8::from(*b)),
        Value::Number(n) => n.as_f64().unwrap_or(f64::NAN),
        Value::String(s) => string_number(s),
        Value::Array(_) => string_number(&string(v)),
        Value::Object(_) => f64::NAN,
    }
}

/// `JSON.stringify(value)`.
pub fn stringify(v: &Value) -> String {
    v.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn strings_read_like_js() {
        assert_eq!(string(&json!(2)), "2");
        assert_eq!(string(&json!(2.5)), "2.5");
        assert_eq!(string(&json!(null)), "null");
        assert_eq!(string(&json!([1, null, "a"])), "1,,a");
        assert_eq!(string(&json!({})), "[object Object]");
        assert_eq!(string_opt(None), "undefined");
        assert_eq!(number_string(1e21), "1e+21");
        assert_eq!(number_string(1.5e-7), "1.5e-7");
    }

    #[test]
    fn numbers_read_like_js() {
        assert_eq!(to_number(&json!("12")), 12.0);
        assert_eq!(to_number(&json!("")), 0.0);
        assert!(to_number(&json!("wide")).is_nan());
        assert!(to_number(&json!("inf")).is_nan());
        assert_eq!(to_number(&json!([5])), 5.0);
        assert_eq!(to_number(&json!(true)), 1.0);
        assert_eq!(round(2.5), 3.0);
        assert_eq!(round(-2.5), -2.0);
    }
}
