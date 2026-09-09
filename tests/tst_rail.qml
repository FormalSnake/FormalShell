import QtQuick
import QtTest
import "../shell/Components"

// Rail.qml: the one positioner the bar's regions and group rows share,
// which lays the same children out as a row or, with `vertical`, as a
// column. Pinned here because it leans on Qt reading a non-positive
// `rows`/`columns` as unset, which nothing in Grid's own documentation
// promises.
TestCase {
    id: testCase
    name: "Rail"
    width: 400
    height: 400
    visible: true
    when: windowShown

    Component {
        id: railComponent

        Rail {
            id: rail
            property bool stood: false
            readonly property Item probeA: a
            readonly property Item probeB: b
            readonly property Item probeC: c
            vertical: rail.stood
            spacing: 4

            Rectangle { id: a; width: 30; height: 20 }
            Rectangle { id: b; width: 30; height: 20 }
            Rectangle { id: c; width: 30; height: 20 }
        }
    }

    function test_a_rail_is_a_row() {
        var rail = createTemporaryObject(railComponent, testCase);
        verify(rail);
        waitForRendering(rail);
        compare(rail.probeA.x, 0);
        compare(rail.probeB.x, 34);
        compare(rail.probeC.x, 68);
        compare(rail.probeC.y, 0);
        compare(rail.implicitWidth, 98);
        compare(rail.implicitHeight, 20);
    }

    function test_a_stood_rail_is_a_column() {
        var rail = createTemporaryObject(railComponent, testCase, { stood: true });
        verify(rail);
        waitForRendering(rail);
        compare(rail.probeA.y, 0);
        compare(rail.probeB.y, 24);
        compare(rail.probeC.y, 48);
        compare(rail.probeC.x, 0);
        compare(rail.implicitWidth, 30);
        compare(rail.implicitHeight, 68);
    }

    // The bar switches the same rail between the two when bar.position
    // changes under it, so both directions have to hold on one item.
    // Waited for rather than read off the next frame: a rail carries a child
    // it re-places to its new slot (M53 D2), so the frame after the switch
    // has it partway there. The slot it ends at is the claim.
    function test_a_rail_stands_up_and_lies_back_down() {
        var rail = createTemporaryObject(railComponent, testCase);
        verify(rail);
        waitForRendering(rail);
        rail.stood = true;
        tryCompare(rail.probeC, "y", 48);
        tryCompare(rail.probeC, "x", 0);
        rail.stood = false;
        tryCompare(rail.probeC, "x", 68);
        tryCompare(rail.probeC, "y", 0);
    }

    // A hidden child takes no slot, the same as in a Row.
    function test_a_hidden_child_takes_no_slot() {
        var rail = createTemporaryObject(railComponent, testCase, { stood: true });
        verify(rail);
        rail.probeB.visible = false;
        tryCompare(rail.probeC, "y", 24);
        tryCompare(rail, "implicitHeight", 44);
    }

    // `animate: false` is what a strip that is itself arriving takes: the
    // re-place lands in the frame it was asked for rather than being
    // travelled to, so a card built fresh on open (BarOverflow.qml) opens
    // with its cells already in their slots. Compared on the next frame,
    // not waited for, which is the whole claim.
    function test_a_flat_rail_re_places_in_one_frame() {
        var rail = createTemporaryObject(railComponent, testCase, { animate: false });
        verify(rail);
        waitForRendering(rail);
        rail.probeA.width = 60;
        waitForRendering(rail);
        compare(rail.probeB.x, 64);
        compare(rail.probeC.x, 98);
    }
}
