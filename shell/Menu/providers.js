.pragma library
.import "frecency.js" as Frecency

// Provider functions populate a "provider" kind node's children at
// tree-build time (Model.buildTree() infers "provider" from an entry's
// `provider` key — see default-menu.jsonc's "apps" node). Providers return
// ready-made Node fragments (Model's Node shape: id/label/icon/title/
// aliases/kind/childIds) rather than JSONC entries, because they bypass
// buildTree()'s action/target/provider kind inference entirely — an app has
// no `action` string, it has a DesktopEntry to call execute() on, which
// respects .desktop field codes/Exec quoting that re-running it through
// `sh -c` would mangle.

// `entries` = DesktopEntries.applications.values (Quickshell's built-in
// desktop-entry index, already excludes Hidden/NoDisplay). Each app node
// keeps a reference to its DesktopEntry (`_entry`) so Menu.qml's activation
// can call `_entry.execute()` directly instead of spawning a shell command.
//
// `entry.icon` is an icon-theme NAME ("firefox", "mpv"), not a glyph — it
// must never land in the node's `icon` slot, which MenuRow renders as
// literal text (the M13b "apps list shows app IDs" symptom: rows led with
// the raw icon name, which conventionally equals the app id). Instead
// `resolveIcon` (Menu.qml passes Quickshell.iconPath with check=true, tests
// pass a stub) maps the name to an image URL for MenuRow's image slot, or
// "" when the theme has no such icon — the row then simply has no leading
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
function appsProvider(entries, resolveIcon, launches, nowMs) {
    var ordered = Frecency.order(entries || [], launches, nowMs === undefined ? Date.now() : nowMs);
    return ordered.map(function (entry) {
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
// Unlike appsProvider these are plain "action" nodes — Menu.qml's existing
// `_activateRow`/`_runAction` spawn-command path already re-copies the entry
// via `qs ipc call clipboard copy <id>` with zero Menu.qml changes, so no
// bespoke node kind (and no `_entry`-style back-reference) is needed here.
//
// `selfPath` is the running shell's own config root (`Quickshell.shellDir`,
// e.g. `<store-path>/share/formalshell`) — without `-p <selfPath>` on the
// call, `qs ipc`'s instance lookup falls back to the default XDG quickshell
// config dir (command.cpp's locateConfigFile()/selectInstance()), which
// formalshell doesn't register under, so the copy would silently hit "No
// running instances" instead of this shell.
//
// No `--any-display` alongside it, unlike the keybind form USAGE.md documents
// for callers that may have no WAYLAND_DISPLAY at all. A row's command is
// spawned by this shell, so it already carries this shell's display, and that
// display is quickshell's only discriminator between two instances sharing one
// `by-path/<md5(configFilePath)>` registry entry (selectInstance() takes the
// oldest match and reports no ambiguity). A nested smoke session and the
// owner's live bar share XDG_RUNTIME_DIR, so they share that entry whenever
// they were built from the same store path, and the flag would let this
// shell's own menu row write the other one's clipboard.
//
// Image entries (M14 Task 1, history.js's `kind: "image"`) get a fixed
// "IMAGE" label instead of a text preview, a dimmed capture time in the
// `desc` slot (same trailing-text idiom nixRows uses), and `thumbSource` —
// a new node field MenuRow doesn't render yet (Task 6 wires the thumbnail
// row); the activation action is identical to a text row's.
function _capturedAtLabel(capturedAt) {
    var d = new Date(capturedAt);
    var pad2 = function (n) { return (n < 10 ? "0" : "") + n; };
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

// `mode` ("copy", the default, or "share") only changes the row's id
// prefix and activation — label/desc/thumbSource stay identical either
// way. "share" rows need their own id namespace ("share.history.<id>"
// rather than "clipboard.<id>"): both providers read the SAME
// ClipboardService.items list, and tree.nodes is one flat map keyed by id,
// so reusing "clipboard.<id>" here would silently overwrite the real
// clipboard node's own rows (or vice versa, depending on provider order).
function clipboardProvider(items, selfPath, mode) {
    mode = mode || "copy";
    var idPrefix = mode === "share" ? "share.history." : "clipboard.";
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
            aliases: [],
            kind: "action",
            action: mode === "share"
                ? shareEntryCommand(entry)
                : "qs ipc -p " + selfPath + " call clipboard copy " + entry.id,
            childIds: []
        };
    });
}

// Single-quotes `value` for a sh -c string, escaping embedded single quotes
// the same way HyprlandBackend.qml's _quoteArg does ('\'' — close the
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
// upstream's own arg parser — LoadSelectionFromArgsAction in
// app/lib/provider/selection/selected_sending_files_provider.dart,
// localsend/localsend — has no `--headless`/`send` mode at all: unknown
// dash-flags are silently skipped and a bare non-path token like "send" is
// silently ignored too, so omarchy's invocation happens to still work by
// accident, not by design). The real, verified mechanism is narrower still:
// LoadSelectionFromArgsAction (app/lib/provider/selection/
// selected_sending_files_provider.dart:290-293) skips every arg starting
// with "-" outright, then only keeps args where File(arg).existsSync() or
// Directory(arg).existsSync() — a bare file path pre-populates the GUI's
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
// wallpaperEntry() is: its action depends on the CURRENT newest clipboard
// entry (items[0]), which static jsonc can't express. default-menu.jsonc
// still declares a "share.clipboard" placeholder so this fragment's key
// overwrites an already-present entry rather than appending a new one —
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

// First non-blank line only, capped at maxLen chars — clipboard captures can
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

var EMOJI_MAX_RESULTS = 40;

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
// skin-tone variants for free. Empty query browses the head of the list so
// the summoned route is never an empty surface.
function emojiSearch(list, query) {
    list = list || [];
    var q = String(query || "").trim().toLowerCase();
    if (!q) return list.slice(0, EMOJI_MAX_RESULTS);
    var results = [];
    for (var i = 0; i < list.length; i++) {
        var name = String(list[i].name).toLowerCase();
        var tier;
        if (name === q) tier = 4;
        else if (name.indexOf(q) === 0) tier = 3;
        else if (name.indexOf(" " + q) >= 0) tier = 2;
        else if (name.indexOf(q) >= 0) tier = 1;
        else continue;
        results.push({ entry: list[i], tier: tier, index: i });
    }
    results.sort(function (a, b) {
        if (b.tier !== a.tier) return b.tier - a.tier;
        return a.index - b.index;
    });
    return results.slice(0, EMOJI_MAX_RESULTS).map(function (r) { return r.entry; });
}

// Emoji rows are plain "action" nodes (clipboardProvider's own trick): Enter
// runs `wl-copy` through the existing activation path and closes, and the
// clipboard service captures the copy like any other. The char rides the
// icon slot, the uppercase name is the label. Single quotes are required
// around the char: keycap sequences start with ASCII `#`/`*`/digits (comment
// and glob hazards unquoted), and no emoji contains an ASCII apostrophe.
// `typeText` marks the row for Menu.qml's instant-paste hook (M13 Task 6):
// on top of the copy, the char is auto-typed via wtype into whatever window
// focus returns to once the menu surface has actually closed.
function emojiRows(list, query) {
    return emojiSearch(list, query).map(function (e) {
        return {
            id: "emoji." + e.ch,
            parentId: null,
            label: e.name.toUpperCase(),
            icon: e.ch,
            title: "",
            aliases: [],
            kind: "action",
            action: "wl-copy -- '" + e.ch + "'",
            typeText: e.ch,
            childIds: []
        };
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
// or null when the text isn't a JSON object at all — nixSearchOutcome below
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
// rather than escaped — nixpkgs attrs are [A-Za-z0-9._+-] in practice.
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
// "note": not activatable, MenuRow renders the label via foregroundDim):
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

// ~/.clipssh/aliases (`name=user@host` lines, clipssh's own alias store —
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

// Alias rows for the clipssh route: Enter spawns `clipssh <name>` through
// the normal activation path — clipssh grabs the clipboard image, scp's it
// to the alias's host, and wl-copy's the remote path back, which
// ClipboardService captures like any other copy, so the new clipboard
// entry IS the success feedback. The scp can take seconds, so the row also
// fires the activation toast (nixRows' notifySummary idiom) the moment
// Enter lands. Names go through _shq: clipssh bans `=`/whitespace in them
// but nothing else. Empty store renders one dim note row whose desc is the
// exact add command, not a bare shrug.
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
            action: "clipssh " + _shq(a.name),
            notifySummary: "CLIPSSH",
            notifyBody: a.name,
            childIds: []
        };
    });
}

