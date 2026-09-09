import QtQuick
import QtTest
import "../shell/Core/handoff.js" as Handoff

// PanelRegistry's handoff bookkeeping (M53 D5). The registry holds the two
// Panel instances and reads their frames; the question it asks about them is
// pure, and is tested head-on here, the same split cursor.js and geometry.js
// already use.
TestCase {
    id: testCase
    name: "PanelHandoff"

    function merge(base, overrides) {
        for (var key in overrides)
            base[key] = overrides[key];
        return base;
    }

    function outgoing(overrides) {
        return testCase.merge({
            isOpen: true,
            handingOver: false,
            owned: false,
            screenName: "DP-1",
            rect: { x: 1528, y: 46, width: 380, height: 260 }
        }, overrides);
    }

    function incoming(overrides) {
        return testCase.merge({
            isOpen: false,
            handingOver: false,
            owned: false,
            screenName: "DP-1",
            rect: { x: 12, y: 46, width: 380, height: 420 }
        }, overrides);
    }

    function test_replacing_the_open_panel_records_its_rect() {
        var rect = Handoff.outgoingRect(testCase.outgoing({}), testCase.incoming({}));
        verify(rect);
        compare(rect.x, 1528);
        compare(rect.y, 46);
        compare(rect.width, 380);
        compare(rect.height, 260);
    }

    function test_the_recorded_rect_is_a_copy() {
        var from = testCase.outgoing({});
        var rect = Handoff.outgoingRect(from, testCase.incoming({}));
        from.rect.x = 0;
        compare(rect.x, 1528);
    }

    function test_a_second_output_is_two_cards() {
        compare(Handoff.outgoingRect(testCase.outgoing({}),
            testCase.incoming({ screenName: "HDMI-A-1" })), null);
    }

    function test_an_output_nobody_named_is_not_a_handoff() {
        compare(Handoff.outgoingRect(testCase.outgoing({ screenName: "" }),
            testCase.incoming({})), null);
        compare(Handoff.outgoingRect(testCase.outgoing({}),
            testCase.incoming({ screenName: "" })), null);
    }

    function test_an_owned_popout_is_not_a_handoff() {
        // The tray's menu over its second bar, and every widget panel opened
        // from the chevron's: a card hanging off another card was never the
        // same card.
        compare(Handoff.outgoingRect(testCase.outgoing({ owned: true }),
            testCase.incoming({})), null);
        compare(Handoff.outgoingRect(testCase.outgoing({}),
            testCase.incoming({ owned: true })), null);
    }

    function test_a_panel_that_is_not_open_hands_nothing_over() {
        compare(Handoff.outgoingRect(testCase.outgoing({ isOpen: false }),
            testCase.incoming({})), null);
    }

    function test_a_panel_already_handing_over_is_skipped() {
        compare(Handoff.outgoingRect(testCase.outgoing({ handingOver: true }),
            testCase.incoming({})), null);
    }

    function test_a_frame_with_no_size_yet_is_skipped() {
        compare(Handoff.outgoingRect(
            testCase.outgoing({ rect: { x: 0, y: 0, width: 0, height: 0 } }),
            testCase.incoming({})), null);
        compare(Handoff.outgoingRect(testCase.outgoing({ rect: null }),
            testCase.incoming({})), null);
    }

    function test_nothing_to_replace_is_a_plain_open() {
        compare(Handoff.outgoingRect(null, testCase.incoming({})), null);
        compare(Handoff.outgoingRect(testCase.outgoing({}), null), null);
    }
}
