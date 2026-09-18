import QtQuick
import QtTest
import "../shell/Components"
import "../shell/Menu/nav.js" as Nav

// The view behaviour the launcher's one sync step (Menu.qml's `_syncRows`,
// M72 T1) is built on, checked against Qt itself rather than assumed:
// Menu.qml cannot be instantiated here (a layer-shell window with IPC and
// singletons behind it), so each case is the part under test, verbatim.
TestCase {
    id: testCase
    name: "MenuViews"
    width: 600
    height: 600
    visible: true
    when: windowShown

    ListModel {
        id: keyed
    }

    function fill(model, ids) {
        model.clear();
        model.append(ids.map(function (id) { return { rowId: id }; }));
    }

    Component {
        id: listComponent

        ListView {
            property int cursor: 0
            width: 300
            height: 300
            model: keyed
            currentIndex: cursor
            highlightMoveDuration: 0
            delegate: Item {
                required property string rowId
                width: 300
                height: 30
            }
        }
    }

    // Why the cursor is asserted rather than bound: an insert above the
    // current item moves the view's currentIndex with that item, and a
    // binding whose value did not change never puts it back. That is the
    // accent fill on one row while Enter acts on another.
    function test_a_bound_current_index_drifts_under_a_keyed_insert() {
        fill(keyed, ["a", "b", "c"]);
        var view = createTemporaryObject(listComponent, testCase);
        verify(view);
        waitForRendering(view);
        compare(view.currentIndex, 0);
        keyed.insert(0, { rowId: "x" });
        view.forceLayout();
        compare(view.cursor, 0);
        compare(view.currentIndex, 1);
        // What `_placeCursor` does after every sync.
        view.currentIndex = 0;
        compare(keyed.get(view.currentIndex).rowId, "x");
    }

    // Assigning the index straight after the ops applies them first, so the
    // index lands on the row the model now holds there.
    function test_an_assigned_current_index_after_the_ops_holds() {
        fill(keyed, ["a", "b", "c"]);
        var view = createTemporaryObject(listComponent, testCase);
        waitForRendering(view);
        keyed.remove(0);
        keyed.insert(2, { rowId: "d" });
        view.currentIndex = 1;
        compare(keyed.get(view.currentIndex).rowId, "c");
        waitForRendering(view);
        compare(view.currentIndex, 1);
    }

    Component {
        id: fieldComponent

        // The launcher's field with its key handler, down to what it hands
        // the field: everything `keyAction` answers "pass" to.
        TextInput {
            property var actions: []
            width: 300
            height: 30
            focus: true
            Keys.onPressed: event => {
                var action = Nav.keyAction(event.key, event.modifiers, event.isAutoRepeat, {
                    mode: "menu", query: text.length > 0, grid: true,
                    appView: false, scrollable: false, variants: false
                });
                if (action === "pass")
                    return;
                event.accepted = true;
                actions.push(action);
            }
        }
    }

    // The grid owns the plain arrows, and the field still edits by word:
    // Ctrl+Left moves the caret, Ctrl+Backspace deletes, and neither reaches
    // the results.
    function test_the_field_edits_by_word_while_the_grid_owns_the_arrows() {
        var field = createTemporaryObject(fieldComponent, testCase);
        verify(field);
        field.forceActiveFocus();
        field.text = "fire fox";
        field.cursorPosition = field.text.length;
        keyClick(Qt.Key_Left);
        compare(field.cursorPosition, 8);
        compare(field.actions.join(","), "left");
        keyClick(Qt.Key_Left, Qt.ControlModifier);
        compare(field.cursorPosition, 5);
        field.cursorPosition = field.text.length;
        keyClick(Qt.Key_Backspace, Qt.ControlModifier);
        compare(field.text, "fire ");
        compare(field.actions.join(","), "left");
    }

    ListModel {
        id: cells
    }

    Component {
        id: gridComponent

        GridView {
            width: 300
            height: 300
            cellWidth: 100
            cellHeight: 100
            model: cells
            delegate: Item {
                required property string rowId
                width: 100
                height: 100
            }
            footer: Item {
                width: 300
                height: 40
            }
        }
    }

    // The app grid with no app hits: no cells, and the rows under them (the
    // footer) at the top of the view rather than where the cells used to end.
    function test_a_grid_with_no_cells_still_lays_out_its_footer_at_the_top() {
        fill(cells, ["a", "b", "c", "d", "e"]);
        var grid = createTemporaryObject(gridComponent, testCase);
        verify(grid);
        waitForRendering(grid);
        verify(grid.footerItem);
        compare(grid.footerItem.y, 200);
        fill(cells, []);
        grid.forceLayout();
        waitForRendering(grid);
        verify(grid.footerItem);
        compare(grid.contentHeight, 40);
        compare(grid.footerItem.y - grid.originY, 0);
    }

    Component {
        id: flickComponent

        Flickable {
            id: flick
            width: 300
            height: 200
            contentHeight: 2000
            property alias wheel: wheelScroll

            WheelScroll {
                id: wheelScroll
                flickable: flick
                step: 100
            }
        }
    }

    // A keyboard move scrolls the view to its cursor while a notch is still
    // gliding: without the cancel, the glide writes its next frame over it.
    function test_a_cancelled_glide_stops_writing_the_view() {
        var flick = createTemporaryObject(flickComponent, testCase);
        verify(flick);
        waitForRendering(flick);
        mouseWheel(flick, 150, 100, 0, -120);
        tryVerify(function () { return flick.contentY > 0; }, 1000);
        flick.wheel.cancel();
        flick.contentY = 20;
        wait(300);
        compare(flick.contentY, 20);
    }

    // And left alone, the glide reaches the notch's own target.
    function test_a_notch_glides_to_one_step() {
        var flick = createTemporaryObject(flickComponent, testCase);
        waitForRendering(flick);
        mouseWheel(flick, 150, 100, 0, -120);
        tryCompare(flick, "contentY", 100, 2000);
    }
}
