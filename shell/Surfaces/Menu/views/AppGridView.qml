import QtQuick
import qs.Core as Core
import qs.Components
import ".." as MenuParts
import "../../../Components/cursor.js" as Cursor
import "../../../Menu/appgrid.js" as AppGrid
import "../../../Menu/toggles.js" as Toggles

// The launcher's app grid (M58, behind `menu.appGrid`): Launchpad's reading
// of an app list, an icon large with its name centred under it. The key is
// on by default under every theme (M72 T2).
//
// The grid owns the app rows only. Whatever else the ranking returned draws
// as ordinary `MenuRow`s in the view's footer, under their own headings,
// which is why Menu/appgrid.js partitions the row list before it ever
// reaches here: the cells are rows 0..appCount-1 and the footer is the rest,
// so a cell's index IS its index in the launcher's own list. The cells sit
// under their own heading too (`cellsHeading`, "Applications" wherever the
// level has more than the one group), so the body reads as sections top to
// bottom with no rule anywhere. A query no app matches leaves the grid with
// no cells and the rows alone: the view stays the level's view rather than
// handing over to the row list.
//
// Both halves are Menu.qml's keyed models (ids only, `rowsById` for the
// rows), never a fresh array per keystroke, so a cell survives a re-rank,
// the grid keeps its scroll, and the footer's rows are not rebuilt from
// nothing every time a letter lands. Enter, Shift+Enter and the action
// bar all act on Menu.qml's own cursor index and never on a view-local row,
// which is what keeps an app's secondary action (Shift+Enter onto the
// discrete card) reachable from a cell without this file knowing it exists.
//
// Columns come from the card's width against a fixed minimum cell, so a
// wider `popupWidth` fits more cells rather than stretching the ones it has.
// The grid then divides the width by that count, the same way the wallpaper
// and emoji grids do, so the gutters come out equal, the two outer ones
// included.
Item {
    id: root

    // Menu.qml's keyed models: the app cells, and the rows under them.
    property var cellsModel: null
    property var tailModel: null
    // Menu.qml's rows by id (this sync and the one before), and what an id
    // resolving to neither draws.
    property var rowsById: ({})
    property var rowsPrev: ({})
    property var blankRow: ({})
    // Where the apps stop in the launcher's row list.
    property int appCount: 0
    // The cells' own heading, "" where the level is one group.
    property string cellsHeading: ""
    // Written by placeCursor() alone, after the models it indexes changed.
    property int cursor: -1
    // Whether the cursor's box travels to its next place or is simply there
    // (Menu.qml's `_cursorTravels`).
    property bool cursorTravels: false

    // The inset under the rule above and over the one below.
    property real inset: 0

    // Menu.qml's one gate, passed in rather than rebuilt: filtering
    // re-renders cells under a parked pointer and Qt delivers that as a
    // hover move indistinguishable from a real one.
    property var hoverGate: null

    // What a footer row needs to paint a toggle's check and a confirm-gated
    // row's second Enter. Handed in as the objects rather than as resolved
    // values, so a toggle flipping repaints the row it is on.
    property var stateSnapshot: ({})
    property var checkedResults: ({})
    property string confirmPendingId: ""

    // The output's scale, read off the window in Menu.qml: an icon decoded
    // at its logical size is soft on a scaled screen.
    property real pixelRatio: 1

    signal activated(int index)
    signal cursorRequested(int index)

    // 64px at the default scale. Icon themes ship a 64 directory and
    // `Quickshell.iconPath` hands back an `image://icon` url, so the decode
    // below asks for the size this draws at rather than scaling a 48 up.
    readonly property real iconExtent: Core.Theme.space.controlHeight * 2
    // A cell is twice the icon wide, so the name under it has half an icon
    // of room either side before it elides. At `popupWidthMenu` that is four
    // columns, which holds a two-word app name whole.
    readonly property real _cellMin: root.iconExtent * 2
    // The gutter every cell holds in its own margins.
    readonly property real _cellGutter: Core.Theme.space.sm

    readonly property int columns: AppGrid.columnsFor(root.width, root._cellMin)
    readonly property int tailCount: root.tailModel ? root.tailModel.count : 0

    readonly property real contentHeight: grid.contentHeight
    // From the top of the header, which the view places above its first
    // cell, at a negative origin.
    readonly property real contentY: grid.contentY - grid.originY
    readonly property real cellHeight: grid.cellHeight

    function _rowFor(id) {
        var entry = root.rowsById[id] || root.rowsPrev[id];
        return entry ? entry.row : root.blankRow;
    }

    // The cursor's one way in. The grid's currentIndex is set here rather
    // than bound: a keyed model moves it along with its current cell on an
    // insert, and a binding whose value did not change would never put it
    // back. -1 while the cursor is in the footer, or the view would scroll
    // a cell back into sight over the row the reader is on.
    function placeCursor(index) {
        root.cursor = index;
        grid.currentIndex = index >= 0 && index < root.appCount ? index : -1;
    }

    // What the view draws the cursor on, by index and by the id its own
    // model holds there, for `menu status`.
    function cursorReport() {
        if (grid.currentIndex >= 0 && root.cellsModel && grid.currentIndex < root.cellsModel.count)
            return { index: grid.currentIndex, id: root.cellsModel.get(grid.currentIndex).rowId };
        var k = root.cursor - root.appCount;
        if (root.tailModel && k >= 0 && k < root.tailModel.count)
            return { index: root.cursor, id: root.tailModel.get(k).rowId };
        return { index: -1, id: "" };
    }

    function cancelGlide() {
        wheel.cancel();
    }

    function scrollHome() {
        if (root.cellsModel)
            grid.positionViewAtBeginning();
    }

    // The name's own band, measured rather than guessed: a GridView's cell
    // height is a number on the view and cannot be a child's implicit one.
    TextMetrics {
        id: nameMetrics
        font.family: Core.Theme.fontFamilySans
        font.pixelSize: Core.Theme.fontSize.body
        font.weight: Core.Theme.weight.medium
        text: "Ag"
    }

    // What a cell gives its content: its own box less a small inset, rather
    // than the `controlPaddingX` a `Cell` insets a row's text by. A centred
    // name has no column of labels to line up with, and every character that
    // padding costs is one the name elides instead. Measured off the view
    // rather than off the cell, since a `Cell` sizes itself from its content
    // and a child measured back off it closes a loop.
    readonly property real _contentWidth: Math.max(0, grid.cellWidth
        - root._cellGutter * 2 - Core.Theme.space.sm * 2)
    readonly property real _contentHeight: root.iconExtent
        + Core.Theme.space.rowGap + nameMetrics.height

    GridView {
        id: grid

        // Every tile and every footer row leaves its own selected fill to
        // the one box that travels under them (`GridCursor`, `tailCursor`).
        readonly property bool ownsSelectionFill: true

        // Delegates recycle rather than being destroyed and rebuilt on every
        // flick, the same contract the two grids in Menu.qml take: every
        // delegate here is required properties plus bindings off them, with
        // no Component.onCompleted work a reused item would skip.
        reuseItems: true
        anchors.fill: parent
        clip: true
        model: root.cellsModel
        cellWidth: root.columns > 0 ? root.width / root.columns : root.width
        cellHeight: root._contentHeight + Core.Theme.space.controlPaddingY * 2
            + root._cellGutter * 2
        // Same hard-jump follow the launcher's other views take: held arrow
        // keys outrun the default animated highlight move and the cursor
        // cell ends up off-viewport.
        highlightMoveDuration: 0

        // A row here is a row of icons, not a text line.
        WheelScroll {
            id: wheel
            flickable: grid
            step: grid.cellHeight
        }

        GridCursor {
            view: grid
            gutter: root._cellGutter
            travels: root.cursorTravels
        }

        // The top inset, and the cells' heading under it when the level has
        // one. The heading stands on the same row inset the footer's rows
        // take, so every heading in the body starts on one column.
        header: Item {
            width: grid.width
            height: root.inset + (appsHeading.visible ? appsHeading.implicitHeight + Core.Theme.space.rowGap : 0)

            SectionLabel {
                id: appsHeading
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Core.Theme.space.rowGap
                anchors.left: parent.left
                leftPadding: root._cellGutter + Core.Theme.space.controlPaddingX
                visible: root.cellsHeading !== "" && root.appCount > 0
                text: root.cellsHeading
            }
        }

        // The wrapper carries the GridView's own cell so the tile inside it
        // can hold the gutter in its margins, exactly as the wallpaper and
        // emoji grids do.
        delegate: Item {
            id: appSlot
            required property int index
            required property string rowId
            readonly property var modelData: root._rowFor(appSlot.rowId)

            width: grid.cellWidth
            height: grid.cellHeight

            LauncherTile {
                id: appCell
                anchors.fill: parent
                anchors.margins: root._cellGutter
                selected: appSlot.index === root.cursor
                hoverGate: root.hoverGate
                // The name in full, and only where the cell had to cut it.
                tooltipText: appName.truncated ? appSlot.modelData.label : ""
                onPointed: root.cursorRequested(appSlot.index)
                onClicked: root.activated(appSlot.index)

                Item {
                    anchors.centerIn: parent
                    width: root._contentWidth
                    height: root._contentHeight

                    // The app's own themed icon, resolved by the apps
                    // provider with the check every row takes, so a name the
                    // icon theme cannot answer for is "" here rather than a
                    // missing-texture box.
                    Picture {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.iconExtent
                        height: root.iconExtent
                        visible: (appSlot.modelData.iconSource || "") !== ""
                        source: appSlot.modelData.iconSource || ""
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: root.iconExtent * root.pixelRatio
                        sourceSize.height: root.iconExtent * root.pixelRatio
                    }

                    // What an app with no themed icon draws: the apps route's
                    // own mark, dim, which says "an app, no icon of its own"
                    // rather than leaving a name floating over nothing. The
                    // row list renders no icon slot at all there, which a
                    // grid cell cannot do without collapsing.
                    Icon {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: (appSlot.modelData.iconSource || "") === ""
                        name: "layout-grid"
                        size: root.iconExtent
                        color: appCell.dimForeground
                    }

                    Text {
                        id: appName
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: appSlot.modelData.label
                        // A desktop entry's Name reaches this label verbatim,
                        // so it is drawn as the bytes it is rather than
                        // parsed as a rich-text document.
                        textFormat: Text.PlainText
                        color: appCell.foreground
                        font.family: Core.Theme.fontFamilySans
                        font.pixelSize: Core.Theme.fontSize.body
                        font.weight: Core.Theme.weight.medium
                    }
                }
            }
        }

        // Everything the ranking returned that is not an app (M58 G2): the
        // commands, the routes, the calculator's answer, in the order they
        // ranked, drawn as the rows they are everywhere else in the launcher
        // and under the headings they carry there. In the view's own footer
        // rather than beside it, so the grid keeps virtualising its cells and
        // one wheel carries both.
        footer: Item {
            id: tailFooter
            width: grid.width
            height: (root.tailCount > 0 ? tailColumn.y + tailColumn.height : 0) + root.inset

            // Brings the footer row the cursor has landed on into view. The
            // grid's own `currentIndex` does this for the cells; the footer
            // is one item to the view and its rows differ in height, so the
            // row reports its own rect through the scene rather than being
            // computed from a row count.
            //
            // Which row that is gets resolved here rather than handed in
            // when the reveal was queued a tick earlier: a query can rebuild
            // these rows inside that tick, and a delegate that has left the
            // view still answers `mapToItem` as though it sat at the scene's
            // own origin, a whole card above the grid. The scroll is
            // Panel's (Components/cursor.js): the smallest one that puts the
            // row inside the viewport, and never past either end of what
            // the view has to scroll.
            function revealCursorRow() {
                var index = root.cursor - root.appCount;
                if (!grid.contentItem || index < 0 || index >= root.tailCount)
                    return;
                var row = tailRepeater.itemAt(index);
                if (!row)
                    return;
                // Cursor.follow clamps to [0, contentHeight - height], and
                // the header puts this view's range at `originY` instead.
                var origin = grid.originY;
                grid.contentY = origin + Cursor.follow(row.mapToItem(grid.contentItem, 0, 0).y - origin,
                    row.height, grid.contentY - origin, grid.height, grid.contentHeight, 0);
            }

            // The footer rows' cursor, the grid's box on this side of it:
            // the `cell` role's `selected` state, travelling between rows.
            Box {
                id: tailCursor
                readonly property Item slot: {
                    var index = root.cursor - root.appCount;
                    return index >= 0 && index < tailRepeater.count ? tailRepeater.itemAt(index) : null;
                }
                z: -1
                role: "cell"
                state: "selected"
                visible: tailCursor.slot !== null
                x: tailColumn.x
                y: tailCursor.slot ? tailColumn.y + tailCursor.slot.y + tailCursor.slot.band : 0
                width: tailColumn.width
                height: tailCursor.slot ? tailCursor.slot.height - tailCursor.slot.band : 0

                Behavior on y {
                    enabled: root.cursorTravels
                    Anim { kind: "spatialFast" }
                }
            }

            // Straight under the cells, or under the header's inset where
            // there are none: the gap above the first heading is the row's
            // own (MenuRow's `sectionFirst`).
            Column {
                id: tailColumn
                anchors.left: parent.left
                anchors.leftMargin: root._cellGutter
                anchors.right: parent.right
                anchors.rightMargin: root._cellGutter

                Repeater {
                    id: tailRepeater
                    model: root.tailModel

                    delegate: Item {
                        id: tailSlot
                        required property int index
                        required property string rowId
                        readonly property var entry: root.rowsById[tailSlot.rowId] || root.rowsPrev[tailSlot.rowId] || null
                        readonly property var modelData: tailSlot.entry ? tailSlot.entry.row : root.blankRow

                        readonly property int rowIndex: root.appCount + tailSlot.index
                        readonly property bool isCursor: root.cursor === tailSlot.rowIndex
                        // The heading band above the row proper, which the
                        // cursor's box must not swallow.
                        readonly property real band: tailRow._headerBand

                        width: tailColumn.width
                        height: tailRow.height

                        // A tick late: the row's own height and place are
                        // still settling on the frame the cursor arrives.
                        // Nothing is handed over with it, so the reveal
                        // reads the cursor and the rows as they are by then.
                        onIsCursorChanged: if (tailSlot.isCursor) Qt.callLater(tailFooter.revealCursorRow)

                        MenuParts.MenuRow {
                            id: tailRow
                            width: tailSlot.width
                            modelData: tailSlot.modelData
                            index: tailSlot.rowIndex
                            current: tailSlot.isCursor
                            hoverLive: !root.hoverGate || root.hoverGate.live
                            checkedState: Toggles.checkedFor(tailSlot.modelData,
                                root.stateSnapshot, root.checkedResults)
                            confirming: root.confirmPendingId === tailSlot.modelData.id
                            section: tailSlot.entry ? tailSlot.entry.section : ""
                            sectionFirst: tailSlot.entry ? tailSlot.entry.sectionFirst : false

                            onActivate: root.activated(tailSlot.rowIndex)
                            onHoverMoved: (source, x, y) => {
                                if (root.hoverGate && root.hoverGate.moved(source, x, y))
                                    root.cursorRequested(tailSlot.rowIndex);
                            }
                        }
                    }
                }
            }
        }
    }
}
