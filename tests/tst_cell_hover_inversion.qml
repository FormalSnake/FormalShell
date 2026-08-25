import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Bar-cell hover = full inversion (DESIGN.md §1.1/§3 amendment, M18 Task 4):
// a standalone (bar) cell's hover-cursor state swaps its fill and content to
// the primary pair (`Theme.inverted()`, same pair the ledger's `selected`
// fill uses), replacing the fill-alpha tint + border every other cell keeps.
// Full-bleed primary/destructive/warning cells ink with their own
// `*Foreground` role (§2.4), never each other's.
//
// Verified against a synthetic palette (init()/cleanup() below), not
// Palette.fallback()'s real hex values: a fallback set can coincidentally
// share a hex across two different roles, which would make a hex-equality
// assertion against it unable to distinguish a correct role from a swapped
// one, so every role below is pairwise distinct.
TestCase {
    id: testCase
    name: "CellHoverInversion"
    width: 400
    height: 400
    visible: true
    when: windowShown

    readonly property var sentinelColors: ({
        background: "#010101",
        foreground: "#eeeeee",
        mutedForeground: "#aaaaaa",
        border: "#444444",
        primary: "#1133ff",
        primaryForeground: "#ffdd00",
        destructive: "#ff2222",
        destructiveForeground: "#22ff88",
        warning: "#ffaa00",
        warningForeground: "#001122"
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
        id: cellComponent
        Cell {}
    }

    function settle(item) {
        waitForRendering(item);
        wait(50);
    }

    function test_standalone_hover_inverts_to_accent_pair() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.inverted().fg));
    }

    function test_non_standalone_hover_keeps_the_tint_model() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: false, hovered: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.foreground));
    }

    function test_standalone_not_hovered_stays_plain_foreground() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: false });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.foreground));
    }

    function test_selected_wins_over_hover_inversion() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: true, selected: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.inverted().fg));
    }

    function test_accent_wins_over_hover_inversion() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: true, accent: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.primaryForeground));
    }

    function test_urgent_wins_over_hover_inversion() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: true, urgent: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.destructiveForeground));
    }

    function test_warning_wins_over_hover_inversion() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: true, warning: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.warningForeground));
    }

    // The ink button (DESIGN.md §2 item 11, M19 Task 4): fill priority is
    // urgent > accent > warning > ink > selected-inversion.
    function test_ink_cell_rests_with_background_ink() {
        var cell = createTemporaryObject(cellComponent, testCase, { ink: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.background));
    }

    function test_ink_wins_over_selected() {
        var cell = createTemporaryObject(cellComponent, testCase, { ink: true, selected: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.background));
    }

    function test_warning_wins_over_ink() {
        var cell = createTemporaryObject(cellComponent, testCase, { ink: true, warning: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.warningForeground));
    }

    // Hover/press on an ink cell keeps the accent-pair inversion, exactly
    // like the standalone bar-cell path — even a non-standalone (ledger)
    // ink cell inverts on hover instead of falling back to the plain tint
    // model non-ink ledger cells keep (test_non_standalone_hover_keeps_the_
    // tint_model above).
    function test_ink_hover_inverts_to_accent_pair() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: false, ink: true, hovered: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.inverted().fg));
    }

    function test_accent_wins_over_ink_hover_inversion() {
        var cell = createTemporaryObject(cellComponent, testCase, { ink: true, hovered: true, accent: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.primaryForeground));
    }

    // DESIGN.md §1.1's snap rule: under hover inversion, a meta caption
    // bound to `dimForeground` collapses into the same band as content ink
    // instead of staying a dim variant on top of the primary fill (M20 Task
    // 2, MetaLabel captions like Clock's TIME / WeatherWidget's temperature
    // used to hardcode `mutedForeground` and never invert at all).
    function test_standalone_hover_promotes_dimForeground_to_primaryForeground() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.dimForeground, Theme.inverted().fg));
    }

    function test_standalone_not_hovered_dimForeground_stays_dim() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: false });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.mutedForeground));
    }

    function test_invertedNow_tracks_hover_inversion() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: true });
        verify(cell);
        settle(cell);
        verify(cell.invertedNow);
    }

    function test_invertedNow_false_at_rest() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: false });
        verify(cell);
        settle(cell);
        verify(!cell.invertedNow);
    }

    // PanelOpenDot (DESIGN.md §1.1 amendment): stays visible against the
    // hover-inverted primary fill by swapping to `primaryForeground` instead
    // of vanishing as a plain primary dot on a primary background.
    Component {
        id: dotComponent
        PanelOpenDot {}
    }

    function test_panel_open_dot_rests_at_primary() {
        var dot = createTemporaryObject(dotComponent, testCase, { inverted: false });
        verify(dot);
        settle(dot);
        verify(Qt.colorEqual(dot.color, Theme.color.primary));
    }

    function test_panel_open_dot_flips_to_primaryForeground_when_inverted() {
        var dot = createTemporaryObject(dotComponent, testCase, { inverted: true });
        verify(dot);
        settle(dot);
        verify(Qt.colorEqual(dot.color, Theme.color.primaryForeground));
    }
}
