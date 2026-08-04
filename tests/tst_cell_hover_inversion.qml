import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Bar-cell hover = full inversion (DESIGN.md §1.1/§3 amendment, M-polish
// batch item E): a standalone (bar) cell's hover-cursor state swaps its
// fill to `foreground` and its content to `background`, replacing the
// fill-alpha tint + border every other cell keeps. Verified against the
// same real Theme stub tst_cell_geometry.qml uses (Palette.fallback()'s
// real background/foreground hex values, not invented ones).
TestCase {
    id: testCase
    name: "CellHoverInversion"
    width: 400
    height: 400
    visible: true
    when: windowShown

    Component {
        id: cellComponent
        Cell {}
    }

    function settle(item) {
        waitForRendering(item);
        wait(50);
    }

    function test_standalone_hover_inverts_foreground_to_background() {
        var cell = createTemporaryObject(cellComponent, testCase, { standalone: true, hovered: true });
        verify(cell);
        settle(cell);
        verify(Qt.colorEqual(cell.foreground, Theme.color.background));
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
        verify(Qt.colorEqual(cell.foreground, Theme.color.onAccent));
    }
}
