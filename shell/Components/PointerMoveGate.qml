import QtQuick

// Keeps a moving list's own churn from reading as pointer input
// (reimplemented from omarchy's `shell/Ui/PointerMoveGate.qml`, a
// read-reference per CLAUDE.md — no line of it is copied).
//
// The problem: a row MouseArea's onPositionChanged cannot tell a real mouse
// move from a different row sliding under a parked pointer. Qt re-delivers a
// hover move to whatever item lands under the cursor whenever geometry
// changes, and the row's own local coordinates change with it, so a surface
// that wires hover straight to its keyboard cursor (Menu.qml's row delegate)
// loses that cursor on every filter keystroke and every scroll — the pointer
// never moved, but the row underneath it did.
//
// Contract:
//  - reset() after anything that moves rows without the pointer: a search
//    keystroke, arrow-key navigation, a level change.
//  - moved() from the row MouseArea's onPositionChanged, and act only when it
//    answers true.
//  - allowStationarySample() re-arms exactly one stationary sample for a
//    transition the pointer itself caused (a click that opens a new level), so
//    the row landing under the still-parked cursor takes it.
//
// Samples are compared in SCENE coordinates, never the row's own: the row is
// the thing that moved, so its local frame is exactly the one that lies.
QtObject {
    id: root

    // Pixels the pointer must travel before a sample counts as deliberate.
    // 1 rejects the churn outright (a re-delivered hover reports the identical
    // scene point) while still passing the smallest real move.
    property real threshold: 1

    property bool _primed: false
    property bool _stationaryAllowed: false
    property real _lastX: 0
    property real _lastY: 0

    function reset() {
        root._primed = false;
        root._stationaryAllowed = false;
        root._lastX = 0;
        root._lastY = 0;
    }

    function allowStationarySample() {
        root.reset();
        root._stationaryAllowed = true;
    }

    // The decision itself, in scene coordinates — moved() below is the mapping
    // wrapper consumers actually call, this is what the unit tests drive.
    function movedTo(x, y) {
        var first = !root._primed;
        var didMove = first
            ? root._stationaryAllowed
            : (Math.abs(x - root._lastX) > root.threshold || Math.abs(y - root._lastY) > root.threshold);
        // A rejected sample leaves the accepted point alone, so a slow drag
        // accumulates across frames instead of re-baselining on every
        // sub-threshold step and never crossing it.
        if (first || didMove) {
            root._lastX = x;
            root._lastY = y;
        }
        root._primed = true;
        root._stationaryAllowed = false;
        return didMove;
    }

    // `item` is whatever the sample's coordinates are local to — the row's own
    // MouseArea. mapToItem(null, …) is the scene frame (Qt 6: a null target
    // maps into the scene).
    function moved(item, x, y) {
        var point = item.mapToItem(null, x, y);
        return root.movedTo(point.x, point.y);
    }
}
