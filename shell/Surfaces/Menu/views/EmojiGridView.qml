import QtQuick
import qs.Core as Core
import qs.Components

// The emoji route's grid (M48 D5): 3,944 glyphs are something you hunt for
// by eye, not something you read down a column one name per line (owner,
// 2026-08-26). The ":e " trigger draws the same grid from any level,
// because it lists the same rows.
GridView {
    id: root

    property var rowsById: ({})
    property var rowsPrev: ({})
    property int cursorIndex: -1
    property var hoverGate: null

    // 8 columns (M48 D5): Menu.qml's `cursorColumns` reads it back for
    // wrap/page-step arithmetic, the same seam appGrid's own `columns`
    // property already is.
    readonly property int columns: 8

    signal activated(int index)
    signal cursorRequested(int index)

    // Delegates recycle rather than being destroyed and rebuilt on every
    // flick. Safe here because every delegate in this file is required
    // properties plus bindings off them, with no Component.onCompleted work
    // that a reused item would skip.
    reuseItems: true
    clip: true
    cellWidth: root.width / root.columns
    cellHeight: root.cellWidth
    // Same hard-jump follow as the two other views: held arrow keys outrun
    // the default animated highlight move and the cursor cell ends up
    // off-viewport.
    highlightMoveDuration: 0

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

    function cursorReport() {
        if (root.currentIndex >= 0 && root.model && root.currentIndex < root.model.count)
            return { index: root.currentIndex, id: root.model.get(root.currentIndex).rowId };
        return { index: -1, id: "" };
    }

    WheelScroll {
        id: wheel
        flickable: root
        step: root.cellHeight
    }

    // The wrapper carries the GridView's own cell so the `Cell` inside it
    // can hold the gutter between glyphs in its margins, exactly as the
    // wallpaper grid does.
    delegate: Item {
        id: emojiSlot
        required property int index
        required property string rowId
        readonly property var entry: root.rowsById[emojiSlot.rowId] || root.rowsPrev[emojiSlot.rowId] || null

        width: root.cellWidth
        height: root.cellHeight

        Cell {
            id: emojiCell
            anchors.fill: parent
            anchors.margins: Core.Theme.space.xs
            radius: Core.Theme.radiusSm
            // Ghost, so a grid of 40 glyphs is 40 glyphs rather than 40
            // boxes; hover fills `accent` and the cursor is the ring, the
            // same two states every other cell draws.
            ghost: true
            cursor: emojiSlot.index === root.cursorIndex
            hovered: emojiCell.containsPointer && (!root.hoverGate || root.hoverGate.live)
            interactive: true
            // Same gate as the row list: filtering re-renders cells under a
            // parked pointer, and Qt delivers that as a hover move
            // indistinguishable from a real one.
            onPointerMoved: (x, y) => {
                if (root.hoverGate && root.hoverGate.moved(emojiCell, x, y))
                    root.cursorRequested(emojiSlot.index);
            }
            onClicked: root.activated(emojiSlot.index)

            // The glyph IS the row's icon (providers.js's emojiRows),
            // carried in the mono font that renders it. At `display` rather
            // than `heading`: a cell eight columns into `popupWidthMenu` is
            // wide enough that a heading-sized glyph read as a scatter of
            // dots rather than as a picture to pick from (read off
            // menu-emoji.png).
            Text {
                anchors.centerIn: parent
                text: emojiSlot.entry ? emojiSlot.entry.row.icon : ""
                color: Core.Theme.color.foreground
                font.family: Core.Theme.fontFamilyMono
                font.pixelSize: Core.Theme.fontSize.display
            }
        }
    }
}
