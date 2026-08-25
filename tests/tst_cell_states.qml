import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Cell's state table (DESIGN.md §2, M41 plan D3): which layer paints, and
// what ink content and meta rows resolve to, for every flag combination.
// The mapped legacy props are asserted alongside their new names, since 59
// files still set the old ones.
//
// Verified against a synthetic palette (init()/cleanup() below), not
// Palette.fallback()'s real hex values: a fallback set can coincidentally
// share a hex across two different roles, which would make a hex-equality
// assertion against it unable to distinguish a correct role from a swapped
// one, so every role below is pairwise distinct.
TestCase {
    id: testCase
    name: "CellStates"
    width: 400
    height: 400
    visible: true
    when: windowShown

    readonly property var sentinelColors: ({
        background: "#010101",
        foreground: "#eeeeee",
        mutedForeground: "#aaaaaa",
        card: "#151515",
        border: "#444444",
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
        id: cellComponent
        Cell {}
    }

    function settle(item) {
        waitForRendering(item);
        wait(50);
    }

    // The three painted layers, in declaration order: the ring halo, the
    // body, the hover fill. They carry no ids reachable from here, so they
    // are picked out by being the cell's only Rectangle children;
    // test_cell_paints_three_layers below is what fails if that changes.
    function layers(cell) {
        var out = [];
        for (var i = 0; i < cell.children.length; i++) {
            var child = cell.children[i];
            if (child.radius !== undefined && child.border !== undefined)
                out.push(child);
        }
        return out;
    }

    function makeCell(props) {
        var cell = createTemporaryObject(cellComponent, testCase, props);
        verify(cell);
        settle(cell);
        return cell;
    }

    function test_cell_paints_three_layers() {
        var cell = makeCell({});
        var rects = layers(cell);
        compare(rects.length, 3);
        // The body is the only one that draws a border, and the halo is the
        // only one that reaches outside the cell.
        compare(rects[1].border.width, Theme.borderWidth);
        compare(rects[0].anchors.margins, -Theme.ringWidth);
    }

    function test_rest_is_card_over_border() {
        var cell = makeCell({});
        var rects = layers(cell);
        verify(!rects[0].visible);
        verify(Qt.colorEqual(rects[1].color, Theme.color.card));
        verify(Qt.colorEqual(rects[1].border.color, Theme.color.border));
        compare(rects[2].opacity, 0);
        verify(Qt.colorEqual(cell.foreground, Theme.color.foreground));
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.mutedForeground));
    }

    function test_hover_fades_in_the_accent_layer() {
        var cell = makeCell({ hovered: true });
        var rects = layers(cell);
        verify(Qt.colorEqual(rects[2].color, Theme.color.accent));
        // The layer fades on Theme.motion.fast, so it is still climbing
        // when settle() returns.
        tryCompare(rects[2], "opacity", 1);
        verify(Qt.colorEqual(rects[1].color, Theme.color.card));
        verify(Qt.colorEqual(cell.foreground, Theme.color.foreground));
    }

    function test_active_fills_with_primary() {
        var cell = makeCell({ active: true });
        var rects = layers(cell);
        verify(Qt.colorEqual(rects[1].color, Theme.color.primary));
        verify(Qt.colorEqual(cell.foreground, Theme.color.primaryForeground));
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.primaryForeground));
        verify(cell.invertedNow);
    }

    function test_accent_and_ink_map_to_active() {
        var accentCell = makeCell({ accent: true });
        var inkCell = makeCell({ ink: true });
        verify(Qt.colorEqual(layers(accentCell)[1].color, Theme.color.primary));
        verify(Qt.colorEqual(layers(inkCell)[1].color, Theme.color.primary));
        verify(accentCell.invertedNow);
        verify(inkCell.invertedNow);
    }

    function test_selected_fills_with_accent() {
        var cell = makeCell({ selected: true });
        verify(Qt.colorEqual(layers(cell)[1].color, Theme.color.accent));
        verify(Qt.colorEqual(cell.foreground, Theme.color.accentForeground));
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.accentForeground));
    }

    function test_active_wins_over_selected() {
        var cell = makeCell({ active: true, selected: true });
        verify(Qt.colorEqual(layers(cell)[1].color, Theme.color.primary));
        verify(Qt.colorEqual(cell.foreground, Theme.color.primaryForeground));
    }

    function test_a_filled_cell_takes_no_hover_layer() {
        var activeCell = makeCell({ active: true, hovered: true });
        var selectedCell = makeCell({ selected: true, hovered: true });
        compare(layers(activeCell)[2].opacity, 0);
        compare(layers(selectedCell)[2].opacity, 0);
    }

    // Colour on the border and the ink, never a fill (DESIGN.md §5).
    function test_destructive_colours_the_border_and_the_ink() {
        var cell = makeCell({ destructive: true });
        var rects = layers(cell);
        verify(Qt.colorEqual(rects[1].color, Theme.color.card));
        verify(Qt.colorEqual(rects[1].border.color, Theme.color.destructive));
        verify(Qt.colorEqual(cell.foreground, Theme.color.destructive));
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.mutedForeground));
    }

    function test_urgent_maps_to_destructive() {
        var cell = makeCell({ urgent: true });
        verify(Qt.colorEqual(layers(cell)[1].border.color, Theme.color.destructive));
        verify(Qt.colorEqual(cell.foreground, Theme.color.destructive));
    }

    function test_warning_colours_the_border_and_the_ink() {
        var cell = makeCell({ warning: true });
        var rects = layers(cell);
        verify(Qt.colorEqual(rects[1].color, Theme.color.card));
        verify(Qt.colorEqual(rects[1].border.color, Theme.color.warning));
        verify(Qt.colorEqual(cell.foreground, Theme.color.warning));
    }

    function test_cursor_draws_the_ring() {
        var cell = makeCell({ cursor: true });
        var rects = layers(cell);
        verify(rects[0].visible);
        verify(Qt.colorEqual(rects[0].color, Theme.color.ring));
        compare(rects[0].opacity, Theme.ringAlpha);
        compare(rects[0].radius, Theme.radiusMd + Theme.ringWidth);
        verify(Qt.colorEqual(rects[1].border.color, Theme.color.ring));
    }

    function test_cursor_ring_beats_a_destructive_border() {
        var cell = makeCell({ cursor: true, destructive: true });
        verify(Qt.colorEqual(layers(cell)[1].border.color, Theme.color.ring));
        verify(Qt.colorEqual(cell.foreground, Theme.color.destructive));
    }

    function test_standalone_and_pending_paint_nothing() {
        var cell = makeCell({ standalone: true, pending: true });
        var rects = layers(cell);
        compare(rects.length, 3);
        verify(Qt.colorEqual(rects[1].color, Theme.color.card));
        verify(Qt.colorEqual(cell.foreground, Theme.color.foreground));
    }

    function test_invertedNow_false_when_nothing_is_filled() {
        verify(!makeCell({}).invertedNow);
        verify(!makeCell({ selected: true }).invertedNow);
        verify(!makeCell({ hovered: true }).invertedNow);
    }

    // PanelOpenDot: 22 bar widgets bind its `inverted` to their cell's
    // `invertedNow` so the dot stays visible against a primary fill.
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
