//! `formalshell-ipc`'s argument parsing, matching the golden contract in
//! `tests/ipc-golden.jsonl` for the same words under CLI11, quirks included,
//! since the smoke legs were written against them:
//!
//! - an argument that starts with `[` and ends with `]` is a list: split on
//!   commas outside quotes, each piece trimmed and empty ones dropped;
//! - a word naming a sibling subcommand (`show`, `wait`, `listen`, `prop`)
//!   switches to it mid-call, keeping the target and function read so far;
//! - anything shaped like an option is refused, a negative number is not;
//! - `--` ends all of that.

use super::wire::Request;

#[derive(Debug, PartialEq, Eq)]
pub struct CliError {
    pub exit: i32,
    pub message: String,
}

impl CliError {
    pub fn stderr(&self) -> String {
        format!("{}\nRun with --help for more information.\n", self.message)
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    Call,
    Show,
    Signal,
    Prop,
    PropGet,
}

fn subcommand(word: &str) -> Option<Mode> {
    match word {
        "call" => Some(Mode::Call),
        "show" => Some(Mode::Show),
        "wait" | "listen" => Some(Mode::Signal),
        "prop" => Some(Mode::Prop),
        _ => None,
    }
}

/// CLI11's `valid_first_char`.
fn valid_first(byte: u8) -> bool {
    byte != b'-' && byte > 33
}

fn option_like(arg: &str) -> bool {
    let b = arg.as_bytes();
    if b.len() > 2 && b.starts_with(b"--") && valid_first(b[2]) {
        return true;
    }
    if b.len() > 1 && b[0] == b'-' && valid_first(b[1]) {
        let numeric = b[1].is_ascii_digit() || (b[1] == b'.' && arg[1..].parse::<f64>().is_ok());
        return !numeric;
    }
    false
}

/// CLI11's `split_up` on `,`: quotes keep their commas and stay in the text.
fn split_list(inner: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut current = String::new();
    let mut quote: Option<char> = None;
    for c in inner.chars() {
        match (quote, c) {
            (Some(q), c) if c == q => {
                quote = None;
                current.push(c);
            }
            (None, '"' | '\'' | '`') => {
                quote = Some(c);
                current.push(c);
            }
            (None, ',') => parts.push(std::mem::take(&mut current)),
            _ => current.push(c),
        }
    }
    parts.push(current);
    parts.into_iter().map(|p| p.trim().to_owned()).collect()
}

fn expand(arg: &str, out: &mut Vec<String>) {
    if arg.len() >= 2 && arg.starts_with('[') && arg.ends_with(']') {
        for part in split_list(&arg[1..arg.len() - 1]) {
            if !part.is_empty() {
                expand(&part, out);
            }
        }
    } else {
        out.push(arg.to_owned());
    }
}

/// The request the words ask for, or the usage error CLI11 would print.
pub fn parse(argv: &[String]) -> Result<Request, CliError> {
    let Some((first, rest)) = argv.split_first() else {
        return Err(CliError { exit: 106, message: "A subcommand is required".into() });
    };
    let mut extras: Vec<String> = Vec::new();
    let mut mode = match subcommand(first) {
        Some(mode) => mode,
        None => {
            extras.push(first.clone());
            Mode::Show
        }
    };
    let mut used = vec![mode];
    let (mut target, mut name) = (String::new(), String::new());
    // Positionals each subcommand has taken: its own target and name slots.
    let mut taken = 0;
    let mut args = Vec::new();
    let mut literal = false;
    // CLI11 hands what follows `--` only to a positional that had nothing
    // before it: `set eq-bass -- -2` leaves -2 unexpected.
    let mut args_before_literal = 0;

    for arg in rest {
        if !literal && arg == "--" {
            literal = true;
            args_before_literal = args.len();
            continue;
        }
        if !literal {
            let next = match (mode, arg.as_str()) {
                (Mode::Prop, "get") => Some(Mode::PropGet),
                _ => subcommand(arg).filter(|m| !used.contains(m)),
            };
            if let Some(next) = next {
                mode = next;
                used.push(next);
                taken = 0;
                continue;
            }
            if option_like(arg) {
                extras.push(arg.clone());
                continue;
            }
        }
        match (mode, taken) {
            (Mode::Call | Mode::Signal | Mode::PropGet, 0) => {
                target = arg.clone();
                taken = 1;
            }
            (Mode::Call | Mode::Signal | Mode::PropGet, 1) => {
                name = arg.clone();
                taken = 2;
            }
            (Mode::Call, _) if literal && args_before_literal > 0 => extras.push(arg.clone()),
            (Mode::Call, _) => expand(arg, &mut args),
            _ => extras.push(arg.clone()),
        }
    }

    if mode == Mode::Prop {
        return Err(CliError { exit: 106, message: "A subcommand is required".into() });
    }
    match extras.len() {
        0 => {}
        1 => {
            return Err(CliError { exit: 109, message: format!("The following argument was not expected: {}", extras[0]) });
        }
        _ => {
            return Err(CliError {
                exit: 109,
                message: format!("The following arguments were not expected: {}", extras.join(" ")),
            });
        }
    }
    Ok(match mode {
        Mode::Call => Request::Call { target, function: name, args },
        Mode::Show => Request::Show { target, name },
        Mode::Signal => Request::Signal { target, signal: name },
        Mode::Prop | Mode::PropGet => Request::Prop { target, property: name },
    })
}

/// What the client checks once connected, before anything is sent.
pub fn missing(request: &Request) -> Option<&'static str> {
    match request {
        Request::Call { target, .. } | Request::Prop { target, .. } if target.is_empty() => {
            Some("Target required to send message.\n")
        }
        Request::Call { function, .. } if function.is_empty() => Some("Function required to send message.\n"),
        Request::Prop { property, .. } if property.is_empty() => Some("Property required to send message.\n"),
        Request::Signal { target, .. } if target.is_empty() => Some("Target required to listen for signals.\n"),
        Request::Signal { signal, .. } if signal.is_empty() => Some("Signal required to listen.\n"),
        _ => None,
    }
}
