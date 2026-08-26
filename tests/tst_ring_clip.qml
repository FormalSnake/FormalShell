import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// The ring reservation (DESIGN.md §1 "Ring", M48 D2). The focus ring is a
// halo drawn `ringWidth` OUTSIDE an item's own bounds, so an item sitting
// flush against the edge of a clipping container loses that band: the top
// row of every panel list, the notification centre and the launcher all had
// their cursor ring cut off along one side.
//
// The rule is on the container, never on the surface: a clipping container
// grows its clip rect by `ringWidth` on every side and insets its content by
// the same amount, so a row keeps the x, width and top it had without a ring
// and the halo has somewhere to land. Panel.qml's contentFlickable is the
// shipped instance; this rebuilds the same shape around a real `Cell` and
// measures the halo against the clip rect.
TestCase {
    id: testCase
    name: "RingClip"
    width: 500
    height: 300
    visible: true
    when: windowShown

    // The clip rect grown on every side, with the content inset to match:
    // the shape Panel.qml builds around its content column.
    Component {
        id: reservedComponent

        Item {
            id: container
            property alias cell: reservedCell
            readonly property real inset: Theme.ringWidth

            width: 200
            height: 120

            Item {
                id: clipper
                objectName: "clipper"
                x: -container.inset
                y: -container.inset
                width: container.width + container.inset * 2
                height: container.height + container.inset * 2
                clip: true

                Cell {
                    id: reservedCell
                    x: container.inset
                    y: container.inset
                    width: container.width
                    cursor: true
                }
            }
        }
    }

    // The same list with no reservation at all, which is what every clipping
    // container in the shell used to be.
    Component {
        id: flushComponent

        Item {
            id: container
            property alias cell: flushCell

            width: 200
            height: 120

            Item {
                id: clipper
                objectName: "clipper"
                anchors.fill: parent
                clip: true

                Cell {
                    id: flushCell
                    x: 0
                    y: 0
                    width: container.width
                    cursor: true
                }
            }
        }
    }

    function make(component) {
        var item = createTemporaryObject(component, testCase);
        verify(item);
        waitForRendering(item);
        wait(50);
        return item;
    }

    function clipperOf(item) {
        for (var i = 0; i < item.children.length; i++) {
            if (item.children[i].objectName === "clipper")
                return item.children[i];
        }
        return null;
    }

    // The halo is the cell's first painted layer, a rounded rectangle at
    // negative `ringWidth` margins (Cell.qml).
    function halo(cell) {
        return cell.children[0];
    }

    // The halo's own rect in the clipping container's coordinates.
    function haloRect(cell, clipper) {
        var h = halo(cell);
        var topLeft = cell.mapToItem(clipper, h.x, h.y);
        return { left: topLeft.x, top: topLeft.y, right: topLeft.x + h.width, bottom: topLeft.y + h.height };
    }

    function test_the_halo_exists_and_is_the_ring() {
        var item = make(reservedComponent);
        var h = halo(item.cell);
        verify(h.visible);
        verify(Qt.colorEqual(h.color, Theme.color.ring));
    }

    function test_a_reserved_container_holds_the_whole_halo() {
        var item = make(reservedComponent);
        var clipper = clipperOf(item);
        verify(clipper);
        var rect = haloRect(item.cell, clipper);
        verify(rect.left >= 0);
        verify(rect.top >= 0);
        verify(rect.right <= clipper.width);
        verify(rect.bottom <= clipper.height);
    }

    // The reservation costs the row nothing: it sits where it would without
    // one, at the same width, which is what keeps a panel's rows lined up
    // with its header.
    function test_the_reservation_does_not_move_the_row() {
        var reserved = make(reservedComponent);
        var flush = make(flushComponent);
        var clipper = clipperOf(reserved);
        var topLeft = reserved.cell.mapToItem(clipper, 0, 0);
        compare(topLeft.x - reserved.inset, flush.cell.x);
        compare(topLeft.y - reserved.inset, flush.cell.y);
        compare(reserved.cell.width, flush.cell.width);
    }

    // The failure the rule exists for: without the reservation the halo runs
    // past the clip rect on both the left and the top, so the ring on the
    // first row is drawn with two sides missing.
    function test_a_flush_container_cuts_the_halo() {
        var item = make(flushComponent);
        var clipper = clipperOf(item);
        var rect = haloRect(item.cell, clipper);
        compare(rect.left, -Theme.ringWidth);
        compare(rect.top, -Theme.ringWidth);
    }
}
