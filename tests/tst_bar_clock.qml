import QtQuick
import QtTest
import qs.Core
import "../shell/Surfaces/Bar/widgets"

// The bar clock's face (DESIGN.md §1 "Type"): a time is a value, so it
// renders in the mono alias and its digits stay tabular as the minute ticks.
TestCase {
    id: testCase
    name: "BarClock"
    width: 400
    height: 200
    visible: true
    when: windowShown

    Component {
        id: clockComponent
        Clock {}
    }

    function findText(item) {
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i];
            if (child.font !== undefined && child.text !== undefined && child.text !== "")
                return child;
            var nested = findText(child);
            if (nested)
                return nested;
        }
        return null;
    }

    function test_the_time_renders_in_mono() {
        var clock = createTemporaryObject(clockComponent, testCase);
        verify(clock);
        waitForRendering(clock);
        var label = findText(clock);
        verify(label);
        compare(label.font.family, Theme.fontFamilyMono);
        compare(label.font.weight, Theme.weight.medium);
    }
}
