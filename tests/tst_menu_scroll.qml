import QtQuick
import QtTest

// Cursor-follow guard for the unified menu's row list
// (shell/Surfaces/Menu/Menu.qml's `rowsView`).
//
// Menu.qml itself is a Quickshell layer-shell window with IPC handlers and
// singletons behind it, so it can't be instantiated under qmltestrunner —
// this mirrors the one part under test structurally verbatim: a clipped
// ListView whose height is `min(contentHeight, cap)`, uniform delegates
// sized from a monospace Text plus the row's own padding and rule, and a
// `currentIndex` driven by the keyboard cursor.
//
// The defect this guards (owner, live shell 2026-08-10: "scrolling down
// goes too except for the last few items, i never see them but they are
// selected"): ListView always creates a highlight item, even with no
// `highlight` component, and the default `highlightMoveDuration: -1` moves
// it at `highlightMoveVelocity` (400px/s). Key repeat outruns that, so the
// viewport lags several rows behind the cursor and takes seconds to settle
// — the tail of a long list is never on screen while the cursor is on it.
// A single `waitForRendering` after the last step is exactly the budget a
// hard jump needs and an animated follow misses.
TestCase {
    id: testCase
    name: "MenuScroll"
    width: 600
    height: 800
    visible: true
    when: windowShown

    Component {
        id: viewComponent

        Item {
            id: host
            width: 500
            height: 700

            property real cap: 420
            readonly property alias view: rowsView

            ListView {
                id: rowsView
                width: 400
                height: Math.min(rowsView.contentHeight, host.cap)
                clip: true
                model: 200
                currentIndex: 0
                highlightMoveDuration: 0

                delegate: Item {
                    required property int index
                    width: ListView.view ? ListView.view.width : 0
                    height: label.implicitHeight + 4 * 2 + 2

                    Text {
                        id: label
                        text: "row " + index
                        font.family: "monospace"
                        font.pixelSize: 14
                    }
                }
            }
        }
    }

    function _verifyCursorRowVisible(view, index) {
        var item = view.itemAtIndex(index);
        verify(item !== null, "row " + index + " has no delegate — outside the viewport");
        verify(item.y >= view.contentY - 0.5,
               "row " + index + " top " + item.y + " above viewport top " + view.contentY);
        verify(item.y + item.height <= view.contentY + view.height + 0.5,
               "row " + index + " bottom " + (item.y + item.height)
               + " below viewport bottom " + (view.contentY + view.height));
    }

    // One row per frame, the shape of a held Down key.
    function test_stepping_to_the_last_row_leaves_it_on_screen() {
        var host = createTemporaryObject(viewComponent, testCase);
        var view = host.view;
        waitForRendering(host);

        for (var i = 1; i < view.count; i++) {
            view.currentIndex = i;
            waitForRendering(host);
        }
        testCase._verifyCursorRowVisible(view, view.count - 1);
    }

    // The wrap back to the top (_moveCursor's modulo) is the same follow in
    // the other direction, over the full content height in one step.
    function test_wrapping_from_the_last_row_to_the_first_scrolls_back() {
        var host = createTemporaryObject(viewComponent, testCase);
        var view = host.view;
        waitForRendering(host);

        view.currentIndex = view.count - 1;
        waitForRendering(host);
        testCase._verifyCursorRowVisible(view, view.count - 1);

        view.currentIndex = 0;
        waitForRendering(host);
        testCase._verifyCursorRowVisible(view, 0);
    }
}
