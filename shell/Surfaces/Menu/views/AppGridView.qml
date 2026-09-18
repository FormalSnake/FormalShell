import QtQuick
import qs.Core as Core
import qs.Components
import ".." as MenuParts
import "../../../Components/cursor.js" as Cursor
import "../../../Menu/appgrid.js" as AppGrid
import "../../../Menu/toggles.js" as Toggles

// The launcher's app grid (M58, behind `menu.appGrid`): Launchpad's reading
// of an app list, an icon large with its name centred under it, in place of
// the row per app the launcher draws by default. The key is off by default,
// so nothing here is on a stock install.
//
// The grid owns the app rows only. Whatever else the ranking returned draws
// as ordinary `MenuRow`s in the view's footer, under a rule, which is why
// Menu/appgrid.js partitions the row list before it ever reaches here: the
// cells are rows 0..appCount-1 and the footer is the rest, so a cell's index
// IS its index in the launcher's own list. Enter, Shift+Enter and the action
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

    // The launcher's own `_displayRows`, already partitioned, and where the
    // apps stop in it.
    property var rows: []
    property int appCount: 0
    property int cursor: 0

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
    // The gutter every cell holds in its own margins. Wider than
    // `Theme.ringWidth`, so a cursor cell's halo lands in the gutter instead
    // of under the neighbour or the grid's own clip.
    readonly property real _cellGutter: Core.Theme.space.sm

    readonly property int columns: AppGrid.columnsFor(root.width, root._cellMin)
    readonly property var appRows: root.rows.slice(0, root.appCount)
    readonly property var tailRows: root.rows.slice(root.appCount)

    readonly property real contentHeight: grid.contentHeight
    readonly property real contentY: grid.contentY

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
        // Delegates recycle rather than being destroyed and rebuilt on every
        // flick, the same contract the two grids in Menu.qml take: every
        // delegate here is required properties plus bindings off them, with
        // no Component.onCompleted work a reused item would skip.
        reuseItems: true
        anchors.fill: parent
        clip: true
        model: root.appRows
        cellWidth: root.columns > 0 ? root.width / root.columns : root.width
        cellHeight: root._contentHeight + Core.Theme.space.controlPaddingY * 2
            + root._cellGutter * 2
        // -1 while the cursor is in the footer: the view would otherwise
        // scroll a cell back into sight over the row the reader is on.
        currentIndex: root.cursor < root.appCount ? root.cursor : -1
        // Same hard-jump follow the launcher's other views take: held arrow
        // keys outrun the default animated highlight move and the cursor
        // cell ends up off-viewport.
        highlightMoveDuration: 0

        // A row here is a row of icons, not a text line.
        WheelScroll {
            flickable: grid
            step: grid.cellHeight
        }

        // The wrapper carries the GridView's own cell so the `Cell` inside it
        // can hold the gutter in its margins, exactly as the wallpaper and
        // emoji grids do.
        delegate: Item {
            id: appSlot
            required property int index
            required property var modelData

            width: grid.cellWidth
            height: grid.cellHeight

            Cell {
                id: appCell
                anchors.fill: parent
                anchors.margins: root._cellGutter
                radius: Core.Theme.radiusMd
                // Ghost, so a grid of forty apps is forty icons rather than
                // forty boxes; hover washes and the cursor is the ring, the
                // two states every other cell in the shell draws.
                ghost: true
                cursor: appSlot.index === root.cursor
                interactive: true
                // The name in full, and only where the cell had to cut it.
                tooltipText: appName.truncated ? appSlot.modelData.label : ""
                onPointerMoved: (x, y) => {
                    if (root.hoverGate && root.hoverGate.moved(appCell, x, y))
                        root.cursorRequested(appSlot.index);
                }
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
                        color: Core.Theme.color.mutedForeground
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
                        color: Core.Theme.color.foreground
                        font.family: Core.Theme.fontFamilySans
                        font.pixelSize: Core.Theme.fontSize.body
                        font.weight: Core.Theme.weight.medium
                    }
                }
            }
        }

        // Everything the ranking returned that is not an app (M58 G2): the
        // commands, the routes, the calculator's answer, in the order they
        // ranked, drawn as the rows they are everywhere else in the launcher.
        // In the view's own footer rather than beside it, so the grid keeps
        // virtualising its cells and one wheel carries both.
        //
        // The seam is a rule (DESIGN.md §1's ladder, rung 4): two halves of
        // one surface that differ in kind, with no name to give the second
        // one that its rows do not already carry.
        footer: Item {
            id: tailFooter
            width: grid.width
            height: root.tailRows.length > 0
                ? tailColumn.y + tailColumn.height + Core.Theme.space.rowGap
                : 0
            visible: root.tailRows.length > 0

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
                if (!grid.contentItem || index < 0 || index >= root.tailRows.length)
                    return;
                var row = tailRepeater.itemAt(index);
                if (!row)
                    return;
                grid.contentY = Cursor.follow(row.mapToItem(grid.contentItem, 0, 0).y,
                    row.height, grid.contentY, grid.height, grid.contentHeight, 0);
            }

            Separator {
                id: tailRule
                anchors.top: parent.top
                anchors.topMargin: Core.Theme.space.rowGap
                anchors.left: parent.left
                anchors.right: parent.right
            }

            Column {
                id: tailColumn
                anchors.top: tailRule.bottom
                anchors.topMargin: Core.Theme.space.rowGap
                anchors.left: parent.left
                anchors.leftMargin: root._cellGutter
                anchors.right: parent.right
                anchors.rightMargin: root._cellGutter

                Repeater {
                    id: tailRepeater
                    model: root.tailRows

                    delegate: Item {
                        id: tailSlot
                        required property int index
                        required property var modelData

                        readonly property int rowIndex: root.appCount + tailSlot.index
                        readonly property bool isCursor: root.cursor === tailSlot.rowIndex

                        width: tailColumn.width
                        height: tailRow.height

                        // A tick late: the row's own height and place are
                        // still settling on the frame the cursor arrives.
                        // Nothing is handed over with it, so the reveal
                        // reads the cursor and the rows as they are by then.
                        onIsCursorChanged: if (tailSlot.isCursor) Qt.callLater(tailFooter.revealCursorRow)

                        // The cursor fill the row list draws under its rows,
                        // drawn per row here: the footer is one item and its
                        // rows do not move under a query, so there is nothing
                        // for a single travelling fill to travel between.
                        // primitive-exempt: the launcher's list is the one
                        // place in the shell with no Cell chrome at all
                        // (MenuRow.qml's header), so its cursor is this bare
                        // fill rather than a primitive's state.
                        Rectangle {
                            anchors.fill: parent
                            radius: Core.Theme.radiusSm
                            color: Core.Theme.color.accent
                            visible: tailSlot.isCursor
                        }

                        MenuParts.MenuRow {
                            id: tailRow
                            width: tailSlot.width
                            modelData: tailSlot.modelData
                            index: tailSlot.rowIndex
                            current: tailSlot.isCursor
                            checkedState: Toggles.checkedFor(tailSlot.modelData,
                                root.stateSnapshot, root.checkedResults)
                            confirming: root.confirmPendingId === tailSlot.modelData.id

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
