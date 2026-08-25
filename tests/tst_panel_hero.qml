import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// PanelHero's caption line (DESIGN.md §1 "Type", §5): `bodySmall`,
// `mutedForeground`, sentence case, in the face `metaMono` picks. It used to
// render through MetaLabel, which uppercases, so DisplayPanel's mode line
// read back as `1920X1080@60`.
TestCase {
    id: testCase
    name: "PanelHero"
    width: 400
    height: 300
    visible: true
    when: windowShown

    readonly property string modeLine: "1920x1080@60"

    Component {
        id: heroComponent
        PanelHero { width: 320 }
    }

    function make(props) {
        var hero = createTemporaryObject(heroComponent, testCase, props);
        verify(hero);
        waitForRendering(hero);
        wait(50);
        return hero;
    }

    // The caption is the only Text in the tree carrying that string; the
    // title above it is handed a different one by every case here.
    function findText(item, needle) {
        if (item.font !== undefined && item.text !== undefined && item.text === needle)
            return item;
        for (var i = 0; i < item.children.length; i++) {
            var hit = findText(item.children[i], needle);
            if (hit)
                return hit;
        }
        return null;
    }

    function metaOf(hero) {
        var text = findText(hero, testCase.modeLine);
        verify(text);
        return text;
    }

    function test_the_caption_is_never_uppercased() {
        var meta = metaOf(make({ title: "Built-in display", meta: testCase.modeLine }));
        compare(meta.text, testCase.modeLine);
        verify(meta.font.capitalization !== Font.AllUppercase);
    }

    function test_the_caption_is_body_small_and_muted() {
        var hero = make({ title: "Built-in display", meta: testCase.modeLine });
        var meta = metaOf(hero);
        compare(meta.font.pixelSize, Theme.fontSize.bodySmall);
        verify(Qt.colorEqual(meta.color, Theme.color.mutedForeground));
    }

    // A caption carrying an identifier or a number is a value, so the caller
    // opts it into mono; words stay sans.
    function test_meta_mono_picks_the_face() {
        compare(metaOf(make({ title: "Built-in display", meta: testCase.modeLine, metaMono: true })).font.family,
            Theme.fontFamilyMono);
        compare(metaOf(make({ title: "Built-in display", meta: testCase.modeLine })).font.family,
            Theme.fontFamilySans);
    }

    function test_an_empty_caption_draws_nothing() {
        var hero = make({ title: "Built-in display", meta: "" });
        verify(!findText(hero, testCase.modeLine));
    }
}
