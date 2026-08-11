.pragma library

// Pure model for the "flake inputs behind upstream" widget/panel: parses a
// flake.lock, builds the cheapest correct upstream probe per input type,
// parses each probe's output, and folds the result into one bar label. No
// Quickshell access, no Date.now(), no I/O, so it's testable head-on
// against captured command output (tests/tst_systemupdate_model.qml),
// mirroring Tailscale/model.js.
//
// WHAT THIS ANSWERS, precisely: "are my flake inputs behind their upstream
// refs". That is NOT "does my running system differ from what a rebuild
// would produce". Do not let the label drift toward the latter.
//
// NETWORK COST, stated plainly because it drives the whole design: stage 1
// is free (read flake.lock off disk, no nix invocation) and stage 2 costs
// one network round trip PER DIRECT INPUT. That is why the panel's poll
// cadence is hours, not minutes, and why the unauthenticated GitHub rate
// limit (60 requests/hour/IP) matters: a 403 must land in `unknown`, never
// in `current`.
//
// Rejected alternatives, so nobody re-litigates them:
//   - `nix flake metadata --json <dir>` returns only the LOCKED revs, which
//     flake.lock already holds verbatim, and copies the flake directory
//     into the store on every invocation. Strictly more expensive than
//     reading the file, and it says nothing about upstream.
//   - `nix flake update --output-lock-file <tmp>` is the only pure-nix way
//     to learn upstream revs, but computing a narHash requires fully
//     fetching every input source: a ~40MB nixpkgs tarball per poll
//     whenever upstream moved.
//   - `git ls-remote` against nixpkgs was measured at over 120 seconds
//     during design recon (twice, including protocol v2 with an explicit
//     refspec) because nixpkgs advertises ~100k refs. That is why github
//     inputs go through the API and only type:"git" forges use ls-remote.
//     Unifying the two probe paths onto ls-remote would wedge the poll.

function _isSha(s) {
    return /^[0-9a-f]{40}$/.test(String(s || "")) || /^[0-9a-f]{64}$/.test(String(s || ""));
}

function _str(v) {
    return (typeof v === "string") ? v : "";
}

// Reads nodes[root].inputs, the DIRECT inputs only. A nixpkgs pinned into
// some dependency by a `follows` is not something the user updates, so the
// transitive closure is deliberately not walked.
//
// `ref` lives in `original` for a github input pinned to a branch
// ("nixos-unstable") and in `locked` for a git input ("refs/heads/master"),
// verified against this repo's own flake.lock, hence the two-step read.
// A root input whose value is an array is a follows path pointing at
// another node the user already sees listed, and is skipped.
//
// Malformed, absent, or unparsable text returns { ok: false, inputs: [] }
// and never throws, matching Tailscale/model.js's parseStatus contract.
function parseLock(text) {
    var raw = String(text || "").trim();
    var empty = { ok: false, inputs: [] };
    if (raw === "")
        return empty;

    var data;
    try {
        data = JSON.parse(raw);
    } catch (e) {
        return empty;
    }
    if (!data || typeof data !== "object")
        return empty;

    var nodes = data.nodes;
    if (!nodes || typeof nodes !== "object")
        return empty;

    var rootKey = (_str(data.root) !== "") ? data.root : "root";
    var rootNode = nodes[rootKey];
    if (!rootNode || typeof rootNode !== "object")
        return empty;

    var direct = rootNode.inputs;
    if (!direct || typeof direct !== "object")
        return { ok: true, inputs: [] };

    var inputs = [];
    Object.keys(direct).forEach(function (name) {
        var key = direct[name];
        if (typeof key !== "string")
            return;
        var node = nodes[key];
        if (!node || typeof node !== "object")
            return;
        var locked = node.locked || {};
        var original = node.original || {};
        inputs.push({
            name: name,
            type: _str(locked.type) || _str(original.type),
            rev: _str(locked.rev),
            ref: _str(original.ref) || _str(locked.ref),
            owner: _str(locked.owner) || _str(original.owner),
            repo: _str(locked.repo) || _str(original.repo),
            url: _str(locked.url) || _str(original.url),
            lastModified: (typeof locked.lastModified === "number") ? locked.lastModified : 0
        });
    });

    // Alphabetical, so the panel's ledger has a stable row order across
    // polls rather than flake.lock's JSON key order.
    inputs.sort(function (a, b) { return a.name.localeCompare(b.name); });
    return { ok: true, inputs: inputs };
}

