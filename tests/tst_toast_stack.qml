import QtQuick
import QtTest
import "../shell/Notifications/stack.js" as Stack

// The sonner depth stack's invariants (M34's locked contract, M44 Task 1's
// extraction of the math into shell/Notifications/stack.js). The tokens are
// spelled out rather than read off Theme so a token change has to be a
// deliberate edit here too: at the default scale `peekInset` is
// `Theme.space.lg` (8), `peekOffset` is `Theme.space.sm` (4), `gap` is
// `Theme.space.panelGap` (14) and the frame is `popupWidthNarrow` (320).
TestCase {
    name: "ToastStack"

    readonly property var tokens: ({
        frameWidth: 320,
        peekInset: 8,
        peekOffset: 4,
        maxPeekLevels: 2,
        gap: 14
    })

    function layout(params) {
        var merged = {};
        for (var key in tokens)
            merged[key] = tokens[key];
        for (var given in params)
            merged[given] = params[given];
        return Stack.layout(merged);
    }

    // --- collapsed: the depth stack ---------------------------------------

    function test_the_front_card_is_full_width_against_the_anchored_edge() {
        var out = layout({ collapsed: ["a", "b", "c"] });
        var front = out.byKey["a"].collapsed;
        compare(front.x, 0);
        compare(front.width, tokens.frameWidth);
        // Bottom-anchored: the front card sits the full peek reserve away
        // from the top of the stack, so both levels behind it can poke out.
        compare(front.y, tokens.maxPeekLevels * tokens.peekOffset);
        compare(front.contentVisible, true);
    }

    function test_each_level_narrows_by_one_whole_inset_per_side() {
        var out = layout({ collapsed: ["a", "b", "c"] });
        compare(out.byKey["a"].collapsed.width, 320);
        compare(out.byKey["b"].collapsed.width, 304);
        compare(out.byKey["c"].collapsed.width, 288);
    }

    // The owner's 2026-08-18 amendment: stepped integer sizing, never a
    // fractional scale. A width or an x that came out fractional would be a
    // border rasterized off the pixel grid.
    function test_every_collapsed_edge_lands_on_a_whole_pixel() {
        var out = layout({ collapsed: ["a", "b", "c", "d"] });
        var keys = ["a", "b", "c", "d"];
        for (var i = 0; i < keys.length; i++) {
            var geom = out.byKey[keys[i]].collapsed;
            verify(geom.x === Math.round(geom.x), keys[i] + " x is fractional");
            verify(geom.y === Math.round(geom.y), keys[i] + " y is fractional");
            verify(geom.width === Math.round(geom.width), keys[i] + " width is fractional");
        }
    }

    function test_each_level_stays_centred_on_the_front_card() {
        var out = layout({ collapsed: ["a", "b", "c"] });
        var keys = ["a", "b", "c"];
        for (var i = 0; i < keys.length; i++) {
            var geom = out.byKey[keys[i]].collapsed;
            compare(geom.x * 2 + geom.width, tokens.frameWidth);
        }
    }

    function test_only_the_front_card_shows_its_content() {
        var out = layout({ collapsed: ["a", "b", "c"] });
        compare(out.byKey["a"].collapsed.contentVisible, true);
        compare(out.byKey["b"].collapsed.contentVisible, false);
        compare(out.byKey["c"].collapsed.contentVisible, false);
    }

    function test_the_front_card_is_in_front() {
        var out = layout({ collapsed: ["a", "b", "c"] });
        verify(out.byKey["a"].collapsed.z > out.byKey["b"].collapsed.z);
        verify(out.byKey["b"].collapsed.z > out.byKey["c"].collapsed.z);
    }

    // At most two levels peek; a fourth popup exists only in the count the
    // expanded stack reveals, so it takes the last level's geometry and
    // hides behind it.
    function test_levels_clamp_at_the_peek_limit() {
        var out = layout({ collapsed: ["a", "b", "c", "d", "e"] });
        var third = out.byKey["c"].collapsed;
        compare(out.byKey["d"].collapsed.width, third.width);
        compare(out.byKey["d"].collapsed.x, third.x);
        compare(out.byKey["d"].collapsed.y, third.y);
        compare(out.byKey["e"].collapsed.width, third.width);
        verify(out.byKey["d"].collapsed.z < third.z);
    }

    function test_a_peek_pokes_out_one_offset_per_level() {
        var out = layout({ collapsed: ["a", "b", "c"] });
        compare(out.byKey["a"].collapsed.y - out.byKey["b"].collapsed.y, tokens.peekOffset);
        compare(out.byKey["b"].collapsed.y - out.byKey["c"].collapsed.y, tokens.peekOffset);
    }

    // Top-anchored, the reveal recedes downward instead: the front card is
    // flush against the top edge and the levels behind it grow away from it.
    function test_a_top_anchor_flips_the_reveal() {
        var out = layout({ collapsed: ["a", "b", "c"], top: true });
        compare(out.byKey["a"].collapsed.y, 0);
        compare(out.byKey["b"].collapsed.y, tokens.peekOffset);
        compare(out.byKey["c"].collapsed.y, tokens.maxPeekLevels * tokens.peekOffset);
    }

    function test_the_pile_is_the_front_card_plus_the_peek_reserve() {
        var out = layout({ collapsed: ["a", "b"], heights: { a: 90, b: 120 } });
        compare(out.collapsedHeight, 90 + tokens.maxPeekLevels * tokens.peekOffset);
    }

    // --- expanded: the plain list -----------------------------------------

    function test_every_expanded_card_is_full_width_in_the_order_given() {
        var out = layout({ expanded: ["a", "b", "c"], heights: { a: 90, b: 60, c: 70 } });
        compare(out.byKey["a"].expanded.x, 0);
        compare(out.byKey["a"].expanded.width, tokens.frameWidth);
        compare(out.byKey["a"].expanded.y, 0);
        compare(out.byKey["b"].expanded.y, 90 + tokens.gap);
        compare(out.byKey["c"].expanded.y, 90 + tokens.gap + 60 + tokens.gap);
        compare(out.byKey["c"].expanded.width, tokens.frameWidth);
        compare(out.byKey["b"].expanded.contentVisible, true);
    }

    function test_the_expanded_column_carries_no_trailing_gap() {
        var out = layout({ expanded: ["a", "b"], heights: { a: 90, b: 60 } });
        compare(out.expandedHeight, 90 + tokens.gap + 60);
    }

    function test_the_first_expanded_card_is_in_front() {
        var out = layout({ expanded: ["a", "b"], heights: { a: 90, b: 60 } });
        verify(out.byKey["a"].expanded.z > out.byKey["b"].expanded.z);
    }

    // --- edges -------------------------------------------------------------

    // A group with no slot of its own draws nothing, but the cards around it
    // keep the level they would have had.
    function test_a_missing_slot_still_consumes_its_rank() {
        var out = layout({ collapsed: ["a", null, "c"] });
        compare(out.byKey["a"].collapsed.width, 320);
        compare(out.byKey["c"].collapsed.width, 288);
        verify(out.byKey[null] === undefined);
    }

    function test_a_missing_slot_costs_the_expanded_column_no_height() {
        var out = layout({ expanded: ["a", null, "c"], heights: { a: 90, c: 70 } });
        compare(out.byKey["c"].expanded.y, 90 + tokens.gap);
        compare(out.expandedHeight, 90 + tokens.gap + 70);
    }

    function test_an_empty_stack_has_nothing_in_it() {
        var out = layout({});
        compare(out.expandedHeight, 0);
        compare(out.collapsedHeight, tokens.maxPeekLevels * tokens.peekOffset);
    }

    function test_one_card_alone_carries_the_whole_pile() {
        var out = layout({ collapsed: ["a"], expanded: ["a"], heights: { a: 90 } });
        compare(out.byKey["a"].collapsed.width, tokens.frameWidth);
        compare(out.byKey["a"].expanded.width, tokens.frameWidth);
        compare(out.expandedHeight, 90);
    }
}
