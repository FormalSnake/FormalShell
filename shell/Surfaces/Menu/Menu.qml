import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Core as Core
import qs.Compositor
import qs.Components
import qs.Services
import qs.Notifications
import "../../Menu/model.js" as Model
import "../../Menu/search.js" as Search
import "../../Menu/providers.js" as Providers
import "../../Menu/calc.js" as Calc
import "../../Menu/frecency.js" as Frecency

// The unified menu (DESIGN.md §Concrete translations/Menu): a single
// keyboard-exclusive top-layer window, centered on the focused output. Top
// cell is the search field (breadcrumb as its meta row); below it, rows are
// either search.rank() matches (query non-empty) or model.visibleChildren()
// of the current level (query empty). Whole-tree search, cursor wraps,
// Escape/backspace-on-empty pop one level, confirm-gated actions need a
// second Enter.
//
// Tree assembly: default-menu.jsonc (read once, it ships inside the
// package) merged with Config's customPowerButtons (system.custom.N,
// providers.customPowerButtonEntries()) go through Model.buildTree(), then
// providers.applyProviders() expands "provider" nodes ("apps" ->
// DesktopEntries) into real children. Recomputes whenever the jsonc text
// loads or Core.Config.settings changes, so custom power buttons and the
// installed-apps list never need a manual refresh.
PanelWindow {
    id: root

    property bool isOpen: false
    property var currentNodeId: null
    property int _cursorIndex: 0
    property string _confirmPendingId: ""
    property var _condResults: ({})
    property var _checkedResults: ({})

    // "menu" (tree navigation) | "select" | "input" — the dmenu-replacement
    // modes summoned via MenuIpc's select()/input(). Both repurpose the same
    // window/search field; _displayRows, breadcrumb and key handling branch
    // on this. _abandonPendingSelect() is what resets it back to "menu".
    property string _mode: "menu"
    property string _selectPrompt: ""
    property var _selectOptions: []
    property string _selectToken: ""

    // Fires whenever a select()/input() request resolves (submitted value or
    // cancelled) — the same event external callers poll menu-selection.txt
    // for (see MenuIpc.qml's header comment), exposed as a signal so
    // in-process callers (the Calendar panel's life-progress easter egg,
    // M6 Task 4) don't need a FileView of their own.
    signal selectionResolved(string token, var value, bool cancelled)

    property string _defaultMenuText: ""
    property string _userMenuText: ""

    // Set from shell.qml — the single Center instance, needed for
    // "@ipc:notifications.showHistory" (see _dispatchInternal below).
    property var center: null

    readonly property string _configDir: {
        const xdgConfig = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config");
        return xdgConfig + "/formalshell";
    }

    FileView {
        id: defaultMenuFile
        path: Quickshell.shellPath("Menu/default-menu.jsonc")
        // default-menu.jsonc ships inside the package, so this load only
        // ever races startup once — but Component.onCompleted's auto-open
        // (and a very early `menu summon`, Task 7) can call open() before
        // it lands, evaluating conditions against an empty tree with
        // nothing left to ever re-check them. Re-running the batch here,
        // once the real tree exists, closes that gap; _evalConditions()'s
        // per-node `undefined` guard makes it a cheap no-op otherwise.
        onLoaded: {
            root._defaultMenuText = defaultMenuFile.text();
            root._evalConditions();
        }
        onLoadFailed: error => console.warn("Menu: failed to load default-menu.jsonc:", error)
    }

    // Vendored emoji dataset (M12 Task 6) — ships inside the package like
    // default-menu.jsonc, parsed with Model.parseJsonc because
    // dev/gen-emoji.sh writes a provenance header comment JSON.parse would
    // reject. Load failure degrades to an empty list (the emoji route and
    // ":e" trigger simply return no rows), one console.warn.
    property string _emojiText: ""

    FileView {
        id: emojiFile
        path: Quickshell.shellPath("Menu/emoji.json")
        onLoaded: root._emojiText = emojiFile.text()
        onLoadFailed: error => console.warn("Menu: failed to load emoji.json:", error)
    }

    readonly property var _emojiList: {
        if (!root._emojiText) return [];
        try {
            return Model.parseJsonc(root._emojiText);
        } catch (e) {
            console.warn("Menu: failed to parse emoji.json:", e.message);
            return [];
        }
    }

    // Nix package runner state (M12 Task 7; M13b Task 4 added the honest
    // end states). `nix search` is seconds-slow and network-bound, so
    // unlike calc/emoji the rows can't be computed in the _displayRows
    // binding: keystrokes arm a 500ms debounce (_requestNixSearch, called
    // from onTextChanged/query(), never from a binding), one Process runs
    // at a time, and a result is only cached when it still answers the
    // latest requested query — anything else is dropped and the search
    // re-runs (_startNixSearch from onExited). Each cached answer carries
    // its outcome (Providers.nixSearchOutcome) so _nixRowsFor renders NO
    // RESULTS and SEARCH FAILED distinctly instead of one ambiguous
    // nothing. `nix` missing from PATH (the sh wrapper's `command -v`
    // guard, exit 127) latches _nixAvailable false: every nix surface then
    // renders the single dim NO NIX row and no further processes spawn.
    property string _nixQuery: ""       // the query _nixResults answers
    property var _nixResults: []
    property string _nixOutcome: "results"  // how _nixQuery ended: results|empty|failed
    property string _nixWantQuery: ""   // latest requested query
    property bool _nixAvailable: true

    function _requestNixSearch(q) {
        q = String(q || "").trim();
        if (q === "" || !root._nixAvailable || q === root._nixQuery) return;
        root._nixWantQuery = q;
        nixDebounce.restart();
    }

    function _startNixSearch() {
        if (nixSearchProc.running || root._nixWantQuery === "" || !root._nixAvailable) return;
        nixSearchProc._query = root._nixWantQuery;
        nixSearchProc.command = ["sh", "-c", 'command -v nix >/dev/null 2>&1 || exit 127; exec nix search nixpkgs "$1" --json', "sh", root._nixWantQuery];
        nixSearchProc.running = true;
    }

    // The rows a nix surface (route level or ":nix" trigger) shows for `q`
    // right now: the honest NO NIX row, a dim SEARCHING note while the
    // cached answer doesn't cover this exact query yet (the debounce +
    // Process round trip runs tens of seconds on a cold real-host eval
    // cache), or the cached end state — result rows, NO RESULTS, SEARCH
    // FAILED. Stale rows for a previous query never linger.
    function _nixRowsFor(q) {
        if (!root._nixAvailable) return [Providers.nixUnavailableRow()];
        q = String(q || "").trim();
        if (q === "") return [];
        if (q !== root._nixQuery) return [Providers.nixSearchingRow()];
        if (root._nixOutcome === "failed") return [Providers.nixFailedRow()];
        if (root._nixOutcome === "empty") return [Providers.nixNoResultsRow()];
        return Providers.nixRows(root._nixResults);
    }

    Timer {
        id: nixDebounce
        interval: 500
        onTriggered: root._startNixSearch()
    }

    Process {
        id: nixSearchProc

        property string _query: ""

        stdout: StdioCollector {
            id: nixSearchCollector
        }
        onExited: exitCode => {
            var outcome = Providers.nixSearchOutcome(exitCode, nixSearchCollector.text);
            if (outcome.state === "unavailable") {
                root._nixAvailable = false;
                console.warn("Menu: nix not found on PATH, nix runner disabled");
                return;
            }
            if (_query !== root._nixWantQuery) {
                root._startNixSearch();
                return;
            }
            root._nixQuery = _query;
            root._nixOutcome = outcome.state;
            root._nixResults = outcome.results;
        }
    }

    // ~/.config/formalshell/menu.jsonc — the per-key user overlay (plan-wide
    // constraint: user wins, `"hidden": true` drops a default node). Same
    // bounded-retry-until-watch-attaches pattern as Config.qml's
    // settings.json: the file (and its parent dir) may not exist yet at
    // first launch, so a bare watchChanges: true would never attach. Unlike
    // settings.json this file is OPTIONAL and usually absent, so the retry
    // is actually bounded here (once the parent dir exists the directory
    // watch catches the file appearing; `menu refresh` stays the manual
    // fallback), FileView's own per-read warning is off, and the absence is
    // logged once instead of once per retry (the e1504g trial logged the
    // identical warning six times over, M13 Task 5).
    property int _userMenuRetries: 0
    property bool _userMenuMissingLogged: false

    Timer {
        id: userMenuRewatchTimer
        interval: 300
        onTriggered: userMenuFile.reload()
    }

    FileView {
        id: userMenuFile
        printErrors: false
        path: root._configDir + "/menu.jsonc"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root._userMenuRetries = 0;
            root._userMenuMissingLogged = false;
            root._userMenuText = userMenuFile.text();
            root._evalConditions();
        }
        onLoadFailed: error => {
            root._userMenuText = "";
            if (error === FileViewError.FileNotFound) {
                if (!root._userMenuMissingLogged) {
                    root._userMenuMissingLogged = true;
                    console.info("Menu: no user overlay at", userMenuFile.path, "(optional, defaults apply)");
                }
                if (root._userMenuRetries < 20) {
                    root._userMenuRetries++;
                    userMenuRewatchTimer.restart();
                }
            }
        }
    }

    // ~/.clipssh/aliases — clipssh's own `name=user@host` store, optional
    // like menu.jsonc but with none of its retry machinery: open() reloads
    // it every summon, so an alias added mid-session (even before the file
    // first existed) shows on the next open without a watch ever having
    // attached. Absence just means zero aliases — clipsshRows' own NO
    // ALIASES note row — never a warning.
    property string _clipsshAliasesText: ""

    FileView {
        id: clipsshAliasFile
        printErrors: false
        path: Quickshell.env("HOME") + "/.clipssh/aliases"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._clipsshAliasesText = clipsshAliasFile.text()
        onLoadFailed: root._clipsshAliasesText = ""
    }

    // Mirrors ClipboardService.items ONLY while the menu is actually open
    // (M17 review finding, M-polish batch item G, owner: low-end laptop) —
    // the ternary's closed branch never reads ClipboardService.items, so
    // QML's binding dependency tracker doesn't subscribe to it while
    // closed: a clipboard capture landing while the menu is closed no
    // longer touches this property at all, which is what keeps
    // _defaultObj/_tree below from rebuilding the ENTIRE tree (every app,
    // every provider) on every single capture. The moment isOpen flips
    // true this re-reads the live list and resubscribes, so content is
    // exactly as fresh as before for as long as the menu stays open.
    readonly property var _liveClipboardItems: root.isOpen ? ClipboardService.items : []

    readonly property var _defaultObj: {
        if (!root._defaultMenuText) return {};
        var parsed;
        try {
            parsed = Model.parseJsonc(root._defaultMenuText);
        } catch (e) {
            console.warn("Menu: failed to parse default-menu.jsonc:", e.message);
            return {};
        }
        var buttons = Providers.customPowerButtonEntries(Core.Config.get("menu.customPowerButtons", []));
        var wallpaper = Providers.wallpaperEntry(Quickshell.shellDir);
        var stayAwake = Providers.stayAwakeEntry(Quickshell.shellDir);
        // Live-while-open, unlike wallpaper/buttons above: its action
        // depends on the current newest clipboard entry, so
        // _liveClipboardItems rides this same binding for _defaultObj (and
        // _tree below) to recompute whenever it changes — but only while
        // that dependency is actually subscribed (see _liveClipboardItems'
        // own comment). Merged as a plain overwrite of the
        // "share.clipboard" key default-menu.jsonc already declares, so the
        // row keeps that declared position instead of jumping to the end.
        var shareClipboard = Providers.shareClipboardEntry(root._liveClipboardItems);
        var merged = {};
        Object.keys(parsed).forEach(function (k) { merged[k] = parsed[k]; });
        Object.keys(shareClipboard).forEach(function (k) { merged[k] = shareClipboard[k]; });
        Object.keys(wallpaper).forEach(function (k) { merged[k] = wallpaper[k]; });
        Object.keys(stayAwake).forEach(function (k) { merged[k] = stayAwake[k]; });
        Object.keys(buttons).forEach(function (k) { merged[k] = buttons[k]; });
        return merged;
    }

    readonly property var _userObj: {
        if (!root._userMenuText) return {};
        try {
            return Model.parseJsonc(root._userMenuText);
        } catch (e) {
            console.warn("Menu: failed to parse menu.jsonc:", e.message);
            return {};
        }
    }

    readonly property var _tree: Providers.applyProviders(Model.buildTree(root._defaultObj, root._userObj), {
        // check=true so a name the icon theme can't resolve yields "" (the
        // glyph-slot fallback) instead of the provider's missing-texture box.
        //
        // Core.State.appLaunches rides this binding deliberately: recording
        // a launch (_activateRow below) rebuilds the tree, which is what
        // re-orders the rows for the next summon. It lands as the menu is
        // closing, where _liveClipboardItems' own isOpen flip already pays
        // for a rebuild. Date.now() is read at rebuild time, so the recency
        // decay is as fresh as the tree itself.
        apps: function () {
            return Providers.appsProvider(DesktopEntries.applications.values, function (name) {
                return Quickshell.iconPath(name, true);
            }, Core.State.appLaunches, Date.now());
        },
        clipboard: function () { return Providers.clipboardProvider(root._liveClipboardItems, Quickshell.shellDir); },
        shareHistory: function () { return Providers.clipboardProvider(root._liveClipboardItems, Quickshell.shellDir, "share"); },
        clipssh: function () { return Providers.clipsshRows(Providers.clipsshAliases(root._clipsshAliasesText)); }
    })
    readonly property var _nodes: root._tree.nodes

    // True while the current level's own node carries an unsatisfied (or
    // not-yet-resolved) `when` gate — see _displayRows' own comment for why
    // this only matters for the direct-summon path.
    readonly property bool _currentNodeGated: {
        if (root.currentNodeId === null) return false;
        var node = root._nodes[root.currentNodeId];
        return node ? !Model.isWhenVisible(node, root._condResults) : false;
    }

    readonly property var _displayRows: {
        if (root._mode === "select") {
            var query = searchInput.text.toLowerCase();
            return root._selectOptions
                .map(function (opt, i) { return { id: "select." + i, label: String(opt), icon: "", kind: "option" }; })
                .filter(function (n) { return query.length === 0 || n.label.toLowerCase().indexOf(query) >= 0; });
        }
        if (root._mode === "input")
            return [];
        var q = searchInput.text;
        // The emoji route searches the vendored dataset exclusively (an
        // empty query browses its head, Providers.emojiSearch), and the
        // ":e " trigger narrows to the same rows from any level (M12
        // Task 6). Neither ever falls through to whole-tree ranking: 3,944
        // emoji in the tree would drown every root search.
        var emojiQuery = Providers.emojiTriggerQuery(q);
        if (root.currentNodeId === "emoji")
            return Providers.emojiRows(root._emojiList, emojiQuery !== null ? emojiQuery : q);
        if (emojiQuery !== null)
            return Providers.emojiRows(root._emojiList, emojiQuery);
        // The nix route/":nix" trigger works the same way, except the rows
        // come from the debounced-Process cache (see the state block above)
        // rather than a pure function over local data.
        var nixQuery = Providers.nixTriggerQuery(q);
        if (root.currentNodeId === "nix" || nixQuery !== null)
            return root._nixRowsFor(nixQuery !== null ? nixQuery : q);
        if (q.length === 0) {
            // Route-summon when-gate guard (M17 review finding, item F):
            // `open(route)` resolves a node by id directly, bypassing the
            // parent-level isWhenVisible() filter that keeps a gated node
            // (e.g. "share" without localsend_app) from ever appearing as
            // a row in the first place — without this, landing on that
            // level here would still list its children as if the gate
            // never existed. `root._currentNodeGated` covers "not yet
            // resolved" the same as "resolved false": _condResults starts
            // empty every open()/_enterLevel(), so a level entered before
            // its own condition Process has exited must not flash
            // actionable rows it may end up refusing a moment later.
            if (root._currentNodeGated)
                return [Model.gatedNoteRow(root._nodes[root.currentNodeId])];
            return Model.visibleChildren(root._nodes, root.currentNodeId, root._condResults);
        }
        // A query that parses as an expression leads with the CALC result row
        // (M12 Task 5). At the dedicated calc level the result row is the
        // whole surface — whole-tree matches would just be root search noise
        // there. Parse failures are silent: calcRow is null, nothing renders.
        var calcRow = Calc.resultNode(q);
        if (root.currentNodeId === "calc")
            return calcRow ? [calcRow] : [];
        var ranked = Search.rank(root._nodes, q, root._condResults);
        return calcRow ? [calcRow].concat(ranked) : ranked;
    }

    // Uppercased at display time only (MetaLabel's own font.capitalization,
    // the one shared uppercase/meta convention) — the JS-level
    // `.toUpperCase()` this used to carry was pure redundancy, since
    // `breadcrumb` has no other consumer (audit "uppercase/meta treatment").
    readonly property string breadcrumb: {
        if (root._mode === "select")
            return "SELECT / " + root._selectPrompt;
        if (root._mode === "input")
            return "INPUT / " + root._selectPrompt;
        var parts = [];
        var id = root.currentNodeId;
        while (id !== null && root._nodes[id]) {
            parts.unshift(root._nodes[id].label);
            id = root._nodes[id].parentId;
        }
        return ["MENU"].concat(parts).join(" / ");
    }

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }
    readonly property real _maxTotalHeight: root._screen ? root._screen.height * 0.6 : 400
    // Content gets a `popupPadding` gutter (DESIGN.md's omarchy card chrome:
    // "internal padding") on all four sides now — the frame draws its own
    // explicit ring on all four (below). Rows still draw their own
    // bottom+right per Cell's shared-rule contract (needed for the divider
    // between adjacent rows), which would otherwise double the frame's
    // right/bottom rule `popupPadding` apart — the two eraser rectangles
    // below paint over just that trailing hairline with the frame's own
    // background color, leaving the frame's rule as the single visible line
    // on every edge (same technique as Panel.qml's `_contentWidth`).
    readonly property real _contentWidth: root.implicitWidth - Core.Theme.borderWidth * 2 - Core.Theme.space.popupPadding * 2
    readonly property real _chrome: Core.Theme.borderWidth * 2 + Core.Theme.space.popupPadding * 2
    readonly property real _rowsAreaHeight: Math.min(rowsView.contentHeight, Math.max(0, root._maxTotalHeight - root._chrome - searchCell.height))

    // Card-top freeze (omarchy parity, M16 Task 2): the first filter
    // keystroke or submenu move in a session pins the top margin at
    // whatever it currently resolves to, so every row-count change after
    // that grows/shrinks the card downward instead of re-centering it.
    // null means "not frozen yet" — margins.top below falls back to the
    // live centered formula. Released on every open()/openSelect()/
    // openInput()/close() so a fresh summon always starts re-centered.
    property var _frozenTop: null

    function _freezeTop() {
        if (root._frozenTop === null && root._screen)
            root._frozenTop = Math.round((root._screen.height - root.implicitHeight) / 2);
    }

    function _releaseTopFreeze() {
        root._frozenTop = null;
    }

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }

    readonly property string _selectionPath: root._stateDir + "/menu-selection.txt"

    // Write-only: select()/input() answers land here as `{token, value}` /
    // `{token, cancelled: true}` JSON. Every write goes through a Process
    // (`printf '%s' "$content" > "$path"`), never FileView.setText() —
    // ThemeEngine.qml documents FileView silently skipping the write *and*
    // the saved() signal when the new text is byte-identical to what it has
    // cached, which a repeated identical answer hits every time, and which a
    // caller-side truncate can't work around either (FileView compares
    // against its own cached text, not what's actually on disk). Callers
    // poll/read the file themselves — see MenuIpc.qml's header comment for
    // the full contract.
    function _writeSelectionFile(content) {
        var proc = _selectionFileProcComponent.createObject(root, {});
        proc.command = ["sh", "-c", 'printf \'%s\' "$2" > "$1"', "sh", root._selectionPath, content];
        proc.running = true;
    }

    // Deletes whatever's currently on disk. Used to invalidate the channel
    // before a brand-new select()/input() request's UI opens (see
    // _beginSelectionRequest below).
    function _clearSelectionFile() {
        var proc = _selectionFileProcComponent.createObject(root, {});
        proc.command = ["rm", "-f", root._selectionPath];
        proc.running = true;
    }

    Component {
        id: _selectionFileProcComponent

        Process {
            onExited: exitCode => {
                if (exitCode !== 0)
                    console.warn("Menu: selection-file write failed, code", exitCode);
                destroy();
            }
        }
    }

    function _writeSelection(payload) {
        root._writeSelectionFile(JSON.stringify(payload));
        root.selectionResolved(payload.token, payload.value !== undefined ? payload.value : null, !!payload.cancelled);
    }

    // Leaving select/input mode without the caller ever getting an answer
    // (a fresh open()/openSelect()/openInput() supersedes it, or the window
    // is closed) must still resolve that caller's poll loop — write the
    // cancel record before switching back to "menu". A no-op once already
    // back in "menu" mode, so close() and _completeSelect()/_submitInput()
    // (which set _mode = "menu" themselves before calling close()) never
    // double-write.
    function _abandonPendingSelect() {
        if (root._mode !== "menu") {
            root._writeSelection({ token: root._selectToken, cancelled: true });
            root._mode = "menu";
        }
    }

    // Prepares the selection file for a brand-new select()/input() request,
    // before that request's UI ever opens. Exactly one write happens
    // either way: if another request was still pending, _abandonPendingSelect
    // above already overwrote the file with that request's own cancel
    // record — invalidating it for free — so nothing else is done; otherwise
    // the file may still hold an already-resolved answer from an earlier,
    // now-finished request (the README's own tok1/tok2 examples reuse a
    // stable token across invocations, with no requirement that tokens be
    // unique per run), so it's deleted outright. Deliberately not folded
    // into _abandonPendingSelect itself — that function also runs from
    // open()/close(), including right after _completeSelect() writes a real
    // answer, where deleting the file would race the write just made.
    function _beginSelectionRequest() {
        var hadPending = root._mode !== "menu";
        root._abandonPendingSelect();
        if (!hadPending)
            root._clearSelectionFile();
    }

    function open(route) {
        root._abandonPendingSelect();
        root._releaseTopFreeze();
        // Fresh session: last session's condition results must not leak
        // into this one (a `when`/`checked` shell command can change
        // between opens — bluetooth power, mode toggle, device presence).
        root._condResults = {};
        root._checkedResults = {};
        clipsshAliasFile.reload();
        // A ":"-led route is a search prefill, not a node id: `menu summon
        // ':nix hello'` opens root with the trigger query already typed
        // (onTextChanged side effects included, so the debounced search
        // arms), giving compositor keybinds — and the smoke rig's toast
        // assertion — a direct path into the trigger surfaces without
        // keyboard delivery. No node id or alias starts with ":".
        var prefill = (route && route.indexOf(":") === 0) ? route : "";
        var target = null;
        var resolved = (route && prefill === "") ? root._resolveRoute(route) : null;
        var node = resolved ? root._nodes[resolved] : null;
        if (node) {
            if (node.kind === "submenu" || node.kind === "provider")
                target = node.id;
            else if (node.kind === "link")
                target = (node.target && root._nodes[node.target]) ? node.target : node.id;
        }
        root._enterLevel(target);
        if (prefill !== "")
            searchInput.text = prefill;
        root.isOpen = true;
        Qt.callLater(function () { searchInput.forceActiveFocus(); });
    }

    function openSelect(prompt, options, token) {
        root._beginSelectionRequest();
        root._releaseTopFreeze();
        root._mode = "select";
        root._selectPrompt = prompt;
        root._selectOptions = options;
        root._selectToken = token;
        root._cursorIndex = 0;
        root._confirmPendingId = "";
        searchInput.text = "";
        root.isOpen = true;
        Qt.callLater(function () { searchInput.forceActiveFocus(); });
    }

    function openInput(prompt, token) {
        root._beginSelectionRequest();
        root._releaseTopFreeze();
        root._mode = "input";
        root._selectPrompt = prompt;
        root._selectOptions = [];
        root._selectToken = token;
        root._cursorIndex = 0;
        root._confirmPendingId = "";
        searchInput.text = "";
        root.isOpen = true;
        Qt.callLater(function () { searchInput.forceActiveFocus(); });
    }

    function close() {
        root._abandonPendingSelect();
        root.isOpen = false;
        root._confirmPendingId = "";
        root._releaseTopFreeze();
        // The next summon maps the card wherever it centers, possibly under a
        // pointer that never moved: a sample left over from this session would
        // read that as a move.
        pointerGate.reset();
    }

    // Force an immediate re-read of default+user jsonc — Config's settings
    // watch is already live/reactive (_defaultObj recomputes on its own), so
    // this is mainly a manual fallback for an editor save that an fs watcher
    // missed (atomic-save tools can swap the inode).
    function refresh() {
        defaultMenuFile.reload();
        userMenuFile.reload();
        root._evalConditions();
    }

    function _completeSelect(value) {
        root._writeSelection({ token: root._selectToken, value: value });
        root._mode = "menu";
        root.close();
    }

    function _submitInput() {
        root._completeSelect(searchInput.text);
    }

    // Emoji instant paste (M13 Task 6): an activated row carrying `typeText`
    // (Providers.emojiRows) closes the menu like any action, then auto-types
    // the char into whatever window focus returned to. The wtype spawn is
    // gated on the window's actual visible flip plus a short settle — typing
    // while this keyboard-exclusive surface still holds focus would land the
    // char in the menu's own search field. wtype missing from PATH (the sh
    // wrapper's exit 127) or a compositor without the virtual-keyboard
    // protocol degrade to the copy that already ran: one warning, no error
    // surface. Re-opening before the settle fires drops the pending char
    // (onVisibleChanged below) — better untyped than typed at the menu.
    property string _pendingTypeText: ""

    onVisibleChanged: {
        if (visible) {
            typeSettleTimer.stop();
            root._pendingTypeText = "";
        } else if (root._pendingTypeText !== "") {
            typeSettleTimer.restart();
        }
    }

    Timer {
        id: typeSettleTimer
        interval: 150
        onTriggered: {
            // No `--` guard needed: no emoji starts with ASCII `-` (keycap
            // sequences start with `#`/`*`/digits), and the list form keeps
            // the char out of any shell interpolation.
            typeProc.command = ["sh", "-c", 'command -v wtype >/dev/null 2>&1 || exit 127; exec wtype "$1"', "sh", root._pendingTypeText];
            root._pendingTypeText = "";
            typeProc.running = true;
        }
    }

    Process {
        id: typeProc
        onExited: exitCode => {
            if (exitCode === 127)
                console.warn("Menu: wtype not on PATH, emoji copied but not typed");
            else if (exitCode !== 0)
                console.warn("Menu: wtype failed (exit " + exitCode + "), emoji copied but not typed");
        }
    }

    // Launch feedback for app rows. DesktopEntry.execute() is
    // fire-and-forget — it hands the entry's Exec line off and reports
    // nothing back — so the only truthful confirmation a launch can ever
    // get is the app's own window turning up. CompositorService.windows is
    // the live toplevel list on both backends, so this watches instead of
    // claiming: baseline the window count (and the focused window id) the
    // moment Enter lands, and if something new arrives within
    // `_launchGraceMs`, THE WINDOW is the feedback and no toast fires at
    // all. omarchy's AppLibrary.qml (launchSerial/launchToplevelCount/
    // launchActiveToplevel, and its note about the OSD outliving the launch
    // that opened it) takes the same position for the same reason. Only a
    // grace period that passes with nothing new gets a toast, and it says
    // exactly what is known: LAUNCHING, this app, nothing on screen yet.
    //
    // Success is never claimed, and neither is failure: a slow cold start,
    // a second instance handing its argv to an already-open window, and an
    // Exec line that died immediately are indistinguishable from out here,
    // so one honest in-progress wording covers all three. The one case that
    // fires immediately is a backend that isn't connected
    // (CompositorService.available false, e.g. an unrecognized compositor):
    // there is nothing to observe at any point, so waiting out the grace
    // period would only delay the same sentence.
    //
    // One watch at a time — a second launch inside the grace period
    // supersedes the first, so a burst of Enters can't stack up toasts.
    readonly property int _launchGraceMs: 2000
    property string _launchWatchLabel: ""
    property int _launchBaselineWindows: 0
    property string _launchBaselineFocusedId: ""

    function _beginLaunchWatch(label) {
        if (!CompositorService.available) {
            NotificationService.notify("LAUNCHING", label);
            return;
        }
        root._launchWatchLabel = label;
        root._launchBaselineWindows = (CompositorService.windows || []).length;
        root._launchBaselineFocusedId = CompositorService.focusedWindowId;
        launchGraceTimer.restart();
    }

    Timer {
        id: launchGraceTimer
        interval: root._launchGraceMs
        onTriggered: {
            var label = root._launchWatchLabel;
            root._launchWatchLabel = "";
            if (label === "")
                return;
            // A focus move is evidence alongside the count: an app that
            // raised an already-open window of its own never changes the
            // total. Either reading can also be the user's own doing, which
            // costs at worst one toast NOT shown — never a false claim.
            if ((CompositorService.windows || []).length > root._launchBaselineWindows
                || CompositorService.focusedWindowId !== root._launchBaselineFocusedId)
                return;
            NotificationService.notify("LAUNCHING", label);
        }
    }

    // The smoke rig's stand-in for Enter on the row at `index`
    // (PickerIpc.choose's rationale: real keyboard delivery into an
    // exclusive-focus layer surface isn't provable headlessly). Same path a
    // real Enter takes.
    function activate(index) {
        if (!root.isOpen)
            return false;
        root._activateRow(index);
        return true;
    }

    // Debug-only: ranks `q` against the live tree without requiring the
    // surface to be open — backs the `debug query` IPC hook used to verify
    // the apps provider + fuzzy filtering where keyboard injection isn't
    // available (nested test sessions).
    function query(q) {
        // Same ":e" narrowing as _displayRows, so the smoke rig's `debug
        // query ':e thumbs'` proves the trigger and the vendored dataset
        // without keyboard input; icon carries the emoji char itself.
        var emojiQuery = Providers.emojiTriggerQuery(q);
        if (emojiQuery !== null) {
            return Providers.emojiRows(root._emojiList, emojiQuery).map(function (n) {
                return { id: n.id, label: n.label, icon: n.icon, kind: n.kind };
            });
        }
        // ":nix" narrows the same way, but the search is async: the first
        // call arms the debounce and returns the SEARCHING note row — the
        // smoke rig calls twice, reading the cached end state (result rows,
        // NO RESULTS, SEARCH FAILED) on the second pass.
        var nixQuery = Providers.nixTriggerQuery(q);
        if (nixQuery !== null) {
            root._requestNixSearch(nixQuery);
            return root._nixRowsFor(nixQuery).map(function (n) {
                return { id: n.id, label: n.label, desc: n.desc || "", kind: n.kind };
            });
        }
        root._evalConditions();
        // iconSource rides along so the smoke rig can assert an app row's
        // themed icon resolved (or honestly didn't) without a screenshot.
        var rows = Search.rank(root._nodes, q, root._condResults).map(function (n) {
            return { id: n.id, label: n.label, kind: n.kind, iconSource: n.iconSource || "" };
        });
        // Same CALC prepend as _displayRows' ranked branch, so the smoke
        // rig's `debug query "2+2*3"` proves the row without keyboard input.
        var calcRow = Calc.resultNode(q);
        if (calcRow)
            rows.unshift({ id: calcRow.id, label: calcRow.label, kind: calcRow.kind });
        return rows;
    }

    function _resolveRoute(route) {
        if (root._nodes[route]) return route;
        var ids = Object.keys(root._nodes);
        for (var i = 0; i < ids.length; i++) {
            var n = root._nodes[ids[i]];
            if ((n.aliases || []).indexOf(route) >= 0) return n.id;
        }
        return null;
    }

    function _enterLevel(id) {
        root.currentNodeId = id;
        root._cursorIndex = 0;
        root._confirmPendingId = "";
        searchInput.text = "";
        // A whole new row set arrives under an unmoved pointer, in or out.
        pointerGate.reset();
        root._evalConditions();
        // Only a real submenu move (drilling in via _activateRow, popping
        // via _pop) freezes the card's top — open()'s own initial level
        // entry runs before isOpen flips true, so it's exempt.
        if (root.isOpen)
            root._freezeTop();
    }

    function _pop() {
        if (root.currentNodeId === null) {
            root.close();
            return;
        }
        root._enterLevel(root._nodes[root.currentNodeId].parentId);
    }

    // Hover owns the cursor only while the pointer is the thing that moved.
    // Filtering re-renders the row list under a parked pointer on every
    // keystroke, and Qt hands the row that slid underneath a hover move
    // indistinguishable from a real one — which used to yank the keyboard
    // cursor to wherever the mouse happened to be sitting. Every keyboard
    // path below re-arms the gate; the first genuine pointer movement takes
    // the cursor straight back.
    PointerMoveGate {
        id: pointerGate
    }

    function _moveCursor(delta) {
        var n = root._displayRows.length;
        if (n === 0) return;
        root._cursorIndex = (root._cursorIndex + delta + n) % n;
        root._confirmPendingId = "";
        pointerGate.reset();
    }

    function _setCursor(index) {
        if (index === root._cursorIndex) return;
        root._cursorIndex = index;
        root._confirmPendingId = "";
    }

    // A click IS the pointer acting, so the level it opens hands the cursor to
    // whatever row lands under the (still parked) pointer: re-arm one
    // stationary sample after _activateRow's own level change has reset the
    // gate. Only the row delegate's own MouseArea takes this path — activate()
    // over IPC stays keyboard-shaped.
    function _activateFromPointer(index) {
        root._activateRow(index);
        pointerGate.allowStationarySample();
    }

    function _activateRow(index) {
        var rows = root._displayRows;
        if (index < 0 || index >= rows.length) return;
        var node = rows[index];
        if (node.kind === "option") {
            root._completeSelect(node.label);
            return;
        }
        if (node.kind === "action") {
            if (node.confirm === true && root._confirmPendingId !== node.id) {
                root._confirmPendingId = node.id;
                return;
            }
            root._runAction(node.action);
            // Launch acknowledgment (nix rows): the spawned terminal can be
            // seconds from mapping, so rows carrying notifySummary get a
            // shell-local toast the moment Enter lands.
            if (node.notifySummary)
                NotificationService.notify(node.notifySummary, node.notifyBody || "");
            if (node.typeText)
                root._pendingTypeText = node.typeText;
            root.close();
            return;
        }
        if (node.kind === "app") {
            // Baseline first: nothing can map a window inside this same JS
            // block, so the count _beginLaunchWatch reads is genuinely the
            // "before". execute() stays exactly as it was — the entry's own
            // Exec field codes and quoting only survive that path (see
            // providers.js's header), so the feedback wraps it rather than
            // routing around it.
            root._beginLaunchWatch(node.label);
            node._entry.execute();
            Core.State.setAppLaunches(Frecency.record(Core.State.appLaunches, node._entry.id, Date.now()));
            root.close();
            return;
        }
        if (node.kind === "submenu" || node.kind === "provider") {
            root._enterLevel(node.id);
            return;
        }
        if (node.kind === "link") {
            root._enterLevel((node.target && root._nodes[node.target]) ? node.target : node.id);
        }
    }

    // "@ipc:<name>" actions (see default-menu.jsonc's header comment)
    // dispatch in-process instead of spawning a shell command — needed for
    // anything that must run in the shell's own process, like toggling
    // Core.State directly.
    function _runAction(action) {
        if (action.indexOf("@ipc:") === 0) {
            root._dispatchInternal(action.slice(5));
            return;
        }
        CompositorService.spawn(["sh", "-c", action]);
    }

    function _dispatchInternal(name) {
        switch (name) {
        case "theme.toggleMode":
            Core.State.toggleMode();
            break;
        case "notifications.showHistory":
            if (root.center) {
                if (root.center.isOpen)
                    root.center.close();
                else
                    root.center.open();
            }
            break;
        default:
            console.warn("Menu: unknown internal action:", name);
        }
    }

    // Shell-condition batch: `when`/`checked` for EVERY node in the tree,
    // not just the current level — whole-tree search (see _displayRows) can
    // surface a node whose level the user hasn't descended into yet, and a
    // submenu with an unevaluated-when child self-prunes to invisible
    // (Model.visibleChildren), which would make that child undescendable and
    // its own condition permanently unevaluated. Runs once per open()
    // (open() clears both result caches first) and again on every
    // _enterLevel(), where the `undefined` guards make repeat calls within
    // the same session cheap no-ops. Never per-keystroke — search filters
    // purely against whatever's already cached. Results are merged into
    // fresh objects so QML's var-property change detection fires.
    function _evalConditions() {
        Object.keys(root._nodes).forEach(function (id) {
            var n = root._nodes[id];
            if (n.when !== undefined && root._condResults[n.id] === undefined)
                root._runCondition(n.id, n.when, "when");
            if (n.checked !== undefined && root._checkedResults[n.id] === undefined)
                root._runCondition(n.id, n.checked, "checked");
        });
    }

    function _runCondition(nodeId, cond, kind) {
        var proc = _condProcComponent.createObject(root, { _nodeId: nodeId, _kind: kind });
        proc.command = ["sh", "-c", cond];
        proc.running = true;
    }

    Component {
        id: _condProcComponent

        Process {
            property string _nodeId
            property string _kind
            onExited: exitCode => {
                var id = _nodeId;
                var ok = exitCode === 0;
                var isWhen = _kind === "when";
                destroy();
                var merged = {};
                var source = isWhen ? root._condResults : root._checkedResults;
                for (var k in source) merged[k] = source[k];
                merged[id] = ok;
                if (isWhen) root._condResults = merged;
                else root._checkedResults = merged;
            }
        }
    }

    Component.onCompleted: {
        if (Quickshell.env("FORMALSHELL_SMOKE_OPEN_MENU") === "1")
            root.open();
    }

    screen: root._screen
    // Held visible through the exit fade (DESIGN.md §4): close() drops
    // isOpen, card's opacity Behavior runs to 0, then the window unmaps.
    // Keyboard exclusivity releases on isOpen itself, so nothing types into
    // a fading-out menu — and the emoji typeText settle timer still keys
    // off the real visible flip below, exactly as before, just one exit
    // fade later. The window is transparent so the fade covers the whole
    // card; card paints its own background.
    visible: root.isOpen || card.opacity > 0
    color: "transparent"
    implicitWidth: Core.Theme.space.popupWidthMenu
    implicitHeight: root._chrome + searchCell.height + root._rowsAreaHeight

    WlrLayershell.namespace: "formalshell:menu"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; left: true }
    margins {
        left: root._screen ? Math.round((root._screen.width - root.implicitWidth) / 2) : 0
        // Frozen once a session's first filter keystroke/submenu move
        // fires (_freezeTop): every row-count change from there on grows
        // or shrinks the card downward instead of re-centering it.
        top: root._frozenTop !== null ? root._frozenTop : (root._screen ? Math.round((root._screen.height - root.implicitHeight) / 2) : 0)
    }

    // Enter/exit (DESIGN.md §4): the whole card fades and slides down into
    // its centered spot, one animated scalar so a resummon mid-exit
    // reverses in place.
    Item {
        id: card
        anchors.fill: parent
        opacity: root.isOpen ? 1 : 0
        transform: Translate { y: (card.opacity - 1) * Core.Theme.motion.slide }

        Behavior on opacity {
            NumberAnimation { duration: Core.Theme.motion.standard; easing.type: Core.Theme.motion.easing }
        }

        Rectangle {
            anchors.fill: parent
            color: Core.Theme.color.background
        }

        // The card's own border ring (DESIGN.md's omarchy card chrome: "a single
        // bordered rectangle") — explicit on all four sides, with the
        // popupPadding gutter below insetting content uniformly. The search
        // field and result rows still close their own bottom+right per Cell's
        // shared-rule contract (needed for the divider between adjacent rows);
        // the eraser rectangles further down paint over just the trailing
        // hairline that would otherwise double these two rules.
        Rectangle {
            id: topRule
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Core.Theme.borderWidth
            color: Core.Theme.color.rule
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Core.Theme.borderWidth
            color: Core.Theme.color.rule
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: Core.Theme.borderWidth
            color: Core.Theme.color.rule
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Core.Theme.borderWidth
            color: Core.Theme.color.rule
        }

        Cell {
            id: searchCell
            anchors.top: topRule.bottom
            anchors.topMargin: Core.Theme.space.popupPadding
            anchors.left: parent.left
            anchors.leftMargin: Core.Theme.borderWidth + Core.Theme.space.popupPadding
            width: root._contentWidth
            height: searchColumn.implicitHeight + Core.Theme.space.sm * 2 + Core.Theme.borderWidth

            Column {
                id: searchColumn
                width: parent.width
                spacing: Core.Theme.space.xxs

                MetaLabel {
                    text: root.breadcrumb
                }

                TextInput {
                    id: searchInput
                    width: searchColumn.width
                    color: Core.Theme.color.foreground
                    font.family: Core.Theme.fontFamily
                    font.pixelSize: Core.Theme.fontSize.body
                    focus: true
                    selectByMouse: true
                    cursorVisible: true

                    onTextChanged: {
                        root._cursorIndex = 0;
                        root._confirmPendingId = "";
                        // Typing re-ranks the rows under a pointer that hasn't
                        // moved — the churn the gate exists for.
                        pointerGate.reset();
                        // Real filter keystrokes freeze the card's top the
                        // same as a submenu move; open()'s own prefill/reset
                        // writes land before isOpen flips true, so they're
                        // exempt (see _enterLevel's matching guard).
                        if (root.isOpen)
                            root._freezeTop();
                        // Arm the debounced nix search from the event, never
                        // from the _displayRows binding (side effect).
                        if (root._mode === "menu") {
                            var nixQuery = Providers.nixTriggerQuery(searchInput.text);
                            if (nixQuery === null && root.currentNodeId === "nix")
                                nixQuery = searchInput.text;
                            if (nixQuery !== null)
                                root._requestNixSearch(nixQuery);
                        }
                    }

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Up:
                            root._moveCursor(-1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Down:
                            root._moveCursor(1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            if (root._mode === "input")
                                root._submitInput();
                            else
                                root._activateRow(root._cursorIndex);
                            event.accepted = true;
                            break;
                        case Qt.Key_Escape:
                            // select/input have no tree level to pop out of —
                            // Escape just cancels the request and closes (close()
                            // writes the {cancelled:true} record via
                            // _abandonPendingSelect()).
                            if (root._mode !== "menu")
                                root.close();
                            else
                                root._pop();
                            event.accepted = true;
                            break;
                        case Qt.Key_Backspace:
                            if (root._mode === "menu" && searchInput.text.length === 0) {
                                root._pop();
                                event.accepted = true;
                            }
                            break;
                        }
                    }
                }
            }
        }

        ListView {
            id: rowsView
            anchors.top: searchCell.bottom
            anchors.left: parent.left
            anchors.leftMargin: Core.Theme.borderWidth + Core.Theme.space.popupPadding
            width: root._contentWidth
            height: root._rowsAreaHeight
            clip: true
            model: root._displayRows
            currentIndex: root._cursorIndex

            delegate: MenuRow {
                current: root._cursorIndex === index
                checkedState: node.checked !== undefined && root._checkedResults[node.id] === true
                confirming: root._confirmPendingId === node.id

                onActivate: root._activateFromPointer(index)
                onHoverMoved: (source, x, y) => {
                    if (pointerGate.moved(source, x, y))
                        root._setCursor(index);
                }
            }
        }

        // Erases the trailing hairline searchCell and every row draw along
        // their own right edge (Cell's shared-rule contract) — without this,
        // that continuous line and the frame's own right rule above would read
        // as two parallel borders `popupPadding` apart.
        Rectangle {
            anchors.top: searchCell.top
            anchors.right: rowsView.right
            anchors.bottom: rowsView.bottom
            width: Core.Theme.borderWidth
            color: Core.Theme.color.background
        }

        // Same erasure for the bottom: the last row's own bottom rule sits
        // flush with rowsView's own bottom edge whenever the rows fit without
        // scrolling, which would otherwise double the frame's own bottom rule.
        Rectangle {
            anchors.left: rowsView.left
            anchors.right: rowsView.right
            anchors.bottom: rowsView.bottom
            height: Core.Theme.borderWidth
            color: Core.Theme.color.background
        }

        // Dog-ear fold mark (DESIGN.md §2 item 7).
        DogEar {}
    }

    // Multi-monitor dismiss (M16 Task 7): a click on another screen closes
    // the menu exactly like Escape does.
    DismissTwins {
        active: root.isOpen
        ownScreen: root.screen
        onDismissed: root.close()
    }
}
