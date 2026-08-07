import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Bar-cell hover = full inversion (DESIGN.md §1.1/§3 amendment, M18 Task 4):
// a standalone (bar) cell's hover-cursor state swaps its fill and content to
// the accent pair (`Theme.inverted()`, same pair the ledger's `selected`
// fill uses), replacing the fill-alpha tint + border every other cell keeps.
// Full-bleed accent/urgent cells ink with their own `on*` role (§2.4), never
// each other's.
//
// Verified against a synthetic palette (init()/cleanup() below), not
// Palette.fallback()'s real hex values: the Flexoki fallback sets
// onAccent == onUrgent == background in both modes (dark ink #100F0F
// doubles as the dark background; light paper #FFFCF0 doubles as the
// light background), so hex-equality assertions against it can't
// distinguish a correct role from a swapped one — every role below is
// pairwise distinct so a wrong-role bug actually fails the assertion.
TestCase {
    id: testCase
    name: "CellHoverInversion"
    width: 400
    height: 400
    visible: true
    when: windowShown

    readonly property var sentinelColors: ({
        background: "#010101",
        backgroundAlt: "#020202",
        foreground: "#eeeeee",
        foregroundDim: "#aaaaaa",
        foregroundFaint: "#888888",
        rule: "#444444",
        accent: "#1133ff",
        onAccent: "#ffdd00",
        urgent: "#ff2222",
        onUrgent: "#22ff88",
        warning: "#ffaa00",
        onWarning: "#001122"
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
        verify(Qt.colorEqual(cell.foreground, Theme.color.onAccent));
    }

    function test_urgent_wins_over_hover_inversion() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: true, urgent: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.onUrgent));
    }
}
