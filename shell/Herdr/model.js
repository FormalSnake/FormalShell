.pragma library

// Pure model for HerdrService (M74 Task 1, plan at
// docs/superpowers/plans/2026-09-28-m74-spaces.md). No Quickshell dependency,
// so the process-tree walk and the ssh/fish/bash quoting can both be tested
// head-on against fixture strings rather than a live herdr install.
//
// herdr (github.com/tornikegomareli/herdr) classifies every agent kind it
// knows itself, so this reads `herdr agent list` rather than installing a
// hook or walking pids for one specific agent binary. Its API has no
// unscoped status-change event (`pane.agent_status_changed` needs a
// pane_id), so HerdrService polls every client key on a plain timer instead.

// ---- ps table -------------------------------------------------------------

// `ps -eo pid=,ppid=,args=` prints three left-padded/space-separated columns
// per line, `args` running to end of line and free to contain its own
// spaces, so only the first two whitespace runs are split off. A line that
// doesn't match (a wrapped/truncated row, a blank line) is dropped rather
// than guessed at.
function parsePsRows(text) {
    var rows = [];
    var lines = typeof text === "string" ? text.split("\n") : [];
    for (var i = 0; i < lines.length; i++) {
        var m = /^\s*(\d+)\s+(\d+)\s+(.*)$/.exec(lines[i]);
        if (!m)
            continue;
        rows.push({ pid: Number(m[1]), ppid: Number(m[2]), args: m[3] });
    }
    return rows;
}

// ---- client identification -------------------------------------------------

// A process's argv (ps's own `args` column) to `null` or `{ key, remote,
// session }`. Only a bare `herdr` binary (any directory prefix, so a nix
// store path still matches) carrying nothing but `--remote`/`--session`
// counts: `herdr client` (the wire connection herdr's own remote mode
// spawns), `herdr server`, `herdr agent ...` and every other subcommand
// come back null, since none of them answer `agent list` the way the
// top-level client does.
function parseClient(args) {
    if (typeof args !== "string")
        return null;
    var tokens = args.trim().split(/\s+/).filter(function (t) { return t.length > 0; });
    if (tokens.length === 0)
        return null;

    var slash = tokens[0].lastIndexOf("/");
    var base = slash >= 0 ? tokens[0].slice(slash + 1) : tokens[0];
    if (base !== "herdr")
        return null;

    var remote = "";
    var session = "";
    for (var i = 1; i < tokens.length; i++) {
        if (tokens[i] === "--remote" && i + 1 < tokens.length)
            remote = tokens[++i];
        else if (tokens[i] === "--session" && i + 1 < tokens.length)
            session = tokens[++i];
        else
            return null;
    }

    var key = remote !== "" ? "remote:" + remote : "local";
    if (session !== "")
        key += ":" + session;
    return { key: key, remote: remote, session: session };
}

// Walks the `pid ppid args` table down from each window pid (BFS) and
// collects every herdr client in that subtree, not descending into a
// client's own children (a client nested inside another client's pane is
// that outer client's business). `byWindow` maps a window pid to its client
// keys, shallowest first; a pid with none anywhere under it is simply
// absent. One pid can carry several: a terminal like ghostty or a foot
// server draws every window from one process, so its subtree holds the
// clients of all of them, and windowKeys below decides which window is
// which. `clients` carries the `{remote, session}` behind every key that
// turned up at all, since HerdrService needs that to build the key's own
// poll command and the key string alone doesn't losslessly decode back to it.
function clientsByWindow(psRows, windowPids) {
    var rows = Array.isArray(psRows) ? psRows : [];
    var byPid = {};
    var childrenOf = {};
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        byPid[row.pid] = row;
        if (!childrenOf[row.ppid])
            childrenOf[row.ppid] = [];
        childrenOf[row.ppid].push(row.pid);
    }

    var byWindow = {};
    var clients = {};
    var pids = Array.isArray(windowPids) ? windowPids : [];
    for (var w = 0; w < pids.length; w++) {
        var wp = Number(pids[w]);
        if (!isFinite(wp) || wp <= 0 || byWindow[wp])
            continue;

        var visited = {};
        visited[wp] = true;
        var queue = [wp];
        var keys = [];
        while (queue.length > 0) {
            var pid = queue.shift();
            var row = byPid[pid];
            var found = row ? parseClient(row.args) : null;
            if (found) {
                if (keys.indexOf(found.key) < 0)
                    keys.push(found.key);
                clients[found.key] = { remote: found.remote, session: found.session };
                continue;
            }
            var kids = childrenOf[pid] || [];
            for (var k = 0; k < kids.length; k++) {
                if (!visited[kids[k]]) {
                    visited[kids[k]] = true;
                    queue.push(kids[k]);
                }
            }
        }
        if (keys.length > 0)
            byWindow[wp] = keys;
    }
    return { byWindow: byWindow, clients: clients };
}