// The cheapest correct upstream probe for one input, as an argv the caller
// hands straight to a Process.
//
// github goes to the commits API with the sha media type, which answers
// with a bare 40-char sha and is the same endpoint nix's own github fetcher
// uses to resolve a ref to a rev. Measured at 0.5s for NixOS/nixpkgs during
// design recon.
//
// git runs `git ls-remote`, measured at 1.0s against git.outfoxxed.me. The
// `command -v git` guard makes a git-less environment exit 127, which
// parseProbe folds into `unknown` rather than a wrong count. url and ref
// are passed as positional arguments to sh rather than interpolated into
// the script, so nothing from the lock file is ever parsed as shell.
//
// gitlab uses the v4 commits API. UNVERIFIED against a live GitLab; a wrong
// guess produces an empty rev, which counts as unknown.
//
// Everything else (path, tarball, indirect, sourcehut) is kind "none" and
// counts as unknown. Never as current, never as behind.
function probeCommand(input) {
    var i = input || {};
    var type = _str(i.type);
    var ref = _str(i.ref);
    var none = { kind: "none", argv: [] };

    if (type === "github") {
        var owner = _str(i.owner);
        var repo = _str(i.repo);
        if (owner === "" || repo === "")
            return none;
        var ghUrl = "https://api.github.com/repos/" + owner + "/" + repo
            + "/commits/" + (ref !== "" ? ref : "HEAD");
        return {
            kind: "github",
            argv: ["curl", "-sS", "-f", "-m", "15", "-H", "Accept: application/vnd.github.sha", ghUrl]
        };
    }

    if (type === "gitlab") {
        var glOwner = _str(i.owner);
        var glRepo = _str(i.repo);
        if (glOwner === "" || glRepo === "")
            return none;
        var glUrl = "https://gitlab.com/api/v4/projects/" + encodeURIComponent(glOwner + "/" + glRepo)
            + "/repository/commits/" + encodeURIComponent(ref !== "" ? ref : "HEAD");
        return {
            kind: "gitlab",
            argv: ["curl", "-sS", "-f", "-m", "15", glUrl]
        };
    }

    if (type === "git") {
        var url = _str(i.url);
        if (url === "")
            return none;
        return {
            kind: "git",
            argv: [
                "sh", "-c",
                "command -v git >/dev/null 2>&1 || exit 127; exec git ls-remote \"$1\" \"$2\"",
                "systemupdate-probe", url, (ref !== "" ? ref : "HEAD")
            ]
        };
    }

    return none;
}

// The upstream rev a probe resolved, or "" for every failure: non-zero
// exit, empty output, unparsable output, or anything that is not a commit
// hash. A github 403 (rate limited) exits non-zero under `curl -f` and
// lands here as "", which countBehind then reports as unknown.
function parseProbe(kind, exitCode, stdout) {
    if (Number(exitCode) !== 0)
        return { rev: "" };

    var out = String(stdout || "").trim();
    if (out === "")
        return { rev: "" };

    if (kind === "github") {
        var sha = out.split(/\s+/)[0];
        return { rev: _isSha(sha) ? sha : "" };
    }

    if (kind === "git") {
        // "<sha>\t<ref>", one line per matching ref.
        var tok = out.split("\n")[0].split("\t")[0].trim();
        return { rev: _isSha(tok) ? tok : "" };
    }

    if (kind === "gitlab") {
        var data;
        try {
            data = JSON.parse(out);
        } catch (e) {
            return { rev: "" };
        }
        var id = (data && typeof data === "object") ? _str(data.id) : "";
        return { rev: _isSha(id) ? id : "" };
    }

    return { rev: "" };
}

// `headsByName` maps input name -> upstream rev, as resolved by parseProbe.
// An input whose head did not resolve to a non-empty rev is `unknown`, and
// so is an input with no locked rev of its own. Never silently current.
function countBehind(inputs, headsByName) {
    var list = Array.isArray(inputs) ? inputs : [];
    var heads = headsByName || {};
    var counts = { behind: 0, current: 0, unknown: 0, behindNames: [] };

    list.forEach(function (input) {
        var rev = _str((input || {}).rev);
        var head = _str(heads[(input || {}).name]);
        if (rev === "" || head === "") {
            counts.unknown++;
            return;
        }
        if (rev === head) {
            counts.current++;
            return;
        }
        counts.behind++;
        counts.behindNames.push(input.name);
    });

    return counts;
}

// Per-row ledger status for the panel, routed through countBehind so a row
// can never disagree with the header count.
function rowStatus(input, headsByName) {
    var counts = countBehind([input], headsByName);
    if (counts.behind > 0)
        return "BEHIND";
    if (counts.current > 0)
        return "CURRENT";
    return "?";
}

// The dim locked rev the panel prints beside each input name.
function shortRev(rev) {
    return _str(rev).slice(0, 7);
}

// The bar cell's whole text, so every honest state is one tested string
// instead of QML branching.
//
// `state` is the poll's own stage: "noflake" (no systemUpdate.flakeDir
// configured), "nolock" (the directory has no readable flake.lock),
// "checking" (probes in flight), "offline" (every probe failed to reach its
// forge), "ok" (probes finished). Anything else is treated as still
// resolving, never as UP TO DATE.
//
// UP TO DATE is only ever returned when nothing is behind AND nothing is
// unknown, and no zero count is ever printed.
function summaryLabel(state, counts) {
    switch (String(state || "")) {
    case "noflake":
        return "NO FLAKE";
    case "nolock":
        return "NO LOCK";
    case "checking":
        return "CHECKING";
    case "offline":
        return "NO NETWORK";
    case "ok":
        break;
    default:
        return "CHECKING";
    }

    var c = counts || {};
    var behind = Number(c.behind) || 0;
    var unknown = Number(c.unknown) || 0;

    if (behind > 0 && unknown > 0)
        return behind + " BEHIND / " + unknown + " ?";
    if (behind > 0)
        return behind + " BEHIND";
    if (unknown > 0)
        return unknown + " ?";
    return "UP TO DATE";
}
