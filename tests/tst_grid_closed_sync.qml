import QtQuick
import QtQuick.Window
import QtTest
import "../shell/Menu/rowsync.js" as RowSync

// The launcher's cells model is edited while its window is hidden (every
// tree rebuild between two summons runs `_syncRows`), and the first
// rebuilds land before the window has ever mapped. Checked against Qt
// itself: the delegates a GridView with reused items then files at each
// index against the model it was handed.
TestCase {
    id: testCase
    name: "GridClosedSync"
    width: 400
    height: 400
    visible: true
    when: windowShown

    ListModel {
        id: keyed
    }

    function fill(ids) {
        keyed.clear();
        keyed.append(ids.map(function (id) { return { rowId: id }; }));
    }

    function applyPlan(held, ids) {
        var plan = RowSync.plan(held, ids, 64);
        if (plan.reset) {
            fill(ids);
            return;
        }
        for (var i = 0; i < plan.ops.length; i++) {
            var op = plan.ops[i];
            if (op.op === "remove")
                keyed.remove(op.index);
            else if (op.op === "insert")
                keyed.insert(op.index, { rowId: op.id });
            else
                keyed.move(op.from, op.to, 1);
        }
    }

    function modelIds() {
        var out = [];
        for (var i = 0; i < keyed.count; i++)
            out.push(keyed.get(i).rowId);
        return out;
    }

    function viewIds(grid) {
        var out = [];
        for (var i = 0; i < grid.count; i++) {
            var it = grid.itemAtIndex(i);
            out.push(it ? it.rowId : "?");
        }
        return out;
    }

    Component {
        id: windowComponent
        Window {
            width: 400
            height: 400
            visible: false
            property alias grid: grid
            GridView {
                id: grid
                anchors.fill: parent
                reuseItems: true
                cellWidth: 100
                cellHeight: 100
                model: keyed
                delegate: Item {
                    required property string rowId
                    width: 100
                    height: 100
                }
            }
        }
    }

    function shuffle(ids, seed) {
        var a = ids.slice();
        var s = seed;
        for (var i = a.length - 1; i > 0; i--) {
            s = (s * 1103515245 + 12345) % 2147483648;
            var j = s % (i + 1);
            var t = a[i]; a[i] = a[j]; a[j] = t;
        }
        return a;
    }

    // `shownFirst`: map the window before editing; `hideWhileEditing`: unmap
    // it again for the edits. Six launcher-style syncs, then the view read.
    function run(shownFirst, hideWhileEditing, seed) {
        var win = windowComponent.createObject(testCase);
        var pool = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"];
        var ids = pool.slice(0, 8);
        fill(ids);
        if (shownFirst) {
            win.visible = true;
            waitForRendering(win.grid);
            if (hideWhileEditing)
                win.visible = false;
        }
        var held = ids;
        for (var step = 0; step < 6; step++) {
            var next = shuffle(pool, seed * 31 + step).slice(0, 8);
            applyPlan(held, next);
            held = next;
        }
        win.visible = true;
        waitForRendering(win.grid);
        wait(50);
        var out = { shown: viewIds(win.grid), want: modelIds() };
        win.destroy();
        return out;
    }

    function test_edits_on_a_shown_grid() {
        for (var seed = 1; seed <= 10; seed++) {
            var r = run(true, false, seed);
            compare(r.shown.join(","), r.want.join(","), "seed " + seed);
        }
    }

    function test_edits_on_a_hidden_grid() {
        for (var seed = 1; seed <= 10; seed++) {
            var r = run(true, true, seed);
            compare(r.shown.join(","), r.want.join(","), "seed " + seed);
        }
    }

    function test_edits_on_a_never_shown_grid() {
        for (var seed = 1; seed <= 10; seed++) {
            var r = run(false, false, seed);
            compare(r.shown.join(","), r.want.join(","), "seed " + seed);
        }
    }
}