// ---- window titles ----------------------------------------------------------

// The titles a herdr client can give its outer terminal under herdr's
// default `ui.window_title`, "{hostname}: {workspace}", rendered on the
// server: one per workspace label that server has. A server configured with
// another title (or none) matches nothing here, which only matters for a
// window that needs its title to tell it apart (windowKeys).
function defaultTitles(hostname, labels) {
    if (typeof hostname !== "string" || hostname === "" || !Array.isArray(labels))
        return [];
    var out = [];
    for (var i = 0; i < labels.length; i++) {
        if (typeof labels[i] === "string" && labels[i] !== "")
            out.push(hostname + ": " + labels[i]);
    }
    return out;
}

// `windows`: `[{id, pid, title}]`, `keysByPid`: clientsByWindow's
// `byWindow`, `titlesByKey`: key -> defaultTitles() for that key's server.
// Returns window id -> key. Neither Hyprland nor the terminal exposes which
// of a process's windows owns which pty, so the pid alone settles a window
// only when it is that pid's one window and one client sits under it.
// Anything else is ambiguous (several windows on one ghostty or foot
// server, or several clients under one window) and the window takes a key
// only when its title is exactly one candidate's rendered title and no
// other candidate's; otherwise it gets nothing rather than a guess.
function windowKeys(windows, keysByPid, titlesByKey) {
    var ws = Array.isArray(windows) ? windows : [];
    var byPid = keysByPid || {};
    var titles = titlesByKey || {};
    var windowsOnPid = {};
    var i;
    for (i = 0; i < ws.length; i++) {
        var p = Number(ws[i].pid);
        windowsOnPid[p] = (windowsOnPid[p] || 0) + 1;
    }

    var out = {};
    for (i = 0; i < ws.length; i++) {
        var pid = Number(ws[i].pid);
        var keys = byPid[pid];
        if (!Array.isArray(keys) || keys.length === 0)
            continue;
        if (windowsOnPid[pid] === 1 && keys.length === 1) {
            out[ws[i].id] = keys[0];
            continue;
        }
        var title = typeof ws[i].title === "string" ? ws[i].title : "";
        var matched = [];
        for (var k = 0; k < keys.length; k++) {
            var t = titles[keys[k]];
            if (title !== "" && Array.isArray(t) && t.indexOf(title) >= 0)
                matched.push(keys[k]);
        }
        if (matched.length === 1)
            out[ws[i].id] = matched[0];
    }
    return out;
}

// ---- agent list -------------------------------------------------------------

// One `agent list` reply line (herdr 0.9.1's own shape:
// `{"result":{"type":"agent_list","agents":[{agent_status, ...}, ...]}}`)
// to the agents array, or `null` on anything that isn't that shape: bad
// JSON, the poll loop's own `echo null` stand-in for a failed call, a reply
// with no `result.agents` array.
function parseList(line) {
    var parsed = _parseJson(line);
    if (!parsed || typeof parsed !== "object" || !parsed.result)
        return null;
    var agents = parsed.result.agents;
    return Array.isArray(agents) ? agents : null;
}

function _parseJson(line) {
    if (typeof line !== "string" || line.trim() === "")
        return null;
    try {
        return JSON.parse(line);
    } catch (e) {
        return null;
    }
}

// Sorts one poll loop line into what it carries: `{hostname}` off the
// loop's own `hostname <name>` preamble, `{labels}` off a `workspace list`
// reply, and `{agents}` (parseList, null included) for everything else, so
// a line nobody recognises still reads as a failed agent list.
function parsePollLine(line) {
    if (typeof line === "string" && line.indexOf("hostname ") === 0)
        return { hostname: line.slice("hostname ".length).trim() };
    var parsed = _parseJson(line);
    var ws = parsed && typeof parsed === "object" && parsed.result ? parsed.result.workspaces : null;
    if (Array.isArray(ws)) {
        var labels = [];
        for (var i = 0; i < ws.length; i++) {
            if (ws[i] && typeof ws[i].label === "string")
                labels.push(ws[i].label);
        }
        return { labels: labels };
    }
    return { agents: parseList(line) };
}

