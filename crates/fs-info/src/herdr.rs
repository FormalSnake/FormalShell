//! Model for HerdrService. No IO, so the process-tree walk and the
//! ssh/fish/bash quoting can both be tested head-on against fixture strings
//! rather than a live herdr install.
//!
//! herdr classifies every agent kind it knows itself, so this reads `herdr
//! agent list` rather than installing a hook or walking pids for one specific
//! agent binary. Its API has no unscoped status-change event
//! (`pane.agent_status_changed` needs a pane_id), so the service polls every
//! client key on a plain timer instead.

use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::sync::LazyLock;

use regex::Regex;
use serde_json::Value;

use crate::js;

// ---- ps table ---------------------------------------------------------------

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PsRow {
    pub pid: i64,
    pub ppid: i64,
    pub args: String,
}

/// `ps -eo pid=,ppid=,args=` prints three left-padded/space-separated columns
/// per line, `args` running to end of line and free to contain its own
/// spaces, so only the first two whitespace runs are split off. A line that
/// doesn't match (a wrapped/truncated row, a blank line) is dropped rather
/// than guessed at.
pub fn parse_ps_rows(text: Option<&str>) -> Vec<PsRow> {
    static ROW: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"^\s*([0-9]+)\s+([0-9]+)\s+([^\n\r\x{2028}\x{2029}]*)$").unwrap()
    });
    text.unwrap_or("")
        .split('\n')
        .filter_map(|line| {
            let m = ROW.captures(line)?;
            Some(PsRow { pid: m[1].parse().ok()?, ppid: m[2].parse().ok()?, args: m[3].to_owned() })
        })
        .collect()
}

