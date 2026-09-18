import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Components/InkGlow.qml (M63 O6): one MultiEffect per layer the table
// declares, and nothing at all when it declares none, which is what keeps a
// theme with no ink shadow paying for the mechanism.
TestCase {
    id: testCase
    name: "InkGlow"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: glowComponent

        Item {
            width: 80
            height: 24

            property alias glow: glowItem
            property alias glyph: glyphItem

            InkGlow {
                id: glowItem
                anchors.fill: parent
                source: glyphItem
            }

            Text {
                id: glyphItem
                anchors.fill: parent
                text: "84%"
            }
        }
    }

    // The effects are the glow's only children carrying a shadow, so this is
    // what fails if the delegate stops being a MultiEffect.
    function effectsIn(glow) {
        var out = [];
        for (var i = 0; i < glow.children.length; i++) {
            if (glow.children[i].shadowEnabled !== undefined)
                out.push(glow.children[i]);
        }
        return out;
    }

    function test_an_empty_list_instantiates_nothing() {
        var host = createTemporaryObject(glowComponent, testCase);
        verify(host);
        host.glow.shadows = [];
        waitForRendering(host);
        compare(testCase.effectsIn(host.glow).length, 0);
        verify(!host.glow.on);
    }

    function test_one_effect_per_layer() {
        var host = createTemporaryObject(glowComponent, testCase);
        verify(host);
        host.glow.shadows = [
            { x: 0, y: 0, blur: 2, color: "#4d000000" },
            { x: 0, y: 1, blur: 2, color: "#99000000" },
            { x: 2, y: 0, blur: 0, color: "#40ffffff" }
        ];
        waitForRendering(host);
        var effects = testCase.effectsIn(host.glow);
        compare(effects.length, 3);
        verify(host.glow.on);
        for (var i = 0; i < effects.length; i++)
            verify(effects[i].shadowEnabled);
    }

    // Every layer asks the shared source layer for the same rect, so the
    // blur budget and the padding are the list's maxima rather than each
    // layer's, and each layer's own blur is a fraction of that budget.
    function test_the_budget_is_the_lists_widest_layer() {
        var host = createTemporaryObject(glowComponent, testCase);
        verify(host);
        host.glow.shadows = [
            { x: 0, y: 0, blur: 2, color: "#4d000000" },
            { x: 0, y: 3, blur: 6, color: "#99000000" }
        ];
        waitForRendering(host);
        var effects = testCase.effectsIn(host.glow);
        compare(effects.length, 2);
        compare(host.glow._blurMax, 6);
        compare(host.glow._reach, 3);
        compare(effects[0].blurMax, effects[1].blurMax);
        compare(effects[0].paddingRect, effects[1].paddingRect);
        fuzzyCompare(effects[0].shadowBlur, 2 / 6, 0.001);
        fuzzyCompare(effects[1].shadowBlur, 1, 0.001);
        compare(effects[1].shadowVerticalOffset, 3);
    }

    // First layer on top, the way a CSS shadow list stacks.
    function test_the_first_layer_sits_over_the_rest() {
        var host = createTemporaryObject(glowComponent, testCase);
        verify(host);
        host.glow.shadows = [
            { x: 0, y: 0, blur: 2, color: "#4d000000" },
            { x: 0, y: 1, blur: 2, color: "#99000000" }
        ];
        waitForRendering(host);
        var effects = testCase.effectsIn(host.glow);
        compare(effects.length, 2);
        verify(effects[0].z > effects[1].z);
    }
}
