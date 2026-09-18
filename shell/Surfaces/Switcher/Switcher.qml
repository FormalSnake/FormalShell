import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import "switcher.js" as Model

// Gala's Alt+Tab (`src/Widgets/WindowSwitcher/WindowSwitcher.vala`,
// `WindowSwitcherIcon.vala`; the 2026-09-17 spec's Part 2, M60 T6): a row of
// the FOCUSED WORKSPACE's windows as app icons on one card in the middle of
// the output, the selected one on a quarter-strength `accent` tile with its
// title under the row. Keyboard only, and summoned over IPC alone
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
// with a single cursor means. Instantiated only under a theme whose
// `switcher` habit is on (shell.qml's Loader), which is why nothing in this
// file reads the habit itself.
//
// The cursor here is a FILL rather than the `cursor` ring every other
// keyboard surface draws (DESIGN.md §1 "Ring"): Gala marks the selected
// window by tinting its cell, the card carries no other selectable chrome to
// confuse it with, and a ring around a 64px icon at this size reads as a
// second border on the icon rather than as a cursor.
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

    readonly property var entries: Model.entries(CompositorService.windows,
        root._openHistory, root._openWorkspaceId)
    readonly property int count: root.entries.length
    readonly property var selected: (root.count > 0 && root.index < root.count)
        ? root.entries[root.index] : null
    readonly property string selectedId: root.selected ? root.selected.id : ""
    readonly property string selectedTitle: root.selected ? root.selected.title : ""

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
            root._openWorkspaceId = CompositorService.focusedWorkspaceId;
            root.index = Model.advance(0, root.count, direction);
            root._focusPrimed = false;
            root.isOpen = true;
            root._beginFocusPrime();
            Qt.callLater(function () { backdrop.forceActiveFocus(); });
            return;
        }
        root.index = Model.advance(root.index, root.count, direction);
    }

    // The selected window through the backend's own focus verb, on the
    // opaque id the compositor handed over (CLAUDE.md: never parsed, never
    // compared numerically).
    //
    // Nothing at all while the card is closed: this is bound to the RELEASE
    // of a modifier, so it arrives on every tap of that key, and a commit
    // that ran anyway would move focus to whatever the last switch left the
    // cursor on.
    function commit() {
        if (!root.isOpen)
            return false;
        var id = root.selectedId;
        root.close();
        if (id === "")
            return false;
        CompositorService.focusWindow(id);
        return true;
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

    // One cell: Gala's 64px icon inside `WRAPPER_PADDING` on all four sides
    // (`WindowSwitcherIcon.vala`'s `reload_icon`), which is the same 12 the
    // card keeps around its own contents, so both are `panelPadding` here.
    // The cells touch: Gala lays them out in a `Clutter.FlowLayout` and sets
    // no spacing on it, and the 24px the two paddings leave between two
    // icons is the gap the row reads as.
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

    // The card is as wide as its widest row and no wider, which is Gala's
    // own `get_preferred_width`: the icons set the width and the caption
    // ellipsizes into it, never the other way round. A card that resized as
    // the cursor walked would move the icons under it (the plan-wide
    // no-jitter contract), so nothing here reads the title's length.
    readonly property real _contentWidth: root.count > 0
        ? root._gridWidth : Theme.space.popupWidthNarrow
    readonly property real _cardWidth: root._contentWidth + Theme.space.panelPadding * 2
    readonly property real _cardHeight: root._gridHeight + Theme.space.panelPadding
        + captionMetric.implicitHeight + Theme.space.panelPadding * 2

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

    // Off-screen calibration: the caption's band is one line of `heading` at
    // the live font, whatever title is in it, so a two-word title and a path
    // leave the card the same height.
    Item {
        visible: false

        Text {
            id: captionMetric
            text: "Ag"
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.heading
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
    // the table's own `switcher` clock rather than the popover habit's:
    // Gala's card fades and does not travel, so `edge: "center"` zeroes the
    // drop a popover would otherwise take and leaves the fade alone.
    // `joined: false` because the card floats in the middle of the output
    // and meets no line, so there is nothing for it to bud off and no gap to
    // publish.
    Drawer {
        id: drawer
        anchors.fill: parent
        owner: root
        open: root.isOpen
        mapped: root.backingWindowVisible
        edge: "center"
        screen: root._screen
        joined: false
        role: "switcher"
        clock: "switcher"
        rect: Qt.rect(Math.round((root._outputWidth - root._cardWidth) / 2),
            Math.round((root._outputHeight - root._cardHeight) / 2),
            root._cardWidth, root._cardHeight)

        Column {
            anchors.centerIn: parent
            spacing: Theme.space.panelPadding

            // The row, wrapped: `_columns` cells across, the last row short
            // and centred under the ones above it.
            Column {
                visible: root.count > 0
                anchors.horizontalCenter: parent.horizontalCenter
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

                            delegate: Box {
                                id: cell
                                required property int index

                                readonly property int _entry: cellRow._first + cell.index
                                readonly property var _window: root.entries[cell._entry]
                                readonly property bool _selected: cell._entry === root.index

                                // The desktop entry behind the window's appId,
                                // the same lookup ActiveWindow's cell and the
                                // launcher's app rows make.
                                readonly property var _desktopEntry: (cell._window
                                    && cell._window.appId !== "")
                                    ? DesktopEntries.heuristicLookup(cell._window.appId) : null
                                // check=true, so a theme that cannot resolve
                                // the entry's icon name yields "" and the
                                // glyph below stands in rather than an Image
                                // drawing a missing texture.
                                readonly property string _iconSource: (cell._desktopEntry
                                    && cell._desktopEntry.icon)
                                    ? Quickshell.iconPath(cell._desktopEntry.icon, true) : ""

                                role: "switcher.cell"
                                state: cell._selected ? "selected" : "rest"
                                width: root._cellExtent
                                height: root._cellExtent

                                Picture {
                                    anchors.centerIn: parent
                                    visible: cell._iconSource !== ""
                                    source: cell._iconSource
                                    width: Theme.space.switcherIcon
                                    height: Theme.space.switcherIcon
                                    sourceSize.width: Theme.space.switcherIcon
                                    sourceSize.height: Theme.space.switcherIcon
                                    fillMode: Image.PreserveAspectFit
                                }

                                // No entry, or an entry naming an icon this
                                // theme has never heard of: the shell's own
                                // window glyph at the icon's size.
                                Icon {
                                    anchors.centerIn: parent
                                    visible: cell._iconSource === ""
                                    name: "app-window"
                                    size: Theme.space.switcherIcon
                                    color: Theme.color.foreground
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

            // The selected window's title under the row, centred, in the
            // card's own words rather than the mono column a value would
            // take. `heading` because Gala pins the caption at 12 against
            // elementary's own `Inter 9` system font (`Text.vala`'s
            // `set_system_font_name`, default-settings' gschema override),
            // and 12/9 is this ladder's heading step exactly.
            Text {
                width: root._contentWidth
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.selectedTitle
                color: Theme.color.foreground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.heading
            }
        }
    }
}