// blocked > working > done > "" (idle/unknown draw nothing): the one badge
// a window's whole set of agents rolls up to, worst status wins.
function aggregate(agents) {
    if (!Array.isArray(agents))
        return "";
    var blocked = false, working = false, done = false;
    for (var i = 0; i < agents.length; i++) {
        var status = agents[i] && agents[i].agent_status;
        if (status === "blocked")
            blocked = true;
        else if (status === "working")
            working = true;
        else if (status === "done")
            done = true;
    }
    if (blocked)
        return "blocked";
    if (working)
        return "working";
    if (done)
        return "done";
    return "";
}

// ---- poll command -----------------------------------------------------------

var POLL_INTERVAL_SECONDS = 2;

// POSIX single-quote escaping, embedding a value inside a `sh -c`/`bash -c`
// script text: `'` -> `'\''`, same idiom as Monitor/procs.js's `_shq`.
function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

// Escapes for the OUTER single quotes fish (the remote login shell) parses.
// fish's single quotes only alter `\\` and `\'`, unlike bash's, which alter
// nothing at all inside single quotes. That is the rule this has to match:
// sshd hands the remote login shell (fish) the whole trailing command as
// one `-c` argument, so it is fish, not bash, that parses the outer
// quoting; bash only ever sees what fish handed it as its own `-c`
// argument, already unquoted. Verified against a real fish 4.9.3 round
// trip (`\`, `'`, and a shellQuote()'d value all came back byte-identical
// through `fish -c "bash -c '<fishQuote output>'"`).
function fishQuote(text) {
    var escaped = String(text).replace(/\\/g, "\\\\").replace(/'/g, "\\'");
    return "'" + escaped + "'";
}

function _herdrArgs(session) {
    return session ? " --session " + shellQuote(session) : "";
}

// The hostname line and `workspace list` feed defaultTitles(); a failed
// `workspace list` prints nothing, so only a failed `agent list` ever reads
// as the `null` that clears a key's state.
function _loopBody(herdr, session) {
    return 'echo "hostname $(uname -n)"; ' +
        "while :; do " + herdr + _herdrArgs(session) + " agent list 2>/dev/null || echo null; " +
        herdr + _herdrArgs(session) + " workspace list 2>/dev/null; " +
        "sleep " + POLL_INTERVAL_SECONDS + "; done";
}

function _localScript(session) {
    return "command -v herdr >/dev/null 2>&1 || exit 127; " + _loopBody("herdr", session);
}

// The remote login shell may be fish with a minimal PATH (no herdr on it
// even when the interactive shell's own config would find one), so this
// resolves herdr the same three ways dualsense-herdr already does outside
// this repo: `command -v`, then the nix-profile bin, then the per-user
// system profile.
function _remoteScript(session) {
    return 'h=$(command -v herdr 2>/dev/null); ' +
        'if [ -z "$h" ] && [ -x "$HOME/.nix-profile/bin/herdr" ]; then h="$HOME/.nix-profile/bin/herdr"; fi; ' +
        'if [ -z "$h" ] && [ -x "/etc/profiles/per-user/$USER/bin/herdr" ]; then h="/etc/profiles/per-user/$USER/bin/herdr"; fi; ' +
        'if [ -z "$h" ]; then exit 127; fi; ' + _loopBody('"$h"', session);
}

// `client`: `{remote, session}` (clientsByWindow's `clients` map holds
// exactly this shape per key). Returns the argv HerdrService hands straight
// to a `Process.command`, local `sh -c` for an empty remote, an `ssh`
// round trip otherwise. The ssh options mirror dualsense-herdr's own
// robustness (BatchMode so a prompt fails instead of hanging,
// ServerAlive* so a dead link is noticed rather than left half-open).
// Quickshell keeps the child's stdin pipe open for its whole life, and bash
// run by sshd sources ~/.bashrc even under `-c`: one that starts an
// interactive fish leaves it reading that stdin forever, and the loop after
// it never runs. `-n` hands the remote an EOF and `--norc` skips the rc file,
// so neither a blocking nor a chatty .bashrc reaches the poll.
function pollCommand(client) {
    var remote = client && client.remote ? String(client.remote) : "";
    var session = client && client.session ? String(client.session) : "";
    if (remote === "")
        return ["sh", "-c", _localScript(session)];
    return ["ssh", "-n",
        "-o", "BatchMode=yes",
        "-o", "ClearAllForwardings=yes",
        "-o", "ConnectTimeout=10",
        "-o", "ServerAliveInterval=15",
        "-o", "ServerAliveCountMax=2",
        remote,
        "bash --norc -c " + fishQuote(_remoteScript(session))];
}
