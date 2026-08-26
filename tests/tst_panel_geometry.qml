import QtQuick
import QtTest
import "../shell/Components/geometry.js" as Geometry

// Panel.qml's frame geometry (DESIGN.md §1 "Padding", M48 D3). Panel imports
// Quickshell, so the arithmetic it drives lives in geometry.js and is tested
// head-on, the same split tst_panel_cursor and tst_theme_tokens use.
//
// The numbers below are the shipped tokens at spacingScale 1.0: barMargin 6,
// screenPadding 12, panelPadding 12, sectionGap 16, and a 40px bar.
TestCase {
    id: testCase
    name: "PanelGeometry"

    readonly property real barHeight: 40
    readonly property real barMargin: 6
    readonly property real screenPadding: 12
    readonly property real panelPadding: 12
    readonly property real sectionGap: 16
    readonly property real headerHeight: 32

    function test_an_ipc_open_sits_one_screen_padding_from_the_right_edge() {
        // No anchor cell, so the frame falls back to the right edge.
        compare(Geometry.frameX(-1, 1920, 380, testCase.screenPadding), 1920 - 380 - 12);
    }

    function test_a_cell_anchored_open_keeps_the_cell_x() {
        compare(Geometry.frameX(600, 1920, 380, testCase.screenPadding), 600);
    }

    function test_an_anchor_near_the_right_edge_is_pulled_back_to_the_padding() {
        // A cell at 1800 would put a 380-wide frame 260px off the screen.
        compare(Geometry.frameX(1800, 1920, 380, testCase.screenPadding), 1920 - 380 - 12);
    }

    function test_an_anchor_at_the_left_edge_is_pushed_in_to_the_padding() {
        compare(Geometry.frameX(0, 1920, 380, testCase.screenPadding), 12);
    }

    function test_a_frame_wider_than_the_screen_gives_up_the_right_clamp() {
        // Rather than being pushed off the left edge, which is where a naive
        // min/max pair lands it.
        compare(Geometry.frameX(-1, 300, 380, testCase.screenPadding), 12);
    }

    function test_the_frame_is_capped_at_the_screen_minus_bar_and_paddings() {
        // 1080 - 40 bar - 6 barMargin - 12 screenPadding.
        compare(Geometry.maxFrameHeight(1080, testCase.barHeight, testCase.barMargin,
            testCase.screenPadding), 1022);
    }

    function test_the_cap_never_goes_negative_on_a_tiny_screen() {
        compare(Geometry.maxFrameHeight(40, testCase.barHeight, testCase.barMargin,
            testCase.screenPadding), 0);
    }

    function test_content_gets_the_cap_minus_the_frames_own_chrome() {
        var maxFrame = Geometry.maxFrameHeight(1080, testCase.barHeight, testCase.barMargin,
            testCase.screenPadding);
        // 1022 - 24 padding - 32 header - 16 sectionGap.
        compare(Geometry.maxContentHeight(maxFrame, testCase.panelPadding, testCase.headerHeight,
            testCase.sectionGap), 950);
    }

    function test_a_short_panel_is_its_own_height() {
        var maxContent = 950;
        compare(Geometry.frameHeight(200, maxContent, testCase.panelPadding,
            testCase.headerHeight, testCase.sectionGap), 24 + 32 + 16 + 200);
    }

    function test_a_tall_panel_stops_at_the_cap_and_scrolls() {
        var maxFrame = Geometry.maxFrameHeight(1080, testCase.barHeight, testCase.barMargin,
            testCase.screenPadding);
        var maxContent = Geometry.maxContentHeight(maxFrame, testCase.panelPadding,
            testCase.headerHeight, testCase.sectionGap);
        // A calendar month taller than the screen: the frame lands on the cap
        // exactly, never past it, which is the whole claim.
        compare(Geometry.frameHeight(4000, maxContent, testCase.panelPadding,
            testCase.headerHeight, testCase.sectionGap), maxFrame);
    }
}
