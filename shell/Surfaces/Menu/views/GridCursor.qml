import QtQuick
import qs.Components

// A launcher grid's cursor (M72 T4): the `cell` role's `selected` box, one of
// it travelling between tiles on an arrow step, the grid's version of the
// row list's own. It sits in the view's contentItem and scrolls with the
// tiles; `z` puts it under them, and every tile leaves its own selected fill
// to it (the view's `ownsSelectionFill`).
Box {
    id: root

    property GridView view: null
    // The margin every tile keeps inside its grid cell, so the box sits on
    // the tile rather than on the cell around it.
    property real gutter: 0
    property bool travels: false

    readonly property Item _current: root.view ? root.view.currentItem : null

    // Into the view's own content, stated rather than left to the view: a
    // child declared on an item view stays on the view and would hold still
    // while the tiles scroll under it.
    parent: root.view ? root.view.contentItem : null
    z: -1
    role: "cell"
    state: "selected"
    visible: root._current !== null
    x: root._current ? root._current.x + root.gutter : 0
    y: root._current ? root._current.y + root.gutter : 0
    width: root.view ? root.view.cellWidth - root.gutter * 2 : 0
    height: root.view ? root.view.cellHeight - root.gutter * 2 : 0

    Behavior on x {
        enabled: root.travels
        Anim { kind: "spatialFast" }
    }

    Behavior on y {
        enabled: root.travels
        Anim { kind: "spatialFast" }
    }
}
