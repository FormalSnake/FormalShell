import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Separator, rung 4 of DESIGN.md §1's separation ladder: a 1px `border` rule
// for a seam space cannot carry. The contract worth pinning is that it is
// always exactly one border thick on its own axis whichever way it runs, and
// that `inset` pulls in the ends rather than the thickness.
TestCase {
    id: testCase
    name: "Separator"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: sepComponent
        Separator {}
    }

    function make(props) {
        var o = createTemporaryObject(sepComponent, testCase, props || {});
        verify(o !== null);
        return o;
    }

    function test_horizontal_is_one_border_tall() {
        var sep = make({});
        compare(sep.height, Theme.borderWidth);
        compare(sep.implicitHeight, Theme.borderWidth);
    }

    function test_vertical_is_one_border_wide() {
        var sep = make({ vertical: true });
        compare(sep.width, Theme.borderWidth);
        compare(sep.implicitWidth, Theme.borderWidth);
    }

    // A rule is the border colour, never foreground and never a fill: it is
    // the same ink the card's own edge uses, which is what keeps a seam from
    // outweighing the frame around it.
    function test_it_draws_in_border_ink() {
        verify(Qt.colorEqual(make({}).color, Theme.color.border));
    }

    // `inset` is the ends, not the thickness: a rule inset to the row text
    // still has to be a hairline.
    function test_inset_pulls_the_ends_not_the_thickness() {
        var sep = make({ inset: 12 });
        compare(sep.height, Theme.borderWidth);
        compare(sep.anchors.leftMargin, 12);
        compare(sep.anchors.rightMargin, 12);
        compare(sep.anchors.topMargin, 0);
    }

    function test_a_vertical_inset_pulls_top_and_bottom() {
        var sep = make({ vertical: true, inset: 8 });
        compare(sep.width, Theme.borderWidth);
        compare(sep.anchors.topMargin, 8);
        compare(sep.anchors.bottomMargin, 8);
        compare(sep.anchors.leftMargin, 0);
    }
}
