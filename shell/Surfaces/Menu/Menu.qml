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
import qs.Theme
import qs.Reminders
import "../../Menu/model.js" as Model
import "../../Menu/search.js" as Search
import "../../Menu/providers.js" as Providers
import "../../Menu/calc.js" as Calc
import "../../Menu/frecency.js" as Frecency
import "../../Menu/toggles.js" as Toggles
import "../../Menu/actions.js" as Actions
import "../../Menu/appviews.js" as AppViews
import "../../Menu/appgrid.js" as AppGrid
import "../../Menu/icons.js" as MenuIcons
import "views"
import "../../Compositor/keybinds.js" as Keybinds
import "../../Menu/rowsync.js" as RowSync
import "../../Menu/nav.js" as Nav
import "../../Compositor/appmatch.js" as AppMatch

// The unified menu (M72 T4, Raycast's layout kept plain): a single
// keyboard-exclusive top-layer window covering the focused output, a plain
// black scrim, and the card at 30% of the output height on top of it. The
// card is three bands split by full-bleed rules: the header (a back chip
// inside a level, the search field, the close button), the body (sections,
// each a heading over its rows or tiles; at the root the apps as a grid
// under Applications, then the commands under their own headings), and the
// footer (where you are, and what Enter does). The card is one size per
// level kind and never follows its rows: results scroll inside it.
// Whole-tree search, cursor wraps, Escape clears the query and then pops
// one level, Backspace on an empty field pops one level per press,
// confirm-gated actions need a second Enter.
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

    // The cursor (M72 T1): the id of the row it is on, and where that row
    // sits in `_displayRows` right now. Both are written by `_placeCursor`
    // alone, and `_syncRows` re-derives them (Menu/nav.js's `rederive`)
    // every time the rows change, for whatever reason they changed.
    // `_cursorKey` is the query, level and mode the cursor was last placed
    // for: a different one is a fresh list, which starts on its first row.
    property int _cursorIndex: 0
    property string _cursorId: ""
    property var _cursorNode: null
    property string _cursorKey: ""
    // Whether a key or the pointer has moved the cursor since the list was
    // fresh, and the row it put the cursor on (Menu/nav.js's `rederive`).
    // Kept apart from `_cursorId`, which is whatever row the cursor is on
    // now: a row can leave and come back (the desktop entries reload one at
    // a time), and the cursor goes back to it rather than staying on
    // whichever row it was clamped to while it was gone.
    property bool _cursorPlaced: false
    property string _cursorWant: ""
    // Whether the ring draws on the cell the cursor is on (DESIGN.md §1
    // "Ring", §4): it is the keyboard's mark, so a cell the pointer named
    // keeps its hover wash alone. The row list marks its cursor with the
    // `accent` fill and never sees this; the three grids (the picker, emoji
    // and the app cells) are the surfaces here that draw a ring at all.
    // Published over them on the drawer, which cursor.js's `ringOwner` walk
    // finds from any cell inside the card.
    property bool _cursorFromKeys: false
    property string _confirmPendingId: ""

    // "menu" (tree navigation) | "select" | "input", the dmenu-replacement
    // modes summoned via MenuIpc's select()/input(). Both repurpose the same
    // window/search field; _displayRows, the footer and key handling branch
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
        // once the real tree exists, closes that gap; conditions.evaluate()'s
        // per-node `undefined` guard makes it a cheap no-op otherwise.
        onLoaded: {
            root._defaultMenuText = defaultMenuFile.text();
            conditions.evaluate(root._nodes);
        }
        onLoadFailed: error => console.warn("Menu: failed to load default-menu.jsonc:", error)
    }

    // Vendored emoji dataset (M12 Task 6): load-on-first-need and the
    // usage-sort ledger both live in EmojiProvider.
    EmojiProvider {
        id: emojiProvider
    }

    // Nix package runner (M12 Task 7; M13b Task 4 added the honest end
    // states): debounce, warm and the search Process all live in
    // NixSearchProvider.
    NixSearchProvider {
        id: nixProvider
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

    // Home-manager retargets this file's symlink on every activation, which
    // no watch can see (Core/ConfigReopen.qml carries the why). The overlay
    // is published as a string, so an unchanged reload is already a no-op
    // assignment; the guard in onLoaded below is what keeps the tick from
    // re-running the condition pass on a file that did not change.
    Core.ConfigReopen { file: userMenuFile }

    FileView {
        id: userMenuFile
        printErrors: false
        path: root._configDir + "/menu.jsonc"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root._userMenuRetries = 0;
            root._userMenuMissingLogged = false;
            var text = userMenuFile.text();
            if (text === root._userMenuText)
                return;
            root._userMenuText = text;
            conditions.evaluate(root._nodes);
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

    // Compositor keybinds for the menu's keybinds route (`hyprctl binds`):
    // the refresh Process and the row resolution both live in
    // KeybindsProvider.
    KeybindsProvider {
        id: keybindsProvider
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
    //   one trigger path and is never duplicated here. A pick out of a
    //   Dark/Light set also commits that set as the mode
    //   (Providers.wallpaperPickMode), in the same write.
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
    //
    // The scan, the variants and the route's own mode/dir/token state live
    // in WallpaperPickerProvider; SelectionChannel is the generic
    // selection-file writer it shares with root's own select()/input() modes
    // below.
    SelectionChannel {
        id: selectionChannel
    }

    WallpaperPickerProvider {
        id: pickerProvider
        selectionChannel: selectionChannel
    }

    readonly property bool _isPickerRoute: root._mode === "menu" && root.currentNodeId === pickerProvider.routeId

    // The Dark | Light switcher's one entry point: the segments, Tab, and
    // `picker variant` over IPC all land here. Same-variant calls are a
    // no-op rather than a failure, a caller asking for the variant already
    // showing got what it asked for.
    function setPickerVariant(variant) {
        if (!root.isOpen || !root._isPickerRoute || !pickerProvider.hasVariants)
            return false;
        var next = variant === "light" ? "light" : "dark";
        if (pickerProvider.variant !== next) {
            // The other variant is a different listing, so it is a fresh one
            // for the cursor too: the variant is part of `_cursorKey`.
            pickerProvider.variant = next;
            root._cursorFromKeys = true;
            pointerGate.reset();
        }
        return true;
    }

    // PickerIpc's summon(), the wallpaper-mode open. Everything it needs to
    // reset happens in pickerProvider.enterRoute() off the level entry, so a
    // menu row and this call reach an identical state by construction.
    function openWallpaperPicker() {
        root.open(pickerProvider.routeId);
    }

    function openImageSelect(directory, token) {
        pickerProvider.abandonPending();
        pickerProvider.mode = "select";
        pickerProvider.dir = (directory && directory.length > 0) ? directory : Core.Config.get("picker.directory", "");
        pickerProvider.token = token;
        pickerProvider.requestPending = true;
        root.open(pickerProvider.routeId);
    }

    // Callable over IPC (PickerIpc's choose()) as well as from Enter/click
    // on a cell, the one function that resolves a pick, so both paths stay
    // in sync by construction. Refuses a path outside the current listing
    // rather than trusting an arbitrary caller-supplied one.
    function chooseImage(path) {
        if (!root.isOpen || !root._isPickerRoute || pickerProvider.images.indexOf(path) < 0)
            return false;
        if (pickerProvider.mode === "select") {
            selectionChannel.writeFile(selectionChannel.pickerSelectionPath, JSON.stringify({ token: pickerProvider.token, value: path }));
            pickerProvider.token = "";
        } else {
            Core.State.setWallpaper(path, Providers.wallpaperPickMode(pickerProvider.variants, pickerProvider.variant));
        }
        root.close();
        return true;
    }

    function pickerStatus() {
        return {
            open: root.isOpen && root._isPickerRoute,
            mode: pickerProvider.mode,
            directory: pickerProvider.dir,
            // The listing actually on screen, so this tracks the variant.
            count: pickerProvider.images.length,
            variant: pickerProvider.hasVariants ? pickerProvider.variant : "none",
            hasVariants: pickerProvider.hasVariants,
            // Prerendered thumbnails backing the listing on screen. Cold on
            // a first run and equal to `count` once the warm has caught up;
            // the only way the rig can see the cache at all, since a warm
            // and a fallback draw the same picture.
            cachedThumbnails: ThumbnailService.cachedCount(pickerProvider.images, "cover"),
            darkCount: pickerProvider.variants.dark.length,
            lightCount: pickerProvider.variants.light.length,
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
    // Everything else about the level is untouched: the back chip, Escape,
    // backspace-on-empty and the `menu` IPC all key off currentNodeId, so
    // none of them needs to know a view is live.
    readonly property string _appViewSource: root._mode === "menu" ? AppViews.viewFor(root.currentNodeId) : ""
    readonly property bool _isAppView: root._appViewSource !== ""

    // --- Emoji grid (M48 D5) ---------------------------------------------
    //
    // The emoji route is the picker's grid over a different cell: 3,944
    // glyphs are something you hunt for by eye, not something you read down
    // a column one name per line (owner, 2026-08-26). The ":e " trigger draws
    // the same grid from any level, because it lists the same rows; the
    // route-local surfaces that are checked ahead of it (the picker's own
    // grid, the clipboard split, an app view) keep their rows, which is the
    // order `_resolve` checks them in. Column count is EmojiGridView's own,
    // the same seam appGrid's `columns` already is.

    // --- App grid (M58 G1-G4) --------------------------------------------
    //
    // `menu.appGrid` on draws a level's app rows as a grid of icons with
    // their names under them and whatever else ranked as rows beneath
    // (Surfaces/Menu/views/AppGridView.qml). The owner asked for their app
    // icons (2026-09-17: "similar to what macOS does").
    //
    // The ranking is untouched: `AppGrid.partition` is a stable split of the
    // rows the level resolved, so both blocks keep the order the score gave
    // them and a cell's index is still an index into `_displayRows`. That is
    // what lets Enter, Shift+Enter and the action bar act on the cursor
    // without knowing which view drew it.
    //
    // The grid is the level's view, not the query's (M72 T1): every level
    // that draws the tree's own rows draws them through the grid, with no
    // cells at all when nothing ranked is an app, so typing never swaps the
    // card's whole body between two views. The route-local levels (the
    // clipboard split, nix, keybinds, calc) never produce an app row and
    // keep the row list.
    //
    // The grid is on by default under every theme (M72 T2); `menu.appGrid`
    // stays a user key, an explicit false in settings.json still wins.
    readonly property bool _appGridWanted: Core.Config.get("menu.appGrid", true)

    // Which of the five views draws the level: `rows`, `picker`, `emoji`,
    // `appGrid` or `app`. Committed by `_syncRows` with the rows it draws,
    // never ahead of them. Public because `menu status` reports it (M58 G5):
    // a frame cannot tell a grid of app icons from a row list that happens
    // to carry icons.
    property string viewKind: "rows"
    // Where the app cells stop in `_displayRows`, committed with them.
    property int _appGridCount: 0

    readonly property bool _isPickerGrid: root.viewKind === "picker"
    readonly property bool _isEmojiGrid: root.viewKind === "emoji"
    readonly property bool _isAppGrid: root.viewKind === "appGrid"
    readonly property bool _isGrid: root._isPickerGrid || root._isEmojiGrid || root._isAppGrid

    // Whether the cursor is sitting on a cell rather than on a row, which on
    // the app grid changes with the cursor instead of with the level: the
    // footer's key legend belongs to the grid half of it.
    readonly property bool _gridCursor: root._isAppGrid
        ? root._cursorIndex < root._appGridCount
        : root._isGrid

    // How many cells one row of the level holds, 1 for a row list. On `menu
    // status` because a grid and a list are otherwise indistinguishable in a
    // JSON dump.
    readonly property int cursorColumns: root._isPickerGrid
        ? pickerGridView.columns
        : (root._isEmojiGrid
            ? emojiGridView.columns
            : (root._isAppGrid ? appGrid.columns : 1))

    // Mirrors ClipboardService.items and CompositorService.windows ONLY
    // while the menu is actually open (M17 review finding, M-polish batch
    // item G, owner: low-end laptop): LiveMenuSources' own ternaries never
    // read either service while closed, so QML's binding dependency tracker
    // doesn't subscribe to them, which is what keeps _defaultObj/_tree
    // below from rebuilding the ENTIRE tree (every app, every provider) on
    // every single capture or window event. The moment `active` flips true
    // both re-read the live state and resubscribe, so content is exactly as
    // fresh as before for as long as the menu stays open.
    LiveMenuSources {
        id: liveSources
        active: root.isOpen
    }

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
        // liveSources.clipboardItems rides this same binding for
        // _defaultObj (and _tree below) to recompute whenever it changes,
        // but only while that dependency is actually subscribed (see
        // LiveMenuSources' own comment). Merged as a plain overwrite of the
        // "share.clipboard" key default-menu.jsonc already declares, so the
        // row keeps that declared position instead of jumping to the end.
        var shareClipboard = Providers.shareClipboardEntry(liveSources.clipboardItems);
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
        // closing, where liveSources' own `active` flip already pays for a
        // rebuild. Date.now() is read at rebuild time, so the recency decay
        // is as fresh as the tree itself.
        apps: function () {
            return AppMatch.decorateAppRows(Providers.appsProvider(DesktopEntries.applications.values,
                root._resolveAppIcon, Core.State.appLaunches, Date.now()), liveSources.windows);
        },
        clipboard: function () { return Providers.clipboardProvider(liveSources.clipboardItems, "copy", Core.Config.get("clipboard.paste", true)); },
        shareHistory: function () { return Providers.clipboardProvider(liveSources.clipboardItems, "share"); },
        // ~/.clipssh/aliases lives on ClipsshService, which reads it for the
        // Shift+Enter accelerator and the auto-send too; open() below still
        // reloads it every summon, so an alias added mid-session (even before
        // the file first existed) shows on the next open.
        clipssh: function () { return Providers.clipsshRows(ClipsshService.aliases); },
        // M38 Task 3 (launcher reachability sweep): both self-targeted the
        // same way apps/clipboard above are.
        panels: function () { return Providers.panelsProvider(Quickshell.shellDir); },
        tray: function () { return Providers.trayProvider(SystemTray.items.values, Quickshell.shellDir); },
        // M38 Task 8: card info rows, always present. Launching an app on
        // the discrete card is Shift+Enter on the app row itself
        // (_activateRowAlternate below), not a route mirroring the
        // whole app list a second time.
        gpu: function () { return Providers.gpuProvider(GpuService.cards); }
    })
    readonly property var _nodes: root._tree.nodes

    // The resolver the window switcher's tiles take too (AppIconService,
    // memoised there), handed to the provider rather than imported by it so
    // its tests keep passing their own.
    function _resolveAppIcon(name) {
        return AppIconService.source(name);
    }

    // True while `level`'s own node carries an unsatisfied (or not yet
    // resolved) `when` gate, see `_levelRows`' own comment for why this only
    // matters for the direct-summon path.
    function _levelGated(level) {
        if (level === null) return false;
        var node = root._nodes[level];
        return node ? !Model.isWhenVisible(node, conditions.condResults) : false;
    }

    // What the level resolves to, in one pass over the field, the mode and
    // the level (M72 T1): which view draws it, its rows, where the app cells
    // stop, and the key the cursor is placed for. One evaluation answers all
    // of them from the same three inputs, which is what keeps them agreeing:
    // every one of them used to be its own binding over a different mix of
    // those inputs and of each other, and `_syncRows` read them while some
    // had caught up with a keystroke and some had not.
    readonly property var _resolved: root._resolve(searchInput.text, root._mode, root.currentNodeId)

    function _resolve(q, mode, level) {
        var menu = mode === "menu";
        var picker = menu && level === pickerProvider.routeId;
        var split = menu && (level === "clipboard" || level === "share.history");
        var appView = menu && AppViews.viewFor(level) !== "";
        var emojiQuery = menu ? Providers.emojiTriggerQuery(q) : null;
        var nixQuery = menu ? Providers.nixTriggerQuery(q) : null;
        var keysQuery = menu ? Keybinds.triggerQuery(q) : null;
        var emoji = menu && !picker && !split && !appView && (level === "emoji" || emojiQuery !== null);
        var routeRows = level === "nix" || level === "keybinds" || level === "calc";
        var kind = appView ? "app"
            : (picker ? "picker"
                : (emoji ? "emoji"
                    : (menu && root._appGridWanted && !split && !routeRows ? "appGrid" : "rows")));
        var rows = root._levelRows(q, mode, level, picker, split, emojiQuery, nixQuery, keysQuery);
        // A provider's honest-empty row (NO NIX, an empty history, a gated
        // level) is what the level has instead of rows, not a row of it: it
        // answers no key, so the cursor must never land on it. It is drawn
        // as the body's empty state, in its own words.
        var empty = null;
        var live = rows.filter(function (row) { return !(row.kind === "note" && row.dim === true); });
        if (live.length < rows.length) {
            if (live.length === 0)
                empty = rows[0];
            rows = live;
        }
        // The root's first section is its apps (M72 T4): the head of the
        // apps route's own ranked list, frecency first, and the Apps route
        // row under Suggestions still opens the whole of it.
        if (kind === "appGrid" && level === null && q.length === 0)
            rows = Model.visibleChildren(root._nodes, "apps", conditions.condResults)
                .filter(function (row) { return row.kind === "app"; })
                .slice(0, Core.Theme.launcher.rootApps)
                .concat(rows);
        var appCount = 0;
        if (kind === "appGrid") {
            var parts = AppGrid.partition(rows);
            rows = parts.rows;
            appCount = parts.appCount;
        }
        return {
            empty: empty,
            key: [mode, level === null ? "" : level, q, picker ? pickerProvider.variant : ""].join("\u0001"),
            mode: mode,
            level: level,
            kind: kind,
            rows: rows,
            appCount: appCount,
            // A whole-tree ranked list rather than one level's own children:
            // every route-local surface filters its own data instead of
            // falling through to Search.rank, and its rows belong to that
            // level rather than to a set of results.
            searching: menu && q.length > 0 && !picker && !split && !emoji && !routeRows
                && nixQuery === null && keysQuery === null
        };
    }

    // The level's own rows, before the app grid's split: every branch below
    // is this file's original row resolution and nothing in it knows about
    // the grid.
    function _levelRows(q, mode, level, picker, split, emojiQuery, nixQuery, keysQuery) {
        if (mode === "select") {
            var query = q.toLowerCase();
            return root._selectOptions
                .map(function (opt, i) { return { id: "select." + i, label: String(opt), icon: "", kind: "option" }; })
                .filter(function (n) { return query.length === 0 || n.label.toLowerCase().indexOf(query) >= 0; });
        }
        if (mode === "input")
            return [];
        // The wallpaper route is the picker's grid (M23): route-local rows
        // built from the scanned directory and filtered by filename, never
        // whole-tree ranking, a wallpapers directory would drown a root
        // query exactly the way the emoji dataset would.
        if (picker)
            return Providers.imageRows(pickerProvider.images, q);
        // The clipboard/share-history route is route-local too (M30), for
        // the same reason the picker route above is: typing here narrows
        // history, it never falls through to whole-tree Search.rank or to
        // the trigger routes below (checked here, ahead of them, on
        // purpose, a ":e"/":nix"/":k"-prefixed clipboard entry is filter
        // text on this level, not a trigger).
        if (split) {
            var historyRows = Model.visibleChildren(root._nodes, level, conditions.condResults);
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
        var emojiPaste = Core.Config.get("clipboard.paste", true);
        if (level === "emoji")
            return Providers.emojiRows(emojiProvider.list, emojiQuery !== null ? emojiQuery : q, emojiPaste, emojiProvider.uses, Date.now());
        if (emojiQuery !== null)
            return Providers.emojiRows(emojiProvider.list, emojiQuery, emojiPaste, emojiProvider.uses, Date.now());
        // The nix route/":nix" trigger works the same way, except the rows
        // come from the debounced-Process cache (see the state block above)
        // rather than a pure function over local data.
        if (level === "nix" || nixQuery !== null)
            return nixProvider.rowsFor(nixQuery !== null ? nixQuery : q);
        // The keybinds route is route-local for the same reason: its own
        // tiered search, never Search.rank, so a hundred-odd chords cannot
        // drown a root query.
        if (level === "keybinds" || keysQuery !== null)
            return keybindsProvider.rowsFor(keysQuery !== null ? keysQuery : q);
        if (q.length === 0) {
            // Route-summon when-gate guard (M17 review finding, item F):
            // `open(route)` resolves a node by id directly, bypassing the
            // parent-level isWhenVisible() filter that keeps a gated node
            // (e.g. "share" without localsend_app) from ever appearing as
            // a row in the first place, without this, landing on that
            // level here would still list its children as if the gate
            // never existed. `_levelGated` covers "not yet
            // resolved" the same as "resolved false": conditions.condResults
            // starts empty every open()/_enterLevel(), so a level entered before
            // its own condition Process has exited must not flash
            // actionable rows it may end up refusing a moment later.
            if (root._levelGated(level))
                return [Model.gatedNoteRow(root._nodes[level])];
            return Model.visibleChildren(root._nodes, level, conditions.condResults);
        }
        // A query that parses as an expression leads with the CALC result row
        // (M12 Task 5). At the dedicated calc level the result row is the
        // whole surface, whole-tree matches would just be root search noise
        // there. Parse failures are silent: calcRow is null, nothing renders.
        var calcRow = Calc.resultNode(q);
        if (level === "calc")
            return calcRow ? [calcRow] : [];
        var ranked = Search.rank(root._nodes, q, conditions.condResults, level);
        return calcRow ? [calcRow].concat(ranked) : ranked;
    }

    // What the views draw and what Enter acts on, committed together by
    // `_syncRows` from one `_resolved`. Plain properties rather than
    // bindings, so nothing downstream can see the rows of one keystroke with
    // the cursor, the headings or the view of another.
    property var _displayRows: []

    readonly property int rowCount: root._displayRows.length

    // On `menu status` (M58 G5): which row or cell the cursor sits on. A
    // frame shows the ring, but only a number says an arrow press moved by
    // one cell rather than by a whole row of them.
    readonly property int cursorIndex: root._cursorIndex
    readonly property string cursorId: root._cursorId

    // One heading per row (M48 D6), index-aligned with _displayRows: the
    // delegate draws its `SectionLabel` wherever this array changes value,
    // so nothing is ever reordered to make a group. A level that is all one
    // group comes back blank, since the back chip already names it, and so
    // do the picker and emoji grids, which have nowhere to put a full-width
    // band between two cells of a row.
    property var rowSections: []

    // The distinct headings, in order, for `menu status`: what a heading
    // says is otherwise only observable by reading pixels off a frame.
    readonly property var sectionNames: Model.sectionNames(root.rowSections)

    // --- The keyed row models (M53 D6, M72 T1) ---------------------------
    //
    // A JS array handed to a view is a model reset: no row survives a
    // re-rank, so nothing in the list can move, appear or leave, a grid
    // loses its scroll, and the view's current item is rebuilt under the
    // cursor on every keystroke. These carry the same rows' ids in the same
    // order, synced by Menu/rowsync.js's diff, so the delegate that was
    // already drawing a row stays that row's delegate.
    //
    // `rowsModel` feeds whichever view is on screen (the row list, the
    // picker or emoji grid, the app grid's cells) and `tailModel` the rows
    // under the app grid. Only the live view is attached (`_attachViews`),
    // so a hidden view holds no delegates and measures 0.
    //
    // Ids only. The row objects themselves stay in `_displayRows` and reach
    // the delegate through `_rowsById` below, which keeps these models out
    // of the business of copying every field of every row into ListElement
    // roles on every keystroke.
    ListModel {
        id: rowsModel
    }

    ListModel {
        id: tailModel
    }

    property var _rowsModelIds: []
    property var _tailModelIds: []

    // Rows by id, this sync and the one before it. The delegate reads its
    // own row out of these rather than off `_displayRows[index]`, because a
    // row on its way out through the `remove` transition is still on screen
    // after the model has stopped holding it: an index would then resolve to
    // whichever row slid into that slot, and the fading row would spend its
    // exit drawing somebody else's label. One generation of history is
    // enough, since an exit is over inside a frame or two.
    //
    // Each entry is `{ row, section, sectionFirst }`: the heading a row
    // opens comes off `rowSections`, which is index-aligned with
    // `_displayRows`, and is resolved here so nothing downstream of the
    // model has to reach back into an array by index either.
    property var _rowsById: ({})
    property var _rowsPrev: ({})

    // What a delegate draws when its id resolves to neither generation,
    // which nothing in the sync can produce and a stale delegate would
    // otherwise answer with undefined in every band.
    readonly property var _blankRow: ({ id: "", label: "", kind: "note", icon: "", desc: "", meta: "", dim: true, path: "" })

    // Above this many rows leaving, arriving or changing places, the change
    // is a rebuild rather than a story about what moved (M53 D6), and the
    // model is refilled with no transitions at all.
    readonly property int _rowResetLimit: 64

    // Armed for an incremental sync, disarmed for a refill, read by the row
    // list's transitions. Set before the ops it describes: `_placeCursor`
    // sets the view's currentIndex straight after, which makes the view
    // apply the pending changes then and there, under this value.
    property bool _rowsAnimate: false

    // Set for the length of an open() (and the select/input opens): every
    // sync inside it refills without transitions and puts the cursor on the
    // first row, so the card arrives settled rather than replaying last
    // session's rows into it.
    property bool _rowsSettle: false

    // The mode and level the models were last synced for.
    property string _rowsLevel: ""

    // Whether the cursor travels to where it is going or is simply there
    // (M53 D4). One arrow step travels; a wrap, a page, a re-rank, a level
    // change and the pointer all snap, since nothing meaningful connects the
    // two positions.
    property bool _cursorTravels: false

    on_ResolvedChanged: root._syncRows()

    // The one sync step (M72 T1), synchronous: commits the resolved rows,
    // walks the live view's models to them, re-derives the cursor and
    // asserts every view's currentIndex, in that order and in one call. It
    // can run more than once for one keystroke while the bindings under
    // `_resolved` settle; every run commits a consistent snapshot and the
    // last one is the settled answer.
    function _syncRows() {
        var r = root._resolved;
        var rows = r.rows;
        var kindChanged = r.kind !== root.viewKind;
        var fresh = root._rowsSettle || r.key !== root._cursorKey;
        // A new level is a new list: `levelEnter` is its arrival, and rows
        // sliding about under that fade would be a second one.
        var levelKey = r.mode + "\u0001" + (r.level === null ? "" : r.level);
        var sameLevel = levelKey === root._rowsLevel;
        root._rowsLevel = levelKey;
        var sections = Model.sectionsFor(rows, {
            mode: r.mode,
            grid: r.kind === "picker" || r.kind === "emoji",
            cells: r.appCount,
            searching: r.searching,
            level: r.level,
            levelLabel: (r.level !== null && root._nodes[r.level]) ? root._nodes[r.level].label : "",
            nodes: root._nodes
        });
        var byId = {};
        var ids = [];
        for (var i = 0; i < rows.length; i++) {
            var band = sections[i] || "";
            if (band === (i > 0 ? (sections[i - 1] || "") : ""))
                band = "";
            byId[rows[i].id] = { row: rows[i], section: band, sectionFirst: i === 0 };
            ids.push(String(rows[i].id));
        }
        var animate = sameLevel && !kindChanged && !root._rowsSettle;
        root._rowsPrev = animate ? root._rowsById : ({});
        root._rowsById = byId;
        root._displayRows = rows;
        root.rowSections = sections;
        root._appGridCount = r.appCount;
        root._emptyNote = r.empty;

        // A view swap detaches first, so the view going away never builds
        // delegates for the rows that are arriving for the other one.
        if (kindChanged)
            root._attachViews("");
        var grid = r.kind === "appGrid";
        var cellIds = r.kind === "app" ? [] : (grid ? ids.slice(0, r.appCount) : ids);
        var tailIds = grid ? ids.slice(r.appCount) : [];
        root._applyIds(rowsModel, root._rowsModelIds, cellIds, animate);
        root._rowsModelIds = cellIds;
        root._applyIds(tailModel, root._tailModelIds, tailIds, animate);
        root._tailModelIds = tailIds;
        root.viewKind = r.kind;
        root._attachViews(r.kind);

        if (fresh) {
            root._cursorPlaced = false;
            root._cursorWant = "";
        }
        var index = Nav.rederive(root._cursorWant, root._cursorIndex, ids, fresh, root._cursorPlaced);
        root._cursorKey = r.key;
        root._placeCursor(index, false);
        if (kindChanged || root._rowsSettle)
            root._scrollViewsHome();
    }

    // `held` is the ids the model holds, kept beside it rather than read
    // back out of it: a `get()` per row is an object per row, 3,944 of them
    // on every keystroke of an emoji browse.
    function _applyIds(model, held, ids, animate) {
        var plan = RowSync.plan(held, ids, root._rowResetLimit);
        if (!plan.reset && plan.ops.length === 0)
            return;
        if (plan.reset || !animate) {
            if (model === rowsModel)
                root._rowsAnimate = false;
            model.clear();
            // One append for the whole list rather than one per row: the
            // emoji route's browse is 3,944 of them.
            if (ids.length > 0)
                model.append(ids.map(function (id) { return { rowId: id }; }));
            return;
        }
        if (model === rowsModel)
            root._rowsAnimate = true;
        for (var i = 0; i < plan.ops.length; i++) {
            var op = plan.ops[i];
            if (op.op === "remove")
                model.remove(op.index);
            else if (op.op === "insert")
                model.insert(op.index, { rowId: op.id });
            else
                model.move(op.from, op.to, 1);
        }
    }

    // Only the view on screen holds a model. Assigned here rather than
    // bound, so the model a view holds and the rows in it change in the
    // one step that also places the cursor on them.
    function _attachViews(kind) {
        rowListView.model = kind === "rows" ? rowsModel : null;
        pickerGridView.model = kind === "picker" ? rowsModel : null;
        emojiGridView.model = kind === "emoji" ? rowsModel : null;
        appGrid.cellsModel = kind === "appGrid" ? rowsModel : null;
        appGrid.tailModel = kind === "appGrid" ? tailModel : null;
    }

    // The cursor's one writer. Every view's currentIndex is set here, after
    // the models it reads have changed: a keyed model moves a view's
    // currentIndex along with its current item on an insert or a move, and a
    // bound `currentIndex: _cursorIndex` never re-fires while the number
    // itself stays the same, which left the fill on one row and Enter on
    // another.
    function _placeCursor(index, travels) {
        var rows = root._displayRows;
        var valid = index >= 0 && index < rows.length;
        var k = root.viewKind;
        root._cursorTravels = travels;
        root._cursorIndex = valid ? index : 0;
        root._cursorId = valid ? String(rows[index].id) : "";
        root._cursorNode = valid ? rows[index] : null;
        rowListView.placeCursor(k === "rows" && valid ? index : -1);
        pickerGridView.placeCursor(k === "picker" && valid ? index : -1);
        emojiGridView.placeCursor(k === "emoji" && valid ? index : -1);
        appGrid.placeCursor(k === "appGrid" && valid ? index : -1);
    }

    function _scrollViewsHome() {
        rowListView.scrollHome();
        pickerGridView.scrollHome();
        emojiGridView.scrollHome();
        appGrid.scrollHome();
    }

    // A wheel glide still running writes contentY on every frame, over the
    // position a keyboard move just scrolled its view to.
    function _cancelGlides() {
        rowListView.cancelGlide();
        pickerGridView.cancelGlide();
        emojiGridView.cancelGlide();
        appGrid.cancelGlide();
    }

    // Where the live view's current item actually is, and which row its
    // model says that is, for `menu status`: the rig's check that what the
    // view draws the cursor on is the row Enter acts on.
    function viewCursor() {
        var k = root.viewKind;
        var cell = k === "rows" ? rowListView.cursorReport()
            : (k === "picker" ? pickerGridView.cursorReport()
                : (k === "emoji" ? emojiGridView.cursorReport()
                    : (k === "appGrid" ? appGrid.cursorReport() : null)));
        if (!cell)
            return { view: k, index: -1, id: "" };
        return {
            view: k, index: cell.index, id: cell.id,
            top: cell.top === undefined ? -1 : cell.top,
            bottom: cell.bottom === undefined ? -1 : cell.bottom,
            viewport: cell.viewport === undefined ? -1 : Math.round(cell.viewport)
        };
    }

    // shadcn's `CommandEmpty`. Never in input mode, whose row list is empty
    // by design, and never on an app view, which is its own whole surface.
    readonly property bool _showEmpty: root._mode !== "input" && !root._isAppView
        && root._displayRows.length === 0

    // The provider's own note when the level has one instead of rows (see
    // `_resolve`), committed with the rows by `_syncRows`.
    property var _emptyNote: null

    // What the empty body says: the provider's own note in its own words,
    // or that the query found nothing, naming the query.
    readonly property string _emptyTitle: root._emptyNote
        ? root._emptyNote.label
        : (searchInput.text.length > 0 ? "No results for \u201C" + searchInput.text + "\u201D" : "No results")
    readonly property string _emptyDetail: root._emptyNote ? (root._emptyNote.desc || "") : ""

    // Split-pane preview content (M30), derived from the cursor row: a
    // note row (clipboardEmptyRow/clipboardNoMatchRow) renders an empty
    // pane, an image row (thumbSource set) renders the full image, and
    // everything else renders the full text. Read only while
    // _isSplitRoute's own pane is visible, but cheap enough to leave bound
    // unconditionally rather than gating the bindings themselves.
    readonly property bool _previewIsNote: !!root._cursorNode && root._cursorNode.kind === "note"
    readonly property bool _previewIsImage: !!root._cursorNode && !root._previewIsNote && (root._cursorNode.thumbSource || "") !== ""
    readonly property bool _previewIsText: !!root._cursorNode && !root._previewIsNote && !root._previewIsImage

    // What the two preview slots draw, held past the row that put it there
    // (M53 D3). An image row carries no `fullText` and a text row no
    // `thumbSource`, so a slot reading the cursor row directly empties in the
    // same tick the cursor leaves it and there is nothing left to fade: the
    // slot going out would spend its crossfade blank. The same freeze on a
    // condition the card's own size morph takes, for the same reason.
    //
    // The image one is let go with the route rather than held forever: what
    // it holds is a decoded capture, and the pane it draws in is gone (M50
    // idle cost).
    property string _previewText: root._previewIsText ? (root._cursorNode.fullText || "") : _previewText
    property string _previewImageSource: root._previewIsImage
        ? "file://" + root._cursorNode.thumbSource
        : (root.isOpen && root._isSplitRoute ? _previewImageSource : "")
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
        pickerSelect: pickerProvider.mode === "select",
        // The variant Tab would switch TO, null wherever Tab does nothing.
        variantSwitch: root._isPickerRoute && pickerProvider.hasVariants
            ? (pickerProvider.variant === "dark" ? "light" : "dark")
            : null,
        confirming: root._confirmPendingId !== "" && !!root._cursorNode
            && root._cursorNode.id === root._confirmPendingId,
        // Gates the Shift+Enter hint: on a one-card machine the accelerator
        // falls through to a plain Enter, so advertising it would name a
        // key that does nothing of its own.
        discreteGpu: GpuService.defaultDiscrete() !== null,
        // The clipboard route's image rows, whose Shift+Enter sends the file
        // over ssh instead of copying it (_activateRowAlternate).
        clipsshImage: !!(root._cursorNode && root._cursorNode.clipsshPath)
    })

    // The level the card is on, for the back chip and the footer: its name
    // and its icon. The select and input modes have no tree level, so they
    // name themselves and hand their prompt to the field's placeholder.
    readonly property var _levelNode: root._mode === "menu" && root.currentNodeId !== null
        ? (root._nodes[root.currentNodeId] || null)
        : null
    readonly property string levelName: root._mode === "select"
        ? "Select"
        : (root._mode === "input" ? "Input" : (root._levelNode ? root._levelNode.label : "Launcher"))
    // An emoji tile is a picture with no room for a name, so the footer
    // names the one under the cursor, beside the route's own icon. The
    // dataset spells names the way Unicode does, in capitals, and the footer
    // is sentence case like every other line of copy.
    readonly property string _footerName: {
        if (!root._isEmojiGrid || !root._cursorNode)
            return root.levelName;
        var name = String(root._cursorNode.label || "").toLowerCase();
        return name.charAt(0).toUpperCase() + name.slice(1);
    }
    readonly property string _levelIcon: root._mode !== "menu"
        ? "list"
        : (root._levelNode
            ? (MenuIcons.iconFor(root._levelNode) || MenuIcons.fallbackFor(root._levelNode))
            : "search")

    // What the empty field says it is for: shadcn's Command line at the
    // root, the level's own prompt inside one (its `prompt` key, or "Search
    // <label>", Model.promptFor), and in select/input the caller's own
    // prompt, which is the whole of what those modes ask (M43 D5).
    readonly property string placeholder: {
        if (root._mode !== "menu")
            return root._selectPrompt;
        var node = root.currentNodeId !== null ? root._nodes[root.currentNodeId] : null;
        return node ? Model.promptFor(node) : "Type a command or search...";
    }

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }
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

    // `Card` insets its own slot by `panelPadding` on all four sides, so
    // every child below anchors straight to the slot's edges and this is
    // the width they get.
    readonly property real _contentWidth: root._cardWidth - Core.Theme.space.panelPadding * 2
    readonly property real _listWidth: (root._isSplitRoute
        ? Math.round(root._contentWidth / 2)
        : root._contentWidth) - root._bodySide * 2

    // The three bands (M72 T4). The header and the footer are each a
    // `controlHeight` row with the card's padding on both sides of it, and a
    // full-bleed rule on the body's side; the body is what is left.
    readonly property real _bandHeight: Core.Theme.space.controlHeight + Core.Theme.space.panelPadding * 2
        + Core.Theme.borderWidth
    readonly property real _chrome: root._bandHeight * 2

    // The card's settled height, one per level kind and never the rows':
    // results scroll inside a card that stays put, and the size morphs only
    // when the level changes what kind of view it draws. Capped at a share
    // of the output (`Theme.launcher`), a larger one for an app view, which
    // is a whole surface rather than a list. Input mode asks for a line and
    // nothing under it, so its body is empty.
    readonly property real _kindHeight: root._isAppView
        ? Core.Theme.space.popupHeightMenuApp
        : (root._isSplitRoute ? Core.Theme.space.popupHeightMenuSplit : Core.Theme.space.popupHeightMenu)
    readonly property real _heightCap: root._outputHeight > 0
        ? root._outputHeight * (root._isAppView ? Core.Theme.launcher.appHeightShare : Core.Theme.launcher.heightShare)
        : root._kindHeight
    readonly property real _bodyHeight: root._mode === "input"
        ? 0
        : Math.max(0, Math.min(root._kindHeight, root._heightCap) - root._chrome)

    // How far every view in the body sits in from the card's content edge,
    // the gutter a grid's tiles keep: the rows, the tiles, the headings, the
    // field and the footer all start on one column from it.
    readonly property real _bodySide: Core.Theme.space.sm

    // The gap between a rule and the first or last thing in the body,
    // carried inside each view (its header and footer) so the content
    // scrolls right up to the rule rather than being cut short of it.
    readonly property real _bodyInset: Core.Theme.space.lg

    // How far the live view is scrolled, whichever of the five owns the
    // level. On `menu status` because a wheel notch is otherwise
    // unobservable from the rig: a screenshot shows different rows, but
    // nothing says the cursor stayed put rather than moved with them.
    readonly property real scrollTop: root._isPickerGrid
        ? pickerGridView.contentY - pickerGridView.originY
        : (root._isEmojiGrid
            ? emojiGridView.contentY - emojiGridView.originY
            : (root._isAppGrid
                ? appGrid.contentY
                : (root._isAppView
                    ? (root._appViewScroll ? root._appViewScroll.contentY : 0)
                    : rowListView.contentY - rowListView.originY)))

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
        // the search field off the top edge. `_heightCap` holds the card to
        // a share of the output, so this is a guard, not a normal path.
        if (maxTop < root._topInset)
            return Math.round(root._topInset);
        return Math.round(Math.max(root._topInset, Math.min(top, maxTop)));
    }

    // select()/input() answers go through `selectionChannel` (declared
    // above, beside the picker's own use of it) as `{token, value}` /
    // `{token, cancelled: true}` JSON at menuSelectionPath. Callers
    // poll/read the file themselves, see MenuIpc.qml's header comment for
    // the full contract.
    function _writeSelection(payload) {
        selectionChannel.writeFile(selectionChannel.menuSelectionPath, JSON.stringify(payload));
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
            selectionChannel.clearFile(selectionChannel.menuSelectionPath);
    }

    function open(route) {
        root._rowsSettle = true;
        root._abandonPendingSelect();
        // Fresh session: last session's condition results must not leak
        // into this one (a `when`/`checked` shell command can change
        // between opens, bluetooth power, mode toggle, device presence).
        conditions.reset();
        // "@state:" `checked` conditions are deliberately NOT cleared here:
        // they are never cached, resolving from conditions.stateSnapshot on
        // every evaluation.
        ClipsshService.reloadAliases();
        keybindsProvider.refresh();
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
        root._arrive();
    }

    // The last step of every open: one settled sync (the rows as they are
    // now, the cursor on the first of them, every view at its top) and the
    // field focused. isOpen has already flipped by here, which is what swaps
    // the closed launcher's empty clipboard and window lists for the live
    // ones, so the rows this commits are the ones the card arrives with.
    function _arrive() {
        root._syncRows();
        root._rowsSettle = false;
        Qt.callLater(function () { searchInput.forceActiveFocus(); });
    }

    function openSelect(prompt, options, token) {
        root._rowsSettle = true;
        root._beginSelectionRequest();
        root._mode = "select";
        root._selectPrompt = prompt;
        root._selectOptions = options;
        root._selectToken = token;
        root._confirmPendingId = "";
        searchInput.text = "";
        root.isOpen = true;
        root._arrive();
    }

    function openInput(prompt, token) {
        root._rowsSettle = true;
        root._beginSelectionRequest();
        root._mode = "input";
        root._selectPrompt = prompt;
        root._selectOptions = [];
        root._selectToken = token;
        root._confirmPendingId = "";
        searchInput.text = "";
        root.isOpen = true;
        root._arrive();
    }

    function close() {
        root._abandonPendingSelect();
        // isOpen drops before pickerProvider.leaveRoute() clears the
        // picker's own listing (M51 D5): the card's own height/width freeze
        // below reads isOpen at the instant it flips, and a route that
        // empties its content on the way out must not do so while that
        // freeze still thinks the surface is open.
        root.isOpen = false;
        pickerProvider.leaveRoute();
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
        conditions.evaluate(root._nodes);
    }

    function _completeSelect(value) {
        root._writeSelection({ token: root._selectToken, value: value });
        root._mode = "menu";
        root.close();
    }

    function _submitInput() {
        root._completeSelect(searchInput.text);
    }

    // Instant paste (an activated row carrying `pasteAfter`) and launch
    // feedback for app rows both live in PostActivation: the wtype spawn
    // gated on the window's own visible flip, and the toast that fires only
    // once a launch's grace period passes with nothing new on screen.
    PostActivation {
        id: postActivation
        windowVisible: root.visible
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

    // The same stand-in for Shift+Enter, the accelerator's own path
    // (_activateRowAlternate). An app view has no alternate of its own, so
    // it answers false rather than pressing its primary a second time under
    // another name.
    function activateAlternate(index) {
        if (!root.isOpen || root._isAppView)
            return false;
        root._activateRowAlternate(index);
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
            emojiProvider.ensureLoaded();
            return Providers.emojiRows(emojiProvider.list, emojiQuery, true, emojiProvider.uses, Date.now()).map(function (n) {
                return { id: n.id, label: n.label, icon: n.icon, kind: n.kind };
            });
        }
        // ":nix" narrows the same way, but the search is async: the first
        // call arms the debounce and returns the SEARCHING note row, the
        // smoke rig calls twice, reading the cached end state (result rows,
        // NO RESULTS, SEARCH FAILED) on the second pass.
        var nixQuery = Providers.nixTriggerQuery(q);
        if (nixQuery !== null) {
            nixProvider.requestWarm();
            nixProvider.requestSearch(nixQuery);
            return nixProvider.rowsFor(nixQuery).map(function (n) {
                return { id: n.id, label: n.label, desc: n.desc || "", kind: n.kind };
            });
        }
        // ":k" narrows the same way, so the smoke rig proves the route with
        // zero keyboard delivery: `debug query ':k spawn'`.
        var keysQuery = Keybinds.triggerQuery(q);
        if (keysQuery !== null) {
            keybindsProvider.refresh();
            return keybindsProvider.rowsFor(keysQuery).map(function (n) {
                return { id: n.id, label: n.label, desc: n.desc || "", kind: n.kind };
            });
        }
        conditions.evaluate(root._nodes);
        // iconSource rides along so the smoke rig can assert an app row's
        // themed icon resolved (or honestly didn't) without a screenshot,
        // and `section` so it can assert the rows came out one block per
        // heading, which `menu status`'s deduplicated list cannot say.
        var rows = Search.rank(root._nodes, q, conditions.condResults, root.currentNodeId).map(function (n) {
            return { id: n.id, label: n.label, kind: n.kind, iconSource: n.iconSource || "", checked: Toggles.checkedFor(n, conditions.stateSnapshot, conditions.checkedResults), section: Model.searchSectionOf(root._nodes, n) };
        });
        // Same CALC prepend as _displayRows' ranked branch, so the smoke
        // rig's `debug query "2+2*3"` proves the row without keyboard input.
        var calcRow = Calc.resultNode(q);
        if (calcRow)
            rows.unshift({ id: calcRow.id, label: calcRow.label, kind: calcRow.kind, section: Model.searchSectionOf(root._nodes, calcRow) });
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
        var changingLevel = id !== root.currentNodeId;
        if (id === "emoji")
            emojiProvider.ensureLoaded();
        var leavingPicker = root.currentNodeId === pickerProvider.routeId && id !== pickerProvider.routeId;
        root.currentNodeId = id;
        root._confirmPendingId = "";
        root._cursorFromKeys = true;
        searchInput.text = "";
        // A whole new row set arrives under an unmoved pointer, in or out.
        pointerGate.reset();
        if (leavingPicker)
            pickerProvider.leaveRoute();
        if (id === pickerProvider.routeId)
            pickerProvider.enterRoute();
        conditions.evaluate(root._nodes);
        // Query filtering never reaches this function, so a keystroke's
        // re-rank can't retrigger the entrance: only an actual level change
        // does, and only once per change.
        if (changingLevel)
            root._playLevelEnter();
    }

    function _pop() {
        if (root.currentNodeId === null) {
            root.close();
            return;
        }
        root._enterLevel(root._nodes[root.currentNodeId].parentId);
    }

    // The level/route entrance (DESIGN.md §1 Motion, M54 D8): the in half of
    // caelestia's loader swap, on `effects`, for whichever view stands in for
    // the row list. Separate from the card's own unfold above.
    //
    // A standalone animation rather than a Behavior: the endpoint is constant
    // whichever way the level moved, so a Behavior would see no value change
    // to react to on a repeat call in the same direction. restart() replays
    // from its own `from` every time, which is also what keeps a fast run of
    // navigation from queuing: the previous play is simply abandoned.
    property real _levelEnterOpacity: 1

    function _playLevelEnter() {
        levelEnter.restart();
    }

    // The swap's out half is not here: `_playLevelEnter` runs once the level
    // has already changed what the body draws. Only a level change plays it
    // (M72 T1): a view reached by typing (`:e `) swaps in place, since the
    // query that resolves it is the keystroke itself, and fading the body
    // out and back on a keystroke read as the launcher flickering.
    Anim {
        id: levelEnter
        target: root
        property: "_levelEnterOpacity"
        from: 0
        to: 1
        kind: "effects"
    }

    // Hover owns the cursor only while the pointer is the thing that moved.
    // Filtering re-renders the row list under a parked pointer on every
    // keystroke, and Qt hands the row that slid underneath a hover move
    // indistinguishable from a real one, which used to yank the keyboard
    // cursor to wherever the mouse happened to be sitting. Every keyboard
    // path below re-arms the gate; the first genuine pointer movement takes
    // the cursor straight back. The hover wash reads the gate's `live` for
    // the same reason, so a row sliding under the parked pointer is not lit
    // either.
    PointerMoveGate {
        id: pointerGate
    }

    // One navigation key's move (Menu/nav.js's `step`, which owns the
    // wraps). The cells are the whole list on the picker and emoji grids,
    // the app cells on the app grid, and none on a row list.
    function _moveCursor(dir) {
        var n = root._displayRows.length;
        if (n === 0) return;
        var cells = root._isAppGrid ? root._appGridCount : (root._isGrid ? n : 0);
        var next = Nav.step(root._cursorIndex, dir, n, cells, root.cursorColumns, root._pageStep());
        root._cancelGlides();
        root._placeCursor(next.index, next.travels);
        root._cursorPlaced = true;
        root._cursorWant = root._cursorId;
        root._confirmPendingId = "";
        root._cursorFromKeys = true;
        pointerGate.reset();
    }

    function _runKey(action) {
        // One step is one row, and a page keeps one row of overlap on an app
        // view, so the reader carries context across the jump.
        var row = Core.Theme.space.controlHeight;
        var page = root._appViewScroll ? Math.max(row, root._appViewScroll.height - row) : row;
        switch (action) {
        case "up":
        case "down":
        case "left":
        case "right":
        case "pageUp":
        case "pageDown":
        case "home":
        case "end":
            root._moveCursor(action);
            break;
        case "scrollUp":
            root._scrollAppViewBy(-row);
            break;
        case "scrollDown":
            root._scrollAppViewBy(row);
            break;
        case "scrollPageUp":
            root._scrollAppViewBy(-page);
            break;
        case "scrollPageDown":
            root._scrollAppViewBy(page);
            break;
        case "scrollHome":
            root._scrollAppViewTo(0);
            break;
        case "scrollEnd":
            root._scrollAppViewTo(root._appViewScroll.contentHeight);
            break;
        case "activate":
            root._activateRow(root._cursorIndex);
            break;
        case "activateAlternate":
            root._activateRowAlternate(root._cursorIndex);
            break;
        case "submit":
            root._submitInput();
            break;
        case "clear":
            searchInput.text = "";
            break;
        case "pop":
            root._pop();
            break;
        // select/input have no tree level to pop out of: close() writes the
        // caller's {cancelled:true} record via _abandonPendingSelect().
        case "close":
            root.close();
            break;
        case "variant":
            root.setPickerVariant(pickerProvider.variant === "dark" ? "light" : "dark");
            break;
        }
    }

    // How many entries one PageUp/PageDown moves: as many rows as the view
    // shows, or as many whole rows of cells.
    function _pageStep() {
        var h = root._bodyHeight;
        if (root._isPickerGrid)
            return Math.max(1, Math.floor(h / pickerGridView.cellHeight)) * pickerGridView.columns;
        if (root._isEmojiGrid)
            return Math.max(1, Math.floor(h / emojiGridView.cellHeight)) * emojiGridView.columns;
        if (root._isAppGrid && root._cursorIndex < root._appGridCount)
            return Math.max(1, Math.floor(h / appGrid.cellHeight)) * appGrid.columns;
        return Math.max(1, Math.floor(h / Core.Theme.space.controlHeight));
    }

    function _setCursor(index) {
        if (index === root._cursorIndex) return;
        // The pointer names a row outright rather than stepping to it, and
        // it can arrive on any row in the list from outside it.
        root._placeCursor(index, false);
        root._cursorPlaced = true;
        root._cursorWant = root._cursorId;
        root._confirmPendingId = "";
        root._cursorFromKeys = false;
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
            // An emoji copy is a use of that emoji, recorded on the same
            // Enter that copies it (providers.js's emojiUsageId owns the id
            // both sides spell). Nothing else in the tree carries that
            // prefix, and the record lands after the action so the reorder
            // it triggers cannot move the row out from under this call.
            if (String(node.id).indexOf("emoji.") === 0)
                Core.State.setEmojiUses(Frecency.record(Core.State.emojiUses, node.id, Date.now()));
            // Launch acknowledgment (nix rows): the spawned terminal can be
            // seconds from mapping, so rows carrying notifySummary get a
            // shell-local toast the moment Enter lands.
            if (node.notifySummary)
                NotificationService.notify(node.notifySummary, node.notifyBody || "");
            if (node.pasteAfter === true)
                postActivation.armPaste();
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
            // block, so the count postActivation.beginLaunchWatch reads is
            // genuinely the "before". execute() stays exactly as it was,
            // the entry's own Exec field codes and quoting only survive
            // that path (see providers.js's header), so the feedback wraps
            // it rather than routing around it.
            postActivation.beginLaunchWatch(node.label);
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

    // The Shift+Enter accelerator, and every row kind that answers to it.
    // Falls through to plain _activateRow for the rest: never a no-op that
    // silently does nothing.
    //
    // An app row (M38 Task 8) launches on the default discrete card instead
    // of normally, anywhere in the launcher an app row appears.
    //
    // A clipboard image row (M50) goes over ssh instead of onto the
    // clipboard. clipssh reads the clipboard and nothing else, so the file
    // has to be on it either way; the difference is who names the host.
    // With one resolved (`clipssh.alias`, or the only alias saved)
    // ClipsshService does both in one child and the launcher closes behind
    // it. With none resolved the file is copied here and the launcher drills
    // into the alias route, whose Enter is already this exact send: that is
    // the "ask every time" case, and it is also what a store with no aliases
    // at all gets, since the route's own empty row carries the add command.
    function _activateRowAlternate(index) {
        if (root._isAppView) return;
        var rows = root._displayRows;
        var node = (index >= 0 && index < rows.length) ? rows[index] : null;
        if (node && node.clipsshPath) {
            var alias = ClipsshService.resolveAlias();
            if (alias !== "") {
                ClipsshService.sendImage(alias, node.clipsshPath);
                root.close();
            } else {
                // The row's own copy action rather than a slice of its id:
                // one place decides what a clipboard row copies.
                root._runAction(node.action);
                root._enterLevel("clipssh");
            }
            return;
        }
        var card = GpuService.defaultDiscrete();
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
        // `nix run` goes to the console's own terminal and placement rather
        // than a bare spawn: the package is a program the reader wants to
        // watch, and a drop-down over the current workspace is where this
        // shell already puts one. `read` holds the window after it exits so
        // its last output is still readable.
        if (name.indexOf("nix.run:") === 0) {
            ConsoleService.runOnce("nix run nixpkgs#" + name.slice("nix.run:".length) + "; read");
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
            ThemeEngine.requestMode("toggle");
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

    // Shell-condition batch (`when`/`checked` for every node in the tree)
    // and the toggle snapshot ("@state:" `checked` conditions) both live in
    // ConditionEvaluator.
    ConditionEvaluator {
        id: conditions
    }

    Component.onCompleted: {
        if (Quickshell.env("FORMALSHELL_SMOKE_OPEN_MENU") === "1")
            root.open();
    }

    screen: root._screen
    // Held visible through the exit fade (DESIGN.md §1 Motion): close()
    // drops isOpen, presence's own Behavior runs its progress to 0, and
    // only then does the window unmap. Keyboard exclusivity releases on
    // isOpen itself, so nothing types into a fading-out menu, and the
    // paste settle timer still keys off the real visible flip below,
    // exactly as before, just one exit fade later. The window is
    // transparent so the fade covers the whole card; card paints its own
    // background.
    visible: drawer.presence.shown
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
    readonly property real _cardHeight: root._chrome + root._bodyHeight

    // The card's actual width and height (Components/SizeMorph.qml, M57 D7):
    // _cardWidth/_cardHeight above are the level kind's own target, and a
    // level that changes kind travels into it instead of jumping.
    readonly property real _morphWidth: morphWidth.value
    readonly property real _morphHeight: morphHeight.value

    SizeMorph {
        id: morphWidth
        target: root._cardWidth
        open: root.isOpen
        mapped: root.backingWindowVisible
    }

    SizeMorph {
        id: morphHeight
        target: root._cardHeight
        open: root.isOpen
        mapped: root.backingWindowVisible
    }

    WlrLayershell.namespace: "formalshell:menu"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    // The modal scrim (Components/Scrim.qml): on the drawer's own pose, and
    // off the band the top line belongs to for as long as the card is still
    // budding out of it, so the launcher comes out of a lit bar.
    Scrim {
        anchors.fill: parent
        drawer: drawer
    }

    // Click-to-dismiss on the menu's OWN output. DismissTwins below has
    // always covered every other screen; this output had no backdrop to
    // click at all until the window went full-output, so Escape was the only
    // way out for a pointer user. Declared before the drawer, so the card and
    // every cell in it stack above and keep their own clicks.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }

    // Everything from the top line to the card's own padding is the drawer's
    // (Components/Drawer.qml, M57 D5): the slit, the emerge, the join, the
    // deform and the shape. The launcher is a centre-floating card, so the
    // line it buds off is the top bar's hairline, the frame ring's top line,
    // or the output's own top edge with neither, and the depth back to it is
    // hundreds of pixels rather than a panel's seven. What it states is the
    // edge and the rect; the drawer derives the rest.
    //
    // 0.1 for the deform, caelestia's own launcher figure: the card travels a
    // long way in one open and a popout's 0.15 would fold the field's text
    // into itself.
    Drawer {
        id: drawer
        anchors.fill: parent
        // What every cell in the card reads for whether its ring draws
        // (cursor.js's `ringOwner` walk).
        property bool cursorFromKeys: root._cursorFromKeys
        owner: root
        open: root.isOpen
        mapped: root.backingWindowVisible
        edge: "top"
        screen: root._screen
        rect: Qt.rect(Math.round((root._outputWidth - root._morphWidth) / 2),
            root._clampTop(root._preferredTop), root._morphWidth, root._morphHeight)
        deformAmount: 0.1
        moving: morphWidth.running || morphHeight.running

        // The header band (M72 T4): inside a level, a back chip carrying the
        // level's icon and name; the search field itself, borderless and a
        // type step above the rows; the close button. A `controlHeight` row,
        // the same one a panel's header is.
        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Core.Theme.space.controlHeight

            // Backspace on an empty field pops the level as well; this is
            // the pointer's way up, and the reader's note of where they are.
            Button {
                id: backChip
                anchors.left: parent.left
                anchors.leftMargin: root._bodySide
                anchors.verticalCenter: parent.verticalCenter
                visible: root._mode === "menu" && root.currentNodeId !== null
                variant: "outline"
                icon: root._levelIcon
                text: root.levelName
                labelBudget: Math.round(root._contentWidth / 3)
                tooltipText: "Back"
                onClicked: root._pop()
            }

            TextInput {
                id: searchInput
                anchors.left: backChip.visible ? backChip.right : parent.left
                anchors.leftMargin: backChip.visible
                    ? Core.Theme.space.iconGap
                    : root._bodySide + Core.Theme.space.controlPaddingX
                anchors.right: closeButton.left
                anchors.rightMargin: Core.Theme.space.iconGap
                anchors.verticalCenter: parent.verticalCenter
                color: Core.Theme.color.foreground
                font.family: Core.Theme.fontFamilySans
                font.pixelSize: Core.Theme.fontSize.subtitle
                // The field's own selection is the `input` role's, the same
                // one every `Input` in the shell paints.
                selectionColor: Core.Theme.box("input.selection").fill
                selectedTextColor: Core.Theme.color.primaryForeground
                clip: true
                focus: true
                selectByMouse: true
                cursorVisible: true

                Text {
                    anchors.fill: parent
                    visible: searchInput.text.length === 0
                    text: root.placeholder
                    color: Core.Theme.color.mutedForeground
                    font: searchInput.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                onTextChanged: {
                    root._confirmPendingId = "";
                    // Loaded here and in `_enterLevel`, never from inside
                    // `_resolved`: the first load lands `emojiProvider.list`
                    // while that binding is still evaluating, which Qt
                    // reports as a binding loop and refuses to re-run.
                    if (root._mode === "menu" && Providers.emojiTriggerQuery(searchInput.text) !== null)
                        emojiProvider.ensureLoaded();
                    // Typing re-ranks the rows under a pointer that hasn't
                    // moved, the churn the gate exists for.
                    pointerGate.reset();
                    // Arm the debounced nix search from the event, never
                    // from the _displayRows binding (side effect).
                    if (root._mode === "menu") {
                        var nixQuery = Providers.nixTriggerQuery(searchInput.text);
                        if (nixQuery === null && root.currentNodeId === "nix")
                            nixQuery = searchInput.text;
                        if (nixQuery !== null) {
                            nixProvider.requestWarm();
                            nixProvider.requestSearch(nixQuery);
                        }
                    }
                }

                // Menu/nav.js's `keyAction` decides what a key means;
                // whatever it passes is the field's own, which is how
                // Ctrl+Left/Right and Ctrl+Backspace edit the query while the
                // plain arrows walk the results.
                Keys.onPressed: event => {
                    // An app view with its own cursor gets first refusal
                    // on every key (root._appViewKey's own note).
                    if (root._appViewKey(event.key, event.modifiers)) {
                        event.accepted = true;
                        return;
                    }
                    var action = Nav.keyAction(event.key, event.modifiers, event.isAutoRepeat, {
                        mode: root._mode,
                        query: searchInput.text.length > 0,
                        grid: root._isGrid,
                        appView: root._isAppView,
                        scrollable: root._appViewScroll !== null,
                        variants: root._isPickerRoute && pickerProvider.hasVariants
                    });
                    if (action === "pass")
                        return;
                    event.accepted = true;
                    root._runKey(action);
                }
            }

            IconButton {
                id: closeButton
                anchors.right: parent.right
                anchors.rightMargin: root._bodySide
                anchors.verticalCenter: parent.verticalCenter
                name: "x"
                tooltipText: "Close"
                onClicked: root.close()
            }
        }

        // Full-bleed, a panel header's own seam: the card's padding is
        // bought back out by negative margins, so the rule divides the card
        // rather than the rows.
        Separator {
            id: headerRule
            anchors.top: header.bottom
            anchors.topMargin: Core.Theme.space.panelPadding
            anchors.left: parent.left
            anchors.leftMargin: -drawer.padding
            anchors.right: parent.right
            anchors.rightMargin: -drawer.padding
        }

        // The body: every view the level can draw, one of them live, between
        // the two rules. Everything in it is one item, so the level entrance
        // is one arrival. Its height is the card's settled one rather than
        // the morph's, so a growing card reveals a laid-out level instead of
        // dragging the footer down through the rows.
        Item {
            id: levelBody
            anchors.top: headerRule.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: root._bodyHeight
            visible: root._bodyHeight > 0
            // The level entrance (M54 D8): plays when the level changes,
            // never on a query re-rank.
            opacity: root._levelEnterOpacity

            // The wallpaper route's Dark | Light switcher (spec "Picker"):
            // the `Segmented` primitive, at the head of the body. Absent
            // entirely (zero height) for a directory with no Dark/Light pair
            // and on every other route.
            Segmented {
                id: variantRow
                readonly property bool wanted: root._isPickerRoute && pickerProvider.hasVariants

                anchors.top: parent.top
                anchors.topMargin: variantRow.wanted ? root._bodyInset : 0
                anchors.left: parent.left
                anchors.leftMargin: root._bodySide
                height: variantRow.wanted ? implicitHeight : 0
                visible: variantRow.wanted || variantRow.height > 0
                clip: true
                options: ["Dark", "Light"]
                onChanged: i => root.setPickerVariant(i === 1 ? "light" : "dark")

                Behavior on height {
                    enabled: root.isOpen && drawer.presence.mapped
                    Anim {}
                }
            }

            // The variant belongs to the route, not to the control: Tab and
            // `picker variant` over IPC move it too, and Segmented writes its
            // own `index` on click, which a plain binding would not survive.
            Binding {
                target: variantRow
                property: "index"
                value: pickerProvider.variant === "light" ? 1 : 0
            }

            // The row list (M53 D4, M53 D6): one cursor box travelling between
            // rows and a keyed model so a row survives a re-rank.
            RowListView {
                id: rowListView
                anchors.top: variantRow.bottom
                anchors.left: parent.left
                anchors.leftMargin: root._bodySide
                // Split route (M30): the list keeps the left half so the
                // preview pane beside it can own the right one.
                width: root._listWidth
                anchors.bottom: parent.bottom
                inset: root._bodyInset
                visible: root.viewKind === "rows"
                rowsById: root._rowsById
                rowsPrev: root._rowsPrev
                blankRow: root._blankRow
                cursorIndex: root._cursorIndex
                cursorTravels: root._cursorTravels
                rowsAnimate: root._rowsAnimate
                hoverGate: pointerGate
                stateSnapshot: conditions.stateSnapshot
                checkedResults: conditions.checkedResults
                confirmPendingId: root._confirmPendingId
                onActivated: index => root._activateFromPointer(index)
                onCursorRequested: index => root._setCursor(index)
            }

            // shadcn's `CommandEmpty` (M48 D6), in the body rather than as a
            // row of the list: it answers nothing, and a cursor sitting on it
            // would offer a verb the footer would then have to take back.
            // The provider's own note when the level has one, in its words.
            Column {
                id: emptyState
                anchors.centerIn: parent
                width: parent.width - Core.Theme.space.panelPadding * 2
                spacing: Core.Theme.space.rowGap
                // Rises over the rows leaving through their own remove
                // transition rather than landing on the frame they filled.
                opacity: root._showEmpty ? 1 : 0
                visible: emptyState.opacity > 0
                Behavior on opacity {
                    Anim { kind: "effects" }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: root._emptyTitle
                    textFormat: Text.PlainText
                    color: Core.Theme.color.mutedForeground
                    font.family: Core.Theme.fontFamilySans
                    font.pixelSize: Core.Theme.fontSize.body
                }

                // A detail is a command or a path, so mono.
                Text {
                    width: parent.width
                    visible: root._emptyDetail !== ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: root._emptyDetail
                    textFormat: Text.PlainText
                    color: Core.Theme.color.mutedForeground
                    font.family: Core.Theme.fontFamilyMono
                    font.pixelSize: Core.Theme.fontSize.caption
                }
            }

            // The wallpaper route's grid (spec §11), the picker's own
            // surface, one of the launcher's views over the same rows and
            // cursor rather than a panel of its own.
            PickerGridView {
                id: pickerGridView
                anchors.top: variantRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                inset: root._bodyInset
                visible: root._isPickerGrid
                rowsById: root._rowsById
                rowsPrev: root._rowsPrev
                cursorIndex: root._cursorIndex
                cursorTravels: root._cursorTravels
                hoverGate: pointerGate
                pixelRatio: root.screen ? root.screen.devicePixelRatio : 1
                onActivated: index => root._activateFromPointer(index)
                onCursorRequested: index => root._setCursor(index)
            }

            // The emoji route's grid (M48 D5). A second grid rather than a
            // kind-branching delegate inside the one above: the two share
            // their geometry and their cursor, and nothing else. The cursor
            // tile's name is the footer's, where the picked row's verb is.
            EmojiGridView {
                id: emojiGridView
                anchors.top: variantRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                inset: root._bodyInset
                visible: root._isEmojiGrid
                rowsById: root._rowsById
                rowsPrev: root._rowsPrev
                cursorIndex: root._cursorIndex
                cursorTravels: root._cursorTravels
                hoverGate: pointerGate
                onActivated: index => root._activateFromPointer(index)
                onCursorRequested: index => root._setCursor(index)
            }

            // The app grid (M58): the level's app rows as icons with their
            // names under them, the rest of what ranked as rows beneath, each
            // block under its own heading.
            AppGridView {
                id: appGrid
                anchors.top: variantRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                inset: root._bodyInset
                visible: root._isAppGrid
                rowsById: root._rowsById
                rowsPrev: root._rowsPrev
                blankRow: root._blankRow
                appCount: root._appGridCount
                cellsHeading: root._appGridCount > 0 ? (root.rowSections[0] || "") : ""
                cursorTravels: root._cursorTravels
                hoverGate: pointerGate
                stateSnapshot: conditions.stateSnapshot
                checkedResults: conditions.checkedResults
                confirmPendingId: root._confirmPendingId
                pixelRatio: root.screen ? root.screen.devicePixelRatio : 1
                onActivated: index => root._activateFromPointer(index)
                onCursorRequested: index => root._setCursor(index)
            }

            // An app view (M38, D1): a whole component in place of the row
            // list, for any route Menu/appviews.js registers, inset from the
            // rules like every other view's content.
            //
            // `source` empties off the route rather than the loader merely
            // hiding: an app view holds a live subscription to whatever
            // service it renders. It empties on the window going away too,
            // since close() leaves currentNodeId where it was; keyed off the
            // window's own `visible` rather than `isOpen` so the view
            // survives the exit fade instead of blanking the card mid-way.
            Loader {
                id: appView
                anchors.fill: parent
                anchors.topMargin: root._bodyInset
                anchors.bottomMargin: root._bodyInset
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
            // full content in the launcher's one inner `Card`, a `sm` gutter
            // off the list and the body's inset off both rules.
            SplitPreview {
                id: previewPane
                visible: root._isSplitRoute
                anchors.top: parent.top
                anchors.topMargin: root._bodyInset
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root._bodyInset
                anchors.left: rowListView.right
                anchors.leftMargin: Core.Theme.space.sm
                anchors.right: parent.right
                anchors.rightMargin: root._bodySide
                previewKind: root._previewKind
                previewTime: root._previewTime
                isText: root._previewIsText
                text: root._previewText
                isImage: root._previewIsImage
                imageSource: root._previewImageSource
                pixelRatio: root.screen ? root.screen.devicePixelRatio : 1
            }
        }

        Separator {
            id: footerRule
            anchors.top: levelBody.bottom
            anchors.left: parent.left
            anchors.leftMargin: -drawer.padding
            anchors.right: parent.right
            anchors.rightMargin: -drawer.padding
            visible: root._bodyHeight > 0
        }

        // The footer band (M72 T4): where you are, and what Enter does.
        MenuFooter {
            id: menuFooter
            anchors.top: root._bodyHeight > 0 ? footerRule.bottom : headerRule.bottom
            anchors.topMargin: Core.Theme.space.panelPadding
            anchors.left: parent.left
            anchors.leftMargin: root._bodySide
            anchors.right: parent.right
            anchors.rightMargin: root._bodySide
            height: Core.Theme.space.controlHeight
            levelIcon: root._levelIcon
            levelName: root._footerName
            primary: root._actionBar.primary
            hints: root._actionBar.hints

            // Clicking the verb is the pointer acting, exactly like clicking
            // the row itself: same path, same gate re-arm. On an app view it
            // presses that view's own primary instead, at whatever its
            // cursor already is (index -1).
            onPrimaryActivated: {
                if (root._isAppView) {
                    if (appView.item && appView.item.viewActivate)
                        appView.item.viewActivate(-1);
                    return;
                }
                root._activateFromPointer(root._cursorIndex);
            }
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
