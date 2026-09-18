import QtQuick
import qs.Core as Core
import qs.Components
import ".." as MenuParts
import "../../../Menu/toggles.js" as Toggles

// The launcher's default view: a plain row list, shadcn's `CommandList`
// (M48 D6). Menu.qml's keyed `rowsModel` feeds it (ids only, never a fresh
// array per keystroke, so a row survives a re-rank), and it draws one cursor
// fill that travels between rows rather than one per row, which is what
// lets it travel at all (M53 D4).
ListView {
    id: root

    // Menu.qml's keyed model, assigned (never merely bound) so the model a
    // view holds and the rows in it change in the one step that also places
    // the cursor on them (see Menu.qml's `_attachViews`).
    property var rowsById: ({})
    property var rowsPrev: ({})
    property var blankRow: ({})
    // The cursor's own row index, read by every delegate's `current` flag.
    property int cursorIndex: -1
    // Whether the fill travels to its next row or simply snaps there
    // (M53 D4): an arrow step travels, a wrap/page/re-rank/level change/
    // pointer move all snap.
    property bool cursorTravels: false
    // Rows never reset (M53 D6): armed for an incremental sync, disarmed
    // for the refill the diff falls back to.
    property bool rowsAnimate: false

    // Menu.qml's one pointer gate, passed in rather than rebuilt: filtering
    // re-renders rows under a parked pointer and Qt delivers that as a
    // hover move indistinguishable from a real one.
    property var hoverGate: null

    // What a row needs to paint a toggle's check and a confirm-gated row's
    // second Enter.
    property var stateSnapshot: ({})
    property var checkedResults: ({})
    property string confirmPendingId: ""

    signal activated(int index)
    signal cursorRequested(int index)

    // Delegates recycle rather than being destroyed and rebuilt on every
    // flick. Safe here because every delegate in this file is required
    // properties plus bindings off them, with no Component.onCompleted work
    // that a reused item would skip.
    reuseItems: true
    clip: true
    // ListView tracks the cursor through its (always present, even with no
    // `highlight` component) highlight item, and the default
    // `highlightMoveDuration: -1` moves that item at `highlightMoveVelocity`,
    // 400px/s. Key repeat outruns it, so the view crawls behind the cursor
    // and the tail of a long list stays off-screen for seconds after the
    // cursor has already reached it and wrapped back to the top. 0 makes
    // the follow a hard jump, the only thing that keeps the cursor row
    // visible at repeat speed. What the reader sees travelling is
    // `rowCursor` below, which is not what the view scrolls to.
    highlightMoveDuration: 0

    add: AddTransition { enabled: root.rowsAnimate }
    remove: RemoveTransition { enabled: root.rowsAnimate }
    displaced: MoveTransition { enabled: root.rowsAnimate }
    move: MoveTransition { enabled: root.rowsAnimate }

    function placeCursor(index) {
        root.currentIndex = index;
    }

    function scrollHome() {
        if (root.model)
            root.positionViewAtBeginning();
    }

    function cancelGlide() {
        wheel.cancel();
    }

    // What the view draws the cursor on, by index and by the id its own
    // model holds there, for `menu status`: the rig's check that what the
    // view draws the cursor on is the row Enter acts on.
    function cursorReport() {
        if (root.currentIndex >= 0 && root.model && root.currentIndex < root.model.count)
            return { index: root.currentIndex, id: root.model.get(root.currentIndex).rowId };
        return { index: -1, id: "" };
    }

    WheelScroll {
        id: wheel
        flickable: root
    }

    // The cursor (M53 D4): one fill that travels between rows on an arrow
    // step, drawn here rather than per row so there is one of it to travel.
    // A child of the ListView is a child of its contentItem, so it scrolls
    // with the rows it sits under; `z` puts it under them, since the row's
    // own ink draws over it.
    //
    // Offset by the current row's heading band: a row that opens a group is
    // taller than its own body by that band, and a fill covering it would
    // swallow the heading.
    Rectangle {
        id: rowCursor
        readonly property var row: root.currentItem
        z: -1
        visible: rowCursor.row !== null && root.count > 0
        width: root.width
        y: rowCursor.row ? rowCursor.row.y + rowCursor.row._headerBand : 0
        height: rowCursor.row ? rowCursor.row._rowHeight : 0
        radius: Core.Theme.radiusSm
        color: Core.Theme.color.accent

        Behavior on y {
            enabled: root.cursorTravels
            Anim { kind: "spatialFast" }
        }
    }

    delegate: MenuParts.MenuRow {
        required property string rowId
        // The row this delegate is drawing, by id rather than by index: a
        // row fading out through the `remove` transition above has left the
        // model but not the screen, and its index now belongs to whatever
        // slid up into it.
        readonly property var entry: root.rowsById[rowId] || root.rowsPrev[rowId] || null

        // A delegate is pooled after its exit fade as well as after
        // scrolling out of view, so its opacity is put back before it can
        // be handed to a row that is not entering (M53 D6: an exit that
        // leaves a recycled row invisible is worse than no exit at all).
        ListView.onPooled: opacity = 1

        modelData: entry ? entry.row : root.blankRow
        current: root.cursorIndex === index
        hoverLive: !root.hoverGate || root.hoverGate.live
        checkedState: Toggles.checkedFor(node, root.stateSnapshot, root.checkedResults)
        confirming: root.confirmPendingId === node.id
        // A heading rides the row that opens its group, so a row whose
        // section matches the one above it carries none.
        section: entry ? entry.section : ""
        sectionFirst: entry ? entry.sectionFirst : false

        onActivate: root.activated(index)
        onHoverMoved: (source, x, y) => {
            if (root.hoverGate && root.hoverGate.moved(source, x, y))
                root.cursorRequested(index);
        }
    }
}
