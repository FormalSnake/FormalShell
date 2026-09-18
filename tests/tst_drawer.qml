import QtQuick
import QtTest
import qs.Core
import "../shell/Components"
import "../shell/Components/drawer.js" as Drawer
import "../shell/Theme/themes/metamorphosis.js" as Metamorphosis
import "../shell/Theme/themes/pantheon.js" as Pantheon

// Components/Drawer.qml's derived geometry (M57 D4) and, from M60 T2, the
// facade over its two recipes. The geometry half: a consumer states the
// edge it comes out of and its resting rect, and the line, the depth back to
// it and the band the card is cut at all follow. The tokens are spelled out
// rather than read off Theme so a token change has to be a deliberate edit
// here too: a 40px bar, barMargin 6, screenPadding 12, a 1px border, on a
// 1920x1080 output.
TestCase {
    id: testCase
    name: "Drawer"
    width: 400
    height: 300
    visible: true
    when: windowShown

    readonly property real barThickness: 40
    readonly property real barMargin: 6
    readonly property real screenPadding: 12
    readonly property real borderWidth: 1

    function insets(edge, thickness) {
        var t = thickness === undefined ? testCase.barThickness : thickness;
        return {
            top: edge === "top" ? t : 0,
            bottom: edge === "bottom" ? t : 0,
            left: edge === "left" ? t : 0,
            right: edge === "right" ? t : 0
        };
    }

    // A panel resting one barMargin off the bar on the edge it hangs from.
    function panelRect(edge, shift) {
        var off = testCase.barThickness + testCase.barMargin + (shift || 0);
        switch (edge) {
        case "bottom": return Qt.rect(400, 1080 - off - 300, 360, 300);
        case "left": return Qt.rect(off, 200, 360, 300);
        case "right": return Qt.rect(1920 - off - 360, 200, 360, 300);
        }
        return Qt.rect(400, off, 360, 300);
    }

    function lineAt(edge, target) {
        return Drawer.lineAt(edge, 1920, 1080, insets(edge), target === undefined ? null : target);
    }

    function depth(edge, rect) {
        return Drawer.depth(edge, rect, lineAt(edge), testCase.borderWidth);
    }

    // --- The line ---------------------------------------------------------

    function test_the_line_is_the_output_band_on_the_cards_own_edge() {
        compare(lineAt("top"), 40);
        compare(lineAt("bottom"), 1040);
        compare(lineAt("left"), 40);
        compare(lineAt("right"), 1880);
    }

    // A bare edge, no bar and no frame ring: no line at all, and the depth
    // the consumer is left with is the border alone, which `joined` false
    // then drops to nothing.
    function test_a_bare_edge_puts_the_line_on_the_outputs_own_edge() {
        compare(Drawer.lineAt("right", 1920, 1080, insets("top"), null), 1920);
    }

    // A card hanging off another surface takes that surface's far edge
    // instead, whichever edge it comes out of.
    function test_an_owned_card_takes_its_owners_far_edge() {
        var owner = Qt.rect(400, 46, 360, 200);
        compare(lineAt("top", owner), 246);
        compare(lineAt("bottom", owner), 46);
        compare(lineAt("left", owner), 760);
        compare(lineAt("right", owner), 400);
    }

    // --- The depth back to it ---------------------------------------------
    //
    // One barMargin of room and the line's own row on top of it, so the
    // fillets land ON the line, whichever edge the card is on.

    function test_every_edge_reaches_one_margin_and_one_row_back() {
        compare(depth("top", panelRect("top")), 7);
        compare(depth("bottom", panelRect("bottom")), 7);
        compare(depth("left", panelRect("left")), 7);
        compare(depth("right", panelRect("right")), 7);
    }

    // The notification centre's own case: it rests a screenPadding off the
    // ring rather than a barMargin off the bar, and states nothing extra for
    // it.
    function test_a_card_resting_further_off_reaches_further_back() {
        var rect = Qt.rect(1920 - 40 - 12 - 420, 52, 420, 600);
        compare(depth("right", rect), testCase.screenPadding + 1);
    }

    // A card hanging off another one reaches back to ITS far edge, one
    // barMargin clear of it, and states nothing about where the bar is.
    function test_an_owned_card_reaches_back_to_its_owner() {
        var owner = Qt.rect(400, 46, 360, 194);
        var child = panelRect("top", 200);
        compare(Drawer.depth("top", child, lineAt("top", owner), testCase.borderWidth), 7);
    }

    // --- The slit ---------------------------------------------------------
    //
    // The band runs from the shape's own far reach, one row into the line,
    // out to the far edge of the output.

    function band(edge, owner) {
        var rect = panelRect(edge, owner ? 200 : 0);
        var at = lineAt(edge, owner);
        var d = Drawer.depth(edge, rect, at, testCase.borderWidth);
        return Drawer.clipBand(edge, Drawer.cut(edge, rect, d), 1920, 1080);
    }

    function test_a_top_bar_cuts_the_card_at_the_bars_own_line() {
        var b = band("top");
        compare(b.x, 0);
        compare(b.y, 39);
        compare(b.width, 1920);
        compare(b.height, 1080 - 39);
    }

    function test_a_bottom_bar_cuts_the_card_at_the_bars_own_line() {
        var b = band("bottom");
        compare(b.y, 0);
        compare(b.height, 1041);
    }

    function test_a_left_bar_cuts_the_card_at_the_bars_own_line() {
        var b = band("left");
        compare(b.x, 39);
        compare(b.width, 1920 - 39);
        compare(b.height, 1080);
    }

    function test_a_right_bar_cuts_the_card_at_the_bars_own_line() {
        var b = band("right");
        compare(b.x, 0);
        compare(b.width, 1881);
    }

    // A card hanging off another one comes out from under the OWNER's inner
    // edge, which is where its own resting edge is.
    function test_an_owned_card_is_cut_at_the_owners_inner_edge() {
        compare(band("top", Qt.rect(400, 46, 360, 194)).y, 239);
        compare(band("bottom", Qt.rect(400, 840, 360, 194)).height, 841);
    }

    // --- The bud's own range ----------------------------------------------

    function test_a_bud_narrows_the_band_along_the_line() {
        var b = Drawer.clipBand("top", 39, 1920, 1080);
        var narrowed = Drawer.clipAlong(b, "top", { start: 500, length: 200 });
        compare(narrowed.x, 500);
        compare(narrowed.width, 200);
        compare(narrowed.y, 39);
        compare(narrowed.height, 1080 - 39);
    }

    function test_a_bud_is_clamped_into_the_band_it_narrows() {
        var b = Drawer.clipBand("left", 39, 1920, 1080);
        var narrowed = Drawer.clipAlong(b, "left", { start: -100, length: 300 });
        compare(narrowed.y, 0);
        compare(narrowed.height, 200);
        compare(narrowed.x, 39);
    }

    function test_no_bud_leaves_the_band_whole() {
        var b = Drawer.clipBand("top", 39, 1920, 1080);
        compare(Drawer.clipAlong(b, "top", null).height, b.height);
    }

    // --- The bud the contents are held to ---------------------------------
    //
    // The same range again, in the card's own coordinates: this one is
    // applied under the deform, where it stretches with the card instead of
    // cutting the border off a shape the deform has carried past it.

    function test_a_bud_holds_the_contents_to_its_own_range() {
        var rect = Qt.rect(1400, 46, 400, 300);
        var bud = Drawer.budRect("top", rect, { start: 1520, length: 160 });
        compare(bud.x, 120);
        compare(bud.width, 160);
        compare(bud.y, 0);
        compare(bud.height, 300);
    }

    // A bud reaching past the card is the fillets' own reach, which lies
    // outside it: the contents stop at the card either way.
    function test_a_bud_is_held_to_the_cards_own_rect() {
        var rect = Qt.rect(1400, 46, 400, 300);
        var bud = Drawer.budRect("top", rect, { start: 1380, length: 500 });
        compare(bud.x, 0);
        compare(bud.width, 400);
    }

    function test_a_bud_beside_a_vertical_bar_runs_down_the_card() {
        var rect = Qt.rect(46, 200, 360, 400);
        var bud = Drawer.budRect("left", rect, { start: 260, length: 100 });
        compare(bud.y, 60);
        compare(bud.height, 100);
        compare(bud.x, 0);
        compare(bud.width, 360);
    }

    function test_no_bud_is_the_cards_whole_rect() {
        var rect = Qt.rect(1400, 46, 400, 300);
        var bud = Drawer.budRect("top", rect, null);
        compare(bud.x, 0);
        compare(bud.y, 0);
        compare(bud.width, 400);
        compare(bud.height, 300);
    }

    // --- The facade and its two recipes -----------------------------------
    //
    // The habit is driven by swapping the live table, which is how the shell
    // picks a recipe: no test here names a preset, and none of them reaches
    // into a recipe for anything a consumer cannot read off the drawer.

    Component {
        id: drawerComponent

        Drawer {
            property alias probe: probeItem

            anchors.fill: parent
            owner: testCase
            edge: "top"
            role: "card"
            screen: ({ width: 1920, height: 1080, name: "TEST" })
            rect: Qt.rect(400, 60, 200, 120)

            Item {
                id: probeItem
                anchors.fill: parent
            }
        }
    }

    property var _originalStyle

    function init() {
        testCase._originalStyle = Theme.style;
    }

    function cleanup() {
        Theme.style = testCase._originalStyle;
    }

    function drawerOn(table) {
        Theme.style = table;
        return createTemporaryObject(drawerComponent, testCase);
    }

    function test_the_contract_holds_under_both_habits() {
        var tables = [Metamorphosis.STYLE, Pantheon.STYLE];
        for (var i = 0; i < tables.length; i++) {
            var drawer = testCase.drawerOn(tables[i]);
            verify(drawer.presence !== null);
            verify(drawer.joint !== null);
            verify(drawer.frameItem !== null);
            compare(drawer.frameRect.x, 400);
            compare(drawer.frameRect.y, 60);
            compare(drawer.frameRect.width, 200);
            compare(drawer.frameRect.height, 120);
        }
    }

    // The join's own read-out, and the neutral one a card with no line hands
    // back in its place: `Scrim` binds to it without asking which habit is
    // live, and a popover publishes no gap for the bar to open.
    function test_a_popover_has_no_join_to_attach_to() {
        compare(testCase.drawerOn(Metamorphosis.STYLE).joint.attach, 1);
        compare(testCase.drawerOn(Pantheon.STYLE).joint.attach, 0);
    }

    // The popover's frame is the table's box for the consumer's own role,
    // drawn by the one chrome renderer: a `Box`, not a `Shoulders`.
    function test_the_popover_frame_is_a_box_of_the_consumers_role() {
        var drawer = testCase.drawerOn(Pantheon.STYLE);
        var frame = drawer.frameItem;
        compare(frame.role, "card");
        compare(frame.box.fill, Theme.box("card").fill);
        compare(frame.radius, Math.round(drawer.radius));
        compare(frame.padding, drawer.padding);
    }

    // The travel each recipe hands the shared `Presence`: the whole shape
    // behind the line for a join, the few pixels a popover drops through.
    function test_each_recipe_states_its_own_travel() {
        compare(testCase.drawerOn(Pantheon.STYLE).presence.extent, Theme.space.md);
        verify(testCase.drawerOn(Metamorphosis.STYLE).presence.extent > 120);
    }

    // And the clock both of them ride, which is the table's own: Gala's menu
    // map under pantheon, the shared spatial family under metamorphosis.
    function test_the_emerge_clock_comes_off_the_table() {
        Theme.style = Pantheon.STYLE;
        compare(Theme.motion.emerge, 150);
        Theme.style = Metamorphosis.STYLE;
        compare(Theme.motion.emerge, Theme.motion.spatial);
    }

    // The contents land inside the card's own padding whichever recipe drew
    // it, which is what every consumer's layout is written against.
    function test_the_contents_sit_inside_the_cards_padding() {
        var tables = [Metamorphosis.STYLE, Pantheon.STYLE];
        for (var i = 0; i < tables.length; i++) {
            var drawer = testCase.drawerOn(tables[i]);
            compare(drawer.probe.width, 200 - drawer.padding * 2);
            compare(drawer.probe.height, 120 - drawer.padding * 2);
        }
    }

    // --- The card's own axes ----------------------------------------------

    function test_the_across_and_along_axes_follow_the_edge() {
        var rect = Qt.rect(400, 46, 360, 300);
        compare(Drawer.across("top", rect), 300);
        compare(Drawer.across("left", rect), 360);
        compare(Drawer.alongStart("top", rect), 400);
        compare(Drawer.alongLength("top", rect), 360);
        compare(Drawer.alongStart("right", rect), 46);
        compare(Drawer.alongLength("right", rect), 300);
    }
}
