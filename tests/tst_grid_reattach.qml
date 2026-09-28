import QtQuick
import QtTest

// The launcher's views give up their model whenever another view is live
// (Menu.qml's `_attachViews`) and take it back on the way home. On Qt 6.11 a
// delegate pooled before that swap comes back out of the pool with its
// required properties still bound to the old model: a grid of eight read
// back h,g,f,e,d,c,b,a over a model holding a..h, which drew in the
// launcher as nameless placeholder cells and as rows shown twice. Checked
// against Qt itself, with the views' own `reuseItems: !!model` gate.
TestCase {
    id: testCase
    name: "GridReattach"
    width: 400
    height: 400
    visible: true
    when: windowShown

    ListModel {
        id: keyed
    }

    function fill(ids) {
        keyed.clear();
        if (ids.length > 0)
            keyed.append(ids.map(function (id) { return { rowId: id }; }));
    }

    function modelIds() {
        var out = [];
        for (var i = 0; i < keyed.count; i++)
            out.push(keyed.get(i).rowId);
        return out;
    }

    function viewIds(view) {
        var out = [];
        for (var i = 0; i < view.count; i++) {
            var it = view.itemAtIndex(i);
            out.push(it ? it.rowId : "?");
        }
        return out;
    }

    Component {
        id: gridComponent
        GridView {
            id: grid
            width: 400
            height: 400
            reuseItems: !!grid.model
            cellWidth: 100
            cellHeight: 100
            delegate: Item {
                required property string rowId
                width: 100
                height: 100
            }
        }
    }

    Component {
        id: listComponent
        ListView {
            id: list
            width: 400
            height: 400
            reuseItems: !!list.model
            delegate: Item {
                required property string rowId
                width: 400
                height: 40
            }
        }
    }

    // Root grid, a query that leaves one cell (seven pooled), another view
    // takes over, then back at root with the same eight or a different eight.
    function run(component, back) {
        var view = component.createObject(testCase);
        fill(["a", "b", "c", "d", "e", "f", "g", "h"]);
        view.model = keyed;
        waitForRendering(view);
        fill(["a"]);
        waitForRendering(view);
        view.model = null;
        fill(["r1", "r2", "r3"]);
        fill(back);
        view.model = keyed;
        waitForRendering(view);
        var out = { shown: viewIds(view).join(","), want: modelIds().join(",") };
        view.destroy();
        return out;
    }

    function test_grid_reattached_to_the_same_ids() {
        var r = run(gridComponent, ["a", "b", "c", "d", "e", "f", "g", "h"]);
        compare(r.shown, r.want);
    }

    function test_grid_reattached_to_other_ids() {
        var r = run(gridComponent, ["p", "q", "r", "s", "t", "u", "v", "w"]);
        compare(r.shown, r.want);
    }

    function test_list_reattached_to_other_ids() {
        var r = run(listComponent, ["p", "q", "r", "s", "t", "u", "v", "w"]);
        compare(r.shown, r.want);
    }

    // The gate still pools while attached: a delegate scrolled or filtered
    // out is reused, not rebuilt, under the model it was pooled for.
    function test_pools_while_attached() {
        var view = gridComponent.createObject(testCase);
        fill(["a", "b", "c", "d", "e", "f", "g", "h"]);
        view.model = keyed;
        waitForRendering(view);
        var first = view.itemAtIndex(7);
        fill(["a"]);
        waitForRendering(view);
        fill(["p", "q", "r", "s", "t", "u", "v", "w"]);
        waitForRendering(view);
        var reused = false;
        for (var i = 0; i < view.count; i++)
            reused = reused || view.itemAtIndex(i) === first;
        verify(reused, "a pooled delegate was reused while the model stayed");
        compare(viewIds(view).join(","), modelIds().join(","));
        view.destroy();
    }
}
