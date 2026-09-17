import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Relief's contract (DESIGN.md §1 "Depth", 2026-09-17): nothing at all
// under a preset without depth, which is what the stub Theme renders; the
// line cut to the band the top corners span; dark when sunken and light
// when raised; and the lift wash only when asked for.
TestCase {
    id: testCase
    name: "Relief"
    width: 200
    height: 100
    visible: true
    when: windowShown

    Component {
        id: reliefComponent
        Relief {}
    }

    function make(props) {
        var item = createTemporaryObject(reliefComponent, testCase, props);
        verify(item);
        return item;
    }

    function bandOf(item) { return item.children[0]; }
    function lineOf(item) { return bandOf(item).children[0]; }
    function washOf(item) { return item.children[1]; }

    function test_it_draws_nothing_without_depth() {
        compare(Theme.depth, false);
        compare(make({ width: 100, height: 32 }).visible, false);
        compare(make({ width: 100, height: 32, shown: true, lift: true }).visible, false);
    }

    function test_the_band_spans_the_top_corners_only() {
        var item = make({ width: 100, height: 32, radius: 8, inset: 1 });
        compare(bandOf(item).height, 9);
        compare(bandOf(item).clip, true);
        compare(lineOf(item).radius, 7);
        compare(lineOf(item).x, 1);
        compare(lineOf(item).width, 98);
    }

    function test_a_square_body_still_gets_a_one_pixel_line() {
        var item = make({ width: 100, height: 32, radius: 0, inset: 0 });
        compare(bandOf(item).height, 1);
        compare(lineOf(item).radius, 0);
    }

    function test_sunken_is_the_dark_line_and_raised_the_light_one() {
        verify(Qt.colorEqual(lineOf(make({ sunken: true })).border.color, Theme.insetLine));
        verify(Qt.colorEqual(lineOf(make({ sunken: false })).border.color, Theme.highlight));
    }

    // `visible` reads back effective visibility, and the whole item is
    // hidden under the stub's flat preset, so only the negative half can be
    // read here; the gradient itself is what lift switches on.
    function test_the_wash_is_hidden_without_lift() {
        compare(washOf(make({ lift: false })).visible, false);
        verify(washOf(make({ lift: true })).gradient !== null);
    }
}
