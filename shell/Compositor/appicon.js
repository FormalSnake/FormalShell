.pragma library

// Which desktop entry a window belongs to, and the picture that entry names.
// Pure, so the chain is testable against fixture entries
// (tests/tst_app_icon.qml); Services/AppIcons.qml supplies the live entry
// list, the /proc answers and the themed lookup.
//
// The window is the backend's row (`appId`, and on Hyprland `initialClass`,
// `initialTitle` and `pid`); `entries` is DesktopEntries.applications.values
// or anything shaped like it (`id`, `startupClass`, `name`, `icon`,
// `command`); `procs` is `parseProcs`' answer for the window's pid, or
// nothing. First hit wins, in this order:
//
//   1. The window's class, then its initial class, against each entry by
//      the tiers DesktopEntryManager::heuristicLookup runs in the pinned
//      quickshell (src/core/desktopentry.cpp:437-464): the id, the id
//      case-folded, StartupWMClass, StartupWMClass case-folded. Then a
//      reverse-DNS tier heuristicLookup does not have: the last dot segment
//      of either side against the other, case-folded, which is what joins a
//      Flatpak's `com.discordapp.Discord` to a window classed `discord` and
//      `org.wezfurlong.wezterm` to an entry called `wezterm`.
//   2. The process. The window's own pid against each entry's Exec program,
//      by absolute path or by basename; then up to three ancestors, by
//      absolute path only. An app launched through a script (`Exec=~/bin/x`
//      running `sh ~/bin/x`, which starts the real binary) leaves the
//      script's path in an ancestor's argv, while a basename match that far
//      up would hand a class-less window launched from a terminal the
//      terminal's own icon.
//   3. The initial title against an entry's Name, case-folded. A native
//      Wayland app that never sets an app id (class and initialClass both
//      "") and runs from a wrapper the process walk cannot see through
//      still usually titles its first window with its own name.
//
// appmatch.js deliberately stops at tier 1's first four steps, because a
// wrong hit there focuses the wrong app. A wrong hit here costs a wrong
// picture on a tile that would otherwise be the generic one, and the tiers
// past heuristicLookup's only run once it has missed.

var ANCESTOR_DEPTH = 3;

// Interpreters and launchers whose basename says nothing about the app
// running under them: an entry whose Exec starts with one of these would
// otherwise claim every script that one runs.
var _LAUNCHERS = ["sh", "bash", "dash", "zsh", "fish", "env", "python",
    "python3", "node", "perl", "ruby", "systemd-run", "flatpak", "uwsm", "app2unit"];

function _str(value) {
    return value === undefined || value === null ? "" : String(value);
}

// A list-shaped value out of QML (a QVector<QString> or a JS array), as a
// plain array: `DesktopEntry.command` measures and indexes fine but is not
// an Array.
function _list(value) {
    var out = [];
    if (!value)
        return out;
    for (var i = 0; i < (value.length || 0); i++)
        out.push(_str(value[i]));
    return out;
}

function _tail(value) {
    var s = _str(value);
    var dot = s.lastIndexOf(".");
    return dot >= 0 ? s.slice(dot + 1) : s;
}

// A program's name as a user would call it: the path's last segment with a
// nixpkgs wrapper's `.name-wrapped` undone, so `/nix/store/…/bin/.foot-wrapped`
// reads as `foot`.
function _basename(path) {
    var s = _str(path);
    var name = s.slice(s.lastIndexOf("/") + 1);
    var wrapped = /^\.(.+)-wrapped$/.exec(name);
    return wrapped ? wrapped[1] : name;
}

function _classTiers(needle, entries) {
    var tiers = [
        function (e) { return _str(e.id) === needle; },
        function (e) { return _str(e.id).toLowerCase() === needle.toLowerCase(); },
        function (e) { return _str(e.startupClass) === needle; },
        function (e) { return _str(e.startupClass) !== ""
            && _str(e.startupClass).toLowerCase() === needle.toLowerCase(); },
        function (e) { return _tail(e.id).toLowerCase() === needle.toLowerCase(); },
        function (e) { return _str(e.id).toLowerCase() === _tail(needle).toLowerCase(); }
    ];
    for (var t = 0; t < tiers.length; t++) {
        for (var i = 0; i < entries.length; i++) {
            if (entries[i] && tiers[t](entries[i]))
                return entries[i];
        }
    }
    return null;
}

// The entry the first class tier finds, or null. Split out so the service
// can tell which windows need their process read at all.
function byClass(win, entries) {
    var w = win || {};
    var list = [];
    for (var k = 0; k < (entries ? entries.length || 0 : 0); k++)
        list.push(entries[k]);
    var needles = [_str(w.appId), _str(w.initialClass)];
    for (var n = 0; n < needles.length; n++) {
        if (needles[n] === "" || (n > 0 && needles[n] === needles[0]))
            continue;
        var hit = _classTiers(needles[n], list);
        if (hit)
            return hit;
    }
    return null;
}

