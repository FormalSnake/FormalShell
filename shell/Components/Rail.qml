import QtQuick

// A Row that can stand up: `vertical` lays the same children out top to
// bottom instead of left to right. One Grid pinned to a single row or a
// single column rather than a Row swapped for a Column, so a strip that
// follows the bar's edge (Bar.qml's three regions, the tray, the
// indicators) keeps one item, one set of bindings and one `spacing` across
// both. Qt reads a non-positive `rows`/`columns` as unset
// (QQuickGrid::doPositioning), so the axis not pinned to 1 is left to the
// child count. Children take no anchors, same as in any positioner.
Grid {
    id: root

    property bool vertical: false

    rows: root.vertical ? -1 : 1
    columns: root.vertical ? 1 : -1
    verticalItemAlignment: Grid.AlignVCenter
    horizontalItemAlignment: Grid.AlignHCenter

    // The layout rule (DESIGN.md §1 "Motion", M53 D2) for every strip in the
    // shell: a child this positioner re-places because something beside it
    // appeared, vanished or changed width travels to its new slot. It does
    // not fire for the children the positioner is created with (`populate`
    // is the one that would), so a bar's first layout still lands in one
    // frame.
    //
    // Move only, deliberately. An `add` transition animates the child's own
    // `opacity`, which drops whatever binding held it and leaves it wherever
    // a cancelled run stopped: a strip whose children toggle their own
    // visibility (a bar cell that turns on, a label inside a lockup) had
    // cells stuck invisible for the rest of the session that way. A slot
    // that wants to fade in carries its own presence instead, on a Behavior
    // nothing else writes (Bar.qml's region delegate).
    move: MoveTransition {}
}
