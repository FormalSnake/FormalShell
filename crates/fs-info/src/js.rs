//! The few JavaScript coercions the ported modules lean on, kept exact where
//! the output reaches the UI or an IPC reply (number printing, rounding,
//! `Number()`, `parseInt`, `trim`).

use serde_json::Value;

/// JS `WhiteSpace` plus `LineTerminator`, which is what `\s` and `trim` use.
pub fn is_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n' | '\u{b}' | '\u{c}' | '\r' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200a}' | '\u{2028}' | '\u{2029}' | '\u{202f}' | '\u{205f}' | '\u{3000}' | '\u{feff}'
    )
}

pub fn trim(s: &str) -> &str {
    s.trim_matches(is_space)
}

pub fn split_spaces(s: &str) -> impl Iterator<Item = &str> {
    s.split(is_space).filter(|t| !t.is_empty())
}

/// JS truthiness of an optional JSON value (`undefined` is `None`).
pub fn truthy(v: Option<&Value>) -> bool {
    match v {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_f64().is_some_and(|f| f != 0.0 && !f.is_nan()),
        Some(Value::String(s)) => !s.is_empty(),
        Some(_) => true,
    }
}

pub fn num_to_string(x: f64) -> String {
    if x.is_nan() {
        return "NaN".into();
    }
    if x.is_infinite() {
        return if x > 0.0 { "Infinity" } else { "-Infinity" }.into();
    }
    if x == 0.0 {
        return "0".into();
    }
    let abs = x.abs();
    if abs < 1e-6 {
        return format!("{x:e}");
    }
    if abs >= 1e21 {
        return format!("{x:e}").replace('e', "e+");
    }
    format!("{x}")
}

/// `String(value)` for a present, non-nullish JSON value.
pub fn to_js_string(v: &Value) -> String {
    match v {
        Value::Null => "null".into(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => num_to_string(n.as_f64().unwrap_or(f64::NAN)),
        Value::String(s) => s.clone(),
        Value::Array(items) => items
            .iter()
            .map(|i| if i.is_null() { String::new() } else { to_js_string(i) })
            .collect::<Vec<_>>()
            .join(","),
        Value::Object(_) => "[object Object]".into(),
    }
}

/// The `_str` idiom: `undefined` and `null` read as the empty string.
pub fn str_of(v: Option<&Value>) -> String {
    match v {
        None | Some(Value::Null) => String::new(),
        Some(v) => to_js_string(v),
    }
}

pub fn string_to_number(s: &str) -> f64 {
    let t = trim(s);
    if t.is_empty() {
        return 0.0;
    }
    match t {
        "Infinity" | "+Infinity" => return f64::INFINITY,
        "-Infinity" => return f64::NEG_INFINITY,
        _ => {}
    }
    for (prefix, radix) in [("0x", 16), ("0X", 16), ("0o", 8), ("0O", 8), ("0b", 2), ("0B", 2)] {
        if let Some(digits) = t.strip_prefix(prefix) {
            return u64::from_str_radix(digits, radix).map_or(f64::NAN, |n| n as f64);
        }
    }
    let rest = t.strip_prefix(['+', '-']).unwrap_or(t);
    let mut seen_digit = false;
    let mut seen_dot = false;
    let mut exp_at = None;
    for (i, c) in rest.char_indices() {
        match c {
            '0'..='9' => seen_digit = true,
            '.' if !seen_dot => seen_dot = true,
            'e' | 'E' if seen_digit => {
                exp_at = Some(i);
                break;
            }
            _ => return f64::NAN,
        }
    }
    if !seen_digit {
        return f64::NAN;
    }
    if let Some(i) = exp_at {
        let exp = &rest[i + 1..];
        let digits = exp.strip_prefix(['+', '-']).unwrap_or(exp);
        if digits.is_empty() || !digits.chars().all(|c| c.is_ascii_digit()) {
            return f64::NAN;
        }
    }
    t.parse().unwrap_or(f64::NAN)
}

/// `Number(value)`; `None` is `undefined`.
pub fn number(v: Option<&Value>) -> f64 {
    match v {
        None => f64::NAN,
        Some(Value::Null) => 0.0,
        Some(Value::Bool(b)) => f64::from(u8::from(*b)),
        Some(Value::Number(n)) => n.as_f64().unwrap_or(f64::NAN),
        Some(Value::String(s)) => string_to_number(s),
        Some(other) => string_to_number(&to_js_string(other)),
    }
}

/// `typeof v === "number" && isFinite(v)`.
pub fn finite_number(v: Option<&Value>) -> Option<f64> {
    match v {
        Some(Value::Number(n)) => n.as_f64().filter(|f| f.is_finite()),
        _ => None,
    }
}

/// `parseInt(s, 10)`; `None` is NaN.
pub fn parse_int(s: &str) -> Option<f64> {
    let t = s.trim_start_matches(is_space);
    let (neg, rest) = match t.strip_prefix('-') {
        Some(r) => (true, r),
        None => (false, t.strip_prefix('+').unwrap_or(t)),
    };
    let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
    if digits.is_empty() {
        return None;
    }
    let n: f64 = digits.parse().ok()?;
    Some(if neg { -n } else { n })
}

/// `Math.round`: halves go toward positive infinity.
pub fn round(x: f64) -> f64 {
    (x + 0.5).floor()
}

/// `x.toFixed(2)`: ties round up on the exact binary value, where Rust's
/// formatter rounds them to even.
pub fn to_fixed2(x: f64) -> String {
    let negative = x < 0.0;
    let exact = format!("{:.60}", x.abs());
    let (int, frac) = exact.split_once('.').unwrap_or((&exact, ""));
    let mut hundredths: u128 = format!("{int}{}", &frac[..2]).parse().unwrap_or(0);
    if frac.as_bytes()[2] >= b'5' {
        hundredths += 1;
    }
    format!(
        "{}{}.{:02}",
        if negative { "-" } else { "" },
        hundredths / 100,
        hundredths % 100
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn to_fixed2_rounds_exact_ties_up_like_js() {
        assert_eq!(to_fixed2(0.125), "0.13");
        assert_eq!(to_fixed2(29.118083), "29.12");
        assert_eq!(to_fixed2(-13.566583), "-13.57");
        assert_eq!(to_fixed2(-0.001), "-0.00");
    }

    #[test]
    fn round_sends_halves_up() {
        assert_eq!(round(-64.5), -64.0);
        assert_eq!(round(2.5), 3.0);
    }

    #[test]
    fn number_follows_js_coercion() {
        assert_eq!(number(Some(&Value::Null)), 0.0);
        assert_eq!(number(Some(&Value::String(" 42 ".into()))), 42.0);
        assert!(number(Some(&Value::String("4x".into()))).is_nan());
        assert!(number(None).is_nan());
    }

    #[test]
    fn parse_int_reads_a_numeric_prefix() {
        assert_eq!(parse_int("5260 MHz"), Some(5260.0));
        assert_eq!(parse_int("x5"), None);
    }

    #[test]
    fn num_to_string_matches_js() {
        assert_eq!(num_to_string(52.52), "52.52");
        assert_eq!(num_to_string(-0.0), "0");
        assert_eq!(num_to_string(1.5e-7), "1.5e-7");
    }
}
