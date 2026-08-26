.pragma library
.import "frecency.js" as Frecency

// Provider functions populate a "provider" kind node's children at
// tree-build time (Model.buildTree() infers "provider" from an entry's
// `provider` key, see default-menu.jsonc's "apps" node). Providers return
// ready-made Node fragments (Model's Node shape: id/label/icon/title/
// aliases/kind/childIds) rather than JSONC entries, because they bypass
// buildTree()'s action/target/provider kind inference entirely, an app has
// no `action` string, it has a DesktopEntry to call execute() on, which
// respects .desktop field codes/Exec quoting that re-running it through
// `sh -c` would mangle.

// `entries` = DesktopEntries.applications.values (Quickshell's built-in
// desktop-entry index, already excludes Hidden/NoDisplay). Each app node
// keeps a reference to its DesktopEntry (`_entry`) so Menu.qml's activation
// can call `_entry.execute()` directly instead of spawning a shell command.
//
// `entry.icon` is an icon-theme NAME ("firefox", "mpv"), not a glyph, it
// must never land in the node's `icon` slot, which MenuRow renders as
// literal text (the M13b "apps list shows app IDs" symptom: rows led with
// the raw icon name, which conventionally equals the app id). Instead
// `resolveIcon` (Menu.qml passes Quickshell.iconPath with check=true, tests
// pass a stub) maps the name to an image URL for MenuRow's image slot, or
// "" when the theme has no such icon, the row then simply has no leading
// cell, never a missing-texture box. `entry.name` can't be empty for listed
// applications (quickshell drops invalid entries in onScanCompleted), but
// the id fallback keeps the row honest if that ever changes.
//
// `launches` (Core.State.appLaunches, frecency.js's record array) and
// `nowMs` order the entries by launch frecency BEFORE the map, which is
// the whole of frecency's reach into ranking: search.js:85-89 breaks
// equal-score ties by declaration order, and a provider's rows are
// declared in exactly the order returned here (applyProviders below pushes
// them onto childIds in order, and Search.rank's declIndex counts that
// same depth-first walk). So a launched app leads a tie against an app
// that matched the query exactly as well, while a stronger match tier
// still beats any launch count outright. Empty/absent `launches` leaves
// DesktopEntries' own order intact.
//
// `_entry` is read for more than execute() now: Compositor/appmatch.js reads
// `startupClass` and `id` off it to decide whether activating a row focuses
// a running window instead of launching a new one, so the back-reference
// carries more weight than it used to.
//
// `recent` marks the head of that frecency order for the launcher's own
// `Recent` heading (M48 D6). It is capped rather than "everything with a
// launch record": the score of a launch decays but never reaches zero, so
// an uncapped rule would eventually file every app anyone has ever opened
// under Recent and leave the heading meaning nothing. Five is what a reader
// takes in without scanning, and the rows below it are the whole list in
// the same order, so nothing is hidden by the split.
var APPS_RECENT_MAX = 5;

function appsProvider(entries, resolveIcon, launches, nowMs) {
    var now = nowMs === undefined ? Date.now() : nowMs;
    var ordered = Frecency.order(entries || [], launches, now);
    return ordered.map(function (entry, i) {
        var iconName = entry.icon || "";
        return {
            id: "apps." + entry.id,
            parentId: null,
            label: entry.name || entry.id,
            icon: "",
            iconSource: (iconName !== "" && resolveIcon) ? resolveIcon(iconName) : "",
            title: entry.genericName || "",
            aliases: [],
            kind: "app",
            recent: i < APPS_RECENT_MAX && Frecency.score(launches, entry.id, now) > 0,
            childIds: [],
            _entry: entry
        };
    });
}

// Merges every "provider" node's produced children into `tree` (a
// Model.buildTree() result): for each provider node, looks up its
// `provider` name in `providerFns` (name -> fn(): [Node]), parents the
// returned nodes under it, and registers them in `tree.nodes`. Mutates and
// returns `tree`.
function applyProviders(tree, providerFns) {
    Object.keys(tree.nodes).forEach(function (id) {
        var node = tree.nodes[id];
        if (node.kind !== "provider") return;
        var fn = providerFns[node.provider];
        if (!fn) return;
        fn().forEach(function (child) {
            child.parentId = node.id;
            tree.nodes[child.id] = child;
            node.childIds.push(child.id);
        });
    });
    return tree;
}

