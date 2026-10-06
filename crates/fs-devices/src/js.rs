//! The few JavaScript semantics the ported logic leans on: `String(x)`,
//! `Number(x)`, `Math.round`, `trim` and `localeCompare`. Output strings
//! reach IPC and the UI byte for byte, so these match the engine rather than
//! Rust's neighbours (`f64::round` rounds half away from zero, JS rounds
//! half up; Rust's `trim` also strips U+0085, JS's does not).

use std::cmp::Ordering;
use std::sync::LazyLock;

use icu_collator::options::CollatorOptions;
use icu_collator::{Collator, CollatorBorrowed};
use serde_json::Value;

/// The whitespace set of JS `\s` and `String.prototype.trim`.
pub(crate) fn is_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n'
            | '\u{b}'
            | '\u{c}'
            | '\r'
            | ' '
            | '\u{a0}'
            | '\u{1680}'
            | '\u{2000}'..='\u{200a}'
            | '\u{2028}'
            | '\u{2029}'
            | '\u{202f}'
            | '\u{205f}'
            | '\u{3000}'
            | '\u{feff}'
    )
}

pub(crate) fn trim(s: &str) -> &str {
    s.trim_matches(is_space)
}

/// JS `\s` as the body of a regex character class.
pub(crate) const SPACE: &str =
    r"\t\n\x0B\x0C\r \x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}\x{feff}";

/// JS `.` (no `s` flag) as a regex atom: everything but the four line terminators.
pub(crate) const DOT: &str = r"[^\n\r\x{2028}\x{2029}]";

/// `Math.round`: halves go toward positive infinity.
pub(crate) fn round(x: f64) -> f64 {
    let r = x.floor();
    if x - r >= 0.5 { r + 1.0 } else { r }
}

/// `String(n)` for a number.
pub(crate) fn num_str(n: f64) -> String {
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

/// `Number(string)`.
pub(crate) fn parse_number(s: &str) -> f64 {
    let t = trim(s);
    if t.is_empty() {
        return 0.0;
    }
    let lower = t.to_ascii_lowercase();
    for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] {
        if let Some(digits) = lower.strip_prefix(prefix) {
            return u64::from_str_radix(digits, radix).map_or(f64::NAN, |n| n as f64);
        }
    }
    match t {
        "Infinity" | "+Infinity" => return f64::INFINITY,
        "-Infinity" => return f64::NEG_INFINITY,
        _ => {}
    }
    // Rust's parser also takes "inf" and "nan"; JS does not.
    if !t.bytes().all(|b| b.is_ascii_digit() || matches!(b, b'.' | b'e' | b'E' | b'+' | b'-')) {
        return f64::NAN;
    }
    t.parse().unwrap_or(f64::NAN)
}

/// `String(v)` for a defined, non-null value.
pub(crate) fn to_str(v: &Value) -> String {
    match v {
        Value::Null => "null".into(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => num_str(n.as_f64().unwrap_or(f64::NAN)),
        Value::String(s) => s.clone(),
        Value::Array(a) => a
            .iter()
            .map(|e| if e.is_null() { String::new() } else { to_str(e) })
            .collect::<Vec<_>>()
            .join(","),
        Value::Object(_) => "[object Object]".into(),
    }
}

/// The `_str` helper the JS models share: undefined and null read as "".
pub(crate) fn opt_str(v: Option<&Value>) -> String {
    match v {
        None | Some(Value::Null) => String::new(),
        Some(v) => to_str(v),
    }
}

/// `Number(v)`; an absent field is `undefined`, so NaN.
pub(crate) fn to_number(v: Option<&Value>) -> f64 {
    match v {
        None => f64::NAN,
        Some(Value::Null) => 0.0,
        Some(Value::Bool(b)) => f64::from(u8::from(*b)),
        Some(Value::Number(n)) => n.as_f64().unwrap_or(f64::NAN),
        Some(Value::String(s)) => parse_number(s),
        Some(Value::Array(a)) => match a.as_slice() {
            [] => 0.0,
            [one] => parse_number(&to_str(one)),
            _ => f64::NAN,
        },
        Some(Value::Object(_)) => f64::NAN,
    }
}

/// `_int`: a rounded finite number, else 0.
pub(crate) fn int(v: Option<&Value>) -> i64 {
    let n = to_number(v);
    if n.is_finite() { round(n) as i64 } else { 0 }
}

/// `obj[key]` where `obj` may be anything: only objects have fields.
pub(crate) fn field<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
    v.as_object().and_then(|o| o.get(key))
}

