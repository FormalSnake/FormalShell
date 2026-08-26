import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers

// The emoji route browses the whole 3944-entry dataset since the cap came
// off (tst_menu_emoji.qml owns the search contract). What this file guards
// is that showing all of it stays cheap: the two ways a list that size could
// cost real time are building a row object per entry on every keystroke, and
// instantiating a delegate per entry on every render.
TestCase {
    id: testCase
    name: "EmojiGrid"
    width: 400
    height: 300
    visible: true
    when: windowShown

    property var list: []

    function initTestCase() {
        var done = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) done = true;
        };
        xhr.open("GET", Qt.resolvedUrl("../shell/Menu/emoji.json"));
        xhr.send();
        tryVerify(function () { return done; }, 5000);
        list = Model.parseJsonc(xhr.responseText);
        verify(list.length > 3000);
    }

    // The whole-set build, which is what an empty query does on route entry
    // and what the broadest query does per keystroke. Budget is deliberately
    // loose: this asserts the work is linear and small, not a specific
    // machine's speed. A regression that made it quadratic (a scan per row,
    // an indexOf into a growing array) would blow past this by orders of
    // magnitude rather than by a factor.
    function test_building_every_row_stays_under_the_frame_budget() {
        var t0 = new Date().getTime();
        var rows = Providers.emojiRows(list, "");
        var elapsed = new Date().getTime() - t0;
        compare(rows.length, list.length);
        verify(elapsed < 200, "building " + rows.length + " rows took " + elapsed + "ms");
    }

    // Repeat queries pay for the lowercase memo once, so a held-down key is
    // cheaper than the first press rather than the same cost every time.
    function test_repeat_search_is_not_slower_than_the_first() {
        Providers.emojiRows(list, "face");
        var t0 = new Date().getTime();
        for (var i = 0; i < 5; i++)
            Providers.emojiRows(list, "face");
        var elapsed = new Date().getTime() - t0;
        verify(elapsed < 500, "five repeat searches took " + elapsed + "ms");
    }

    // A grid draws no headings, so the per-row section pass has nothing to
    // produce and must not walk the list to say so.
    function test_a_grid_skips_the_section_pass() {
        compare(Model.sectionsFor(Providers.emojiRows(list, ""), { grid: true, mode: "menu" }).length, 0);
    }

    // The row memo hands the same object back for the same entry, which is
    // what makes a repeat query cost the array and nothing else. Two paste
    // modes are two rows, because `verb` and `action` differ.
    function test_a_row_is_built_once_per_entry() {
        var first = Providers.emojiRows(list, "grinning face")[0];
        var second = Providers.emojiRows(list, "grinning face")[0];
        verify(first === second);
        var copyMode = Providers.emojiRows(list, "grinning face", false)[0];
        verify(copyMode !== first);
        compare(copyMode.verb, "Copy");
        compare(first.verb, "Paste");
    }

    // The load-bearing assumption behind showing all 3944: a GridView whose
    // height is capped (Menu.qml's _rowsAreaCap) instantiates delegates for
    // what it can see plus its cache buffer, never for the model. If this
    // ever stopped holding, browsing emoji would build thousands of items.
    Component {
        id: gridComponent
        GridView {
            property int built: 0
            width: 400
            height: 200
            cellWidth: 50
            cellHeight: 50
            clip: true
            delegate: Item {
                width: 50
                height: 50
                Component.onCompleted: GridView.view.built++
            }
        }
    }

    function test_the_grid_only_builds_what_it_can_show() {
        var model = [];
        for (var i = 0; i < 4000; i++)
            model.push({ n: i });
        var grid = createTemporaryObject(gridComponent, testCase, { model: model });
        verify(grid !== null);
        waitForRendering(grid);
        compare(grid.count, 4000);
        // 8 columns x 4 visible rows is 32 cells; the default cache buffer
        // adds a few rows either side. Anything in the hundreds still proves
        // virtualisation, anything near 4000 proves it broke.
        verify(grid.built < 400, "grid built " + grid.built + " delegates for 4000 items");
    }
}
