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
}