// Expands Config's `menu.customPowerButtons` (the spec's "first-class, not
// a workaround" case — e.g. an owner's Windows-reboot bootloader shortcut)
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

// Root "wallpaper" node (M13 Task 5), merged into the default tree object
// before Model.buildTree() exactly like customPowerButtonEntries above —
// it can't live in default-menu.jsonc because the action needs the running
// shell's own path (clipboardProvider's selfPath rationale). Activation
// spawns the self-targeting `qs ipc call picker summon` rather than opening
// the picker in-process: the spawned call lands after the menu surface has
// already closed, so the picker never fights the menu's keyboard-exclusive
// focus.
function wallpaperEntry(selfPath) {
    return {
        "wallpaper": {
            label: "Wallpaper",
            icon: "\u{F0E09}", // nf-md-wallpaper
            action: "qs ipc -p " + selfPath + " call picker summon"
        }
    };
}

// Root "capture" node, merged into the default tree object exactly like
// wallpaperEntry() above, and for the same reason: every action needs the
// running shell's own path, which static jsonc can't express. Routing
// through real IPC also means a menu row and a compositor keybind exercise
// one implementation. The parent node is declared here rather than left to
// buildTree's ancestor synthesis so it carries a label and an icon of its
// own.
//
// "Video To GIF" takes no argument on purpose: `record gif` falls back to
// RecordingService.lastPath, so the row needs no menu.input round trip.
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
        }
    };
}