function _program(entry) {
    var argv = _list(entry.command);
    return argv.length > 0 ? argv[0] : "";
}

function _procMatches(proc, program, depth) {
    var argv = _list(proc.argv);
    var exe = _str(proc.exe);
    if (program.charAt(0) === "/") {
        if (exe === program)
            return true;
        for (var i = 0; i < argv.length; i++) {
            if (argv[i] === program)
                return true;
        }
    }
    if (depth > 0)
        return false;
    var name = _basename(program);
    if (name === "" || _LAUNCHERS.indexOf(name) >= 0)
        return false;
    return _basename(exe) === name || (argv.length > 0 && _basename(argv[0]) === name);
}

// `procs` is the window's own process first, then its ancestors, nearest
// first: `[{ exe, argv }]`.
function byProcess(procs, entries) {
    var chain = procs || [];
    for (var depth = 0; depth < chain.length && depth <= ANCESTOR_DEPTH; depth++) {
        for (var i = 0; i < (entries ? entries.length || 0 : 0); i++) {
            var entry = entries[i];
            if (!entry)
                continue;
            var program = _program(entry);
            if (program !== "" && _procMatches(chain[depth] || {}, program, depth))
                return entry;
        }
    }
    return null;
}

function byTitle(win, entries) {
    var title = _str((win || {}).initialTitle).trim().toLowerCase();
    if (title === "")
        return null;
    for (var i = 0; i < (entries ? entries.length || 0 : 0); i++) {
        var entry = entries[i];
        if (entry && _str(entry.name).trim().toLowerCase() === title)
            return entry;
    }
    return null;
}

function entryFor(win, entries, procs) {
    return byClass(win, entries) || byProcess(procs, entries) || byTitle(win, entries);
}

// An entry's `Icon=` as something an Image can load: an absolute path as a
// file url, an existing url as given, a theme name through `themed`
// (Quickshell.iconPath(name, true), "" for a name the theme lacks). A path
// goes straight to the file rather than through the icon provider, whose
// `QIcon::fromTheme` is a theme lookup.
function source(name, themed) {
    var s = _str(name);
    if (s === "")
        return "";
    if (s.indexOf("file:") === 0 || s.indexOf("image:") === 0)
        return s;
    if (s.charAt(0) === "/")
        return "file://" + s;
    return themed ? _str(themed(s)) : "";
}

// The one shell pass `AppIcons` runs over /proc, one line per process:
// `<window pid>\t<depth>\t<exe>\t<argv joined by \x1f>`. Returns
// `{ "<pid>": [{ exe, argv }, …] }`, depth order; a line that does not
// parse is dropped rather than guessed at.
function parseProcs(text) {
    var out = {};
    var lines = _str(text).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].split("\t");
        if (fields.length < 4 || !/^[0-9]+$/.test(fields[0]) || !/^[0-9]+$/.test(fields[1]))
            continue;
        var argv = fields.slice(3).join("\t").split("\x1f");
        while (argv.length > 0 && argv[argv.length - 1] === "")
            argv.pop();
        var chain = out[fields[0]] || (out[fields[0]] = []);
        chain[Number(fields[1])] = { exe: fields[2], argv: argv };
    }
    for (var pid in out) {
        var dense = [];
        for (var d = 0; d < out[pid].length && out[pid][d]; d++)
            dense.push(out[pid][d]);
        out[pid] = dense;
    }
    return out;
}

// The command that produces `parseProcs`' input for `pids`: each one and up
// to `ANCESTOR_DEPTH` parents, stopping at init. `/proc/<pid>/status`'s
// PPid line rather than `stat`'s fourth field, which sits after a comm that
// may itself carry spaces and parentheses.
function procCommand(pids) {
    var script = 'for p in "$@"; do q=$p; d=0; '
        + 'while [ "$d" -le ' + ANCESTOR_DEPTH + ' ] && [ "$q" -gt 1 ] && [ -r "/proc/$q/cmdline" ]; do '
        + 'printf "%s\\t%s\\t%s\\t" "$p" "$d" "$(readlink "/proc/$q/exe" 2>/dev/null)"; '
        + 'tr "\\000" "\\037" < "/proc/$q/cmdline"; echo; '
        + 'q=$(sed -n "s/^PPid:[[:space:]]*//p" "/proc/$q/status" 2>/dev/null); q=${q:-0}; d=$((d + 1)); '
        + 'done; done';
    var argv = ["sh", "-c", script, "appicon"];
    for (var i = 0; i < pids.length; i++)
        argv.push(String(Number(pids[i])));
    return argv;
}
