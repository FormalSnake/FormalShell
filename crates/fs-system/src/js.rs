//! The few JavaScript number and string semantics the ported modules lean on,
//! so a parser reads `Number("")` as 0 and `toFixed` rounds ties up exactly
//! as the QML shell did.

/// JavaScript `\s` and `String.prototype.trim` whitespace.
pub fn is_space(c: char) -> bool {
    c != '\u{85}' && (c.is_whitespace() || c == '\u{feff}')
}

pub fn trim(s: &str) -> &str {
    s.trim_matches(is_space)
}

pub fn trim_end(s: &str) -> &str {
    s.trim_end_matches(is_space)
}

/// `s.trim().split(/\s+/)`: one empty string for an empty input, as JS gives.
pub fn split_ws(s: &str) -> Vec<&str> {
    let t = trim(s);
    if t.is_empty() {
        return vec![""];
    }
    t.split(is_space).filter(|p| !p.is_empty()).collect()
}

/// `Number(s)`: NaN when it does not parse, 0 for an empty or blank string.
pub fn number(s: &str) -> f64 {
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
        if let Some(rest) = t.strip_prefix(prefix) {
            return u64::from_str_radix(rest, radix).map_or(f64::NAN, |v| v as f64);
        }
    }
    if t.bytes().any(|b| !(b.is_ascii_digit() || matches!(b, b'.' | b'e' | b'E' | b'+' | b'-'))) {
        return f64::NAN;
    }
    t.parse::<f64>().unwrap_or(f64::NAN)
}

/// `Number(x) || 0`.
pub fn number_or_zero(s: &str) -> f64 {
    let n = number(s);
    if n.is_nan() { 0.0 } else { n }
}

/// `parseInt(s, 10)`: NaN when there is no leading integer.
pub fn parse_int(s: &str) -> f64 {
    let t = s.trim_start_matches(is_space);
    let (neg, rest) = match t.as_bytes().first() {
        Some(b'-') => (true, &t[1..]),
        Some(b'+') => (false, &t[1..]),
        _ => (false, t),
    };
    let digits: &str = &rest[..rest.bytes().take_while(u8::is_ascii_digit).count()];
    if digits.is_empty() {
        return f64::NAN;
    }
    let v: f64 = digits.parse().unwrap_or(f64::NAN);
    if neg { -v } else { v }
}

/// `Math.round`: halves round toward positive infinity.
pub fn round(x: f64) -> f64 {
    (x + 0.5).floor()
}

/// `Number.prototype.toFixed`: an exact tie rounds away from zero, where
/// Rust's formatter rounds it to even.
pub fn to_fixed(x: f64, digits: usize) -> String {
    if !x.is_finite() {
        return num_str(x);
    }
    let wide = format!("{:.*}", digits + 40, x.abs());
    let (int_part, frac) = wide.split_once('.').unwrap_or((&wide, ""));
    let tail = &frac[digits.min(frac.len())..];
    let tie = tail.starts_with('5') && tail[1..].bytes().all(|b| b == b'0');
    let out = if tie {
        let kept = format!("{}{}", int_part, &frac[..digits]);
        let mut bytes: Vec<u8> = kept.into_bytes();
        let mut i = bytes.len();
        loop {
            if i == 0 {
                bytes.insert(0, b'1');
                break;
            }
            i -= 1;
            if bytes[i] == b'9' {
                bytes[i] = b'0';
            } else {
                bytes[i] += 1;
                break;
            }
        }
        let s = String::from_utf8(bytes).unwrap_or_default();
        if digits == 0 {
            s
        } else {
            let split = s.len() - digits;
            format!("{}.{}", &s[..split], &s[split..])
        }
    } else {
        format!("{:.*}", digits, x.abs())
    };
    if x < 0.0 && out.bytes().any(|b| b != b'0' && b != b'.') { format!("-{out}") } else { out }
}

/// `Number(value)` over a JSON value; a missing key is `undefined`, so NaN.
pub fn json_number(value: Option<&serde_json::Value>) -> f64 {
    use serde_json::Value;
    match value {
        None => f64::NAN,
        Some(Value::Null) => 0.0,
        Some(Value::Bool(b)) => f64::from(u8::from(*b)),
        Some(Value::Number(n)) => n.as_f64().unwrap_or(f64::NAN),
        Some(Value::String(s)) => number(s),
        Some(_) => f64::NAN,
    }
}

/// `typeof value === "string" ? value : ""`.
pub fn json_text(value: Option<&serde_json::Value>) -> String {
    value.and_then(serde_json::Value::as_str).unwrap_or("").to_string()
}

/// `String(value || "")` over a JSON value.
pub fn json_string_or_empty(value: Option<&serde_json::Value>) -> String {
    use serde_json::Value;
    match value {
        None | Some(Value::Null) | Some(Value::Bool(false)) => String::new(),
        Some(Value::Bool(true)) => "true".into(),
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => {
            let f = n.as_f64().unwrap_or(f64::NAN);
            if f == 0.0 || f.is_nan() { String::new() } else { num_str(f) }
        }
        Some(Value::Array(items)) => items
            .iter()
            .map(|v| json_string_or_empty(Some(v)))
            .collect::<Vec<_>>()
            .join(","),
        Some(Value::Object(_)) => "[object Object]".into(),
    }
}

/// `String(n)` for a JS number: integers print without a decimal point.
pub fn num_str(x: f64) -> String {
    if x.is_nan() {
        "NaN".into()
    } else if x.is_infinite() {
        if x > 0.0 { "Infinity".into() } else { "-Infinity".into() }
    } else if x == x.trunc() && x.abs() < 1e21 {
        format!("{}", x as i128)
    } else {
        format!("{x}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn to_fixed_ties_round_up() {
        assert_eq!(to_fixed(0.25, 1), "0.3");
        assert_eq!(to_fixed(1.45, 1), "1.4");
        assert_eq!(to_fixed(2.5, 0), "3");
        assert_eq!(to_fixed(9.95, 1), "9.9");
        assert_eq!(to_fixed(0.5, 0), "1");
        assert_eq!(to_fixed(9.5, 0), "10");
        assert_eq!(to_fixed(3.6, 1), "3.6");
    }

    #[test]
    fn number_follows_js() {
        assert_eq!(number(""), 0.0);
        assert!(number("abc").is_nan());
        assert_eq!(number(" 12 "), 12.0);
        assert_eq!(number("0x10"), 16.0);
        assert!(number("inf").is_nan());
    }

    #[test]
    fn round_halves_go_up() {
        assert_eq!(round(2.5), 3.0);
        assert_eq!(round(-2.5), -2.0);
    }
}
