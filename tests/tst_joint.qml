import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Components/Joint.qml: the join a drawer keeps with its line while it
// comes out, and lets go of once it is nearly at rest.
TestCase {
    id: testCase
    name: "Joint"
    when: windowShown

    Component {
        id: presenceComponent
        Presence { edge: "top"; mode: "emerge"; extent: 300 }
    }

    Component {
        id: jointComponent
        Joint {
            edge: "top"
            depth: 7
            radius: 20
            extent: 293
            along: 100
            length: 400
            screen: "DP-1"
        }
    }

    function make() {
        var presence = createTemporaryObject(presenceComponent, testCase);
        var joint = createTemporaryObject(jointComponent, testCase,
            { owner: testCase, presence: presence });
        return { presence: presence, joint: joint };
    }

    function cleanup() {
        PanelRegistry.clearJoin(testCase);
    }

    // Closed, the card sits its whole extent behind the line: nothing of
    // the shape is out, and it is attached, so an open starts on the line.
    function test_a_closed_card_is_attached_with_nothing_out() {
        var j = make().joint;
        compare(j.slide, 300);
        compare(j.shapeDepth, 0);
        compare(j.neck, 0);
        compare(j.attach, 1);
        compare(j.join, null);
    }

    // At rest the card has let go: floating its own neck off the line with
    // nothing published, and the line whole.
    function test_at_rest_the_card_floats_and_the_line_is_whole() {
        var m = make();
        m.presence.open = true;
        tryCompare(m.presence, "settled", true, 2000);
        tryCompare(m.joint, "attach", 0, 2000);
        compare(m.joint.slide, 0);
        compare(m.joint.shapeDepth, 300);
        compare(m.joint.nearInset, 7);
        compare(m.joint.reach, 0);
        compare(m.joint.pivotInset, 0);
        compare(m.joint.join, null);
        compare(PanelRegistry.joinOn("top", "DP-1"), null);
    }

    // On the way out the join is published with the card's own rect and
    // the fillets' reach, and the pivot sits on the line.
    function test_on_the_way_out_the_join_is_published() {
        var m = make();
        m.presence.open = true;
        tryVerify(function () { return m.joint.shapeDepth > 40; }, 1000);
        verify(m.joint.attach > 0);
        var j = PanelRegistry.joinOn("top", "DP-1");
        verify(j !== null);
        compare(j.edge, "top");
        compare(j.reach, 20);
        verify(Math.abs(m.joint.pivotInset - (7 - m.joint.slide)) < 0.001);
    }

    // No line to meet: a plain card, never attached, never published.
    function test_an_unjoined_card_floats_from_the_start() {
        var m = make();
        m.joint.joined = false;
        compare(m.joint.attach, 0);
        m.presence.open = true;
        compare(m.joint.join, null);
        tryCompare(m.presence, "settled", true, 2000);
        compare(m.joint.attach, 0);
        compare(m.joint.nearInset, 7);
    }

    // --- Walls -----------------------------------------------------------
    //
    // A 400 wide card resting 12 off the end of a 1920 line, which is less
    // than its own 20 radius: the far side is walled.
    function walled(extra) {
        var m = make();
        m.joint.restLength = 400;
        m.joint.outputAlong = 1920;
        m.joint.across = 46;
        m.joint.restAlong = 1508;
        for (var key in extra)
            m.joint[key] = extra[key];
        return m;
    }

    // With the line ending at the output, the silhouette runs one radius
    // past it, so nothing the deform does can open a sliver at the edge.
    // The near end has room for its fillet and is left alone.
    function test_a_side_with_no_room_for_its_fillet_is_walled() {
        var j = walled({}).joint;
        compare(j.wallStart, -1);
        compare(j.wallEnd, 32);
    }

    // With a frame ring on that side the silhouette runs out to the ring's
    // band instead, one border past the ring's own line, so the fill's lip
    // lands on the row the ring gave up rather than short of it.
    function test_a_line_ending_in_a_ring_runs_out_to_the_band() {
        var j = walled({ insetEnd: 10, restAlong: 1498 }).joint;
        compare(j.wallEnd, 13);
    }

    // The deform is pinned to the wall rather than to the card's middle, so
    // the squash cannot pull the run-out off it. Nothing to pin to with no
    // wall, or with one at either end.
    function test_the_deform_pivots_on_the_wall_a_walled_card_runs_into() {
        compare(walled({}).joint.alongPivot, 432);
        compare(walled({ restAlong: 400 }).joint.alongPivot, null);
        compare(walled({ restAlong: 12, restLength: 1896 }).joint.alongPivot, null);
    }

    // Room for the fillet, and a card hanging off another panel, are both
    // left unwalled: a nested card's span is its owner's, not the screen's.
    function test_a_card_with_room_or_an_owner_never_walls() {
        compare(walled({ restAlong: 400 }).joint.wallEnd, -1);
        compare(walled({ target: testCase }).joint.wallEnd, -1);
    }

    // On the way out a walled card publishes two joins: its own line's, the
    // gap widened by the run out to the wall, and the wall's own, running
    // from the line to the shape's far edge.
    function test_a_walled_card_publishes_the_walls_own_join() {
        var m = walled({});
        m.presence.open = true;
        tryVerify(function () { return m.joint.shapeDepth > 40; }, 1000);
        var own = PanelRegistry.joinOn("top", "DP-1");
        verify(own !== null);
        compare(Math.round(own.x + own.width), Math.round(m.joint.along + m.joint.length + 32));
        var wall = PanelRegistry.joinOn("right", "DP-1");
        verify(wall !== null);
        // The line is `depth` back from the card's own resting edge, and the
        // shape runs from there to its far edge.
        compare(wall.x, 39);
        compare(Math.round(wall.width), Math.round(m.joint.shapeDepth));
        compare(wall.reach, m.joint.reach);
    }

    // Clearing one edge leaves the other standing: the registry keys a join
    // by owner AND edge, so a side that stops being walled mid-flight takes
    // only its own entry down.
    function test_clearing_one_edge_leaves_the_other_standing() {
        var m = walled({});
        m.presence.open = true;
        tryVerify(function () { return PanelRegistry.joinOn("right", "DP-1") !== null; }, 1000);
        m.joint.outputAlong = 4000;
        compare(m.joint.wallEnd, -1);
        compare(PanelRegistry.joinOn("right", "DP-1"), null);
        verify(PanelRegistry.joinOn("top", "DP-1") !== null);
    }

    // At rest both go, and every line is whole again.
    function test_a_walled_card_lets_go_of_both_lines() {
        var m = walled({});
        m.presence.open = true;
        tryCompare(m.joint, "attach", 0, 2000);
        compare(PanelRegistry.joinOn("top", "DP-1"), null);
        compare(PanelRegistry.joinOn("right", "DP-1"), null);
    }
}
