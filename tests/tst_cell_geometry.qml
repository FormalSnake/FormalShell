import QtQuick
import QtTest
import "../shell/Components"

// Geometry regression guard for THE ledger cell (shell/Components/Cell.qml).
//
// The real Theme singleton is a Quickshell Singleton, so these tests run
// against tests/stubs/qs/Core/Theme.qml (same palette.js/tokens.js values)
// via qmltestrunner's -import, wired up in the justfile/flake test calls.
// space.lg is 8, space.sm is 4, borderWidth is 2 at the default scale;
// they are spelled out in the expectations so a token change has to be a
// deliberate edit here too.
TestCase {
    id: testCase
    name: "CellGeometry"
    width: 400
    height: 400
    visible: true
    when: windowShown

    // The bluetooth panel's device row, structurally verbatim
    // (BluetoothPanel.qml's `deviceRow` component): a parent-width Cell
    // wrapping a Column of a name row and a status sub-line, with a
    // hover-revealed FORGET sub-Cell that sizes itself from its own
    // implicit size while carrying a fill-anchored MouseArea.
    Component {
        id: deviceRowComponent

        Cell {
            id: btCell

            property real rowWidth: 320
            readonly property Item probeForget: forgetCell
            readonly property Item probeForgetLabel: forgetLabel
            readonly property Item probeName: nameText
            readonly property Item probeNameRow: nameRow
            readonly property Item probeStatus: statusText

            width: rowWidth
            selected: true

            Column {
                width: parent.width
                spacing: 2

                Item {
                    id: nameRow
                    width: parent.width
                    height: Math.max(nameText.implicitHeight, forgetCell.height)

                    Text {
                        id: nameText
                        anchors.left: parent.left
                        anchors.right: forgetCell.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: "WH-1000XM4"
                        color: btCell.foreground
                        elide: Text.ElideRight
                        font.family: "monospace"
                        font.pixelSize: 13
                    }

                    Cell {
                        id: forgetCell
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: implicitWidth
                        height: implicitHeight

                        MetaLabel { id: forgetLabel; text: "FORGET" }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }

                    MouseArea {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: forgetCell.left
                        hoverEnabled: true
                    }
                }

                Text {
                    id: statusText
                    text: "CONNECTED"
                    color: btCell.foreground
                    font.family: "monospace"
                    font.pixelSize: 11
                }
            }
        }
    }

    // A bar cell (Clock.qml's shape): implicitly sized in both axes, a
    // vertically centred Column in the default slot, and the cell's own
    // pointer target rather than one the call site built.
    Component {
        id: barCellComponent

        Cell {
            id: barCell

            readonly property Item probeColumn: column
            property int clicks: 0

            standalone: true
            interactive: true
            onClicked: barCell.clicks++

            Column {
                id: column
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                MetaLabel { text: "TIME" }

                Text {
                    text: "09:41"
                    color: barCell.foreground
                    font.family: "monospace"
                    font.pixelSize: 13
                }
            }
        }
    }

    // A plain content cell: one intrinsically sized child, no fill-anchored
    // sibling. This is the shape the childrenRect measurement always got
    // right, so it pins the padding arithmetic against regression.
    Component {
        id: plainCellComponent

        Cell {
            readonly property Item probeLabel: label
            MetaLabel { id: label; text: "NO ADAPTER" }
        }
    }

    // MenuActionBar's shape: a cell whose left half is a button and whose
    // right half is an inert legend, so it builds a partial target in `hit`
    // instead of taking the cell-wide `interactive` one.
    Component {
        id: actionBarComponent

        Cell {
            id: actionBar

            readonly property Item probeHalf: half
            property int clicks: 0

            width: 200

            MetaLabel { text: "SELECT" }

            hit: MouseArea {
                id: half
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 60
                onClicked: actionBar.clicks++
            }
        }
    }

    // The media panel's two awkward children. The progress track is a
    // Rectangle, which has no implicit size at all; the album art is sized
    // to a 96px slot while its own implicit size is the source image's
    // (192px). Both are measured by the size they were given, which is what
    // childrenRect did and what the panel's layout expects.
    Component {
        id: mediaCellsComponent

        Column {
            readonly property Item probeTrackCell: trackCell
            readonly property Item probeArtCell: artCell
            readonly property Item probeTrack: track
            width: 320

            Cell {
                id: artCell
                width: parent.width

                Item {
                    width: 96
                    height: 96
                    implicitWidth: 192
                    implicitHeight: 192
                }
            }

            Cell {
                id: trackCell
                width: parent.width

                Rectangle {
                    id: track
                    width: parent.width
                    height: 6
                    color: "#808080"
                }
            }
        }
    }

    function settle(item) {
        waitForRendering(item);
        wait(50);
    }

    function test_device_row_sizes_its_forget_cell_from_its_own_content() {
        failOnWarning(/Binding loop/);
        var row = createTemporaryObject(deviceRowComponent, testCase);
        verify(row);
        settle(row);

        // The FORGET cell measures its own label plus the cell padding.
        // Deriving the implicit size from childrenRect instead fed the
        // fill-anchored MouseArea's width (which is the cell's own width,
        // minus padding) straight back into it.
        var forget = row.probeForget;
        compare(forget.implicitWidth, row.probeForgetLabel.implicitWidth + 8 * 2 + 2);
        compare(forget.implicitHeight, row.probeForgetLabel.implicitHeight + 4 * 2 + 2);
        compare(forget.width, forget.implicitWidth);
        compare(forget.height, forget.implicitHeight);
        verify(forget.width < row.width / 2);
    }

    function test_device_row_keeps_a_nonzero_height() {
        failOnWarning(/Binding loop/);
        var row = createTemporaryObject(deviceRowComponent, testCase);
        verify(row);
        settle(row);

        // Name row (one body line, or the FORGET cell if taller) + 2px
        // column spacing + the caption status line + the cell's own
        // vertical padding and rule reserve. A collapsed row renders
        // nothing at all on a panel, which is the bug this guards.
        var nameRowHeight = Math.max(row.probeName.implicitHeight, row.probeForget.height);
        compare(row.probeNameRow.height, nameRowHeight);
        compare(row.implicitHeight, nameRowHeight + 2 + row.probeStatus.height + 4 * 2 + 2);
        compare(row.height, row.implicitHeight);
        verify(row.height > 0);
        verify(row.probeName.width > 0);
    }

    function test_bar_cell_sizes_to_its_content_in_both_axes() {
        failOnWarning(/Binding loop/);
        var cell = createTemporaryObject(barCellComponent, testCase);
        verify(cell);
        settle(cell);

        // standalone: no rule reserve, so padding is exactly space.lg * 2
        // by space.sm * 2 around the column. The `hit` layer (which is the
        // cell's full size) and the vertically centred column's own offset
        // must not contribute.
        var column = cell.probeColumn;
        compare(cell.implicitWidth, column.implicitWidth + 8 * 2);
        compare(cell.implicitHeight, column.implicitHeight + 4 * 2);
        compare(cell.width, cell.implicitWidth);
        compare(cell.height, cell.implicitHeight);
        compare(column.y, 0);
    }

    function test_pointer_reaches_every_corner_of_the_cell() {
        failOnWarning(/Binding loop/);
        var cell = createTemporaryObject(barCellComponent, testCase);
        verify(cell);
        settle(cell);

        // The hover fill covers the cell, so the pointer target has to as
        // well. A MouseArea built at the call site lands in the default slot,
        // which is inset by the control padding: 8px either side and 4px top
        // and bottom answered nothing while still lighting up, and on the bar
        // that top band is the row of pixels against the screen edge.
        //
        // The content really is inset by that padding, so these points are
        // not inside it and the check isn't passing by accident.
        compare(cell.probeColumn.mapToItem(cell, 0, 0).x, 8);

        var corners = [[1, 1], [cell.width - 1, 1], [1, cell.height - 1], [cell.width - 1, cell.height - 1]];
        for (var i = 0; i < corners.length; i++) {
            mouseMove(cell, corners[i][0], corners[i][1]);
            settle(cell);
            verify(cell.containsPointer);
            // Nothing bound `hovered`, so it follows the pointer on its own.
            verify(cell.hovered);

            mouseClick(cell, corners[i][0], corners[i][1]);
            compare(cell.clicks, i + 1);
        }
    }

    function test_a_cell_that_never_opted_in_stays_inert() {
        var cell = createTemporaryObject(plainCellComponent, testCase);
        verify(cell);
        settle(cell);

        // `interactive` is the whole opt-in: an ordinary content cell must
        // not light up under the pointer, and must not eat the click.
        mouseMove(cell, cell.width / 2, cell.height / 2);
        settle(cell);
        compare(cell.containsPointer, false);
        compare(cell.hovered, false);
    }

    function test_hit_slot_spans_the_cell_for_a_partial_target() {
        var cell = createTemporaryObject(actionBarComponent, testCase);
        verify(cell);
        settle(cell);

        // MenuActionBar's shape: only part of the cell is a button, so it
        // builds its own target in `hit`. That slot spans the cell, so the
        // target starts at the cell's own edge and covers the padding the
        // content box leaves out.
        var origin = cell.probeHalf.mapToItem(cell, 0, 0);
        compare(origin.x, 0);
        compare(origin.y, 0);
        compare(cell.probeHalf.height, cell.height);

        mouseClick(cell, 1, 1);
        compare(cell.clicks, 1);

        // Past the target's own width, and still inside the cell: inert.
        mouseClick(cell, cell.width - 1, cell.height - 1);
        compare(cell.clicks, 1);
    }

    function test_cell_measures_children_by_the_size_they_were_given() {
        failOnWarning(/Binding loop/);
        var cells = createTemporaryObject(mediaCellsComponent, testCase);
        verify(cells);
        settle(cells);

        // The art slot, not the source image's own 192px implicit size.
        compare(cells.probeArtCell.implicitHeight, 96 + 4 * 2 + 2);
        compare(cells.probeArtCell.height, cells.probeArtCell.implicitHeight);

        // A Rectangle has no implicit size at all, so measuring implicit
        // sizes alone would collapse the track row to its padding.
        compare(cells.probeTrack.height, 6);
        compare(cells.probeTrackCell.implicitHeight, 6 + 4 * 2 + 2);
        compare(cells.probeTrackCell.height, cells.probeTrackCell.implicitHeight);
        // The track stretches to the cell it was given, and reports that
        // width back as the cell's own implicit width.
        compare(cells.probeTrack.width, 320 - 8 * 2 - 2);
        compare(cells.probeTrackCell.implicitWidth, 320);
    }

    function test_plain_cell_pads_its_single_child() {
        failOnWarning(/Binding loop/);
        var cell = createTemporaryObject(plainCellComponent, testCase);
        verify(cell);
        settle(cell);

        compare(cell.implicitWidth, cell.probeLabel.implicitWidth + 8 * 2 + 2);
        compare(cell.implicitHeight, cell.probeLabel.implicitHeight + 4 * 2 + 2);

        // The label sits inside the cell's own padding, and the cell hugs
        // it: leading gutter in, trailing gutter plus the rule reserve out.
        var origin = cell.probeLabel.mapToItem(cell, 0, 0);
        compare(origin.x, 8);
        compare(origin.y, 4);
        compare(cell.width - (origin.x + cell.probeLabel.width), 8 + 2);
        compare(cell.height - (origin.y + cell.probeLabel.height), 4 + 2);
    }
}
