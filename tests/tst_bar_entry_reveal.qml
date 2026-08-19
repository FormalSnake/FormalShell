import QtQuick
import QtTest

// Bar.qml's region delegate decides whether an entry is on screen at all,
// and it used to decide it from a MEASUREMENT of the entry it had just
// hidden. That closes a cycle — visible reads width, width reads the
// hosted item's implicitWidth, and a positioner inside a Loader the same
// binding has hidden contributes nothing to measure — so a widget that
// starts with nothing to show and later has something (Indicators when the
// first glyph turns on, Tray registering its first item, NowPlaying
// finding a player) stayed 0-wide and invisible for the rest of the
// session (g815, 2026-08-19: a live screen recording and a stay-awake
// toggle were both invisible on their own, and both appeared the moment a
// pending reminder — the row's one cell with a per-second label, which
// re-measures itself out of the deadlock — was put beside them).
//
// Both gates are built here over the same item so the test cannot rot into
// a tautology: `oldGate` is the expression that shipped, `newGate` is the
// one that replaced it, and the point is that they disagree.
TestCase {
    id: testCase
    name: "BarEntryReveal"
    width: 200
    height: 40
    visible: true
    when: windowShown

    // Stands in for a bar widget that hides itself: a Row of cells, each
    // shown only while its own condition holds, exposing the condition a
    // second time under `shown` (the contract Bar.qml's delegate reads,
    // since reading a Loader-hosted item's built-in `visible` detaches that
    // item's own binding).
    Component {
        id: widgetComponent

        Row {
            id: widgetRow
            property bool active: false
            readonly property bool shown: widgetRow.active
            spacing: 4
            visible: widgetRow.shown

            Rectangle {
                width: 18
                height: 18
                visible: widgetRow.active
            }
        }
    }

    // Bar.qml's delegate, both gates side by side. `collapsible` is false
    // here, which is every entry in a region with no chevron and every
    // entry outboard of one.
    Component {
        id: delegateComponent

        Loader {
            id: entryLoader
            property bool collapsible: false
            readonly property bool _shown: entryLoader.item
                ? (entryLoader.item.shown !== undefined ? entryLoader.item.shown : true)
                : false
            readonly property bool oldGate: entryLoader.width > 0 && entryLoader._shown
            readonly property bool newGate: entryLoader._shown
                && (!entryLoader.collapsible || entryLoader.width > 0)

            sourceComponent: widgetComponent
            clip: true
            height: 20
            width: entryLoader.implicitWidth
            visible: entryLoader.newGate
        }
    }

    function test_a_widget_with_nothing_to_show_is_not_on_screen() {
        var entry = createTemporaryObject(delegateComponent, testCase);
        verify(entry.item);
        compare(entry.item.shown, false);
        compare(entry.newGate, false);
        compare(entry.visible, false);
    }

    // The regression itself. Waiting on the gate rather than comparing it
    // straight away, so a delegate that merely needs a frame to settle
    // passes: the failure being guarded is permanent, not slow.
    function test_a_widget_that_gains_content_becomes_visible() {
        var entry = createTemporaryObject(delegateComponent, testCase);
        verify(entry.item);
        entry.item.active = true;
        tryCompare(entry, "newGate", true, 2000);
        tryCompare(entry, "visible", true, 2000);
        tryVerify(function () { return entry.width > 0; }, 2000,
            "the entry never got a width, so nothing would be drawn in its slot");
    }

    // And the shipped bug, pinned: the old gate never recovers, because the
    // only thing that could give it a width is the layout it is suppressing.
    // If this ever starts passing, the underlying toolkit behaviour changed
    // and the comment above needs revisiting — it does not mean the new gate
    // is unnecessary.
    function test_the_measured_width_gate_never_recovers() {
        var entry = createTemporaryObject(delegateComponent, testCase);
        verify(entry.item);
        entry.visible = Qt.binding(function () { return entry.oldGate; });
        entry.item.active = true;
        wait(300);
        compare(entry.oldGate, false);
        compare(entry.visible, false);
    }
}