// ---- client identification --------------------------------------------------

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Client {
    pub remote: String,
    pub session: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClientKey {
    pub key: String,
    pub remote: String,
    pub session: String,
}

/// A process's argv (ps's own `args` column) to a client key. Only a bare
/// `herdr` binary (any directory prefix, so a nix store path still matches)
/// carrying nothing but `--remote`/`--session` counts: `herdr client` (the
/// wire connection herdr's own remote mode spawns), `herdr server`, `herdr
/// agent ...` and every other subcommand come back `None`, since none of them
/// answer `agent list` the way the top-level client does.
pub fn parse_client(args: Option<&str>) -> Option<ClientKey> {
    let tokens: Vec<&str> = js::split_spaces(args?).collect();
    let first = tokens.first()?;
    if first.rsplit('/').next() != Some("herdr") {
        return None;
    }

    let mut remote = String::new();
    let mut session = String::new();
    let mut i = 1;
    while i < tokens.len() {
        match tokens[i] {
            "--remote" if i + 1 < tokens.len() => {
                i += 1;
                remote = tokens[i].to_owned();
            }
            "--session" if i + 1 < tokens.len() => {
                i += 1;
                session = tokens[i].to_owned();
            }
            _ => return None,
        }
        i += 1;
    }

    let mut key = if remote.is_empty() { "local".to_owned() } else { format!("remote:{remote}") };
    if !session.is_empty() {
        key.push(':');
        key.push_str(&session);
    }
    Some(ClientKey { key, remote, session })
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct WindowClients {
    /// Window pid to its client keys, shallowest first; a pid with none
    /// anywhere under it is absent.
    pub by_window: BTreeMap<i64, Vec<String>>,
    /// The `{remote, session}` behind every key that turned up at all, since
    /// the service needs that to build the key's own poll command and the key
    /// string alone doesn't losslessly decode back to it.
    pub clients: BTreeMap<String, Client>,
}

/// Walks the `pid ppid args` table down from each window pid (BFS) and
/// collects every herdr client in that subtree, not descending into a
/// client's own children (a client nested inside another client's pane is
/// that outer client's business). One pid can carry several keys: a terminal
/// like ghostty or a foot server draws every window from one process, so its
/// subtree holds the clients of all of them, and `window_keys` decides which
/// window is which.
pub fn clients_by_window(ps_rows: &[PsRow], window_pids: &[f64]) -> WindowClients {
    let mut by_pid: HashMap<i64, &PsRow> = HashMap::new();
    let mut children_of: HashMap<i64, Vec<i64>> = HashMap::new();
    for row in ps_rows {
        by_pid.insert(row.pid, row);
        children_of.entry(row.ppid).or_default().push(row.pid);
    }

    let mut out = WindowClients::default();
    for &pid in window_pids {
        if !pid.is_finite() || pid <= 0.0 {
            continue;
        }
        let window = pid as i64;
        if out.by_window.contains_key(&window) {
            continue;
        }

        let mut visited = HashSet::from([window]);
        let mut queue = VecDeque::from([window]);
        let mut keys: Vec<String> = Vec::new();
        while let Some(current) = queue.pop_front() {
            let found = by_pid.get(&current).and_then(|row| parse_client(Some(&row.args)));
            if let Some(found) = found {
                if !keys.contains(&found.key) {
                    keys.push(found.key.clone());
                }
                out.clients.insert(
                    found.key,
                    Client { remote: found.remote, session: found.session },
                );
                continue;
            }
            for &kid in children_of.get(&current).into_iter().flatten() {
                if visited.insert(kid) {
                    queue.push_back(kid);
                }
            }
        }
        if !keys.is_empty() {
            out.by_window.insert(window, keys);
        }
    }
    out
}

// ---- window titles ----------------------------------------------------------

/// The titles a herdr client can give its outer terminal under herdr's
/// default `ui.window_title`, "{hostname}: {workspace}", rendered on the
/// server: one per workspace label that server has. A server configured with
/// another title (or none) matches nothing here, which only matters for a
/// window that needs its title to tell it apart (`window_keys`).
pub fn default_titles(hostname: &str, labels: Option<&[String]>) -> Vec<String> {
    let Some(labels) = labels else {
        return Vec::new();
    };
    if hostname.is_empty() {
        return Vec::new();
    }
    labels
        .iter()
        .filter(|l| !l.is_empty())
        .map(|l| format!("{hostname}: {l}"))
        .collect()
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Window {
    pub id: String,
    pub pid: i64,
    pub title: String,
}

/// Window id to client key. Neither Hyprland nor the terminal exposes which
/// of a process's windows owns which pty, so the pid alone settles a window
/// only when it is that pid's one window and one client sits under it.
/// Anything else is ambiguous (several windows on one ghostty or foot server,
/// or several clients under one window) and the window takes a key only when
/// its title is exactly one candidate's rendered title and no other
/// candidate's; otherwise it gets nothing rather than a guess.
pub fn window_keys(
    windows: &[Window],
    keys_by_pid: &BTreeMap<i64, Vec<String>>,
    titles_by_key: &HashMap<String, Vec<String>>,
) -> HashMap<String, String> {
    let mut windows_on_pid: HashMap<i64, usize> = HashMap::new();
    for w in windows {
        *windows_on_pid.entry(w.pid).or_default() += 1;
    }

    let mut out = HashMap::new();
    for w in windows {
        let Some(keys) = keys_by_pid.get(&w.pid).filter(|k| !k.is_empty()) else {
            continue;
        };
        if windows_on_pid[&w.pid] == 1 && keys.len() == 1 {
            out.insert(w.id.clone(), keys[0].clone());
            continue;
        }
        let matched: Vec<&String> = keys
            .iter()
            .filter(|k| {
                !w.title.is_empty()
                    && titles_by_key.get(*k).is_some_and(|t| t.contains(&w.title))
            })
            .collect();
        if matched.len() == 1 {
            out.insert(w.id.clone(), matched[0].clone());
        }
    }
    out
}

// ---- agent list -------------------------------------------------------------

fn parse_json(line: Option<&str>) -> Option<Value> {
    let line = line?;
    if js::trim(line).is_empty() {
        return None;
    }
    serde_json::from_str(line).ok()
}

/// One `agent list` reply line (herdr 0.9.1's own shape:
/// `{"result":{"type":"agent_list","agents":[{agent_status, ...}, ...]}}`) to
/// the agents array, or `None` on anything that isn't that shape: bad JSON,
/// the poll loop's own `echo null` stand-in for a failed call, a reply with no
/// `result.agents` array.
pub fn parse_list(line: Option<&str>) -> Option<Vec<Value>> {
    let parsed = parse_json(line)?;
    parsed.get("result")?.get("agents")?.as_array().cloned()
}

#[derive(Clone, Debug, PartialEq)]
pub enum PollLine {
    Hostname(String),
    Labels(Vec<String>),
    /// `None` is a failed agent list.
    Agents(Option<Vec<Value>>),
}

/// Sorts one poll loop line into what it carries: the loop's own `hostname
/// <name>` preamble, a `workspace list` reply's labels, and the agent list
/// (`None` included) for everything else, so a line nobody recognises still
/// reads as a failed agent list.
pub fn parse_poll_line(line: Option<&str>) -> PollLine {
    if let Some(rest) = line.and_then(|l| l.strip_prefix("hostname ")) {
        return PollLine::Hostname(js::trim(rest).to_owned());
    }
    let parsed = parse_json(line);
    let workspaces = parsed
        .as_ref()
        .and_then(|p| p.get("result")?.get("workspaces")?.as_array());
    if let Some(ws) = workspaces {
        return PollLine::Labels(
            ws.iter()
                .filter_map(|w| w.get("label")?.as_str().map(str::to_owned))
                .collect(),
        );
    }
    PollLine::Agents(parse_list(line))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Badge {
    None,
    Done,
    Working,
    Blocked,
}

impl Badge {
    pub fn as_str(self) -> &'static str {
        match self {
            Badge::None => "",
            Badge::Done => "done",
            Badge::Working => "working",
            Badge::Blocked => "blocked",
        }
    }
}

/// blocked > working > done > nothing (idle/unknown draw nothing): the one
/// badge a window's whole set of agents rolls up to, worst status wins.
pub fn aggregate(agents: &[Value]) -> Badge {
    let mut badge = Badge::None;
    for agent in agents {
        let status = match agent.get("agent_status").and_then(Value::as_str) {
            Some("blocked") => Badge::Blocked,
            Some("working") => Badge::Working,
            Some("done") => Badge::Done,
            _ => Badge::None,
        };
        let rank = |b| match b {
            Badge::None => 0,
            Badge::Done => 1,
            Badge::Working => 2,
            Badge::Blocked => 3,
        };
        if rank(status) > rank(badge) {
            badge = status;
        }
    }
    badge
}

/// `aggregate` for a reply that may not be an array at all.
pub fn aggregate_value(agents: &Value) -> Badge {
    agents.as_array().map_or(Badge::None, |a| aggregate(a))
}

// ---- poll command -----------------------------------------------------------

pub const POLL_INTERVAL_SECONDS: u32 = 2;

/// POSIX single-quote escaping, embedding a value inside a `sh -c`/`bash -c`
/// script text: `'` becomes `'\''`.
pub fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

/// Escapes for the OUTER single quotes fish (the remote login shell) parses.
/// fish's single quotes only alter `\\` and `\'`, unlike bash's, which alter
/// nothing at all inside single quotes. That is the rule this has to match:
/// sshd hands the remote login shell (fish) the whole trailing command as one
/// `-c` argument, so it is fish, not bash, that parses the outer quoting; bash
/// only ever sees what fish handed it as its own `-c` argument, already
/// unquoted. Verified against a real fish 4.9.3 round trip (`\`, `'`, and a
/// `shell_quote`d value all came back byte-identical through `fish -c "bash
/// -c '<fish_quote output>'"`).
pub fn fish_quote(text: &str) -> String {
    format!("'{}'", text.replace('\\', "\\\\").replace('\'', "\\'"))
}

fn herdr_args(session: &str) -> String {
    if session.is_empty() {
        String::new()
    } else {
        format!(" --session {}", shell_quote(session))
    }
}

/// The hostname line and `workspace list` feed `default_titles`; a failed
/// `workspace list` prints nothing, so only a failed `agent list` ever reads
/// as the `null` that clears a key's state.
fn loop_body(herdr: &str, session: &str) -> String {
    let args = herdr_args(session);
    format!(
        "echo \"hostname $(uname -n)\"; while :; do {herdr}{args} agent list 2>/dev/null || echo null; \
         {herdr}{args} workspace list 2>/dev/null; sleep {POLL_INTERVAL_SECONDS}; done"
    )
}

fn local_script(session: &str) -> String {
    format!(
        "command -v herdr >/dev/null 2>&1 || exit 127; {}",
        loop_body("herdr", session)
    )
}

/// The remote login shell may be fish with a minimal PATH (no herdr on it even
/// when the interactive shell's own config would find one), so this resolves
/// herdr three ways: `command -v`, then the nix-profile bin, then the per-user
/// system profile.
fn remote_script(session: &str) -> String {
    format!(
        "h=$(command -v herdr 2>/dev/null); \
         if [ -z \"$h\" ] && [ -x \"$HOME/.nix-profile/bin/herdr\" ]; then h=\"$HOME/.nix-profile/bin/herdr\"; fi; \
         if [ -z \"$h\" ] && [ -x \"/etc/profiles/per-user/$USER/bin/herdr\" ]; then h=\"/etc/profiles/per-user/$USER/bin/herdr\"; fi; \
         if [ -z \"$h\" ]; then exit 127; fi; {}",
        loop_body("\"$h\"", session)
    )
}

/// The argv for a spawn: local `sh -c` for an empty remote, an `ssh` round
/// trip otherwise. The ssh options give BatchMode so a prompt fails instead of
/// hanging and ServerAlive* so a dead link is noticed rather than left
/// half-open. The service keeps the child's stdin pipe open for its whole
/// life, and bash run by sshd sources ~/.bashrc even under `-c`: one that
/// starts an interactive fish leaves it reading that stdin forever, and the
/// loop after it never runs. `-n` hands the remote an EOF and `--norc` skips
/// the rc file, so neither a blocking nor a chatty .bashrc reaches the poll.
pub fn poll_command(client: &Client) -> Vec<String> {
    if client.remote.is_empty() {
        return vec!["sh".into(), "-c".into(), local_script(&client.session)];
    }
    [
        "ssh",
        "-n",
        "-o",
        "BatchMode=yes",
        "-o",
        "ClearAllForwardings=yes",
        "-o",
        "ConnectTimeout=10",
        "-o",
        "ServerAliveInterval=15",
        "-o",
        "ServerAliveCountMax=2",
        &client.remote,
        &format!("bash --norc -c {}", fish_quote(&remote_script(&client.session))),
    ]
    .map(str::to_owned)
    .to_vec()
}