// Clipboard history rows, newest first (ClipboardService.items' own order).
// Unlike appsProvider these are plain "action" nodes, Menu.qml's existing
// `_activateRow`/`_runAction` path activates them with no bespoke node kind
// (and no `_entry`-style back-reference) needed here.
//
// Copy-mode rows dispatch in-process (`@ipc:clipboard.copy:<id>`, the same
// argument-carrying internal-action shape `clipssh.send:<alias>` uses)
// rather than spawning `qs ipc -p <shellDir> call clipboard copy <id>`
// through the compositor. That spawn is what made Enter a silent no-op on a
// real install: `qs` is quickshell's own binary, and nothing puts it on a
// session PATH. nix/package.nix wraps it as `formalshell` and nix/hm-module
// installs only that, so `sh -c "qs ipc …"` exits 127 with nowhere to
// report it. The smoke rig never saw it because nix/testvm.nix has the
// whole quickshell package in systemPackages, so `qs` resolves there. The
// menu runs inside the process that owns ClipboardService, so the round
// trip bought nothing even when it worked.
//
// `pasteAfter` marks the row for Menu.qml's paste hook: on top of the copy,
// the chord is synthesized into whatever window focus returns to, which is
// Raycast's clipboard behaviour. Config gates it, so the caller decides.
//
// Image entries (M14 Task 1, history.js's `kind: "image"`) get a fixed
// "IMAGE" label instead of a text preview, a dimmed capture time in the
// `desc` slot (same trailing-text idiom nixRows uses), and `thumbSource`,
// a new node field MenuRow doesn't render yet (Task 6 wires the thumbnail
// row); the activation action is identical to a text row's.
function _capturedAtLabel(capturedAt) {
    var d = new Date(capturedAt);
    var pad2 = function (n) { return (n < 10 ? "0" : "") + n; };
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

// `mode` ("copy", the default, or "share") only changes the row's id
// prefix, verb and activation, label/desc/thumbSource stay identical
// either way. "share" rows need their own id namespace ("share.history.<id>"
// rather than "clipboard.<id>"): both providers read the SAME
// ClipboardService.items list, and tree.nodes is one flat map keyed by id,
// so reusing "clipboard.<id>" here would silently overwrite the real
// clipboard node's own rows (or vice versa, depending on provider order).
//
// `paste` is `clipboard.paste`, threaded in rather than read here so this
// stays pure. It only reaches copy rows: a share row hands the entry to
// LocalSend and never touches the focused window.
function clipboardProvider(items, mode, paste) {
    mode = mode || "copy";
    var share = mode === "share";
    var pasteAfter = !share && paste !== false;
    var idPrefix = share ? "share.history." : "clipboard.";
    return (items || []).map(function (entry) {
        var isImage = entry.kind === "image";
        return {
            id: idPrefix + entry.id,
            parentId: null,
            label: isImage ? "IMAGE" : previewLabel(entry.text),
            icon: "",
            title: "",
            desc: isImage ? _capturedAtLabel(entry.capturedAt) : "",
            thumbSource: isImage ? entry.path : "",
            // Full untruncated text for the split-pane preview (M30),
            // "" for images, same emptiness `desc` already uses to mean
            // "no text preview here". `time` rides every row (not just
            // images, unlike `desc`) since the preview pane's meta line
            // needs a capture time regardless of entry kind.
            fullText: isImage ? "" : entry.text,
            time: _capturedAtLabel(entry.capturedAt),
            aliases: [],
            kind: "action",
            // The action bar's verb, overriding what actions.js infers from
            // `kind` alone: "Run" describes a clipboard row about as well as
            // it describes an app row.
            verb: share ? "Share" : (pasteAfter ? "Paste" : "Copy"),
            action: share
                ? shareEntryCommand(entry)
                : "@ipc:clipboard.copy:" + entry.id,
            pasteAfter: pasteAfter,
            childIds: []
        };
    });
}

// wtype argv for a paste chord ("ctrl+v", "ctrl+shift+v", …): every modifier
// pressed with -M in written order, the key tapped with -k, then the
// modifiers released with -m in reverse.
//
// The seven names below are wtype's whole modifier vocabulary, and they are
// the seven it actually accepts, not the ones that read like it should:
// `wtype -M <name>` was run against each candidate in the VM, and `super`,
// `meta`, `control` and `command` all came back "Invalid modifier name".
// `logo` is the one that means the windows/command key. A name outside the
// list is a config typo, and the honest answer is to report it rather than
// synthesize a keystroke nobody asked for, so a bad chord returns null and
// Menu.qml warns instead of pasting something arbitrary.
//
// The chord is configuration and not row data because the right one depends
// on where focus lands: Ctrl+V everywhere except terminals, which almost
// universally want Ctrl+Shift+V.
var PASTE_MODIFIERS = ["shift", "capslock", "ctrl", "logo", "win", "alt", "altgr"];

function pasteArgv(chord) {
    var parts = String(chord || "").toLowerCase().split("+").map(function (p) { return p.trim(); }).filter(function (p) { return p !== ""; });
    if (parts.length === 0)
        return null;
    var key = parts.pop();
    var mods = parts;
    for (var i = 0; i < mods.length; i++) {
        if (PASTE_MODIFIERS.indexOf(mods[i]) < 0)
            return null;
    }
    if (PASTE_MODIFIERS.indexOf(key) >= 0)
        return null;
    var argv = [];
    for (var m = 0; m < mods.length; m++)
        argv.push("-M", mods[m]);
    argv.push("-k", key);
    for (var r = mods.length - 1; r >= 0; r--)
        argv.push("-m", mods[r]);
    return argv;
}

// Route-local filter for the clipboard/share-history level (M30): unlike
// Search.rank's whole-tree ranking, this only tests one field per row,
// `fullText`, falling back to `label` for image rows (whose `fullText` is
// always ""), so typing here narrows history instead of turning into a
// global search the moment a query is non-empty. Case-insensitive
// substring, not fuzzy: the ask is "does this entry contain what I typed".
function clipboardSearch(rows, query) {
    var q = String(query || "").trim().toLowerCase();
    if (q === "") return rows || [];
    return (rows || []).filter(function (row) {
        var haystack = String(row.fullText || row.label || "").toLowerCase();
        return haystack.indexOf(q) >= 0;
    });
}

// Dim, non-activatable notes for the clipboard/share-history route
// (mirrors `_nixNoteRow` below): an actually-empty history reads
// differently from a query that matched nothing, so they carry distinct
// labels instead of one shared shrug (§2 item 10: empty states take no
// colon).
function _clipboardNoteRow(id, label) {
    return {
        id: id,
        parentId: null,
        label: label,
        icon: "",
        title: "",
        aliases: [],
        kind: "note",
        dim: true,
        childIds: []
    };
}

function clipboardEmptyRow() { return _clipboardNoteRow("clipboard.empty", "CLIPBOARD EMPTY"); }
function clipboardNoMatchRow() { return _clipboardNoteRow("clipboard.nomatch", "NO MATCHES"); }

// Single-quotes `value` for a sh -c string, escaping embedded single quotes
// the same way HyprlandBackend.qml's _quoteArg does ('\'', close the
// quote, an escaped literal quote, reopen). Clipboard text can contain
// anything a shell would otherwise interpret, so this is the one place a
// captured entry's raw content reaches a spawned command.
function _shq(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

// The SHARE route's launch command. omarchy's own bin/omarchy-menu-share
// invokes `localsend --headless send <path>`, but that binary name and
// those flags don't exist on the package this shell actually ships
// (nixpkgs' pkgs.localsend installs a binary named `localsend_app`, and
// upstream's own arg parser, LoadSelectionFromArgsAction in
// app/lib/provider/selection/selected_sending_files_provider.dart,
// localsend/localsend, has no `--headless`/`send` mode at all: unknown
// dash-flags are silently skipped and a bare non-path token like "send" is
// silently ignored too, so omarchy's invocation happens to still work by
// accident, not by design). The real, verified mechanism is narrower still:
// LoadSelectionFromArgsAction (app/lib/provider/selection/
// selected_sending_files_provider.dart:290-293) skips every arg starting
// with "-" outright, then only keeps args where File(arg).existsSync() or
// Directory(arg).existsSync(), a bare file path pre-populates the GUI's
// send selection (`AddFilesAction`), but `-t`/`--text` are dash-prefixed so
// they're dropped before that check ever runs, and the text that follows
// isn't a path either, so nothing gets added. `AddMessageAction` (the
// in-app text-share path) is only reachable from macOS drop streams and
// mobile share intents, never from CLI argv. So text, like omarchy's own
// clipboard mode, has to become a real file: written to a mktemp `.txt`
// file and shared by path exactly like an image entry. Either way this
// only launches the picker; LocalSend's own GUI still owns actually
// starting the transfer to a chosen device.
function shareEntryCommand(entry) {
    if (entry.kind === "image")
        return "localsend_app " + _shq(entry.path);
    return "tmp=$(mktemp --suffix=.txt) && printf '%s' " + _shq(entry.text) + " > \"$tmp\" && exec localsend_app \"$tmp\"";
}

// Root "share.clipboard" leaf (Task 1), injected the same way
// captureEntries() is: its action depends on the CURRENT newest clipboard
// entry (items[0]), which static jsonc can't express. default-menu.jsonc
// still declares a "share.clipboard" placeholder so this fragment's key
// overwrites an already-present entry rather than appending a new one,
// JS object property order only tracks first insertion, so overwriting
// keeps the row's position (right after "share", ahead of "share.history"/
// "share.receive") instead of the row jumping to the end of the level.
// Empty history is the one shape model.js's inferKind can't produce on its
// own (no action/target/provider to key off), which is what the explicit
// `kind`/`dim` override exists for: an honest NOTHING TO SHARE row, the
// same non-activatable shape as nix's own unavailable-state rows.
function shareClipboardEntry(items) {
    var newest = (items || [])[0];
    if (!newest) {
        return {
            "share.clipboard": {
                label: "Nothing To Share",
                icon: "",
                kind: "note",
                dim: true
            }
        };
    }
    return {
        "share.clipboard": {
            label: "Clipboard",
            icon: "\u{F014D}", // nf-md-clipboard_text, same glyph the root clipboard node uses
            action: shareEntryCommand(newest)
        }
    };
}

// First non-blank line only, capped at maxLen chars, clipboard captures can
// be multi-line/arbitrarily long, and MenuRow's label is a single Text with
// no wrapping, so anything longer needs pre-truncating here rather than
// spilling into the ledger row below it.
function previewLabel(text, maxLen) {
    maxLen = maxLen || 60;
    var lines = text.split("\n");
    var firstLine = "";
    for (var i = 0; i < lines.length; i++) {
        var trimmed = lines[i].trim();
        if (trimmed !== "") { firstLine = trimmed; break; }
    }
    if (firstLine === "") firstLine = text.trim();
    var truncated = firstLine.length > maxLen;
    var out = truncated ? firstLine.slice(0, maxLen) : firstLine;
    return (truncated || lines.length > 1) ? out + "…" : out;
}


// ":e" root trigger (M12 Task 6, the DMS muscle-memory prefix): returns the
// emoji query after it, "" for the bare ":e" (browse mode), or null when
// `text` is not the trigger at all.
function emojiTriggerQuery(text) {
    var t = String(text || "");
    if (t === ":e") return "";
    if (t.indexOf(":e ") === 0) return t.slice(3);
    return null;
}

// Name search over the vendored emoji dataset (emoji.json, generated by
// dev/gen-emoji.sh, parsed by Menu.qml): exact > starts-with > word-start >
// contains, ties broken by file order, which puts base emoji ahead of their
// skin-tone variants for free. An empty query browses the whole set, so the
// summoned route is never an empty surface and never a truncated one either.
//
// Uncapped (owner, 2026-08-26: "not all emojis are in the grid"). The cap
// was 40, which predates the route being a grid: forty rows was a sensible
// ceiling on a row list, and forty cells is five rows of a grid that scrolls,
// so it silently put 3900 of the 3944 emoji out of reach. A GridView only
// instantiates the delegates it can see, so the whole set costs the scan
// below and nothing more.
function emojiSearch(list, query) {
    list = list || [];
    var q = String(query || "").trim().toLowerCase();
    if (!q) return list.slice();
    // Four buckets rather than a comparator sort. There are exactly four
    // tiers, and the scan already visits the list in file order, so pushing
    // into a bucket and concatenating them highest-first produces the same
    // order (tier descending, file order within a tier) in one linear pass.
    // A one-letter query matches most of the 3944 entries, and sorting that
    // many with a comparator was the single biggest cost left on the route.
    var exact = [], prefix = [], wordStart = [], substring = [];
    for (var i = 0; i < list.length; i++) {
        var name = _emojiName(list[i]);
        if (name === q) exact.push(list[i]);
        else if (name.indexOf(q) === 0) prefix.push(list[i]);
        else if (name.indexOf(" " + q) >= 0) wordStart.push(list[i]);
        else if (name.indexOf(q) >= 0) substring.push(list[i]);
    }
    return exact.concat(prefix, wordStart, substring);
}

// The lowercased name, memoised onto the entry. Every keystroke rescans all
// 3944 names, and lowercasing them again each time is the one part of that
// scan worth not repeating. The dataset is parsed once and lives as long as
// the shell, so the memo does too.
function _emojiName(entry) {
    if (entry._lcName === undefined)
        entry._lcName = String(entry.name).toLowerCase();
    return entry._lcName;
}

// Emoji rows are plain "action" nodes (clipboardProvider's own trick): Enter
// runs `wl-copy` through the existing activation path and closes, and the
// clipboard service captures the copy like any other. The char rides the
// icon slot, the uppercase name is the label. Single quotes are required
// around the char: keycap sequences start with ASCII `#`/`*`/digits (comment
// and glob hazards unquoted), and no emoji contains an ASCII apostrophe.
//
// `pasteAfter` marks the row for Menu.qml's paste hook, the same field and
// the same `clipboard.paste`/`clipboard.pasteChord` config a clipboard
// history row uses (`paste` threaded in rather than read here, so this stays
// pure): once the surface has closed, the chord is synthesized into whatever
// window focus returns to, on top of the copy that already ran. The old path
// typed the char itself with `wtype <char>`, which only lands where the
// focused client accepts a remapped keysym off a virtual keyboard; a paste
// works wherever the user's own paste chord already works.
// The row objects are memoised onto the entry, one per paste mode, for the
// same reason the lowercase name is: with the cap gone a broad query maps
// most of the 3944 entries on every keystroke, and building a twelve-field
// object apiece was measured at 8.85ms a keystroke against 0.60ms for
// everything else the route does per keystroke combined. Cached, a repeat
// query costs the array and nothing else. A row is read-only everywhere it
// travels (the grid delegate binds to it, `_activateRow` reads it), so
// handing the same object back twice is safe; the memo lives on the entry,
// never on the row, so nothing downstream can see it.
function emojiRows(list, query, paste) {
    var pasteAfter = paste !== false;
    var key = pasteAfter ? "_rowPaste" : "_rowCopy";
    return emojiSearch(list, query).map(function (e) {
        if (e[key] === undefined) {
            e[key] = {
                id: "emoji." + e.ch,
                parentId: null,
                label: e.name.toUpperCase(),
                icon: e.ch,
                title: "",
                aliases: [],
                kind: "action",
                verb: pasteAfter ? "Paste" : "Copy",
                action: "wl-copy -- '" + e.ch + "'",
                pasteAfter: pasteAfter,
                childIds: []
            };
        }
        return e[key];
    });
}

var NIX_MAX_RESULTS = 30;

// ":nix" root trigger (M12 Task 7): returns the package query after it, ""
// for the bare ":nix", or null when `text` is not the trigger at all. Same
// contract as emojiTriggerQuery above.
function nixTriggerQuery(text) {
    var t = String(text || "");
    if (t === ":nix") return "";
    if (t.indexOf(":nix ") === 0) return t.slice(5);
    return null;
}

// `nix search nixpkgs <q> --json` stdout -> [{attr, version, description}],
// or null when the text isn't a JSON object at all, nixSearchOutcome below
// needs unparseable stdout (SEARCH FAILED) kept distinct from nix's clean
// zero-hit `{}` answer (NO RESULTS). Keys arrive as
// `legacyPackages.<system>.<attrpath>`; the first two dotted components are
// the flake/system prefix `nix run nixpkgs#<attr>` must not see, the
// remainder (itself possibly dotted: python312Packages.requests) is the
// attr. Object key order survives JSON.parse for string keys, so nix's own
// output order is kept.
function parseNixSearch(text) {
    var obj;
    try {
        obj = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (obj === null || typeof obj !== "object") return null;
    var out = [];
    Object.keys(obj).forEach(function (key) {
        var attr = key.split(".").slice(2).join(".");
        if (attr === "") return;
        var entry = obj[key] || {};
        out.push({
            attr: attr,
            version: String(entry.version || ""),
            description: String(entry.description || "")
        });
    });
    return out;
}

// One finished search Process -> one honest end state (M13b Task 4): 127
// is the sh wrapper's missing-binary sentinel (NO NIX); any other non-zero
// exit or unparseable stdout is SEARCH FAILED; a clean exit splits on
// whether the parsed set has entries (results) or is nix's `{}` zero-hit
// answer (NO RESULTS). Failure states never carry partial results.
function nixSearchOutcome(exitCode, text) {
    if (exitCode === 127) return { state: "unavailable", results: [] };
    if (exitCode !== 0) return { state: "failed", results: [] };
    var results = parseNixSearch(text);
    if (results === null) return { state: "failed", results: [] };
    if (results.length === 0) return { state: "empty", results: [] };
    return { state: "results", results: results };
}

// Search-result rows are plain "action" nodes: Enter spawns the package in
// a throwaway terminal through the existing activation path and closes.
// `read` holds the window open after the program exits so its output is
// actually readable. The attr is interpolated into a single-quoted sh
// string, so anything outside the safe attr charset is skipped outright
// rather than escaped, nixpkgs attrs are [A-Za-z0-9._+-] in practice.
// `notifySummary`/`notifyBody` mark the row for Menu.qml's activation
// toast: the spawned terminal can be seconds from mapping, so Enter fires
// a shell-local NIX RUN notification the moment it lands.
function nixRows(results) {
    var out = [];
    (results || []).forEach(function (r) {
        if (out.length >= NIX_MAX_RESULTS) return;
        if (!/^[A-Za-z0-9._+-]+$/.test(r.attr)) return;
        out.push({
            id: "nix." + r.attr,
            parentId: null,
            label: r.version !== "" ? r.attr + " " + r.version : r.attr,
            icon: "",
            title: "",
            desc: r.description !== "" ? previewLabel(r.description) : "",
            aliases: [],
            kind: "action",
            action: "ghostty -e sh -c 'nix run nixpkgs#" + r.attr + "; read'",
            notifySummary: "NIX RUN",
            notifyBody: r.attr,
            childIds: []
        });
    });
    return out;
}

// The honest single dim rows for everything that isn't a result list (kind
// "note": not activatable, MenuRow renders the label via mutedForeground):
// no `nix` on PATH, a search still in flight, a clean zero-hit answer, and
// a failed run.
function _nixNoteRow(id, label) {
    return {
        id: id,
        parentId: null,
        label: label,
        icon: "",
        title: "",
        aliases: [],
        kind: "note",
        dim: true,
        childIds: []
    };
}

function nixUnavailableRow() { return _nixNoteRow("nix.unavailable", "NO NIX"); }
function nixSearchingRow() { return _nixNoteRow("nix.searching", "SEARCHING"); }
function nixNoResultsRow() { return _nixNoteRow("nix.noresults", "NO RESULTS"); }
function nixFailedRow() { return _nixNoteRow("nix.failed", "SEARCH FAILED"); }

// ~/.clipssh/aliases (`name=user@host` lines, clipssh's own alias store,
// its alias_add rejects `=`/whitespace in names) -> [{name, target}].
// Malformed or blank lines are skipped: the file is clipssh's own state,
// not input this shell owns validating.
function clipsshAliases(text) {
    var out = [];
    String(text || "").split("\n").forEach(function (line) {
        var trimmed = line.trim();
        if (trimmed === "") return;
        var eq = trimmed.indexOf("=");
        if (eq <= 0 || eq === trimmed.length - 1) return;
        var name = trimmed.slice(0, eq);
        if (/\s/.test(name)) return;
        out.push({ name: name, target: trimmed.slice(eq + 1) });
    });
    return out;
}

// clipssh's own output contract, read off its script (v1.0.0, 2026-08-14):
// a completed transfer exits 0 and prints "Uploaded: <remote path>", every
// refusal exits non-zero and prints "Error: <reason>" on stderr, and both
// lines are wrapped in ANSI color, so the runs are stripped before anything
// is read out of them. 127 is the shell's own answer for a clipssh that
// isn't installed, which is worth saying plainly rather than reporting as an
// empty failure.
//
// ClipsshService turns this into what the user sees; the only thing decided
// here is what actually happened.
function clipsshOutcome(exitCode, stdout, stderr) {
    var out = String(stdout || "").replace(/\u001b\[[0-9;]*m/g, "");
    var err = String(stderr || "").replace(/\u001b\[[0-9;]*m/g, "");
    if (exitCode === 0) {
        var uploaded = out.match(/^\s*Uploaded:\s*(.+?)\s*$/m);
        return { ok: true, path: uploaded ? uploaded[1] : "" };
    }
    if (exitCode === 127)
        return { ok: false, error: "clipssh is not installed" };
    var reason = err.match(/^\s*Error:\s*(.+?)\s*$/m);
    if (reason)
        return { ok: false, error: reason[1] };
    // No line in clipssh's own shape: fall back to whatever it did say, and
    // only then to the bare code, so a failure never reports as nothing.
    var lines = err.split("\n").map(function (l) { return l.trim(); }).filter(function (l) { return l !== ""; });
    return { ok: false, error: lines.length > 0 ? lines[lines.length - 1] : "clipssh exited with code " + exitCode };
}

// Alias rows for the clipssh route: Enter hands the alias to ClipsshService
// (`@ipc:` dispatch, so the shell runs clipssh itself rather than spawning
// it through the compositor and losing sight of it). clipssh reads the
// clipboard image, pipes it over ssh and wl-copy's the remote path back,
// which takes as long as the link does. The service owns saying so, both
// while it is in flight and when it lands, so these rows carry no toast of
// their own. Empty store renders one dim note row whose desc is the exact
// add command, not a bare shrug.
function clipsshRows(aliases) {
    if (!aliases || aliases.length === 0) {
        return [{
            id: "clipssh.empty",
            parentId: null,
            label: "NO ALIASES",
            icon: "",
            title: "",
            desc: "clipssh alias add <name> <user@host>",
            aliases: [],
            kind: "note",
            dim: true,
            childIds: []
        }];
    }
    return aliases.map(function (a) {
        return {
            id: "clipssh." + a.name,
            parentId: null,
            label: a.name,
            icon: "",
            title: "",
            desc: a.target,
            aliases: [],
            kind: "action",
            action: "@ipc:clipssh.send:" + a.name,
            childIds: []
        };
    });
}

// Expands Config's `menu.customPowerButtons` (the spec's "first-class, not
// a workaround" case, e.g. an owner's Windows-reboot bootloader shortcut)
// into JSONC-shaped entry fragments keyed by dotted id, meant to be merged
// into the default tree object before Model.buildTree() runs:
// `system.custom.<i>` auto-nests under the already-declared `system` node
// exactly like any other dotted id.
function customPowerButtonEntries(buttons) {
    var out = {};
    (buttons || []).forEach(function (btn, i) {
        out["system.custom." + i] = {
            label: btn.label,
            icon: btn.icon || "",
            action: btn.command,
            confirm: btn.confirm === true
        };
    });
    return out;
}

// Image rows for the menu's "wallpaper" route (M23): the picker's grid
// moved inside the menu, so its cells are ordinary display rows, kind
// "image", carrying the absolute path, and every piece of machinery the
// menu already has (cursor wrap, the hover gate, `activate(index)` over
// IPC, the confirm/close paths) applies to them unchanged. Menu.qml lays
// them out in a GridView instead of the row ListView; that is the whole
// difference. `query` filters on the basename only: a path's directory
// component is identical for every row in a listing, so matching it would
// make every query match everything.
function imageBasename(path) {
    var p = String(path || "");
    var cut = p.lastIndexOf("/");
    return cut >= 0 ? p.slice(cut + 1) : p;
}

// The picker directory scan, as one argv. Quickshell has no
// directory-listing QML type (same rationale as CalendarEventsService's own
// `find`-backed read), and two callers need the same answer: the picker
// route re-scans on every entry so a directory edited between opens is
// picked up, and ThumbnailService scans the configured directory at startup
// to prerender its thumbnails. One definition of what counts as a pickable
// image, so the grid and the cache can never disagree about the listing.
//
// Both variant subdirectories are named as starting points alongside the
// directory itself: `find` reports a missing one on stderr (swallowed) and
// carries on with the rest, so one invocation covers every layout, and
// `-maxdepth 1` per starting point is what keeps an unrelated subdirectory
// of wallpapers out of the listing. `sort -u` because a case-insensitive
// filesystem answers both `Dark` and `dark` with the same directory.
function pickerScanCommand(dir) {
    return ["sh", "-c",
        'find "$1" "$1/Dark" "$1/dark" "$1/Light" "$1/light" -maxdepth 1 -type f'
        + ' \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.bmp" \\)'
        + ' 2>/dev/null | sort -u',
        "sh", String(dir || "")];
}

// Dark/Light variant split (owner, 2026-08-12: "for wallpapers, i want them
// to read the Dark/Light folders if they exist in the wallpaper folders, if
// not read just the root wallpaper folders"). The scan hands over everything
// it found directly under the picker directory AND directly under its
// `Dark`/`Light` subdirectories (either case) in one listing; this decides
// which of the three each path belongs to, from its position relative to
// `baseDir` rather than from its parent directory's name alone, a picker
// directory itself called `Dark` must not turn its own root listing into a
// variant.
//
// `hasVariants` is what the route keys its switcher off: neither
// subdirectory means one flat listing and no switcher at all, which is every
// existing setup and every `picker select` caller passing an arbitrary
// directory. One of the two present is still variant mode, with the other
// variant simply empty, an empty grid under a LIGHT header reads honestly,
// where silently falling back to the root listing would look like the
// switcher did nothing.
function wallpaperVariants(paths, baseDir) {
    var base = String(baseDir || "").replace(/\/+$/, "");
    var out = { hasVariants: false, dark: [], light: [], root: [] };
    (paths || []).forEach(function (p) {
        var variant = _pathVariant(String(p), base);
        if (variant === "dark")
            out.dark.push(p);
        else if (variant === "light")
            out.light.push(p);
        else
            out.root.push(p);
    });
    out.hasVariants = out.dark.length > 0 || out.light.length > 0;
    return out;
}

function _pathVariant(path, base) {
    if (base !== "" && path.indexOf(base + "/") !== 0)
        return "";
    var rest = base !== "" ? path.slice(base.length + 1) : path;
    var cut = rest.indexOf("/");
    if (cut < 0)
        return "";
    var segment = rest.slice(0, cut).toLowerCase();
    return segment === "dark" || segment === "light" ? segment : "";
}

// The listing one variant shows. The single entry point for it, so the grid,
// `picker choose`'s membership check and `picker status`'s count can never
// disagree about what is currently on screen.
function wallpaperListing(variants, variant) {
    if (!variants || !variants.hasVariants)
        return variants ? variants.root : [];
    return variant === "light" ? variants.light : variants.dark;
}

function imageRows(paths, query) {
    var q = String(query || "").trim().toLowerCase();
    return (paths || []).filter(function (p) {
        return q === "" || imageBasename(p).toLowerCase().indexOf(q) >= 0;
    }).map(function (p) {
        return {
            id: "wallpaper." + p,
            parentId: "wallpaper",
            label: imageBasename(p),
            icon: "",
            title: "",
            aliases: [],
            kind: "image",
            path: p,
            childIds: []
        };
    });
}

// Root nodes merged into the default tree object like
// customPowerButtonEntries above, and for the same reason: every action needs
// the running shell's own path, which static jsonc can't express. Routing
// through real IPC also means a menu row and a compositor keybind exercise
// one implementation. Each parent is declared here rather than left to
// buildTree's ancestor synthesis so it carries a label and an icon of its
// own.
//
// "Video To GIF" takes no argument on purpose: `record gif` falls back to
// RecordingService.lastPath, so the row needs no menu.input round trip.
//
// Kept the name "captureEntries" (M38 Task 3 folded the rest of the
// launcher's self-targeted leaf rows in here too, console, plain
// screenshots, screensaver, plugins, notifications, theme, rather than
// giving Menu.qml a second merge call site for the identical problem).
function captureEntries(selfPath) {
    var call = "qs ipc -p " + selfPath + " call ";
    return {
        "capture": { label: "Capture", icon: "\u{F0E51}" }, // md-monitor_screenshot
        "capture.text": {
            label: "Copy Text From Screen",
            icon: "\u{F113A}", // md-ocr
            action: call + "capture text"
        },
        "capture.color": {
            label: "Pick Color",
            icon: "\u{F020B}", // md-eyedropper_variant
            action: call + "capture color"
        },
        "capture.record": {
            label: "Record Screen",
            icon: "\u{F0567}", // md-video
            action: call + "record toggle screen none"
        },
        "capture.stop": {
            label: "Stop Recording",
            icon: "\u{F04DB}", // md-stop
            action: call + "record stop"
        },
        "capture.gif": {
            label: "Video To GIF",
            icon: "\u{F0D78}", // md-file_gif_box
            action: call + "record gif"
        },
        "capture.screenshot": {
            label: "Screenshot",
            icon: "\u{F0100}", // md-camera
            action: call + "screenshot full"
        },
        "capture.region": {
            label: "Screenshot Region",
            icon: "\u{F0489}", // md-selection
            action: call + "screenshot region"
        },

        "system.console": {
            label: "Console",
            icon: "\u{F018D}", // md-console
            action: call + "console toggle"
        },
        "system.screensaver": {
            label: "Screensaver",
            icon: "\u{F0D90}", // md-monitor_off
            action: call + "screensaver start"
        },
        "system.plugins": { label: "Plugins", icon: "\u{F0431}" }, // md-puzzle
        "system.plugins.list": {
            label: "List Plugins",
            icon: "\u{F0279}", // md-format_list_bulleted
            action: call + "plugins list"
        },
        "system.plugins.reload": {
            label: "Reload Plugins",
            icon: "\u{F0453}", // md-reload
            action: call + "plugins reload"
        },

        // Own root, not nested under "system.notifications" (that id is
        // already an activatable leaf, @ipc:notifications.showHistory,
        // and a "when"-less action node can't also carry children the
        // model would ever enter).
        "notifications": { label: "Notifications", icon: "\u{F009A}" }, // md-bell, same glyph system.notifications uses
        "notifications.clear": {
            label: "Clear All",
            icon: "\u{F039F}", // md-notification_clear_all
            action: call + "notifications clear"
        },
        "notifications.markAllSeen": {
            label: "Mark All Seen",
            icon: "\u{F012D}", // md-check_all
            action: call + "notifications markAllSeen"
        },
        "notifications.dismissAll": {
            label: "Dismiss Popups",
            icon: "\u{F062A}", // md-close_circle_multiple
            action: call + "notifications dismissAll"
        },

        // "theme.retheme" plus explicit dark/light rows alongside the
        // existing in-process toggle ("toggles.dark-mode", @ipc:
        // theme.toggleMode), these three go through real IPC instead
        // since ThemeIpc.mode() takes an explicit argument the internal
        // dispatch switch has no case for.
        "theme": { label: "Theme", icon: "\u{F0301}" }, // md-invert_colors
        "theme.retheme": {
            label: "Retheme",
            icon: "\u{F0301}", // md-invert_colors
            action: call + "theme retheme"
        },
        "theme.mode-dark": {
            label: "Dark Mode",
            icon: "\u{F0594}", // md-weather_night
            action: call + "theme mode dark"
        },
        "theme.mode-light": {
            label: "Light Mode",
            icon: "\u{F0599}", // md-weather_sunny
            action: call + "theme mode light"
        }
    };
}

// Panel rows (M38 Task 3): one per name in shell.qml's PanelIpc registry.
// Static list, not a scan, the registry itself is declared in shell.qml,
// not discoverable at runtime, so a 16th panel needs a new entry here too;
// tst_menu_reachability.qml is the guard that fails when one is missed.
// Self-targeted the same way captureEntries above is, and for the same
// reason (clipboardProvider's own comment has the full mechanism): each
// row spawns "qs ipc -p <selfPath> call panel open <name>", the exact
// invocation PanelIpc.qml's own header names as the mechanism a bar-cell
// click already uses. Registered as a provider (applyProviders), not
// folded into captureEntries' root merge, since this is a submenu of rows
// rather than a handful of individual leaves.
var PANEL_NAMES = [
    { id: "appmenu", label: "App Menu", icon: "\u{F003B}" }, // md-apps, same glyph the apps root node uses
    { id: "audio", label: "Audio", icon: "\u{F057E}" }, // md-volume_high
    { id: "calendar", label: "Calendar", icon: "\u{F00EE}" }, // md-calendar_blank
    { id: "network", label: "Network", icon: "\u{F05A9}" }, // md-wifi
    { id: "bluetooth", label: "Bluetooth", icon: "\u{F00AF}" }, // md-bluetooth
    { id: "airpods", label: "AirPods", icon: "\u{F184F}" }, // md-earbuds
    { id: "dualsense", label: "DualSense", icon: "\u{F0297}" }, // md-gamepad_variant
    { id: "power", label: "Power", icon: "\u{F0079}" }, // md-battery
    { id: "weather", label: "Weather", icon: "\u{F0599}" }, // md-weather_sunny
    { id: "media", label: "Media", icon: "\u{F0387}" }, // md-music_note
    { id: "github", label: "GitHub", icon: "\u{F408}" }, // oct-mark_github
    { id: "usage", label: "Usage", icon: "\u{F16A3}" }, // md-robot_excited
    { id: "tailscale", label: "Tailscale", icon: "\u{F0318}" }, // md-lan_connect
    { id: "systemupdate", label: "System Update", icon: "\u{F03D3}" }, // md-package
    { id: "display", label: "Display", icon: "\u{F0379}" }, // md-monitor
    { id: "monitor", label: "Monitor", icon: "\u{F029A}" } // md-gauge, same glyph MonitorWidget's bar cell uses
];

function panelsProvider(selfPath) {
    return PANEL_NAMES.map(function (p) {
        return {
            id: "panels." + p.id,
            parentId: null,
            label: p.label,
            icon: p.icon,
            title: "",
            aliases: [],
            kind: "action",
            action: "qs ipc -p " + selfPath + " call panel open " + p.id,
            childIds: []
        };
    });
}

// System tray rows (M38 Task 3): SystemTray.items has no launcher path
// today, only a bar-cell click. Mirrors TrayIpc.qml's own activate(id)
// exactly (same registry, same id semantics), self-targeted the same way
// clipboardProvider is. `_shq` guards an id containing whitespace from
// splitting into extra argv tokens on the way through sh -c. An empty tray
// renders one dim row, the same honest-empty shape clipboardEmptyRow/
// clipsshRows already use, never an empty level.
function trayProvider(items, selfPath) {
    if (!items || items.length === 0) {
        return [{
            id: "tray.empty",
            parentId: null,
            label: "NO TRAY ITEMS",
            icon: "",
            title: "",
            aliases: [],
            kind: "note",
            dim: true,
            childIds: []
        }];
    }
    return items.map(function (item) {
        return {
            id: "tray." + item.id,
            parentId: null,
            label: item.tooltipTitle || item.title || item.id,
            icon: "",
            title: "",
            aliases: [],
            kind: "action",
            action: "qs ipc -p " + selfPath + " call tray activate " + _shq(item.id),
            childIds: []
        };
    });
}

// GPU routes (M38 Task 8). "gpu" is an always-present, informational-only
// route (one note row per GpuService card); "gpu.mode" is a runtime-injected
// fragment merged into _defaultObj the way captureEntries/
// shareClipboardEntry already are, not declared in default-menu.jsonc,
// because it must be genuinely ABSENT rather than empty on a machine with
// no supergfxctl (no jsonc placeholder means nothing for a machine without
// it to fall back to).
//
// There is no "launch on GPU" route. It shipped as one and was a second
// full copy of the app list in every root search, for a choice the
// Shift+Enter accelerator on the app row itself already offers.

function _gpuOutputsDesc(outputs) {
    var connected = (outputs || []).filter(function (o) { return o.connected; }).map(function (o) { return o.name; });
    return connected.length > 0 ? connected.join(", ") : "no outputs";
}

// One inert note row per card: name, integrated/discrete, driver, connected
// outputs. Mirrors keybinds.js's own rows() shape for a route that carries
// information but nothing to activate -- Menu.qml's _activateRow has no
// "note" case, so Enter here is a no-op. No cards renders the same NO GPU
// label MonitorPanel/MonitorView use, instead of an empty level.
function gpuProvider(cards) {
    if (!cards || cards.length === 0) {
        return [{
            id: "gpu.empty",
            parentId: null,
            label: "NO GPU",
            icon: "",
            title: "",
            aliases: [],
            kind: "note",
            dim: true,
            childIds: []
        }];
    }
    return cards.map(function (card) {
        return {
            id: "gpu.card." + card.card,
            parentId: null,
            label: card.name || card.card,
            icon: "",
            title: "",
            desc: (card.discrete ? "Discrete" : "Integrated") + " · " + card.driver + " · " + _gpuOutputsDesc(card.outputs),
            aliases: [],
            kind: "note",
            childIds: []
        };
    });
}

// The offload launch Menu.qml's Shift+Enter accelerator runs against the
// cursor's app row. Self-targeted the same way panelsProvider is; `_shq`
// guards a desktop id containing characters a bare interpolation would
// break (flatpak's reverse-DNS ids can carry a trailing instance suffix).
function gpuLaunchAction(selfPath, desktopId, card) {
    return "qs ipc -p " + selfPath + " call monitor launch " + _shq(desktopId) + " " + _shq(card);
}

// "gpu.mode" fragment, same merge mechanism, gated on GpuService.gfxMode
// (supergfxctl's own presence) rather than card count. Neither of the
// owner's machines has supergfxctl, so the normal case is {}.
function gpuModeEntry(selfPath, gfxMode) {
    if (!gfxMode || gfxMode.supported !== true)
        return {};
    var call = "qs ipc -p " + selfPath + " call ";
    return {
        "gpu.mode": { label: "GPU Mode", icon: "\u{F04E1}" }, // md-swap_horizontal
        "gpu.mode.integrated": {
            label: "Integrated",
            icon: "\u{F0322}", // md-laptop
            action: call + "monitor mode integrated"
        },
        "gpu.mode.hybrid": {
            label: "Hybrid",
            icon: "\u{F00FB}", // md-call_split
            action: call + "monitor mode hybrid"
        }
    };
}
