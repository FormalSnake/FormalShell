import QtQuick
import qs.Components

// One cell of a launcher grid (M72 T4): a wallpaper, an emoji, an app. A
// ghost `Cell`, so a grid of forty is forty pictures rather than forty
// boxes; the pointer's wash and the cursor's `selected` box are the `cell`
// role's, the same two every row in the launcher draws, and the corner is
// the table's. The grid under it owns the selected fill, one box travelling
// between tiles, so a tile keeps the selected ink alone.
//
// What the tile holds is the grid's: the picture, the glyph, the icon over
// its name, placed in the default slot and sized off the grid's own cell
// rather than off the tile, which measures its content to size itself.
Cell {
    id: root

    // Menu.qml's one pointer gate: a re-rank slides tiles under a parked
    // pointer, and Qt reports that as a hover move like any other.
    property var hoverGate: null

    // The pointer really moved onto this tile, so it names the cursor.
    signal pointed

    ghost: true
    interactive: true
    hovered: root.containsPointer && (!root.hoverGate || root.hoverGate.live)
    onPointerMoved: (x, y) => {
        if (root.hoverGate && root.hoverGate.moved(root, x, y))
            root.pointed();
    }
}
