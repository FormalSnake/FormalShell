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
    property bool cursorTravels: false
    property var hoverGate: null

    // A fixed count (M48 D5): Menu.qml's `cursorColumns` reads it back for
    // wrap/page-step arithmetic, the same seam appGrid's own `columns`
    // property already is.
    readonly property int columns: Core.Theme.launcher.emojiColumns

    // Every tile keeps its own selected fill off, the `GridCursor` below
    // draws the one.
    readonly property bool ownsSelectionFill: true
    readonly property real _gutter: Core.Theme.space.sm

    // The inset under the rule above and over the one below, as a header and
    // a footer so `contentY` is 0 at the top of the grid.
    property real inset: 0
    header: Item { height: root.inset; width: 1 }
    footer: Item { height: root.inset; width: 1 }

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

    GridCursor {
        view: root
        gutter: root._gutter
        travels: root.cursorTravels
    }

    // The wrapper carries the GridView's own cell so the tile inside it
    // can hold the gutter between glyphs in its margins, exactly as the
    // wallpaper grid does.
    delegate: Item {
        id: emojiSlot
        required property int index
        required property string rowId
        readonly property var entry: root.rowsById[emojiSlot.rowId] || root.rowsPrev[emojiSlot.rowId] || null

        width: root.cellWidth
        height: root.cellHeight

        LauncherTile {
            id: emojiCell
            anchors.fill: parent
            anchors.margins: root._gutter
            selected: emojiSlot.index === root.cursorIndex
            hoverGate: root.hoverGate
            tooltipText: emojiSlot.entry ? emojiSlot.entry.row.label : ""
            onPointed: root.cursorRequested(emojiSlot.index)
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
                color: emojiCell.foreground
                font.family: Core.Theme.fontFamilyMono
                font.pixelSize: Core.Theme.fontSize.display
            }
        }
    }
}
