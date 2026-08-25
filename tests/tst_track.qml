import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Track's contract (DESIGN.md §2): a `trackThickness` groove at `radiusSm`,
// `primary` at 0.2 behind a `primary` fill, the fraction clamped to 0..1.
//
// The groove's colour is asserted against a sentinel palette rather than
// Palette.fallback(): `muted`, `accent` and `secondary` share one zinc step
// there, so a groove that had gone back to `muted` would still satisfy a
// comparison made against the real fallback set.
TestCase {
    id: testCase
    name: "Track"
    width: 400
    height: 200
    visible: true
    when: windowShown

    readonly property real grooveAlpha: 0.2

    readonly property var sentinelColors: ({
        background: "#010101",
        foreground: "#eeeeee",
        mutedForeground: "#aaaaaa",
        card: "#151515",
        border: "#444444",
        muted: "#2a2a2a",
        accent: "#2a2a2a",
        accentForeground: "#dddddd",
        primary: "#1133ff",
        primaryForeground: "#ffdd00",
        destructive: "#ff2222",
        destructiveForeground: "#22ff88",
        warning: "#ffaa00",
        warningForeground: "#001122",
        ring: "#00ccff"
    })

    property var _originalColor

    function init() {
        testCase._originalColor = Theme.color;
        Theme.color = testCase.sentinelColors;
    }

    function cleanup() {
        Theme.color = testCase._originalColor;
    }

    Component {
        id: trackComponent
        Track { width: 200 }
    }

    function make(props) {
        var track = createTemporaryObject(trackComponent, testCase, props);
        verify(track);
        waitForRendering(track);
        wait(200);
        return track;
    }

    // The fill is the groove's only child.
    function fillOf(track) {
        compare(track.children.length, 1);
        return track.children[0];
    }

    function test_groove_is_primary_at_a_fifth() {
        var track = make({ value: 0.5 });
        compare(track.color.a, testCase.grooveAlpha);
        compare(Math.round(track.color.r * 255), 0x11);
        compare(Math.round(track.color.g * 255), 0x33);
        compare(Math.round(track.color.b * 255), 0xff);
    }

    // The groove has to stay visible on a row carrying a `selected` or
    // `active` fill, which is what painting it `muted` cost.
    function test_groove_is_not_a_neutral_step() {
        var track = make({ value: 0.5 });
        verify(!Qt.colorEqual(track.color, Theme.color.muted));
        verify(!Qt.colorEqual(track.color, Theme.color.accent));
    }

    function test_fill_is_opaque_primary() {
        var track = make({ value: 0.5 });
        var fill = fillOf(track);
        verify(Qt.colorEqual(fill.color, Theme.color.primary));
        compare(fill.color.a, 1);
    }

    function test_thickness_and_radius_are_tokens() {
        var track = make({ value: 0.5 });
        compare(track.implicitHeight, Theme.space.trackThickness);
        compare(track.radius, Theme.radiusSm);
        compare(fillOf(track).radius, Theme.radiusSm);
    }

    function test_fill_width_is_the_fraction_of_the_groove() {
        var track = make({ value: 0.25 });
        compare(fillOf(track).width, track.width * 0.25);
    }

    function test_value_clamps_at_both_ends() {
        compare(make({ value: 1.7 })._fraction, 1);
        compare(make({ value: -3 })._fraction, 0);
    }

    function test_a_full_track_never_overflows_the_groove() {
        var track = make({ value: 4 });
        compare(fillOf(track).width, track.width);
    }
}
