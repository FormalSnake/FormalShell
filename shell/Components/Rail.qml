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
}
