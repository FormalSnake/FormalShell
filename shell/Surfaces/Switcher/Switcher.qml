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
// WindowSwitcher.vala`, `WindowSwitcherIcon.vala`; M60 T6): the windows as
// app tiles on one card in the middle of the output, the selected one under
// the cursor with its title and app name below the row. Keyboard only, and
// summoned over IPC alone
// (`switcher next|prev|commit|cancel|state`), so the compositor's own bind
// drives it: Alt+Tab advances, the release of the modifier commits, and
// nothing here ever grabs a modifier of its own. That release bind has to
// carry Hyprland's `t` flag (`bindrt`, M64): a bind whose key is held while
// another bind fires is shadowed for as long as that key stays down, and a
// transparent bind is the only kind `shadowKeybinds` leaves alone
// (docs/examples/hyprland/formalshell.conf).
//
// One instance rather than one per output, the same reasoning Menu, Center
// and Osd carry: it is summoned rather than resident, it lands on the
// focused output at summon time, and one card at a time is what a switcher
// with a single cursor means. Instantiated unless `switcher.enabled` is
// false (shell.qml's Loader), under every theme alike: the table styles the
// card, its tiles and its fade, and nothing here reads a theme.
PanelWindow {
    id: root

    property bool isOpen: false
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
            root._beginFocusPrime();
            Qt.callLater(function () { backdrop.forceActiveFocus(); });
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
        root.close();
        if (id === "")
            return false;
        // A commit inside the prime window lands while this layer still holds
        // the keyboard exclusively, and Hyprland hands focus back to the
        // window it came from once the layer lets go, undoing the switch. One
        // dispatch after that release rather than one either side of it: two
        // make the compositor start its animation, reverse it and start again.
        if (primed) {
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
        root.isOpen = false;
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

    // One tile: Gala's 64px icon inside `WRAPPER_PADDING` on all four sides
    // (`WindowSwitcherIcon.vala`'s `reload_icon`), which is the same 12 the
    // card keeps around its own contents, so both are `panelPadding` here.
    // The tiles touch: Gala lays them out in a `Clutter.FlowLayout` and sets
    // no spacing on it, and the 24px the two paddings leave between two
    // icons is the gap the row reads as. The --switcher leg reads these
    // tiles at fixed pixels, so the extent is a contract with it.
    readonly property real _cellExtent: Theme.space.switcherIcon
        + Theme.space.panelPadding * 2
    readonly property real _cellGap: 0

    // How many cells fit across before the row wraps: the output minus the
    // room the card keeps off both edges and its own padding.
    readonly property int _maxColumns: Math.max(1, Math.floor(
        (root._outputWidth - (Theme.space.switcherInset + Theme.space.panelPadding) * 2
            + root._cellGap) / (root._cellExtent + root._cellGap)))
    readonly property int _columns: Model.columns(root.count, root._maxColumns)
    readonly property int _rows: Model.rows(root.count, root._columns)

    readonly property real _gridWidth: root._columns > 0
        ? root._columns * root._cellExtent + (root._columns - 1) * root._cellGap
        : root._cellExtent
    readonly property real _gridHeight: root._rows > 0
        ? root._rows * root._cellExtent + (root._rows - 1) * root._cellGap
        : root._cellExtent

    // The caption band under the tiles: the title on one line of `heading`
    // and the app's name on one of `caption`, measured at the live fonts
    // whatever is in them, so a two-word title and a path leave the card the
    // same height.
    readonly property real _captionHeight: titleMetric.implicitHeight + Theme.space.rowGap
        + appMetric.implicitHeight

    // As many rows as the output holds under the same inset; past that the
    // tiles scroll inside the card with the cursor's row kept in view.
    readonly property int _maxRows: Math.max(1, Math.floor(
        (root._outputHeight - Theme.space.switcherInset * 2 - Theme.space.panelPadding * 3
            - root._captionHeight + root._cellGap) / (root._cellExtent + root._cellGap)))
    readonly property real _viewHeight: Math.min(root._gridHeight,
        root._maxRows * root._cellExtent + (root._maxRows - 1) * root._cellGap)

    // As wide as its widest row, which is Gala's own `get_preferred_width`,
    // over a floor that keeps one window's title legible. A card that
    // resized as the cursor walked would move the tiles under it (the
    // plan-wide no-jitter contract), so nothing here reads the title's
    // length: the caption elides into whatever the tiles leave it. The tiles
    // are centred in the card and the card on the output, so the floor never
    // moves a tile.
    readonly property real _contentWidth: Math.max(root.count > 0 ? root._gridWidth : 0,
        Theme.space.popupWidthNarrow - Theme.space.panelPadding * 2)
    readonly property real _cardWidth: root._contentWidth + Theme.space.panelPadding * 2
    readonly property real _cardHeight: root._viewHeight + Theme.space.panelPadding
        + root._captionHeight + Theme.space.panelPadding * 2

    // Per tile: the desktop entry, the picture it names, and which of its
    // app's windows it is. One pass rather than a binding per tile, since
    // the ordinals need every tile's app at once. AppIconService is the
    // resolver the launcher's rows take too.
    readonly property var _apps: {
        var out = [];
        for (var i = 0; i < root.entries.length; i++) {
            var win = root.entries[i];
            var entry = AppIconService.entryFor(win);
            out.push({
                key: entry ? "entry:" + entry.id : (win.appId || win.initialClass || ""),
                name: entry ? entry.name : (win.appId || win.initialClass || ""),
                icon: entry ? AppIconService.source(entry.icon) : ""
            });
        }
        return out;
    }
    readonly property var _ordinals: Model.ordinals(root._apps.map(function (app) {
        return app.key;
    }))

    readonly property string _selectedApp: (root.selected && root.index < root._apps.length)
        ? root._apps[root.index].name : ""

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
    WlrLayershell.keyboardFocus: root.isOpen
        ? (root._focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
        : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    onBackingWindowVisibleChanged: root._beginFocusPrime()

    function _beginFocusPrime() {
        if (root.isOpen && root.backingWindowVisible)
            focusPrimeTimer.restart();
    }

    Timer {
        id: focusPrimeTimer
        interval: 75
        onTriggered: if (root.isOpen) root._focusPrimed = true
    }

    // Off-screen calibration for `_captionHeight`: one line of each at the
    // live font, as tall as the lines the caption draws.
    Item {
        visible: false

        Text {
            id: titleMetric
            text: "Ag"
            font: titleText.font
        }

        Text {
            id: appMetric
            text: "Ag"
            font: appText.font
        }
    }

    // The pointer's only part in this: a click anywhere cancels. The window
    // covers the output because the card is centred in it, so it is the
    // surface a click lands on whether or not it wants one, and swallowing
    // those clicks silently would leave a pointer user with nothing to do
    // but find the keyboard.
    MouseArea {
        id: backdrop
        anchors.fill: parent
        enabled: root.isOpen
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => keyCatcher.handle(event)
        onClicked: root.close()
    }

    KeyCatcher {
        id: keyCatcher
        focus: false
        blocked: !root.isOpen

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
        open: root.isOpen
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

        Column {
            anchors.centerIn: parent
            spacing: Theme.space.panelPadding

            // The tiles, wrapped: `_columns` across, the last row short and
            // centred under the ones above it. Held to `_viewHeight` and
            // scrolled from the keyboard alone once the rows outgrow the
            // output.
            Flickable {
                id: tileView
                visible: root.count > 0
                anchors.horizontalCenter: parent.horizontalCenter
                width: root._gridWidth
                height: root._viewHeight
                contentWidth: root._gridWidth
                contentHeight: root._gridHeight
                interactive: false
                clip: root._gridHeight > root._viewHeight

                Connections {
                    target: root
                    function onIndexChanged() {
                        if (root._columns <= 0)
                            return;
                        var row = Math.floor(root.index / root._columns);
                        tileView.contentY = Cursor.follow(row * (root._cellExtent + root._cellGap),
                            root._cellExtent, tileView.contentY, tileView.height,
                            tileView.contentHeight, 0);
                    }
                }

                Column {
                    width: root._gridWidth
                    spacing: root._cellGap

                    Repeater {
                        model: root._rows

                        delegate: Row {
                            id: cellRow
                            required property int index

                            readonly property int _first: cellRow.index * root._columns
                            readonly property int _count: Math.min(root._columns,
                                root.count - cellRow._first)

                            anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                            spacing: root._cellGap

                            Repeater {
                                model: cellRow._count

                                delegate: Item {
                                    id: slot
                                    required property int index

                                    readonly property int _entry: cellRow._first + slot.index
                                    readonly property var _app: root._apps[slot._entry] || ({})
                                    readonly property var _ordinal: root._ordinals[slot._entry]
                                        || ({ n: 0, of: 1 })
                                    readonly property bool _selected: slot._entry === root.index

                                    width: root._cellExtent
                                    height: root._cellExtent

                                    // The launcher grid's tile (AppGridView.qml):
                                    // a ghost `Cell` whose cursor is the ring,
                                    // over the table's own `switcher.cell` fill.
                                    // Inert, since a click anywhere cancels.
                                    Cell {
                                        id: tile
                                        anchors.fill: parent
                                        role: "switcher.cell"
                                        ghost: true
                                        selected: slot._selected
                                        cursor: slot._selected

                                        // The picture the entry names, decoded
                                        // before the card shows: a switcher
                                        // flashed open for one Alt+Tab would
                                        // otherwise commit before an
                                        // asynchronous decode ever painted.
                                        Picture {
                                            id: tileIcon
                                            anchors.centerIn: parent
                                            visible: (slot._app.icon || "") !== "" && tileIcon.status !== Image.Error
                                            source: slot._app.icon || ""
                                            asynchronous: false
                                            width: Theme.space.switcherIcon
                                            height: Theme.space.switcherIcon
                                            sourceSize.width: Theme.space.switcherIcon
                                                * (root._screen ? root._screen.devicePixelRatio : 1)
                                            sourceSize.height: Theme.space.switcherIcon
                                                * (root._screen ? root._screen.devicePixelRatio : 1)
                                            fillMode: Image.PreserveAspectFit
                                        }

                                        // Nothing in the chain answered, or the
                                        // file it named would not decode: the
                                        // generic window mark, dim, which says
                                        // "a window, no icon of its own".
                                        Icon {
                                            anchors.centerIn: parent
                                            visible: !tileIcon.visible
                                            name: "app-window"
                                            size: Theme.space.switcherIcon * 0.75
                                            color: tile.dimForeground
                                        }
                                    }

                                    // Which of its app's windows this is, on
                                    // every tile of an app with more than one
                                    // here, so two identical icons still say
                                    // they are two windows.
                                    Cell {
                                        visible: slot._ordinal.of > 1
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.rightMargin: Theme.space.xs
                                        anchors.bottomMargin: Theme.space.xs
                                        chip: true
                                        active: true
                                        radius: Theme.radiusSm

                                        CellLabel {
                                            text: String(slot._ordinal.n)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Nothing to switch between: one dim cell saying so, rather than
            // an empty card or an invented window.
            Box {
                visible: root.count === 0
                role: "switcher.cell"
                state: "rest"
                width: root._contentWidth
                height: root._cellExtent

                SectionLabel {
                    anchors.centerIn: parent
                    text: "NO WINDOWS"
                }
            }

            // The selected window's title and its app's name under the
            // tiles, centred, each on one line and elided into the card's own
            // width. `heading` for the title because Gala pins its caption at
            // 12 against elementary's `Inter 9` (`Text.vala`'s
            // `set_system_font_name`), and 12/9 is this ladder's heading
            // step. The app line is empty rather than repeated when the title
            // already says it.
            Column {
                width: root._contentWidth
                spacing: Theme.space.rowGap

                Text {
                    id: titleText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                    text: root.selectedTitle
                    color: Theme.color.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.heading
                    font.weight: Theme.weight.medium
                }

                Text {
                    id: appText
                    width: parent.width
                    height: appMetric.implicitHeight
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                    text: root._selectedApp.toLowerCase() === root.selectedTitle.toLowerCase()
                        ? "" : root._selectedApp
                    color: Theme.color.mutedForeground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.caption
                }
            }
        }
    }
}