/// `typeof v === "object" && v` (arrays included, null excluded).
pub(crate) fn is_object_like(v: &Value) -> bool {
    matches!(v, Value::Object(_) | Value::Array(_))
}

/// `for (var k in v)` over a parsed JSON value: integer-like keys first in
/// ascending order, then the rest in insertion order. Array elements are
/// keyed by index.
pub(crate) fn entries(v: &Value) -> Vec<(String, &Value)> {
    match v {
        Value::Object(m) => {
            let is_index = |k: &str| k == "0" || (!k.starts_with('0') && !k.is_empty() && k.len() < 10 && k.bytes().all(|b| b.is_ascii_digit()));
            let mut ints: Vec<(u32, &String, &Value)> = Vec::new();
            let mut rest: Vec<(String, &Value)> = Vec::new();
            for (k, val) in m {
                if is_index(k) {
                    ints.push((k.parse().unwrap_or(0), k, val));
                } else {
                    rest.push((k.clone(), val));
                }
            }
            ints.sort_by_key(|(n, _, _)| *n);
            ints.into_iter().map(|(_, k, val)| (k.clone(), val)).chain(rest).collect()
        }
        Value::Array(a) => a.iter().enumerate().map(|(i, e)| (i.to_string(), e)).collect(),
        _ => Vec::new(),
    }
}

static COLLATOR: LazyLock<CollatorBorrowed<'static>> = LazyLock::new(|| {
    Collator::try_new(Default::default(), CollatorOptions::default()).expect("root collation data is compiled in")
});

/// `a.localeCompare(b)` under the root locale.
pub(crate) fn locale_compare(a: &str, b: &str) -> Ordering {
    COLLATOR.compare(a, b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_goes_half_up() {
        assert_eq!(round(2.5), 3.0);
        assert_eq!(round(-2.5), -2.0);
        assert_eq!(round(-0.4), 0.0);
        assert_eq!(round(42.6), 43.0);
    }

    #[test]
    fn number_strings_match_js() {
        assert_eq!(num_str(85.0), "85");
        assert_eq!(num_str(-0.0), "0");
        assert_eq!(num_str(0.6), "0.6");
        assert_eq!(num_str(1e21), "1e+21");
        assert_eq!(num_str(1.5e-7), "1.5e-7");
    }

    #[test]
    fn parse_number_matches_js() {
        assert_eq!(parse_number(" 42 "), 42.0);
        assert_eq!(parse_number("0x10"), 16.0);
        assert_eq!(parse_number("1e3"), 1000.0);
        assert!(parse_number("loud").is_nan());
        assert!(parse_number("inf").is_nan());
        assert!(parse_number("nan").is_nan());
        assert_eq!(parse_number(""), 0.0);
    }

    #[test]
    fn integer_keys_come_first() {
        let v: Value = serde_json::from_str(r#"{"b":1,"2":2,"a":3,"1":4}"#).unwrap();
        let keys: Vec<String> = entries(&v).into_iter().map(|(k, _)| k).collect();
        assert_eq!(keys, ["1", "2", "b", "a"]);
    }

    #[test]
    fn locale_compare_orders_words() {
        assert_eq!(locale_compare("Alpha", "Mid"), Ordering::Less);
        assert_eq!(locale_compare("zeta", "Alpha"), Ordering::Greater);
    }
}
