import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Track's contract (DESIGN.md §2): a `trackThickness` groove at `radiusSm`,
// `primary` at 0.2 behind a `primary` fill, the fraction clamped to 0..1,
// the optional `notch` mark AudioPanel's overdrive rails need, and the ring
// a panel addressing the track as a row of its own turns on.
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

    // The alpha the table's `cursor` ring layer carries, written out rather
    // than read back off the table: an assertion sourced from the same place
    // as the value under test agrees with itself whatever the table says.
    readonly property real ringAlpha: 0.5

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

    // The groove is a `Box`: what it paints is the rectangles the box draws
    // (tst_box.qml walks the same shape), the cursor's halo when it carries
    // one and then the groove fill, while the fill and the notch it holds
    // are in its content slot, in declaration order. Filtered on `radius` so
    // the hover tracker (a MouseArea) and the dither remainder (a Loader,
    // inactive under the stub's metamorphosis preset) stay out of the count.
    function rects(item) {
        var out = [];
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i];
            if (child.radius !== undefined && child.border !== undefined)
                out.push(child);
        }
        return out;
    }

    function grooveOf(track) {
        var all = rects(track);
        return all[all.length - 2];
    }

    function haloOf(track) {
        var all = rects(track);
        return all.length > 2 ? all[0] : null;
    }

    function layers(track) {
        var out = rects(track.contentItem);
        compare(out.length, 2);
        return out;
    }

    function fillOf(track) {
        return layers(track)[0];
    }

    function notchOf(track) {
        return layers(track)[1];
    }

    // The groove is one `Box` on the `track.groove` role (M60 T1b), so the
    // lines that role's entry declares are drawn rather than dropped.
    function test_the_groove_is_a_box_on_the_track_role() {
        var track = make({ value: 0.5 });
        compare(track.role, "track.groove");
        verify(track.contentItem);
        verify(Qt.colorEqual(grooveOf(track).color, Theme.box(track.role).fill));
    }

    function test_no_notch_unless_one_is_asked_for() {
        verify(!notchOf(make({ value: 0.5 })).visible);
    }

    // AudioPanel's 0..1.5 stream rails put the 1.0 boundary at 2/3, so
    // crossing into overdrive reads as a deliberate line.
    function test_a_notch_is_a_border_wide_cut_centred_on_its_fraction() {
        var track = make({ value: 0.5, notch: 1 / 1.5 });
        var notch = notchOf(track);
        verify(notch.visible);
        compare(notch.width, Theme.borderWidth);
        compare(notch.height, track.height);
        compare(notch.x, track.width * (1 / 1.5) - Theme.borderWidth / 2);
        // Cut through fill and groove alike, so it takes the surface colour
        // rather than either of them.
        verify(Qt.colorEqual(notch.color, Theme.color.background));
    }

    function test_groove_is_primary_at_a_fifth() {
        var groove = grooveOf(make({ value: 0.5 }));
        compare(groove.color.a, testCase.grooveAlpha);
        compare(Math.round(groove.color.r * 255), 0x11);
        compare(Math.round(groove.color.g * 255), 0x33);
        compare(Math.round(groove.color.b * 255), 0xff);
    }

    // The groove has to stay visible on a row carrying a `selected` or
    // `active` fill, which is what painting it `muted` cost.
    function test_groove_is_not_a_neutral_step() {
        var groove = grooveOf(make({ value: 0.5 }));
        verify(!Qt.colorEqual(groove.color, Theme.color.muted));
        verify(!Qt.colorEqual(groove.color, Theme.color.accent));
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
        compare(grooveOf(track).radius, Theme.radiusSm);
        compare(fillOf(track).radius, Theme.radiusSm);
    }

    function test_fill_width_is_the_fraction_of_the_groove() {
        var track = make({ value: 0.25 });
        compare(fillOf(track).width, track.width * 0.25);
    }

    // A held key or a drag updates `value` continuously; the fill's own
    // Behavior has to retarget on every one of those rather than restart,
    // which is what keeps a sweep smooth instead of stepped.
    function test_the_fill_animates_when_value_changes() {
        var track = make({ value: 0.25 });
        track.value = 0.75;
        tryCompare(fillOf(track), "width", track.width * 0.75, 1000);
    }

    function test_value_clamps_at_both_ends() {
        compare(make({ value: 1.7 })._fraction, 1);
        compare(make({ value: -3 })._fraction, 0);
    }

    function test_a_full_track_never_overflows_the_groove() {
        var track = make({ value: 4 });
        compare(fillOf(track).width, track.width);
    }

    function test_cursor_draws_the_ring() {
        var track = make({ value: 0.5, cursor: true });
        var halo = haloOf(track);
        verify(halo.visible);
        // The table's own ring layer: filled at that layer's alpha rather
        // than opaque under a 0.5 opacity, the same band of pixels.
        verify(Qt.colorEqual(halo.color, Qt.alpha(Theme.color.ring, testCase.ringAlpha)));
        compare(halo.opacity, 1);
        compare(halo.radius, Theme.radiusSm + Theme.ringWidth);
        compare(halo.width, track.width + Theme.ringWidth * 2);
        compare(grooveOf(track).border.width, Theme.borderWidth);
        verify(Qt.colorEqual(grooveOf(track).border.color, Theme.color.ring));
    }

    function test_no_cursor_draws_no_ring_and_no_border() {
        var track = make({ value: 0.5 });
        compare(haloOf(track), null);
        compare(grooveOf(track).border.width, 0);
    }

    // The halo falls outside the groove's own bounds, so a track in a column
    // sits at the same y and the same height with the ring on as without it.
    function test_the_ring_leaves_the_groove_geometry_alone() {
        var plain = make({ value: 0.5 });
        var ringed = make({ value: 0.5, cursor: true });
        compare(ringed.implicitHeight, plain.implicitHeight);
        compare(ringed.height, plain.height);
        compare(ringed.width, plain.width);
    }
}
