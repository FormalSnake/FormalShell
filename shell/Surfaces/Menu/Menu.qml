import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import qs.Core as Core
import qs.Compositor
import qs.Components
import qs.Services
import qs.Notifications
import qs.Reminders
import "../../Menu/model.js" as Model
import "../../Menu/search.js" as Search
import "../../Menu/providers.js" as Providers
import "../../Menu/calc.js" as Calc
import "../../Menu/frecency.js" as Frecency
import "../../Menu/toggles.js" as Toggles
import "../../Menu/actions.js" as Actions
import "../../Menu/appviews.js" as AppViews
import "../../Compositor/keybinds.js" as Keybinds
import "../../Compositor/appmatch.js" as AppMatch

// The unified menu, drawn as shadcn's Command palette (DESIGN.md §3
// Launcher): a single keyboard-exclusive top-layer window covering the
// focused output, carrying a plain black scrim with the card sitting at 30%
// of the output height on top of it. Top of the card is the input row (a
// search icon, the field, a rule under it), then the breadcrumb chips, then
// rows that are either search.rank() matches (query non-empty) or
// model.visibleChildren() of the current level (query empty), then the
// footer hint line. Whole-tree search, cursor wraps,
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

    // "menu" (tree navigation) | "select" | "input", the dmenu-replacement
    // modes summoned via MenuIpc's select()/input(). Both repurpose the same
    // window/search field; _displayRows, breadcrumb and key handling branch
    // on this. _abandonPendingSelect() is what resets it back to "menu".
    property string _mode: "menu"
    property string _selectPrompt: ""
    property var _selectOptions: []
    property string _selectToken: ""

    // Fires whenever a select()/input() request resolves (submitted value or
    // cancelled), the same event external callers poll menu-selection.txt
    // for (see MenuIpc.qml's header comment), exposed as a signal so
    // in-process callers (the Calendar panel's life-progress easter egg,
    // M6 Task 4) don't need a FileView of their own.
    signal selectionResolved(string token, var value, bool cancelled)

    property string _defaultMenuText: ""
    property string _userMenuText: ""

    // Set from shell.qml, the single Center instance, needed for
    // "@ipc:notifications.showHistory" (see _dispatchInternal below).
    property var center: null

    readonly property string _xdgConfigDir: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string _configDir: root._xdgConfigDir + "/formalshell"

    FileView {
        id: defaultMenuFile
        path: Quickshell.shellPath("Menu/default-menu.jsonc")
        // default-menu.jsonc ships inside the package, so this load only
        // ever races startup once, but Component.onCompleted's auto-open
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

    // Vendored emoji dataset (M12 Task 6), ships inside the package like
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
    // latest requested query, anything else is dropped and the search
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
    // cache), or the cached end state, result rows, NO RESULTS, SEARCH
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

    // ~/.config/formalshell/menu.jsonc, the per-key user overlay (plan-wide
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

    // ~/.clipssh/aliases, clipssh's own `name=user@host` store, optional
    // like menu.jsonc but with none of its retry machinery: open() reloads
    // it every summon, so an alias added mid-session (even before the file
    // first existed) shows on the next open without a watch ever having
    // attached. Absence just means zero aliases, clipsshRows' own NO
    // ALIASES note row, never a warning.
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

    // Compositor keybinds for the menu's keybinds route: `hyprctl binds`,
    // already expanded across submaps and sourced files, so nothing here
    // reads a config file or walks a lookup chain. The plain table, not `-j`:
    // see parseHyprlandBinds for what Hyprland 0.56.0's JSON encoder does to
    // that reply.
    property string _keybindsText: ""
    property bool _keybindsResolved: false
    property bool _keybindsFailed: false

    Process {
        id: hyprBindsProc
        command: ["hyprctl", "binds"]

        stdout: StdioCollector {
            id: hyprBindsCollector
        }
        onExited: exitCode => {
            root._keybindsFailed = exitCode !== 0;
            root._keybindsText = exitCode === 0 ? hyprBindsCollector.text : "";
            root._keybindsResolved = true;
        }
    }

    function _refreshKeybinds() {
        if (!hyprBindsProc.running)
            hyprBindsProc.running = true;
    }

    // Every end state of the keybinds route resolves here, the same
    // one-function shape _nixRowsFor above uses. No SEARCHING equivalent:
    // the load is a sub-100ms hyprctl, so the one empty frame before it lands
    // has nothing to explain.
    function _keybindRowsFor(q) {
        if (!root._keybindsResolved) return [];
        if (root._keybindsFailed) return [Keybinds.failedRow()];
        var binds = Keybinds.parseHyprlandBinds(root._keybindsText);
        if (binds.length === 0) return [Keybinds.noBindsRow()];
        return Keybinds.rows(binds, q);
    }

    // --- Wallpaper / image picker (M23) ---------------------------------
    //
    // The picker used to be a Panel popout of its own
    // (Surfaces/Picker/ImagePicker.qml, now deleted). It is a menu ROUTE:
    // "wallpaper" is an ordinary provider node in default-menu.jsonc, its
    // level renders as a grid instead of rows, and its cells are ordinary
    // _displayRows entries (Providers.imageRows), so the cursor, the
    // pointer gate, `activate(index)` over IPC, and every close path are
    // the menu's own rather than a second implementation of each.
    //
    // Two modes, both driving the same grid, unchanged from the panel:
    // - "wallpaper" (PickerIpc's summon(), the WALLPAPER menu row, `menu
    //   summon wallpaper`): scans picker.directory from settings.json;
    //   choosing calls Core.State.setWallpaper(), the exact call
    //   WallpaperIpc's set() makes, so ThemeEngine's retheme fires through
    //   one trigger path and is never duplicated here.
    // - "select" (openImageSelect(), PickerIpc's select(), spec §11's
    //   "doubles as a generic image-selector"): scans an arbitrary
    //   directory and writes {token, value: path} to picker-selection.txt
    //   instead of touching the wallpaper. Leaving the route without
    //   choosing resolves the caller's poll loop with {token,
    //   cancelled: true}, mirroring _abandonPendingSelect below. That file
    //   stays separate from the menu's own menu-selection.txt: they are two
    //   documented request channels with different callers, and merging
    //   them would let one answer the other's poll.
    //
    // A `Dark`/`Light` subdirectory pair inside the scanned directory splits
    // the listing in two (Providers.wallpaperVariants) and raises the Dark |
    // Light switcher above the grid; a directory with neither is listed flat
    // and shows no switcher, so nothing changes for a setup that doesn't use
    // them. The variant a route entry lands on is the theme's own current
    // mode, which is the one the owner is looking at.
    readonly property string _pickerRouteId: "wallpaper"
    readonly property bool _isPickerRoute: root._mode === "menu" && root.currentNodeId === root._pickerRouteId
    readonly property int pickerColumns: 4

    property string _pickerMode: "wallpaper"   // "wallpaper" | "select"
    property string _pickerDir: ""
    property string _pickerToken: ""
    // Everything the scan found, both variant subdirectories and the root
    // directory in one listing; the split below is what the grid reads.
    property var _pickerScanned: []
    property string _pickerVariant: "dark"     // "dark" | "light"
    readonly property var _pickerVariants: Providers.wallpaperVariants(root._pickerScanned, root._pickerDir)
    readonly property bool _pickerHasVariants: root._pickerVariants.hasVariants
    readonly property var _pickerImages: Providers.wallpaperListing(root._pickerVariants, root._pickerVariant)
    // Set by openImageSelect() so the level entry it triggers keeps that
    // caller's directory and token, every other way of reaching this level
    // (the menu row, `menu summon wallpaper`, `picker summon`) is a plain
    // wallpaper-mode open and resets both.
    property bool _pickerRequestPending: false

    // Quickshell has no directory-listing QML type (same rationale as
    // CalendarEventsService's own `find`-backed read), re-scanned on every
    // entry into the route, so a directory edited between opens is picked up.
    // Both variant subdirectories are named as starting points alongside the
    // directory itself: `find` reports a missing one on stderr (swallowed)
    // and carries on with the rest, so one invocation covers every layout,
    // and `-maxdepth 1` per starting point is what keeps an unrelated
    // subdirectory of wallpapers out of the listing. `sort -u` because a
    // case-insensitive filesystem answers both `Dark` and `dark` with the
    // same directory.
    function _scanPickerDir() {
        if (root._pickerDir === "") {
            root._pickerScanned = [];
            return;
        }
        pickerScanProc.command = ["sh", "-c",
            'find "$1" "$1/Dark" "$1/dark" "$1/Light" "$1/light" -maxdepth 1 -type f'
            + ' \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.bmp" \\)'
            + ' 2>/dev/null | sort -u',
            "sh", root._pickerDir];
        pickerScanProc.running = true;
    }

    Process {
        id: pickerScanProc

        stdout: StdioCollector {
            onStreamFinished: root._pickerScanned = text.split("\n").filter(function (l) { return l.length > 0; })
        }
    }

    function _enterPickerRoute() {
        if (!root._pickerRequestPending) {
            root._abandonPendingPicker();
            root._pickerMode = "wallpaper";
            root._pickerDir = Core.Config.get("picker.directory", "");
            root._pickerToken = "";
        }
        root._pickerRequestPending = false;
        // The variant the theme is currently in, every entry, a switch is a
        // deliberate act of browsing the other set, not a preference the
        // route carries over from last time.
        root._pickerVariant = Core.State.mode === "light" ? "light" : "dark";
        root._scanPickerDir();
    }

    // Dropping the listing destroys every decoded thumbnail with the grid
    // delegates that held them, the whole point of the old panel's close()
    // override (M16 Task 12), kept. Re-entering re-scans and re-decodes,
    // which is cheap; the decodes were the cost.
    function _leavePickerRoute() {
        root._abandonPendingPicker();
        root._pickerScanned = [];
    }

    // The Dark | Light switcher's one entry point: the segments, Tab, and
    // `picker variant` over IPC all land here. Same-variant calls are a
    // no-op rather than a failure, a caller asking for the variant already
    // showing got what it asked for.
    function setPickerVariant(variant) {
        if (!root.isOpen || !root._isPickerRoute || !root._pickerHasVariants)
            return false;
        var next = variant === "light" ? "light" : "dark";
        if (root._pickerVariant !== next) {
            root._pickerVariant = next;
            // The other variant is a different listing of a different length:
            // the old index would land on an unrelated image, or past the end.
            root._cursorIndex = 0;
            pointerGate.reset();
        }
        return true;
    }

    function _abandonPendingPicker() {
        if (root._pickerMode === "select" && root._pickerToken !== "") {
            root._writeSelectionFile(root._pickerSelectionPath, JSON.stringify({ token: root._pickerToken, cancelled: true }));
            root._pickerToken = "";
        }
    }

    // PickerIpc's summon(), the wallpaper-mode open. Everything it needs to
    // reset happens in _enterPickerRoute() off the level entry, so a menu row
    // and this call reach an identical state by construction.
    function openWallpaperPicker() {
        root.open(root._pickerRouteId);
    }

    function openImageSelect(directory, token) {
        root._abandonPendingPicker();
        root._pickerMode = "select";
        root._pickerDir = (directory && directory.length > 0) ? directory : Core.Config.get("picker.directory", "");
        root._pickerToken = token;
        root._pickerRequestPending = true;
        root.open(root._pickerRouteId);
    }

    // Callable over IPC (PickerIpc's choose()) as well as from Enter/click
    // on a cell, the one function that resolves a pick, so both paths stay
    // in sync by construction. Refuses a path outside the current listing
    // rather than trusting an arbitrary caller-supplied one.
    function chooseImage(path) {
        if (!root.isOpen || !root._isPickerRoute || root._pickerImages.indexOf(path) < 0)
            return false;
        if (root._pickerMode === "select") {
            root._writeSelectionFile(root._pickerSelectionPath, JSON.stringify({ token: root._pickerToken, value: path }));
            root._pickerToken = "";
        } else {
            Core.State.setWallpaper(path);
        }
        root.close();
        return true;
    }

    function pickerStatus() {
        return {
            open: root.isOpen && root._isPickerRoute,
            mode: root._pickerMode,
            directory: root._pickerDir,
            // The listing actually on screen, so this tracks the variant.
            count: root._pickerImages.length,
            variant: root._pickerHasVariants ? root._pickerVariant : "none",
            hasVariants: root._pickerHasVariants,
            darkCount: root._pickerVariants.dark.length,
            lightCount: root._pickerVariants.light.length,
            cursor: root._cursorIndex
        };
    }

    // --- Clipboard split-pane preview (M30) ------------------------------
    //
    // omarchy's clipboard history layout (owner: "copy omarchy's clipboard
    // history layout. It's way better."): a 50/50 split between the history
    // list and a full preview of the cursor row, reached without a second
    // surface, same card, search field, cursor and action bar as every
    // other level, the same "view swap over one level" precedent the
    // wallpaper grid already set. "share.history" qualifies too: it lists
    // the identical rows (Providers.clipboardProvider with mode: "share"),
    // so the split earns it for free rather than needing its own branch.
    readonly property bool _isSplitRoute: root._mode === "menu"
        && (root.currentNodeId === "clipboard" || root.currentNodeId === "share.history")

    // --- App-view routes (M38 plan decision D1) --------------------------
    //
    // The third view over the same level machinery, after the grid and the
    // split: a route registered in Menu/appviews.js renders one whole QML
    // component in place of the row list ("everything is accessible through
    // the main launcher ... it should open a full one in the launcher,
    // similar to raycast apps"). Deliberately a registry lookup rather than
    // a third hardcoded id like the two above, because the next app view
    // must cost one line of appviews.js and one file, not another branch
    // here.
    //
    // Everything else about the level is untouched: the breadcrumb, Escape,
    // backspace-on-empty and the `menu` IPC all key off currentNodeId, so
    // none of them needs to know a view is live.
    readonly property string _appViewSource: root._mode === "menu" ? AppViews.viewFor(root.currentNodeId) : ""
    readonly property bool _isAppView: root._appViewSource !== ""

    // Mirrors ClipboardService.items ONLY while the menu is actually open
    // (M17 review finding, M-polish batch item G, owner: low-end laptop),
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
        var capture = Providers.captureEntries(Quickshell.shellDir);
        // M38 Task 8: the "gpu.mode" fragment, present only when
        // supergfxctl is -- see gpuModeEntry's own header.
        var gpuMode = Providers.gpuModeEntry(Quickshell.shellDir, GpuService.gfxMode);
        // Live-while-open, unlike wallpaper/buttons above: its action
        // depends on the current newest clipboard entry, so
        // _liveClipboardItems rides this same binding for _defaultObj (and
        // _tree below) to recompute whenever it changes, but only while
        // that dependency is actually subscribed (see _liveClipboardItems'
        // own comment). Merged as a plain overwrite of the
        // "share.clipboard" key default-menu.jsonc already declares, so the
        // row keeps that declared position instead of jumping to the end.
        var shareClipboard = Providers.shareClipboardEntry(root._liveClipboardItems);
        var merged = {};
        Object.keys(parsed).forEach(function (k) { merged[k] = parsed[k]; });
        Object.keys(shareClipboard).forEach(function (k) { merged[k] = shareClipboard[k]; });
        Object.keys(capture).forEach(function (k) { merged[k] = capture[k]; });
        Object.keys(gpuMode).forEach(function (k) { merged[k] = gpuMode[k]; });
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
            return AppMatch.decorateAppRows(Providers.appsProvider(DesktopEntries.applications.values, function (name) {
                return Quickshell.iconPath(name, true);
            }, Core.State.appLaunches, Date.now()), CompositorService.windows || []);
        },
        clipboard: function () { return Providers.clipboardProvider(root._liveClipboardItems, "copy", Core.Config.get("clipboard.paste", true)); },
        shareHistory: function () { return Providers.clipboardProvider(root._liveClipboardItems, "share"); },
        clipssh: function () { return Providers.clipsshRows(Providers.clipsshAliases(root._clipsshAliasesText)); },
        // M38 Task 3 (launcher reachability sweep): both self-targeted the
        // same way apps/clipboard above are.
        panels: function () { return Providers.panelsProvider(Quickshell.shellDir); },
        tray: function () { return Providers.trayProvider(SystemTray.items.values, Quickshell.shellDir); },
        // M38 Task 8: card info rows, always present. Launching an app on
        // the discrete card is Shift+Enter on the app row itself
        // (_activateRowOnDiscreteGpu below), not a route mirroring the
        // whole app list a second time.
        gpu: function () { return Providers.gpuProvider(GpuService.cards); }
    })
    readonly property var _nodes: root._tree.nodes

    // True while the current level's own node carries an unsatisfied (or
    // not-yet-resolved) `when` gate, see _displayRows' own comment for why
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
        // The wallpaper route is the picker's grid (M23): route-local rows
        // built from the scanned directory and filtered by filename, never
        // whole-tree ranking, a wallpapers directory would drown a root
        // query exactly the way the emoji dataset would.
        if (root._isPickerRoute)
            return Providers.imageRows(root._pickerImages, q);
        // The clipboard/share-history route is route-local too (M30), for
        // the same reason the picker route above is: typing here narrows
        // history, it never falls through to whole-tree Search.rank or to
        // the trigger routes below (checked here, ahead of them, on
        // purpose, a ":e"/":nix"/":k"-prefixed clipboard entry is filter
        // text on this level, not a trigger).
        if (root._isSplitRoute) {
            var historyRows = Model.visibleChildren(root._nodes, root.currentNodeId, root._condResults);
            if (historyRows.length === 0)
                return [Providers.clipboardEmptyRow()];
            var matchedRows = Providers.clipboardSearch(historyRows, q);
            return matchedRows.length === 0 ? [Providers.clipboardNoMatchRow()] : matchedRows;
        }
        // The emoji route searches the vendored dataset exclusively (an
        // empty query browses its head, Providers.emojiSearch), and the
        // ":e " trigger narrows to the same rows from any level (M12
        // Task 6). Neither ever falls through to whole-tree ranking: 3,944
        // emoji in the tree would drown every root search.
        var emojiQuery = Providers.emojiTriggerQuery(q);
        var emojiPaste = Core.Config.get("clipboard.paste", true);
        if (root.currentNodeId === "emoji")
            return Providers.emojiRows(root._emojiList, emojiQuery !== null ? emojiQuery : q, emojiPaste);
        if (emojiQuery !== null)
            return Providers.emojiRows(root._emojiList, emojiQuery, emojiPaste);
        // The nix route/":nix" trigger works the same way, except the rows
        // come from the debounced-Process cache (see the state block above)
        // rather than a pure function over local data.
        var nixQuery = Providers.nixTriggerQuery(q);
        if (root.currentNodeId === "nix" || nixQuery !== null)
            return root._nixRowsFor(nixQuery !== null ? nixQuery : q);
        // The keybinds route is route-local for the same reason: its own
        // tiered search, never Search.rank, so a hundred-odd chords cannot
        // drown a root query.
        var keysQuery = Keybinds.triggerQuery(q);
        if (root.currentNodeId === "keybinds" || keysQuery !== null)
            return root._keybindRowsFor(keysQuery !== null ? keysQuery : q);
        if (q.length === 0) {
            // Route-summon when-gate guard (M17 review finding, item F):
            // `open(route)` resolves a node by id directly, bypassing the
            // parent-level isWhenVisible() filter that keeps a gated node
            // (e.g. "share" without localsend_app) from ever appearing as
            // a row in the first place, without this, landing on that
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
        // whole surface, whole-tree matches would just be root search noise
        // there. Parse failures are silent: calcRow is null, nothing renders.
        var calcRow = Calc.resultNode(q);
        if (root.currentNodeId === "calc")
            return calcRow ? [calcRow] : [];
        var ranked = Search.rank(root._nodes, q, root._condResults, root.currentNodeId);
        return calcRow ? [calcRow].concat(ranked) : ranked;
    }

    readonly property var _cursorNode: root._displayRows[root._cursorIndex] || null

    // Split-pane preview content (M30), derived from the cursor row: a
    // note row (clipboardEmptyRow/clipboardNoMatchRow) renders an empty
    // pane, an image row (thumbSource set) renders the full image, and
    // everything else renders the full text. Read only while
    // _isSplitRoute's own pane is visible, but cheap enough to leave bound
    // unconditionally rather than gating the bindings themselves.
    readonly property bool _previewIsNote: !!root._cursorNode && root._cursorNode.kind === "note"
    readonly property bool _previewIsImage: !!root._cursorNode && !root._previewIsNote && (root._cursorNode.thumbSource || "") !== ""
    readonly property bool _previewIsText: !!root._cursorNode && !root._previewIsNote && !root._previewIsImage
    // Two bands, since the type is a word and the capture time is a value
    // (spec "Type"): the label takes the sans section face, the time the
    // mono one.
    readonly property string _previewKind: root._previewIsNote || !root._cursorNode
        ? ""
        : (root._previewIsImage ? "Image" : "Text")
    readonly property string _previewTime: root._previewIsNote || !root._cursorNode
        ? ""
        : (root._cursorNode.time || "")

    // What the bottom action bar says right now (Menu/actions.js). Bound
    // rather than pushed, so it tracks the cursor, the mode and the pending
    // confirm without a single imperative update.
    //
    // An app view that declares `viewActions` fills the bar itself (the
    // seam below), because the row cursor those verbs describe does not
    // exist on such a route: the process view's Enter kills the process
    // under ITS own cursor, and a footer still offering the row list's
    // "Open" would be promising a key nothing answers.
    readonly property var _actionBar: root._appViewActions !== null ? root._appViewActions : Actions.actionBar({
        mode: root._mode,
        node: root._cursorNode,
        atRoot: root.currentNodeId === null,
        grid: root._isPickerRoute,
        pickerSelect: root._pickerMode === "select",
        // The variant Tab would switch TO, null wherever Tab does nothing.
        variantSwitch: root._isPickerRoute && root._pickerHasVariants
            ? (root._pickerVariant === "dark" ? "light" : "dark")
            : null,
        confirming: root._confirmPendingId !== "" && !!root._cursorNode
            && root._cursorNode.id === root._confirmPendingId,
        // Gates the Shift+Enter hint: on a one-card machine the accelerator
        // falls through to a plain Enter, so advertising it would name a
        // key that does nothing of its own.
        discreteGpu: GpuService.defaultDiscrete() !== null
    })

    // The path from the root to the current level, one chip per part
    // (M43 D2). Empty at the root, where the chip row is hidden outright:
    // the search field is already the whole surface there. The select and
    // input modes have no tree level, so they name themselves instead and
    // hand their prompt to the field's placeholder (D5).
    readonly property var breadcrumb: {
        if (root._mode === "select")
            return ["Select"];
        if (root._mode === "input")
            return ["Input"];
        var parts = [];
        var id = root.currentNodeId;
        while (id !== null && root._nodes[id]) {
            parts.unshift(root._nodes[id].label);
            id = root._nodes[id].parentId;
        }
        return parts;
    }

    readonly property bool _breadcrumbVisible: root.breadcrumb.length > 0

    // What the empty field says it is for. In select/input that is the
    // caller's own prompt, which is the whole of what those modes ask (D5).
    readonly property string _placeholder: root._mode === "menu" ? "Search" : root._selectPrompt

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }
    // 0.6 of the screen for a row list, which is already more rows than
    // anyone scans. An app view is a whole surface rather than a list, and
    // capping it at the row-list height left the system monitor's own GPU
    // section below the fold on a two-card machine, so it gets a taller
    // ceiling and still scrolls past it.
    // The output's own size, read off THIS WINDOW rather than off the
    // ShellScreen it sits on (M39 Task 6). The window covers the output
    // exactly, so its width/height are the same fact, except they are also
    // already in the window's own coordinate space, which a ShellScreen's are
    // not once two heads differ in size or scale. Reading the screen instead
    // laid the card out for whichever output was resolved rather than the one
    // it was drawn on (owner, live shell, 2026-08-19: "on multi monitor
    // setups it doesn't conform to the screen size of the smaller monitor").
    // The screen is still the fallback for the window's first moments, before
    // it has been given a size at all.
    readonly property real _outputWidth: root.width > 0 ? root.width : (root._screen ? root._screen.width : 0)
    readonly property real _outputHeight: root.height > 0 ? root.height : (root._screen ? root._screen.height : 0)

    readonly property real _maxTotalHeight: root._outputHeight > 0 ? root._outputHeight * (root._isAppView ? 0.82 : 0.6) : 400
    // `Card` insets its own slot by `panelPadding` on all four sides, so
    // every child below anchors straight to the slot's edges and this is
    // the width they get.
    readonly property real _contentWidth: root._cardWidth - Core.Theme.space.panelPadding * 2
    readonly property real _chrome: Core.Theme.space.panelPadding * 2
    // Everything above the view: the input row, the rule under it, and the
    // two optional bands (the breadcrumb chips, the picker's variant
    // switcher), each with the `rowGap` that precedes it when it is there
    // at all.
    readonly property real _headerHeight: searchRow.height + searchRule.height
        + (breadcrumbRow.height > 0 ? Core.Theme.space.rowGap + breadcrumbRow.height : 0)
        + (variantRow.height > 0 ? Core.Theme.space.rowGap + variantRow.height : 0)
    // Whichever view owns the level: the grid on the wallpaper route, the
    // loaded component on an app-view route, the row list everywhere else.
    // The idle ones are emptied or unloaded rather than merely hidden (see
    // their `model`/`source` bindings), so their contribution is 0. The
    // loader reports its item's own implicit height, which is what an app
    // view's content wants before this caps it, and the view scrolls
    // inside whatever it gets.
    readonly property real _viewContentHeight: root._isPickerRoute
        ? gridView.contentHeight
        : (root._isAppView ? appView.implicitHeight : rowsView.contentHeight)
    readonly property real _rowsAreaCap: Math.max(0, root._maxTotalHeight - root._chrome - root._headerHeight
        - Core.Theme.space.rowGap * 2 - actionBar.height)
    // Fixed height on the split route (M30, omarchy parity): the preview
    // pane needs to be genuinely useful, not sized to whatever row count a
    // filter happens to leave, so this route always takes the full cap
    // instead of shrinking to content height like every other level does.
    readonly property real _rowsAreaHeight: root._isSplitRoute ? root._rowsAreaCap : Math.min(root._viewContentHeight, root._rowsAreaCap)

    // How far the live view is scrolled, whichever of the three owns the
    // level. On `menu status` because a wheel notch is otherwise
    // unobservable from the rig: a screenshot shows different rows, but
    // nothing says the cursor stayed put rather than moved with them.
    readonly property real scrollTop: root._isPickerRoute
        ? gridView.contentY
        : (root._isAppView
            ? (root._appViewScroll ? root._appViewScroll.contentY : 0)
            : rowsView.contentY)

    // The card's top edge sits at 30% of the output height (spec
    // "Launcher"), which is where the eye already is and which leaves the
    // list room to grow downward without the card moving. It replaced a
    // centered card plus a per-keystroke top freeze: a fixed top does the
    // same job for free, because a row count that changes only ever moves
    // the bottom edge.
    readonly property real _topFraction: 0.3
    readonly property real _topInset: Core.Theme.space.panelPadding
    readonly property real _preferredTop: root._outputHeight * root._topFraction

    // Keeps the card fully on screen with a `panelPadding` margin whatever the
    // row count does to its height.
    function _clampTop(top) {
        if (root._outputHeight <= 0)
            return 0;
        var maxTop = root._outputHeight - root._cardHeight - root._topInset;
        // Taller than the screen can hold even with no margin at all: sit at
        // the inset rather than returning a negative top, which would push
        // the search field off the top edge. _maxTotalHeight caps the rows
        // area at 60% of the screen, so this is a guard, not a normal path.
        if (maxTop < root._topInset)
            return Math.round(root._topInset);
        return Math.round(Math.max(root._topInset, Math.min(top, maxTop)));
    }

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }

    readonly property string _selectionPath: root._stateDir + "/menu-selection.txt"
    readonly property string _pickerSelectionPath: root._stateDir + "/picker-selection.txt"

    // Write-only: select()/input() answers land here as `{token, value}` /
    // `{token, cancelled: true}` JSON. Every write goes through a Process
    // (`printf '%s' "$content" > "$path"`), never FileView.setText(),
    // ThemeEngine.qml documents FileView silently skipping the write *and*
    // the saved() signal when the new text is byte-identical to what it has
    // cached, which a repeated identical answer hits every time, and which a
    // caller-side truncate can't work around either (FileView compares
    // against its own cached text, not what's actually on disk). Callers
    // poll/read the file themselves, see MenuIpc.qml's header comment for
    // the full contract.
    function _writeSelectionFile(path, content) {
        var proc = _selectionFileProcComponent.createObject(root, {});
        proc.command = ["sh", "-c", 'printf \'%s\' "$2" > "$1"', "sh", path, content];
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
        root._writeSelectionFile(root._selectionPath, JSON.stringify(payload));
        root.selectionResolved(payload.token, payload.value !== undefined ? payload.value : null, !!payload.cancelled);
    }

    // Leaving select/input mode without the caller ever getting an answer
    // (a fresh open()/openSelect()/openInput() supersedes it, or the window
    // is closed) must still resolve that caller's poll loop, write the
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
    // record, invalidating it for free, so nothing else is done; otherwise
    // the file may still hold an already-resolved answer from an earlier,
    // now-finished request (the README's own tok1/tok2 examples reuse a
    // stable token across invocations, with no requirement that tokens be
    // unique per run), so it's deleted outright. Deliberately not folded
    // into _abandonPendingSelect itself, that function also runs from
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
        // Fresh session: last session's condition results must not leak
        // into this one (a `when`/`checked` shell command can change
        // between opens, bluetooth power, mode toggle, device presence).
        root._condResults = {};
        root._checkedResults = {};
        // "@state:" `checked` conditions are deliberately NOT cleared here:
        // they are never cached, resolving from _stateSnapshot on every
        // evaluation.
        clipsshAliasFile.reload();
        root._refreshKeybinds();
        // A ":"-led route is a search prefill, not a node id: `menu summon
        // ':nix hello'` opens root with the trigger query already typed
        // (onTextChanged side effects included, so the debounced search
        // arms), giving compositor keybinds, and the smoke rig's toast
        // assertion, a direct path into the trigger surfaces without
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
        root._leavePickerRoute();
        root.isOpen = false;
        root._confirmPendingId = "";
        // The next summon maps the card wherever it centers, possibly under a
        // pointer that never moved: a sample left over from this session would
        // read that as a move.
        pointerGate.reset();
    }

    // Force an immediate re-read of default+user jsonc, Config's settings
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

    // Instant paste: an activated row carrying `pasteAfter` (the clipboard
    // route's rows and the emoji route's, both gated on `clipboard.paste`)
    // closes the menu like any action, then synthesizes the configured paste
    // chord into whatever window focus returns to, on top of the copy that
    // already ran. One wtype spawn, gated on the window's actual visible flip
    // plus a short settle: synthesizing input while this keyboard-exclusive
    // surface still holds focus would land it in the menu's own search field.
    // That settle doubles as the write barrier, since the copy is exec'd at
    // Enter, a close animation ahead of the keystroke.
    //
    // wtype missing from PATH (the sh wrapper's exit 127) or a compositor
    // without the virtual-keyboard protocol degrade to the copy that already
    // ran: one warning, no error surface. Re-opening before the settle fires
    // drops whatever was pending (onVisibleChanged below), better nothing
    // than typed at the menu.
    property bool _pendingPaste: false

    onVisibleChanged: {
        if (visible) {
            typeSettleTimer.stop();
            root._pendingPaste = false;
        } else if (root._pendingPaste) {
            typeSettleTimer.restart();
        }
    }

    Timer {
        id: typeSettleTimer
        interval: 150
        onTriggered: {
            var paste = root._pendingPaste;
            root._pendingPaste = false;
            if (!paste)
                return;
            var chord = Core.Config.get("clipboard.pasteChord", "ctrl+v");
            var argv = Providers.pasteArgv(chord);
            if (!argv) {
                console.warn("Menu: clipboard.pasteChord is not a wtype chord:", chord, "- copied but not pasted");
                return;
            }
            typeProc.command = ["sh", "-c", 'command -v wtype >/dev/null 2>&1 || exit 127; exec wtype "$@"', "sh"].concat(argv);
            typeProc.running = true;
        }
    }

    Process {
        id: typeProc
        onExited: exitCode => {
            if (exitCode === 127)
                console.warn("Menu: wtype not on PATH, copied but not pasted");
            else if (exitCode !== 0)
                console.warn("Menu: wtype failed (exit " + exitCode + "), copied but not pasted");
        }
    }

    // Launch feedback for app rows. DesktopEntry.execute() is
    // fire-and-forget, it hands the entry's Exec line off and reports
    // nothing back, so the only truthful confirmation a launch can ever
    // get is the app's own window turning up. CompositorService.windows is
    // the live toplevel list, so this watches instead of
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
    // (CompositorService.available false, e.g. a session that is not
    // Hyprland):
    // there is nothing to observe at any point, so waiting out the grace
    // period would only delay the same sentence.
    //
    // One watch at a time, a second launch inside the grace period
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
            // costs at worst one toast NOT shown, never a false claim.
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
        // On an app view the row list is not what is on screen, so the same
        // call presses THAT view's own primary instead (the process route's
        // Enter): `viewActivate(index)` takes the view's cursor to `index`
        // first, exactly as arrowing onto the row and pressing Enter would.
        if (root._isAppView) {
            if (!appView.item || !appView.item.viewActivate)
                return false;
            return appView.item.viewActivate(index) === true;
        }
        root._activateRow(index);
        return true;
    }

    // The rig's stand-in for typing into the search field (`menu filter`).
    // Real keyboard delivery into an OnDemand-focus layer surface is not
    // provable headlessly, and on an app view the field IS the filter, so
    // this is the only way to verify a route's own narrowing.
    function setQuery(text) {
        if (!root.isOpen)
            return false;
        searchInput.text = text;
        return true;
    }

    // Debug-only: ranks `q` against the live tree without requiring the
    // surface to be open, backs the `debug query` IPC hook used to verify
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
        // call arms the debounce and returns the SEARCHING note row, the
        // smoke rig calls twice, reading the cached end state (result rows,
        // NO RESULTS, SEARCH FAILED) on the second pass.
        var nixQuery = Providers.nixTriggerQuery(q);
        if (nixQuery !== null) {
            root._requestNixSearch(nixQuery);
            return root._nixRowsFor(nixQuery).map(function (n) {
                return { id: n.id, label: n.label, desc: n.desc || "", kind: n.kind };
            });
        }
        // ":k" narrows the same way, so the smoke rig proves the route with
        // zero keyboard delivery: `debug query ':k spawn'`.
        var keysQuery = Keybinds.triggerQuery(q);
        if (keysQuery !== null) {
            root._refreshKeybinds();
            return root._keybindRowsFor(keysQuery).map(function (n) {
                return { id: n.id, label: n.label, desc: n.desc || "", kind: n.kind };
            });
        }
        root._evalConditions();
        // iconSource rides along so the smoke rig can assert an app row's
        // themed icon resolved (or honestly didn't) without a screenshot.
        var rows = Search.rank(root._nodes, q, root._condResults, root.currentNodeId).map(function (n) {
            return { id: n.id, label: n.label, kind: n.kind, iconSource: n.iconSource || "", checked: Toggles.checkedFor(n, root._stateSnapshot, root._checkedResults) };
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
        var leavingPicker = root.currentNodeId === root._pickerRouteId && id !== root._pickerRouteId;
        root.currentNodeId = id;
        root._cursorIndex = 0;
        root._confirmPendingId = "";
        searchInput.text = "";
        // A whole new row set arrives under an unmoved pointer, in or out.
        pointerGate.reset();
        if (leavingPicker)
            root._leavePickerRoute();
        if (id === root._pickerRouteId)
            root._enterPickerRoute();
        root._evalConditions();
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
    // indistinguishable from a real one, which used to yank the keyboard
    // cursor to wherever the mouse happened to be sitting. Every keyboard
    // path below re-arms the gate; the first genuine pointer movement takes
    // the cursor straight back.
    PointerMoveGate {
        id: pointerGate
    }

    // `delta` is ±1 for the row list and ±`pickerColumns` for the grid's
    // vertical moves, so the wrap has to survive a step larger than the row
    // count itself, the old `(i + delta + n) % n` only ever saw ±1 and
    // returns a negative index the moment |delta| > n.
    function _moveCursor(delta) {
        var n = root._displayRows.length;
        if (n === 0) return;
        var next = (root._cursorIndex + delta) % n;
        root._cursorIndex = next < 0 ? next + n : next;
        root._confirmPendingId = "";
        pointerGate.reset();
    }

    function _setCursor(index) {
        if (index === root._cursorIndex) return;
        root._cursorIndex = index;
        root._confirmPendingId = "";
    }

    // The app view's scroll seam, sibling of the `query` one below (D1): a
    // view that declares `scrollTarget` hands the launcher its own
    // Flickable and the keys below drive it, since there is no row cursor
    // to move on those routes. It is what keeps the action bar's ↑↓ MOVE
    // hint honest there, and what makes a view taller than the card's
    // height cap reachable at all. A view declaring none leaves the arrows
    // inert, exactly as before.
    readonly property var _appViewScroll: (root._isAppView && appView.item && appView.item.scrollTarget)
        ? appView.item.scrollTarget
        : null

    // The app view's action-bar seam (M39): a view that declares
    // `viewActions` hands the footer its own { primary, hints } in
    // Menu/actions.js's exact shape. A view declaring none keeps the row
    // list's bar, unchanged.
    readonly property var _appViewActions: (root._isAppView && appView.item && appView.item.viewActions)
        ? appView.item.viewActions
        : null

    // The app view's key seam (M39): a view that declares `viewKey(key,
    // modifiers)` is offered every key press BEFORE the menu's own handler
    // and returns true for the ones it consumed. That order is the point:
    // an app view with a cursor of its own has to claim ↑↓ and Enter, and
    // everything it does not claim (Escape, backspace-on-empty, every
    // printable character heading for the search field) still behaves
    // exactly as it does on every other route.
    function _appViewKey(key, modifiers) {
        if (!root._isAppView || !appView.item || !appView.item.viewKey)
            return false;
        return appView.item.viewKey(key, modifiers) === true;
    }

    function _scrollAppViewTo(y) {
        var flick = root._appViewScroll;
        if (!flick) return;
        flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), y));
    }

    function _scrollAppViewBy(delta) {
        if (root._appViewScroll)
            root._scrollAppViewTo(root._appViewScroll.contentY + delta);
    }

    // What the action bar says about the app view's overflow, empty on
    // every other route and on a view whose content already fits. It names
    // the direction that still has content, because the arrows are what the
    // reader presses.
    readonly property string _appViewScrollHint: {
        var flick = root._appViewScroll;
        if (!flick || flick.contentHeight <= flick.height)
            return "";
        if (flick.atYBeginning)
            return "↓ MORE";
        return flick.atYEnd ? "↑ MORE" : "↑↓ MORE";
    }

    // A click IS the pointer acting, so the level it opens hands the cursor to
    // whatever row lands under the (still parked) pointer: re-arm one
    // stationary sample after _activateRow's own level change has reset the
    // gate. Only the row delegate's own MouseArea takes this path, activate()
    // over IPC stays keyboard-shaped.
    function _activateFromPointer(index) {
        root._activateRow(index);
        pointerGate.allowStationarySample();
    }

    function _activateRow(index) {
        // An app view has no row cursor, so Enter has nothing to act on.
        // The guard is not decorative: a typed query on such a route still
        // falls through to whole-tree ranking below, and without this Enter
        // would launch a row that was never on screen.
        if (root._isAppView) return;
        var rows = root._displayRows;
        if (index < 0 || index >= rows.length) return;
        var node = rows[index];
        if (node.kind === "option") {
            root._completeSelect(node.label);
            return;
        }
        if (node.kind === "image") {
            root.chooseImage(node.path);
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
            if (node.pasteAfter === true)
                root._pendingPaste = true;
            // Toggle rows (default-menu.jsonc's "toggles" subtree) stay on
            // screen so the row's own checkmark visibly flips under the
            // cursor; every other action still closes.
            if (node.keepOpen === true) {
                root._confirmPendingId = "";
                return;
            }
            root.close();
            return;
        }
        if (node.kind === "app") {
            // Launch-or-focus: an already-running instance is focused
            // instead of spawning a second copy, and repeat activation
            // cycles that app's instances. Focusing still records a
            // frecency hit, because it is a use of the app. Reads
            // focusedWindowId (the compositor's literal answer) rather than
            // heldFocusedWindowId on purpose: focus.js's hold exists for the
            // bar's active-window cell and would make the cycle skip a
            // window while the menu itself holds focus. A miss falls through
            // to the spawn path below, which is today's behaviour.
            var focusTarget = AppMatch.nextWindow(AppMatch.matchWindows(node._entry, CompositorService.windows || []), CompositorService.focusedWindowId);
            if (focusTarget !== "") {
                CompositorService.focusWindow(focusTarget);
                Core.State.setAppLaunches(Frecency.record(Core.State.appLaunches, node._entry.id, Date.now()));
                root.close();
                return;
            }
            // Baseline first: nothing can map a window inside this same JS
            // block, so the count _beginLaunchWatch reads is genuinely the
            // "before". execute() stays exactly as it was, the entry's own
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

    // Shift+Enter accelerator (M38 Task 8): the cursor row's app launched on
    // the default discrete card instead of normally, anywhere in the
    // launcher an app row appears. Falls through to plain _activateRow when
    // there is no discrete card or the cursor isn't on an app row: never a
    // no-op that silently does nothing.
    function _activateRowOnDiscreteGpu(index) {
        if (root._isAppView) return;
        var card = GpuService.defaultDiscrete();
        var rows = root._displayRows;
        var node = (index >= 0 && index < rows.length) ? rows[index] : null;
        if (!card || !node || node.kind !== "app") {
            root._activateRow(index);
            return;
        }
        root._runAction(Providers.gpuLaunchAction(Quickshell.shellDir, node._entry.id, card.card));
        Core.State.setAppLaunches(Frecency.record(Core.State.appLaunches, node._entry.id, Date.now()));
        root.close();
    }

    // "@ipc:<name>" actions (see default-menu.jsonc's header comment)
    // dispatch in-process instead of spawning a shell command, needed for
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
        // The one `@ipc:` name that carries an argument (`clipssh.send:<alias>`):
        // the alias is per-row data, and the alternative was a shell command
        // the shell could not watch (see ClipsshService's header).
        if (name.indexOf("clipssh.send:") === 0) {
            ClipsshService.send(name.slice("clipssh.send:".length));
            return;
        }
        // The clipboard route's own rows. In-process because this menu runs
        // inside the process that owns the history, providers.js's header
        // has why the spawned `qs ipc` form it replaced only ever worked on
        // the smoke rig.
        if (name.indexOf("clipboard.copy:") === 0) {
            ClipboardService.copy(name.slice("clipboard.copy:".length));
            return;
        }
        switch (name) {
        // In-process for the same reason the clipboard rows are: a spawned
        // `qs ipc call` only ever resolves on the smoke rig, where the whole
        // quickshell package is installed.
        case "lock.lock":
            LockService.lock();
            break;
        case "theme.toggleMode":
            Core.State.toggleMode();
            break;
        case "nightlight.toggle":
            NightLightService.toggle();
            break;
        case "screensaver.stayAwakeToggle":
            IdleService.toggleStayAwake();
            break;
        case "notifications.toggleDnd":
            NotificationService.setDnd(!NotificationService.dnd);
            break;
        case "reminder.set":
            // Qt.callLater is load-bearing, not style: _runAction is reached
            // from the activation path, which calls root.close() as soon as
            // this returns, and that close cancels a pending select before
            // the input field ever renders. CalendarPanel defers its second
            // prompt for exactly the same reason.
            Qt.callLater(function () { root.openInput("Reminder (25m coffee)", ReminderService.inputToken); });
            break;
        case "reminder.show":
            ReminderService.showSummary();
            break;
        case "reminder.clear":
            ReminderService.clear();
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

    // Live source for "@state:" `checked` conditions (toggles.js). Every read
    // here is a plain property read, so this binding re-evaluates the instant
    // any of the four flips and hands a fresh object to the delegate binding
    // below, the same var-change-detection contract the _condResults merge
    // already depends on. Not gated on isOpen the way _liveClipboardItems is:
    // four scalars cost nothing, and the NightLightService read is a second
    // construction site for that lazy singleton, which Indicators.qml wants.
    readonly property var _stateSnapshot: Toggles.snapshot({
        "nightlight.active": NightLightService.active,
        "screensaver.stayAwake": IdleService.stayAwake,
        "notifications.dnd": NotificationService.dnd,
        "theme.dark": Core.State.mode === "dark"
    })

    // Shell-condition batch: `when`/`checked` for EVERY node in the tree,
    // not just the current level, whole-tree search (see _displayRows) can
    // surface a node whose level the user hasn't descended into yet, and a
    // submenu with an unevaluated-when child self-prunes to invisible
    // (Model.visibleChildren), which would make that child undescendable and
    // its own condition permanently unevaluated. Runs once per open()
    // (open() clears both result caches first) and again on every
    // _enterLevel(), where the `undefined` guards make repeat calls within
    // the same session cheap no-ops. Never per-keystroke, search filters
    // purely against whatever's already cached. Results are merged into
    // fresh objects so QML's var-property change detection fires.
    function _evalConditions() {
        Object.keys(root._nodes).forEach(function (id) {
            var n = root._nodes[id];
            if (n.when !== undefined && root._condResults[n.id] === undefined) {
                if (Toggles.isStateCondition(n.when)) {
                    // "@state:" is a `checked` prefix only: a live `when` would
                    // mean re-running visibleChildren over every node (apps
                    // included) on each toggle flip, exactly the churn
                    // _liveClipboardItems exists to avoid.
                    console.warn("Menu: \"@state:\" is not a `when` condition, hiding", n.id);
                    root._condResults = Toggles.withResult(root._condResults, n.id, false);
                } else {
                    root._runCondition(n.id, n.when, "when");
                }
            }
            if (n.checked !== undefined && !Toggles.isStateCondition(n.checked)
                && root._checkedResults[n.id] === undefined)
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
                var source = isWhen ? root._condResults : root._checkedResults;
                var merged = Toggles.withResult(source, id, ok);
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
    // a fading-out menu, and the paste settle timer still keys
    // off the real visible flip below, exactly as before, just one exit
    // fade later. The window is transparent so the fade covers the whole
    // card; card paints its own background.
    visible: root.isOpen || card.opacity > 0
    color: "transparent"

    // The window spans the whole output (M39 Task 2) so it can carry the
    // scrim below; the card is one positioned item inside it rather than the
    // window's own content. These two are what `implicitWidth`/
    // `implicitHeight` used to be, and every consumer of the old window size
    // (_contentWidth, _preferredTop, _clampTop) reads them instead: the
    // window's own width/height now say "the output", which is a different
    // fact and never the one that math wanted.
    readonly property real _cardWidth: root._isAppView
        ? Core.Theme.space.popupWidthMenuApp
        : (root._isSplitRoute ? Core.Theme.space.popupWidthMenuSplit : Core.Theme.space.popupWidthMenu)
    readonly property real _cardHeight: root._chrome + root._headerHeight
        + Core.Theme.space.rowGap * 2 + root._rowsAreaHeight + actionBar.height

    WlrLayershell.namespace: "formalshell:menu"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    // The scrim (omarchy parity): plain black at half opacity over the live
    // desktop, fading with the card so a summon is one motion. It replaced a
    // dithered freeze of the screen itself, which read beautifully in a still
    // frame and could not be made to hold still in motion: refreshing it on
    // an interval meant the capture contained the backdrop it was replacing,
    // and every term in that loop, the resample, the per-frame palette, the
    // darkening wash, drifted a little each generation, so the picture
    // crawled while nothing on screen moved (owner, 2026-08-19). A scrim has
    // no such loop, costs nothing, and stays out of the way of the card,
    // which is the whole job. The lock screen still dithers, because its
    // backdrop is one still wallpaper and never re-reads the screen.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.isOpen ? 0.5 : 0

        Behavior on opacity {
            NumberAnimation { duration: Core.Theme.motion.standard; easing.type: Core.Theme.motion.easing }
        }
    }


    // Click-to-dismiss on the menu's OWN output. DismissTwins below has
    // always covered every other screen; this output had no backdrop to
    // click at all until the window went full-output, so Escape was the only
    // way out for a pointer user. Declared before `card`, so the card and
    // every cell in it stack above and keep their own clicks.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }

    // Enter/exit (DESIGN.md §1 Motion): the whole card fades and slides
    // down into place, one animated scalar so a resummon mid-exit reverses
    // where it stands. `Card` paints the translucent `card` fill Hyprland's
    // blur reads through, the 1px border and the `radiusXl` corners, and
    // insets its own slot by `panelPadding`, so every child below anchors
    // straight to that slot's edges.
    Card {
        id: card
        x: Math.round((root._outputWidth - root._cardWidth) / 2)
        y: root._clampTop(root._preferredTop)
        width: root._cardWidth
        height: root._cardHeight
        opacity: root.isOpen ? 1 : 0
        transform: Translate { y: (card.opacity - 1) * Core.Theme.motion.slide }

        Behavior on opacity {
            NumberAnimation { duration: Core.Theme.motion.standard; easing.type: Core.Theme.motion.easing }
        }

        // Swallows presses that land on the card's own padding gutters
        // rather than on a row, so a click inside the frame never falls
        // through to the dismiss area above. Negative margins put it back
        // over the gutters `Card` insets this slot by; first interactive
        // child, so every row declared after it still wins its own clicks.
        MouseArea {
            anchors.fill: parent
            anchors.margins: -card.padding
            acceptedButtons: Qt.AllButtons
        }

        // The input row (spec "Launcher"): a search icon, the field, and a
        // 1px rule underneath. No frame of its own, so the card's own
        // border is the only one on the surface. Its content takes the
        // rows' own `controlPaddingX` (DESIGN.md §1 Padding): the rows here
        // are borderless, so nothing else would line the icon up with the
        // column of icons under it. The rule below stays full-bleed.
        Item {
            id: searchRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: Core.Theme.space.controlPaddingX
            anchors.right: parent.right
            anchors.rightMargin: Core.Theme.space.controlPaddingX
            height: Core.Theme.space.controlHeight

            Icon {
                id: searchIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: Core.Theme.fontSize.body
                color: Core.Theme.color.mutedForeground
            }

            TextInput {
                id: searchInput
                anchors.left: searchIcon.right
                anchors.leftMargin: Core.Theme.space.iconGap
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: Core.Theme.color.foreground
                font.family: Core.Theme.fontFamilySans
                font.pixelSize: Core.Theme.fontSize.body
                focus: true
                selectByMouse: true
                cursorVisible: true

                Text {
                    anchors.fill: parent
                    visible: searchInput.text.length === 0
                    text: root._placeholder
                    color: Core.Theme.color.mutedForeground
                    font: searchInput.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                onTextChanged: {
                    root._cursorIndex = 0;
                    root._confirmPendingId = "";
                    // Typing re-ranks the rows under a pointer that hasn't
                    // moved, the churn the gate exists for.
                    pointerGate.reset();
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
                    // An app view with its own cursor gets first refusal
                    // on every key (root._appViewKey's own note).
                    if (root._appViewKey(event.key, event.modifiers)) {
                        event.accepted = true;
                        return;
                    }
                    switch (event.key) {
                    // An app view has no row cursor, so the same two keys
                    // scroll its content by a row instead. Claimed
                    // either way: letting them through would only reach
                    // the search field's own text cursor.
                    case Qt.Key_Up:
                        if (root._isAppView)
                            root._scrollAppViewBy(-Core.Theme.space.popupRowHeight);
                        else
                            root._moveCursor(root._isPickerRoute ? -root.pickerColumns : -1);
                        event.accepted = true;
                        break;
                    case Qt.Key_Down:
                        if (root._isAppView)
                            root._scrollAppViewBy(Core.Theme.space.popupRowHeight);
                        else
                            root._moveCursor(root._isPickerRoute ? root.pickerColumns : 1);
                        event.accepted = true;
                        break;
                    // Left/Right belong to the search field's own text
                    // cursor everywhere except the grid, so they're
                    // claimed only there, never accepted otherwise.
                    case Qt.Key_Left:
                        if (root._isPickerRoute) {
                            root._moveCursor(-1);
                            event.accepted = true;
                        }
                        break;
                    case Qt.Key_Right:
                        if (root._isPickerRoute) {
                            root._moveCursor(1);
                            event.accepted = true;
                        }
                        break;
                    // Page/Home/End are the search field's own text
                    // navigation everywhere else, so they are claimed
                    // only where an app view declares something to
                    // scroll. A page keeps one row of overlap, so the
                    // reader carries context across the jump.
                    case Qt.Key_PageUp:
                    case Qt.Key_PageDown:
                        if (root._appViewScroll) {
                            var page = Math.max(Core.Theme.space.popupRowHeight,
                                root._appViewScroll.height - Core.Theme.space.popupRowHeight);
                            root._scrollAppViewBy(event.key === Qt.Key_PageUp ? -page : page);
                            event.accepted = true;
                        }
                        break;
                    case Qt.Key_Home:
                        if (root._appViewScroll) {
                            root._scrollAppViewTo(0);
                            event.accepted = true;
                        }
                        break;
                    case Qt.Key_End:
                        if (root._appViewScroll) {
                            root._scrollAppViewTo(root._appViewScroll.contentHeight);
                            event.accepted = true;
                        }
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        if (root._mode === "input")
                            root._submitInput();
                        else if ((event.modifiers & Qt.ShiftModifier) !== 0)
                            root._activateRowOnDiscreteGpu(root._cursorIndex);
                        else
                            root._activateRow(root._cursorIndex);
                        event.accepted = true;
                        break;
                    case Qt.Key_Escape:
                        // select/input have no tree level to pop out of:
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
                    // Two variants, so Tab and Shift+Tab are the same
                    // switch. Claimed only where the switcher is actually
                    // up, so Tab keeps whatever it does everywhere else.
                    case Qt.Key_Tab:
                    case Qt.Key_Backtab:
                        if (root._isPickerRoute && root._pickerHasVariants) {
                            root.setPickerVariant(root._pickerVariant === "dark" ? "light" : "dark");
                            event.accepted = true;
                        }
                        break;
                    }
                }
            }
        }

        Rectangle {
            id: searchRule
            anchors.top: searchRow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Core.Theme.borderWidth
            color: Core.Theme.color.border
        }

        // The breadcrumb (spec "Launcher"): one chip per level below the
        // root, hidden outright at the root, where the field is already the
        // whole surface. The chips state the path; they are not a control,
        // so nothing in the row answers a click.
        Row {
            id: breadcrumbRow
            anchors.top: searchRule.bottom
            anchors.topMargin: root._breadcrumbVisible ? Core.Theme.space.rowGap : 0
            anchors.left: parent.left
            spacing: Core.Theme.space.xs
            visible: root._breadcrumbVisible
            height: root._breadcrumbVisible ? implicitHeight : 0

            Repeater {
                model: root.breadcrumb

                delegate: Cell {
                    id: crumb
                    required property string modelData

                    radius: Core.Theme.radiusSm
                    selected: true

                    Text {
                        text: crumb.modelData
                        color: crumb.foreground
                        font.family: Core.Theme.fontFamilySans
                        font.pixelSize: Core.Theme.fontSize.caption
                    }
                }
            }
        }

        // The wallpaper route's Dark | Light switcher (spec "Picker"): the
        // `Segmented` primitive. Absent entirely (zero height, no reserved
        // gutter) for a directory with no Dark/Light pair, and on every
        // other route.
        //
        // Both views below anchor to this rather than to the header, so the
        // switcher pushes the grid down without either of them knowing
        // whether it is there.
        Segmented {
            id: variantRow
            anchors.top: breadcrumbRow.bottom
            anchors.topMargin: visible ? Core.Theme.space.rowGap : 0
            anchors.left: parent.left
            visible: root._isPickerRoute && root._pickerHasVariants
            height: visible ? implicitHeight : 0
            options: ["Dark", "Light"]
            onChanged: i => root.setPickerVariant(i === 1 ? "light" : "dark")
        }

        // The variant belongs to the route, not to the control: Tab and
        // `picker variant` over IPC move it too, and Segmented writes its own
        // `index` on click, which a plain binding would not survive.
        Binding {
            target: variantRow
            property: "index"
            value: root._pickerVariant === "light" ? 1 : 0
        }

        ListView {
            id: rowsView
            anchors.top: variantRow.bottom
            anchors.topMargin: Core.Theme.space.rowGap
            anchors.left: parent.left
            // Split route (M30): the list keeps the left half of
            // _contentWidth so the preview pane below can own the right
            // half. Every other route is unchanged, full width.
            width: root._isSplitRoute ? Math.round(root._contentWidth / 2) : root._contentWidth
            height: root._rowsAreaHeight
            visible: !root._isPickerRoute && !root._isAppView
            clip: true
            // Emptied, not merely hidden, on the grid's and an app view's
            // routes: an unread model keeps its delegates alive, and
            // _viewContentHeight above needs the idle view to measure 0.
            model: (root._isPickerRoute || root._isAppView) ? [] : root._displayRows
            currentIndex: root._cursorIndex
            // ListView tracks the cursor through its (always present, even
            // with no `highlight` component) highlight item, and the
            // default `highlightMoveDuration: -1` moves that item at
            // `highlightMoveVelocity`, 400px/s. Key repeat outruns it, so
            // the view crawls behind the cursor and the tail of a long list
            // stays off-screen for seconds after the cursor has already
            // reached it and wrapped back to the top. 0 makes the follow a
            // hard jump, the only thing that keeps the cursor row visible
            // at repeat speed.
            highlightMoveDuration: 0

            WheelScroll { flickable: rowsView }

            delegate: MenuRow {
                current: root._cursorIndex === index
                checkedState: Toggles.checkedFor(node, root._stateSnapshot, root._checkedResults)
                confirming: root._confirmPendingId === node.id

                onActivate: root._activateFromPointer(index)
                onHoverMoved: (source, x, y) => {
                    if (pointerGate.moved(source, x, y))
                        root._setCursor(index);
                }
            }
        }

        // The wallpaper route's grid (DESIGN.md §Concrete translations' "grid
        // of image cells sharing hairline rules", spec §11), the picker's
        // own surface, now one of the menu's two views over the same
        // _displayRows/_cursorIndex state rather than a panel of its own.
        // Shares rowsView's geometry exactly, so the action bar below can
        // anchor to whichever of the two is live without knowing which.
        GridView {
            id: gridView
            anchors.top: variantRow.bottom
            anchors.topMargin: Core.Theme.space.rowGap
            anchors.left: parent.left
            width: root._contentWidth
            height: root._rowsAreaHeight
            visible: root._isPickerRoute
            clip: true
            model: root._isPickerRoute ? root._displayRows : []
            cellWidth: root._contentWidth / root.pickerColumns
            cellHeight: gridView.cellWidth
            currentIndex: root._cursorIndex
            // Same hard-jump follow as rowsView, for the same reason: held
            // arrow keys outrun the default animated highlight move and the
            // cursor cell ends up off-viewport.
            highlightMoveDuration: 0

            // A row here is a row of thumbnails, not a text line.
            WheelScroll {
                flickable: gridView
                step: gridView.cellHeight
            }

            // The wrapper carries the GridView's own cell, so the `Cell`
            // inside it can hold the gutter between thumbnails in its
            // margins and every gap comes out the same width, the edges of
            // the grid included.
            delegate: Item {
                id: imageSlot
                required property int index
                required property var modelData

                width: gridView.cellWidth
                height: gridView.cellHeight

                Cell {
                    id: imageCell
                    anchors.fill: parent
                    anchors.margins: Core.Theme.space.xs
                    radius: Core.Theme.radiusMd
                    // A grid cursor is the ring (spec "Launcher"): the
                    // thumbnail covers the cell, so a fill would sit under
                    // the picture and never be seen.
                    cursor: imageSlot.index === root._cursorIndex

                    // The thumbnail is inset far enough that its square corners
                    // sit inside the cell's rounded ones, which is what lets an
                    // image live in a `radiusMd` frame with no mask: at `sm` the
                    // corner of the inset square is 5.7px from the arc's centre
                    // against a radius of 8.
                    //
                    // Decode capped at the cell's own on-screen size (M16 Task
                    // 12): without this, a 6000×4000 source decodes at full
                    // resolution into a ~130px cell, ~96MB of resident RGBA
                    // per thumbnail, times every file in the directory.
                    //
                    // The 2x factor matters: sourceSize with both dimensions set
                    // decodes to FIT INSIDE that box (Qt's KeepAspectRatio), not
                    // to cover it, so a non-square source into this square cell
                    // would decode short on one axis and PreserveAspectCrop
                    // would upscale it back out, visibly blurrier than an
                    // uncapped decode. A box 2x the cell's side keeps the
                    // fit-inside decode covering the cell for any source up to
                    // 2:1 either way, comfortably past 16:9, while still capping
                    // memory to a small multiple of the cell.
                    // Sized off the GridView's own cell rather than off
                    // `imageCell`: a `Cell` measures its content to publish
                    // an implicit size, so a child measured back off the
                    // cell closes a loop Qt then reports and breaks (its
                    // own anchors already decide its size, but the detector
                    // sees the cycle first).
                    Image {
                        id: thumb
                        anchors.centerIn: parent
                        width: imageSlot.width - (Core.Theme.space.xs + Core.Theme.space.sm) * 2
                        height: imageSlot.height - (Core.Theme.space.xs + Core.Theme.space.sm) * 2
                        source: "file://" + imageSlot.modelData.path
                        fillMode: Image.PreserveAspectCrop
                        // PreserveAspectCrop paints past its own bounds
                        // without this, over the cells beside it.
                        clip: true
                        asynchronous: true
                        cache: false
                        sourceSize.width: thumb.width * 2 * (root.screen ? root.screen.devicePixelRatio : 1)
                        sourceSize.height: thumb.height * 2 * (root.screen ? root.screen.devicePixelRatio : 1)
                    }

                    interactive: true
                    // Same gate as the row list: filtering re-renders cells
                    // under a parked pointer, and Qt delivers that as a
                    // hover move indistinguishable from a real one.
                    onPointerMoved: (x, y) => {
                        if (pointerGate.moved(imageCell, x, y))
                            root._setCursor(imageSlot.index);
                    }
                    onClicked: root._activateFromPointer(imageSlot.index)
                }
            }
        }

        // The third view (M38, D1): a whole component in place of the row
        // list, for any route Menu/appviews.js registers. Shares rowsView's
        // geometry exactly, like gridView above, so the action bar anchors
        // to whichever of the three is live without knowing which.
        //
        // `source` empties off the route rather than the loader merely
        // hiding: an app view holds a live subscription to whatever service
        // it renders, and a hidden-but-loaded one would keep that service
        // polling for a launcher nobody is looking at.
        //
        // It empties on the window going away too, not just on leaving the
        // route. close() deliberately leaves currentNodeId where it was (so
        // a resummon lands back on the same level), which would otherwise
        // hold the subscription open for as long as the shell runs. Keyed
        // off the window's own `visible` rather than `isOpen` so the view
        // survives the exit fade instead of blanking the card mid-animation.
        Loader {
            id: appView
            anchors.top: variantRow.bottom
            anchors.topMargin: Core.Theme.space.rowGap
            anchors.left: parent.left
            width: root._contentWidth
            height: root._rowsAreaHeight
            visible: root._isAppView
            source: (root._isAppView && root.visible) ? Qt.resolvedUrl(root._appViewSource) : ""
        }

        // The seam that makes the registry reusable: a view that wants the
        // search field declares `property string query` and gets the live
        // text; one that declares none (MonitorView) leaves the field inert
        // rather than pretending to filter something.
        Binding {
            target: appView.item
            property: "query"
            value: searchInput.text
            when: appView.item !== null && appView.item.query !== undefined
        }

        // The split route's right half (M30, M43 D4): the cursor row's
        // full content in an inner `Card` at `radiusMd`, a `sm` gutter off
        // the list. Positioned by anchoring off rowsView itself (whichever
        // width it currently has) rather than an independent x/width pair,
        // so the two views can never drift apart.
        Card {
            id: previewPane
            visible: root._isSplitRoute
            anchors.top: rowsView.top
            anchors.left: rowsView.right
            anchors.leftMargin: Core.Theme.space.sm
            anchors.right: parent.right
            height: rowsView.height
            radius: Core.Theme.radiusMd

            Row {
                id: previewHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Core.Theme.space.sm

                SectionLabel {
                    id: previewMeta
                    visible: root._previewKind !== ""
                    text: root._previewKind
                }

                Text {
                    visible: root._previewTime !== ""
                    text: root._previewTime
                    color: Core.Theme.color.mutedForeground
                    font.family: Core.Theme.fontFamilyMono
                    font.pixelSize: Core.Theme.fontSize.caption
                }
            }

            Text {
                anchors.top: previewHeader.bottom
                anchors.topMargin: Core.Theme.space.rowGap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: root._previewIsText
                clip: true
                text: root._cursorNode ? (root._cursorNode.fullText || "") : ""
                wrapMode: Text.WrapAnywhere
                color: Core.Theme.color.foreground
                font.family: Core.Theme.fontFamilyMono
                font.pixelSize: Core.Theme.fontSize.body
            }

            // True-color (menu thumbnails are never dithered) full preview
            // of the cursor row's capture, in its own `radiusMd` frame with
            // a 1px border, decode capped at the frame's own size for the
            // picker grid's reason. The frame is `muted` so a letterboxed
            // capture reads as a picture in a well rather than as a gap in
            // the card.
            Rectangle {
                id: previewImageBox
                anchors.top: previewHeader.bottom
                anchors.topMargin: Core.Theme.space.rowGap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: root._previewIsImage
                radius: Core.Theme.radiusMd
                color: Core.Theme.color.muted
                border.width: Core.Theme.borderWidth
                border.color: Core.Theme.color.border
                clip: true

                Image {
                    id: previewImage
                    anchors.fill: parent
                    anchors.margins: Core.Theme.space.sm
                    source: root._previewIsImage ? ("file://" + root._cursorNode.thumbSource) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    sourceSize.width: previewImage.width * (root.screen ? root.screen.devicePixelRatio : 1)
                    sourceSize.height: previewImage.height * (root.screen ? root.screen.devicePixelRatio : 1)
                }
            }
        }

        // The footer hint line (spec "Launcher"): what Enter does to the
        // row under the cursor, plus the keys that always apply.
        // Menu/actions.js owns the wording.
        MenuActionBar {
            id: actionBar
            anchors.top: rowsView.bottom
            anchors.topMargin: Core.Theme.space.rowGap
            // Same `controlPaddingX` the rows and the input row take, so the
            // legend starts under the column of labels rather than under the
            // card's edge (DESIGN.md §1 Padding).
            anchors.left: parent.left
            anchors.leftMargin: Core.Theme.space.controlPaddingX
            anchors.right: parent.right
            anchors.rightMargin: Core.Theme.space.controlPaddingX
            primary: root._actionBar.primary
            hints: root._actionBar.hints

            // Clicking the primary verb is the pointer acting, exactly like
            // clicking the row itself: same path, same gate re-arm. On an
            // app view it presses that view's own primary instead, at
            // whatever its cursor already is (index -1).
            onPrimaryActivated: {
                if (root._isAppView) {
                    if (appView.item && appView.item.viewActivate)
                        appView.item.viewActivate(-1);
                    return;
                }
                root._activateFromPointer(root._cursorIndex);
            }
        }

        // The app view's overflow hint, at the footer's right end, where the
        // hint line cannot reach it. In the footer rather than over the view
        // because a hint sitting on the content it announces hides the rows
        // the reader is reaching for.
        Text {
            anchors.right: actionBar.right
            anchors.verticalCenter: actionBar.verticalCenter
            visible: root._appViewScrollHint !== ""
            text: root._appViewScrollHint
            color: Core.Theme.color.mutedForeground
            font.family: Core.Theme.fontFamilySans
            font.pixelSize: Core.Theme.fontSize.caption
            font.capitalization: Font.AllLowercase
        }
    }

    // Multi-monitor dismiss (M16 Task 7): a click on another screen closes
    // the menu exactly like Escape does.
    DismissTwins {
        active: root.isOpen
        ownScreen: root.screen
        onDismissed: root.close()
    }
}
