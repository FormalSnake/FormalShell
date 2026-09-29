import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Services
import "../../Components/cursor.js" as Cursor
import "switcher.js" as Model

// The Alt+Tab switcher, after Gala's (`src/Widgets/WindowSwitcher/
// WindowSwitcher.vala`, `WindowSwitcherIcon.vala`; M60 T6) for its behaviour
// and Windows' for its cells (owner, 2026-09-29): the windows as live
// thumbnails on one card in the middle of the output, each with its app icon
// and title under it and the selected one under the cursor. The thumbnails
// are Components/WindowThumb.qml, captured only while the card is up. Keyboard only, and
// summoned over IPC alone
// (`switcher next|prev|commit|cancel|state`), so the compositor's own bind
// drives it: Alt+Tab advances (the binds repeat, so a held Tab walks on),
// the release of the modifier commits, and nothing here ever grabs a
// modifier of its own. The card maps only once `_showTimer` runs out, so a
// quick Alt+Tab switches with no card at all, as Cmd+Tab does on macOS. That release bind has to
// carry Hyprland's `t` flag (`bindrt`, M64): a bind whose key is held while
// another bind fires is shadowed for as long as that key stays down, and a
// transparent bind is the only kind `shadowKeybinds` leaves alone
// (docs/examples/hyprland/formalshell.lua).
//
// One instance rather than one per output, the same reasoning Menu, Center
// and Osd carry: it is summoned rather than resident, it lands on the
// focused output at summon time, and one card at a time is what a switcher
// with a single cursor means. Instantiated unless `switcher.enabled` is
// false (shell.qml's Loader), under every theme alike: the table styles the
// card, its tiles and its fade, and nothing here reads a theme.
PanelWindow {
    id: root

    // A switch is under way: from the first `next`/`prev` to the commit or
    // the cancel. The card itself only maps once `_shown` flips, which a
    // quick Alt+Tab never waits for (macOS's Cmd+Tab: a tap switches with no
    // card at all).
    property bool isOpen: false
    property bool _shown: false
    readonly property bool shown: root._shown
    // How many times the card has mapped since startup, for `switcher
    // state`: a fast tap leaves it where it was.
    property int shows: 0
    // Set one frame after the card maps: the thumbnails' captures attach to a
    // card already on screen with its icons, never ahead of it.
    property bool _capturing: false

    // Which entry the cursor sits on. Held across a close so nothing reads a
    // stale index mid-exit; every open sets it before flipping `isOpen`.
    property int index: 0

    // The ids this session has watched take focus, newest first. The
    // compositor reports no focus history of its own, and it is what makes a
    // single Alt+Tab land on the window you just came from.
    property var _history: []
    // The snapshot of that history one switch runs against: the compositor
    // drops its focused window the moment this surface takes the keyboard,
    // and a live order would then reshuffle the row under the cursor.
    property var _openHistory: []
    // And the workspace it runs against, taken at the same instant and for
    // the same reason: the row is the windows on one workspace, and which
    // one is decided when the card opens rather than followed afterwards.
    property string _openWorkspaceId: ""

    property bool _focusPrimed: false

    // Set when a commit arrives with nothing open (M64 addendum, owner
    // 2026-09-18): the compositor spawns `next` and `commit` as two
    // independent `qs ipc call` processes, one per bind, with no ordering
    // guarantee over which reaches the ipc socket first. A fast enough
    // Alt+Tab can have the release's process win that race, and a commit
    // that just failed silently would leave `next` to open the card on an
    // Alt already gone, stuck until Esc or Enter. `_commitRaceTimer`'s
    // window is far past any ipc scheduling jitter this rig or a real host
    // has shown and far short of the gap between two distinct gestures, so
    // it never couples an unrelated bare Alt tap to a later Alt+Tab.
    property bool _commitPending: false
    property real _committedAt: 0

    readonly property var entries: Model.entries(CompositorService.windows,
        root._openHistory, root._openWorkspaceId)
    readonly property int count: root.entries.length
    readonly property var selected: (root.count > 0 && root.index < root.count)
        ? root.entries[root.index] : null
    readonly property string selectedId: root.selected ? root.selected.id : ""
    readonly property string selectedTitle: root.selected ? root.selected.title : ""

    // The icon chain past a window's class reads its `pid` and
    // `initialTitle`, which Hyprland reports for a window opened since
    // startup only after a refresh. Both are reads: nothing about the row,
    // its order or the cursor waits on them, and a tile repaints when they
    // land.
    onIsOpenChanged: if (root.isOpen) {
        CompositorService.refreshWindows();
        AppIconService.probe(root.entries);
    }
    onEntriesChanged: if (root.isOpen) AppIconService.probe(root.entries)

    Connections {
        target: CompositorService

        function onFocusedWindowIdChanged() {
            var id = CompositorService.focusedWindowId;
            if (id === "")
                return;
            var next = [id];
            for (var i = 0; i < root._history.length && next.length < 32; i++) {
                if (root._history[i] !== id)
                    next.push(root._history[i]);
            }
            root._history = next;
        }
    }

    // `next` and `prev` are the whole summon path: the first press opens the
    // card with the cursor one step along, which is the window before the
    // focused one, and every press after that walks the row. A workspace
    // holding one window wraps that step straight back onto it, so a tap too
    // quick to read the card leaves focus where it already was rather than
    // taking the compositor somewhere else.
    function step(direction) {
        if (!root.isOpen) {
            // The same race the other way round: with Tab held the bind
            // repeats, and a repeat spawned just before Alt came up can land
            // after the commit. Opening on it would leave a card up with no
            // modifier held; no new gesture starts this soon after a release.
            if (Date.now() - root._committedAt < _commitRaceTimer.interval)
                return;
            root._openHistory = root._history;
            // Every workspace unless `switcher.currentWorkspace` asks for
            // Gala's list: a desk that keeps one app per workspace has one
            // window on the focused one, and a switcher offering that alone
            // switches nothing (owner, 2026-09-18).
            root._openWorkspaceId = Config.get("switcher.currentWorkspace", false)
                ? CompositorService.focusedWorkspaceId : "";
            root.index = Model.advance(0, root.count, direction);
            root._focusPrimed = false;
            root.isOpen = true;
            _showTimer.restart();
            // The release that opened this got here first (see
            // `_commitPending`'s header): commit against the row this open
            // just built instead of leaving the card up with nothing
            // holding the modifier any more.
            if (root._commitPending) {
                root._commitPending = false;
                _commitRaceTimer.stop();
                root._commitNow();
            }
            return;
        }
        root.index = Model.advance(root.index, root.count, direction);
    }

    Timer {
        id: _commitRaceTimer
        interval: 80
        onTriggered: root._commitPending = false
    }

    // The delay before the card maps, macOS's: long enough that a tap
    // commits before it runs out, short enough that a held Alt reads as
    // instant.
    Timer {
        id: _showTimer
        interval: 150
        onTriggered: if (root.isOpen) root._show()
    }

    function _show() {
        root._shown = true;
        root.shows++;
        root._beginFocusPrime();
        Qt.callLater(function () { backdrop.forceActiveFocus(); });
    }

    // The selected window through the backend's own focus verb, on the
    // opaque id the compositor handed over (CLAUDE.md: never parsed, never
    // compared numerically).
    function commit() {
        if (root.isOpen)
            return root._commitNow();
        // Bound to the release of a modifier, so it arrives on every tap of
        // that key, open or not; a bare tap resolves as the no-op it always
        // was once `_commitRaceTimer` runs out with no `next`/`prev` to
        // catch.
        root._commitPending = true;
        _commitRaceTimer.restart();
        return true;
    }

    function _commitNow() {
        var id = root.selectedId;
        var primed = root._focusPrimed;
        var shown = root._shown;
        root.close();
        root._committedAt = Date.now();
        if (id === "")
            return false;
        // A commit inside the prime window lands while this layer still holds
        // the keyboard exclusively, and Hyprland hands focus back to the
        // window it came from once the layer lets go, undoing the switch. One
        // dispatch after that release rather than one either side of it: two
        // make the compositor start its animation, reverse it and start again.
        // A card that never mapped never took the keyboard, so there is
        // nothing to wait out.
        if (primed || !shown) {
            CompositorService.focusWindow(id);
        } else {
            root._refocusId = id;
            _refocusTimer.restart();
        }
        return true;
    }

    property string _refocusId: ""

    Timer {
        id: _refocusTimer
        interval: 80
        onTriggered: {
            if (!root.isOpen && root._refocusId !== "")
                CompositorService.focusWindow(root._refocusId);
            root._refocusId = "";
        }
    }

    function close() {
        _showTimer.stop();
        root.isOpen = false;
        root._shown = false;
    }

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    readonly property real _outputWidth: root._screen ? root._screen.width : 0
    readonly property real _outputHeight: root._screen ? root._screen.height : 0

    // One cell: a thumbnail of `switcherThumb` height at its window's own
    // aspect, its caption under it, `panelPadding` on all four sides (the same
    // 12 the card keeps around its own contents). The cells touch, so the
    // padding is the gap the row reads as. The --switcher leg reads the cells
    // off `switcher state`, so nothing in it hardcodes a pixel.
    readonly property real _thumbHeight: Theme.space.switcherThumb
    readonly property real _captionIcon: Theme.space.iconGap * 2
    readonly property real _captionHeight: Math.max(root._captionIcon, captionMetric.implicitHeight)
    readonly property real _cellHeight: root._thumbHeight + Theme.space.iconGap
        + root._captionHeight + Theme.space.panelPadding * 2

    // How wide a row may run: the output minus the room the card keeps off
    // both edges and its own padding.
    readonly property real _maxRowWidth: Math.max(0,
        root._outputWidth - (Theme.space.switcherInset + Theme.space.panelPadding) * 2)

    readonly property var _thumbWidths: root.entries.map(function (win) {
        return Model.thumbWidth(win.rect, root._thumbHeight, root._thumbHeight / 2,
            Math.max(root._thumbHeight / 2, Math.min(root._thumbHeight * 3,
                root._maxRowWidth - Theme.space.panelPadding * 2)));
    })
    readonly property var _layout: Model.layout(root._thumbWidths.map(function (width) {
        return width + Theme.space.panelPadding * 2;
    }), 0, root._maxRowWidth)
    readonly property var _cells: Model.cells(root._layout, root._cellHeight)

    readonly property real _gridWidth: root.count > 0 ? root._layout.width : 0
    readonly property real _gridHeight: root._layout.rows.length > 0
        ? root._layout.rows.length * root._cellHeight : root._cellHeight

    // As many rows as the output holds under the same inset; past that the
    // cells scroll inside the card with the cursor's row kept in view.
    readonly property int _maxRows: Math.max(1, Math.floor(
        (root._outputHeight - Theme.space.switcherInset * 2 - Theme.space.panelPadding * 2)
            / root._cellHeight))
    readonly property real _viewHeight: Math.min(root._gridHeight, root._maxRows * root._cellHeight)

    // As wide as its widest row, over a floor that keeps "No windows"
    // legible. Nothing here reads a title's length: a card that resized as
    // the cursor walked would move the cells under it (the plan-wide
    // no-jitter contract), so captions elide into their cell.
    readonly property real _contentWidth: Math.max(root._gridWidth,
        Theme.space.popupWidthNarrow - Theme.space.panelPadding * 2)
    readonly property real _cardWidth: root._contentWidth + Theme.space.panelPadding * 2
    readonly property real _cardHeight: root._viewHeight + Theme.space.panelPadding * 2

    // Per entry: the picture its desktop entry names, and which of its app's
    // windows it is. One pass rather than a binding per cell, since the
    // ordinals need every entry's app at once. AppIconService is the resolver
    // the launcher's rows take too.
    readonly property var _apps: {
        var out = [];
        for (var i = 0; i < root.entries.length; i++) {
            var win = root.entries[i];
            var entry = AppIconService.entryFor(win);
            out.push({
                key: entry ? "entry:" + entry.id : (win.appId || win.initialClass || ""),
                icon: entry ? AppIconService.source(entry.icon) : ""
            });
        }
        return out;
    }
    readonly property var _ordinals: Model.ordinals(root._apps.map(function (app) {
        return app.key;
    }))

    // How many thumbnails hold a captured frame, and how many hold a capture
    // source at all, for `switcher state`. Read whether or not the card is
    // open: a closed switcher has to answer zero for both.
    function capturedCount() {
        var n = 0;
        for (var i = 0; i < thumbRepeater.count; i++) {
            var cell = thumbRepeater.itemAt(i);
            if (cell && cell.captured)
                n++;
        }
        return n;
    }

    // Per entry, in row order, its window and whether its thumbnail holds a
    // frame.
    function capturedCells() {
        var out = [];
        for (var i = 0; i < thumbRepeater.count; i++) {
            var cell = thumbRepeater.itemAt(i);
            out.push({
                id: root.entries[i] ? root.entries[i].id : "",
                captured: !!(cell && cell.captured)
            });
        }
        return out;
    }

    function capturingCount() {
        var n = 0;
        for (var i = 0; i < thumbRepeater.count; i++) {
            var cell = thumbRepeater.itemAt(i);
            if (cell && cell.sourced)
                n++;
        }
        return n;
    }

    // Each cell's box, its thumbnail's and its caption icon's, in output
    // pixels as drawn now.
    function cellRects() {
        var origin = tileView.mapToItem(null, 0, 0);
        var pad = Theme.space.panelPadding;
        return root._cells.map(function (cell, i) {
            var x = origin.x + cell.x;
            var y = origin.y + cell.y - tileView.contentY;
            var thumbWidth = cell.width - pad * 2;
            return {
                cell: { x: Math.round(x), y: Math.round(y), width: cell.width, height: cell.height },
                thumb: { x: Math.round(x + pad), y: Math.round(y + pad), width: thumbWidth, height: root._thumbHeight },
                icon: {
                    x: Math.round(x + pad),
                    y: Math.round(y + pad + root._thumbHeight + Theme.space.iconGap
                        + (root._captionHeight - root._captionIcon) / 2),
                    width: root._captionIcon,
                    height: root._captionIcon
                }
            };
        });
    }

    screen: root._screen
    // Held visible through the exit (DESIGN.md §1 "Motion"): the keyboard is
    // released on `isOpen` itself, so nothing types into a card on its way
    // out.
    visible: drawer.presence.shown
    color: "transparent"

    WlrLayershell.namespace: "formalshell:switcher"
    // Overlay rather than Top: an Alt+Tab that a fullscreen window drew over
    // would be a switcher you cannot see while switching.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    // OnDemand alone never takes focus for a surface summoned over IPC
    // (wlroots waits for the compositor to route focus there, i.e. for a
    // click), so every open primes with Exclusive and settles back once that
    // focus has landed; Panel.qml carries the full rationale, including why
    // the prime has to stay short under Hyprland.
    WlrLayershell.keyboardFocus: root._shown
        ? (root._focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
        : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    onBackingWindowVisibleChanged: {
        root._beginFocusPrime();
        if (root.backingWindowVisible && root._shown)
            _captureTimer.restart();
        else if (!root.backingWindowVisible)
            root._capturing = false;
    }

    function _beginFocusPrime() {
        if (root._shown && root.backingWindowVisible)
            focusPrimeTimer.restart();
    }

    Timer {
        id: focusPrimeTimer
        interval: 75
        onTriggered: if (root._shown) root._focusPrimed = true
    }

    // Two frames at 60Hz: the card's first frame is on screen before the
    // first capture is requested.
    Timer {
        id: _captureTimer
        interval: 32
        onTriggered: if (root._shown) root._capturing = true
    }

    Timer {
        id: _refreshTimer
        interval: 200
        repeat: true
        running: root._shown && root._capturing
        onTriggered: {
            var cell = thumbRepeater.itemAt(root.index);
            if (cell)
                cell.refresh();
        }
    }

    // Off-screen calibration for `_captionHeight`: one line at the caption's
    // live font.
    Text {
        id: captionMetric
        visible: false
        text: "Ag"
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.caption
    }

    // The pointer's only part in this: a click anywhere cancels. The window
    // covers the output because the card is centred in it, so it is the
    // surface a click lands on whether or not it wants one, and swallowing
    // those clicks silently would leave a pointer user with nothing to do
    // but find the keyboard.
    MouseArea {
        id: backdrop
        anchors.fill: parent
        enabled: root._shown
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => keyCatcher.handle(event)
        onClicked: root.close()
    }

    KeyCatcher {
        id: keyCatcher
        focus: false
        blocked: !root._shown

        // Tab and the arrows walk the row the same way `switcher next` does:
        // right and down forward, left and up back, wrapping at either end.
        // A wrapped row is still one sequence, so there is no second axis to
        // move along.
        onMoveRequested: (dx, dy) => root.step(dx + dy >= 0 ? 1 : -1)
        onTabRequested: direction => root.step(direction)
        onActivateRequested: root.commit()
        onCloseRequested: root.close()
        // Nothing to type into and nothing to delete: a switcher has no
        // search, and closing someone's window on a stray `x` is not a thing
        // to do by accident.
    }

    // Everything the card is, is the drawer's (Components/Drawer.qml), on
    // the table's own `switcher` clock rather than the emerge habit's: the
    // card fades and does not travel, so `edge: "center"` zeroes the drop a
    // popover would otherwise take and leaves the fade alone. `floating` and
    // `joined: false` because the card sits in the middle of the output and
    // meets no line, so there is nothing for it to bud off under any habit
    // and no gap to publish.
    Drawer {
        id: drawer
        anchors.fill: parent
        owner: root
        open: root._shown
        mapped: root.backingWindowVisible
        edge: "center"
        screen: root._screen
        joined: false
        floating: true
        role: "switcher"
        clock: "switcher"
        rect: Qt.rect(Math.round((root._outputWidth - root._cardWidth) / 2),
            Math.round((root._outputHeight - root._cardHeight) / 2),
            root._cardWidth, root._cardHeight)

        // The cells, wrapped: as many across as the output holds, each row
        // centred on the widest. Held to `_viewHeight` and scrolled from the
        // keyboard alone once the rows outgrow the output.
        Flickable {
            id: tileView
            visible: root.count > 0
            anchors.centerIn: parent
            width: root._gridWidth
            height: root._viewHeight
            contentWidth: root._gridWidth
            contentHeight: root._gridHeight
            interactive: false
            clip: root._gridHeight > root._viewHeight

            Connections {
                target: root
                function onIndexChanged() {
                    var cell = root._cells[root.index];
                    if (!cell)
                        return;
                    tileView.contentY = Cursor.follow(cell.y, root._cellHeight,
                        tileView.contentY, tileView.height, tileView.contentHeight, 0);
                }
            }

            Repeater {
                id: thumbRepeater
                model: root.count

                delegate: Item {
                    id: slot
                    required property int index

                    readonly property var _win: root.entries[slot.index]
                    readonly property var _app: root._apps[slot.index] || ({})
                    readonly property var _ordinal: root._ordinals[slot.index] || ({ n: 0, of: 1 })
                    readonly property var _place: root._cells[slot.index] || ({ x: 0, y: 0, width: 0, height: 0 })
                    readonly property bool _selected: slot.index === root.index
                    readonly property bool captured: picture.captured
                    readonly property bool sourced: picture.sourced

                    function refresh() {
                        picture.refresh();
                    }

                    x: slot._place.x
                    y: slot._place.y
                    width: slot._place.width
                    height: slot._place.height

                    // A ghost `Cell`, as the launcher's tiles are
                    // (Menu/views/LauncherTile.qml), over the table's own
                    // `switcher.cell` fill, with the ring on the chosen one.
                    // Inert, since a click anywhere cancels.
                    Cell {
                        anchors.fill: parent
                        role: "switcher.cell"
                        ghost: true
                        selected: slot._selected
                        cursor: slot._selected
                    }

                    Item {
                        id: body
                        x: Theme.space.panelPadding
                        y: Theme.space.panelPadding
                        width: slot.width - Theme.space.panelPadding * 2
                        height: slot.height - Theme.space.panelPadding * 2

                        WindowThumb {
                            id: picture
                            width: body.width
                            height: root._thumbHeight
                            win: slot._win
                            iconSource: slot._app.icon || ""
                            // One frame per window, and the selected one
                            // refreshed by `_refreshTimer`. `live` would
                            // have the compositor copy the window on every
                            // frame and this whole card repaint after each
                            // copy, which is what made Alt+Tab lag.
                            capturing: root._capturing && root.visible
                            live: false
                            lit: slot._selected
                            showTitle: false
                        }

                        // Which of its app's windows this is, on every cell
                        // of an app with more than one here, so two
                        // identical captions still say they are two windows.
                        Cell {
                            visible: slot._ordinal.of > 1
                            anchors.right: picture.right
                            anchors.bottom: picture.bottom
                            anchors.rightMargin: Theme.space.xs
                            anchors.bottomMargin: Theme.space.xs
                            chip: true
                            active: true
                            radius: Theme.radiusSm

                            CellLabel {
                                text: String(slot._ordinal.n)
                            }
                        }

                        Row {
                            y: root._thumbHeight + Theme.space.iconGap
                            width: body.width
                            height: root._captionHeight
                            spacing: Theme.space.iconGap

                            // Decoded before the card shows: a switcher
                            // flashed open for one Alt+Tab would otherwise
                            // commit before an asynchronous decode ever
                            // painted.
                            Picture {
                                id: captionIcon
                                anchors.verticalCenter: parent.verticalCenter
                                visible: (slot._app.icon || "") !== "" && captionIcon.status !== Image.Error
                                source: slot._app.icon || ""
                                asynchronous: false
                                width: root._captionIcon
                                height: root._captionIcon
                                sourceSize.width: root._captionIcon
                                    * (root._screen ? root._screen.devicePixelRatio : 1)
                                sourceSize.height: root._captionIcon
                                    * (root._screen ? root._screen.devicePixelRatio : 1)
                                fillMode: Image.PreserveAspectFit
                            }

                            // Nothing in the chain answered, or the file it
                            // named would not decode: the generic window
                            // mark, which says "a window, no icon of its
                            // own".
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !captionIcon.visible
                                name: "app-window"
                                size: root._captionIcon
                                color: Theme.color.mutedForeground
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: body.width - root._captionIcon - Theme.space.iconGap
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                textFormat: Text.PlainText
                                text: slot._win ? slot._win.title : ""
                                color: slot._selected ? Theme.color.foreground : Theme.color.mutedForeground
                                font.family: Theme.fontFamilySans
                                font.pixelSize: Theme.fontSize.caption
                                font.weight: slot._selected ? Theme.weight.medium : Theme.weight.normal
                            }
                        }
                    }
                }
            }
        }

        // Nothing to switch between: one dim cell saying so, rather than an
        // empty card or an invented window.
        Box {
            visible: root.count === 0
            anchors.centerIn: parent
            role: "switcher.cell"
            state: "rest"
            width: root._contentWidth
            height: root._cellHeight

            SectionLabel {
                anchors.centerIn: parent
                text: "No windows"
            }
        }
    }
}
