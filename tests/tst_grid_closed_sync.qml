import QtQuick
import QtQuick.Window
import QtTest
import "../shell/Menu/rowsync.js" as RowSync

// The launcher's cells model is edited while its window is hidden (every
// tree rebuild between two summons runs `_syncRows`), so the GridView
// applies the accumulated moves and inserts on the next map. This checks
// the delegates the view then shows against the model it was handed.
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

    // What the view itself files at each index, and every delegate still
    // painted inside the viewport that is not one of those: a ghost.
    function delegateIds(grid) {
        var byIndex = [];
        var own = {};
        for (var i = 0; i < grid.count; i++) {
            var it = grid.itemAtIndex(i);
            byIndex.push(it ? it.rowId : "?");
            if (it) own[it] = true;
        }
        var ghosts = [];
        var kids = grid.contentItem.children;
        for (var k = 0; k < kids.length; k++) {
            var c = kids[k];
            if (c.rowId === undefined || own[c] || !c.visible || c.opacity === 0)
                continue;
            if (c.y + c.height <= grid.contentY || c.y >= grid.contentY + grid.height)
                continue;
            ghosts.push(c.rowId + "@" + c.x + "," + c.y + (c.pooled ? "[pooled]" : "[live]"));
        }
        return { byIndex: byIndex, ghosts: ghosts };
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
                    id: cell
                    required property string rowId
                    property bool pooled: false
                    width: 100
                    height: 100
                    GridView.onPooled: cell.pooled = true
                    GridView.onReused: cell.pooled = false
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.hsla((cell.rowId.charCodeAt(0) - 97) / 10, 1, 0.5, 1)
                    }
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

    function run(hiddenWhileEditing, seed) {
        var win = windowComponent.createObject(testCase);
        var pool = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"];
        var ids = pool.slice(0, 8);
        fill(ids);
        win.visible = true;
        waitForRendering(win.grid);
        if (hiddenWhileEditing)
            win.visible = false;
        var held = ids;
        for (var step = 0; step < 6; step++) {
            var next = shuffle(pool, seed + step).slice(0, 8);
            applyPlan(held, next);
            held = next;
        }
        win.visible = true;
        waitForRendering(win.grid);
        wait(50);
        var shown = delegateIds(win.grid);
        var want = modelIds();
        var img = grabImage(win.grid);
        var painted = [];
        for (var p = 0; p < want.length; p++) {
            var px = (p % 4) * 100 + 50, py = Math.floor(p / 4) * 100 + 50;
            var c = img.pixel(px, py);
            var hue = Math.round(Qt.color(c).hslHue * 10);
            painted.push(String.fromCharCode(97 + (hue % 10)));
        }
        shown.painted = painted;
        win.destroy();
        return { shown: shown.byIndex, ghosts: shown.ghosts, painted: shown.painted, want: want };
    }

    // Eight cells down to four while shown: the slots the model no longer
    // fills must paint nothing, whatever the view keeps pooled there.
    function test_a_shrink_leaves_the_freed_slots_blank() {
        var win = windowComponent.createObject(testCase);
        var ids = ["a", "b", "c", "d", "e", "f", "g", "h"];
        fill(ids);
        win.visible = true;
        waitForRendering(win.grid);
        applyPlan(ids, ["a", "b", "c", "d"]);
        waitForRendering(win.grid);
        wait(50);
        var img = grabImage(win.grid);
        var pooled = [];
        var kids = win.grid.contentItem.children;
        for (var k = 0; k < kids.length; k++) {
            if (kids[k].rowId !== undefined && kids[k].pooled)
                pooled.push(kids[k].rowId + " visible=" + kids[k].visible + " parent=" + (kids[k].parent === win.grid.contentItem));
        }
        var slot6 = img.pixel(250, 150);
        win.destroy();
        console.log("pooled:", pooled.join("; "), "slot6:", slot6);
        compare(String(slot6), String(Qt.color("transparent")) === String(slot6) ? String(slot6) : "blank", "freed slot painted " + slot6);
    }

    // The launcher's first rebuilds land before its window ever maps:
    // state.json loads after the first tree, and the reorder it brings
    // reaches a GridView that has never laid out.
    function test_edits_on_a_never_shown_grid() {
        for (var seed = 1; seed <= 10; seed++) {
            var win = windowComponent.createObject(testCase);
            var pool = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"];
            var ids = pool.slice(0, 8);
            fill(ids);
            var held = ids;
            for (var step = 0; step < 6; step++) {
                var next = shuffle(pool, seed * 31 + step).slice(0, 8);
                applyPlan(held, next);
                held = next;
            }
            win.visible = true;
            waitForRendering(win.grid);
            wait(50);
            var shown = delegateIds(win.grid);
            var want = modelIds();
            win.destroy();
            compare(shown.byIndex.join(","), want.join(","), "seed " + seed);
        }
    }

    function test_edits_on_a_shown_grid() {
        for (var seed = 1; seed <= 10; seed++) {
            var r = run(false, seed);
            compare(r.shown.join(","), r.want.join(","), "seed " + seed);
            compare(r.painted.join(","), r.want.join(","), "painted, seed " + seed);
            compare(r.ghosts.join(" "), "", "ghosts, seed " + seed);
        }
    }

    function test_edits_on_a_hidden_grid() {
        for (var seed = 1; seed <= 10; seed++) {
            var r = run(true, seed);
            compare(r.shown.join(","), r.want.join(","), "seed " + seed);
            compare(r.painted.join(","), r.want.join(","), "painted, seed " + seed);
            compare(r.ghosts.join(" "), "", "ghosts, seed " + seed);
        }
    }
}
