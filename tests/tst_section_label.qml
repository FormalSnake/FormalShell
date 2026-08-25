import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// SectionLabel's contract (DESIGN.md §2): caption, medium, mutedForeground,
// uppercase, tracked by letterSpacing.meta, with an optional trailing count.
// No label anywhere carries a trailing colon any more (§5), which is what
// the MetaLabel cases below pin: 25 call sites still set `colon: true`.
TestCase {
    id: testCase
    name: "SectionLabel"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: labelComponent
        SectionLabel {}
    }

    Component {
        id: metaComponent
        MetaLabel {}
    }

    // The paint target is the wrapper's only child.
    function labelOf(item) {
        compare(item.children.length, 1);
        return item.children[0];
    }

    function make(component, props) {
        var item = createTemporaryObject(component, testCase, props);
        verify(item);
        waitForRendering(item);
        return item;
    }

    function test_plain_text_renders_verbatim() {
        var label = make(labelComponent, { text: "NETWORKS" });
        compare(labelOf(label).text, "NETWORKS");
    }

    function test_count_renders_as_a_suffix() {
        var label = make(labelComponent, { text: "NETWORKS", count: 3 });
        compare(labelOf(label).text, "NETWORKS (3)");
    }

    function test_zero_still_counts() {
        var label = make(labelComponent, { text: "DEVICES", count: 0 });
        compare(labelOf(label).text, "DEVICES (0)");
    }

    function test_a_negative_count_draws_no_suffix() {
        var label = make(labelComponent, { text: "DEVICES", count: -1 });
        compare(labelOf(label).text, "DEVICES");
    }

    function test_type_tokens() {
        var label = make(labelComponent, { text: "NETWORKS" });
        var text = labelOf(label);
        compare(text.font.pixelSize, Theme.fontSize.caption);
        compare(text.font.weight, Theme.weight.medium);
        compare(text.font.capitalization, Font.AllUppercase);
        compare(text.font.letterSpacing, Theme.letterSpacing.meta);
        verify(Qt.colorEqual(text.color, Theme.color.mutedForeground));
    }

    // Sans, because a section label is words (DESIGN.md §1 "Type").
    function test_the_face_is_sans() {
        var label = make(labelComponent, { text: "NETWORKS" });
        compare(labelOf(label).font.family, Theme.fontFamilySans);
    }

    function test_implicit_size_tracks_the_label() {
        var label = make(labelComponent, { text: "NETWORKS" });
        var text = labelOf(label);
        compare(label.implicitWidth, text.implicitWidth);
        compare(label.implicitHeight, text.implicitHeight);
        verify(label.implicitWidth > 0);
    }

    function test_meta_label_never_appends_a_colon() {
        var label = make(metaComponent, { text: "NETWORK", colon: true });
        compare(labelOf(label).text, "NETWORK");
    }

    function test_meta_label_is_a_section_label() {
        var label = make(metaComponent, { text: "BAT" });
        var text = labelOf(label);
        compare(text.font.pixelSize, Theme.fontSize.caption);
        compare(text.font.capitalization, Font.AllUppercase);
        verify(Qt.colorEqual(text.color, Theme.color.mutedForeground));
    }
}
