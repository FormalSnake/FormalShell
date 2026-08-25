import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Cell's state table (DESIGN.md §2): which layer paints, and what ink
// content and meta rows resolve to, for every flag combination.
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

    // The four painted layers, in declaration order: the ring halo, the
    // body, the hover fill, the open-panel mark. They carry no ids reachable
    // from here, so they are picked out by being the cell's only Rectangle
    // children; test_cell_paints_four_layers below is what fails if that
    // changes.
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

    function test_cell_paints_four_layers() {
        var cell = makeCell({});
        var rects = layers(cell);
        compare(rects.length, 4);
        // The body is the only one that draws a border, and the halo is the
        // only one that reaches outside the cell.
        compare(rects[1].border.width, Theme.borderWidth);
        compare(rects[0].anchors.margins, -Theme.ringWidth);
        verify(!rects[3].visible);
    }

    function test_rest_is_card_over_border() {
        var cell = makeCell({});
        var rects = layers(cell);
        verify(!rects[0].visible);
        verify(Qt.colorEqual(rects[1].color, Theme.surface(Theme.color.card)));
        verify(Qt.colorEqual(rects[1].border.color, Theme.color.border));
        compare(rects[2].opacity, 0);
        verify(Qt.colorEqual(cell.foreground, Theme.color.foreground));
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.mutedForeground));
    }

    // The rest fill is the card colour at `theme.surfaceOpacity`, which is
    // what lets Hyprland's blur read through a bar cell (DESIGN.md §1
    // "Translucency and blur"). The channels are checked against the
    // sentinel's own literal, not against another Theme.surface() call: a
    // surface() that dropped the colour entirely and painted black at the
    // right alpha would satisfy a self-comparison, and did.
    function test_rest_fill_carries_the_surface_alpha() {
        var cell = makeCell({});
        var rects = layers(cell);
        compare(rects[1].color.a, Theme.surfaceOpacity);
        verify(Theme.surfaceOpacity < 1);
        compare(Math.round(rects[1].color.r * 255), 0x15);
        compare(Math.round(rects[1].color.g * 255), 0x15);
        compare(Math.round(rects[1].color.b * 255), 0x15);
    }

    function test_hover_fades_in_the_accent_layer() {
        var cell = makeCell({ hovered: true });
        var rects = layers(cell);
        verify(Qt.colorEqual(rects[2].color, Theme.color.accent));
        // The layer fades on Theme.motion.fast, so it is still climbing
        // when settle() returns.
        tryCompare(rects[2], "opacity", 1);
        verify(Qt.colorEqual(rects[1].color, Theme.surface(Theme.color.card)));
        verify(Qt.colorEqual(cell.foreground, Theme.color.foreground));
    }

    function test_active_fills_with_primary() {
        var cell = makeCell({ active: true });
        var rects = layers(cell);
        verify(Qt.colorEqual(rects[1].color, Theme.color.primary));
        verify(Qt.colorEqual(cell.foreground, Theme.color.primaryForeground));
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.primaryForeground));
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
        verify(Qt.colorEqual(rects[1].color, Theme.surface(Theme.color.card)));
        verify(Qt.colorEqual(rects[1].border.color, Theme.color.destructive));
        verify(Qt.colorEqual(cell.foreground, Theme.color.destructive));
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.mutedForeground));
    }

    function test_warning_colours_the_border_and_the_ink() {
        var cell = makeCell({ warning: true });
        var rects = layers(cell);
        verify(Qt.colorEqual(rects[1].color, Theme.surface(Theme.color.card)));
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

    // The bar's open-panel mark: 18 cells set `panelOpen` while their panel,
    // the launcher or the notification center is open.
    function test_panel_open_draws_a_primary_line_on_the_bottom_edge() {
        var cell = makeCell({ panelOpen: true });
        var mark = layers(cell)[3];
        verify(mark.visible);
        verify(Qt.colorEqual(mark.color, Theme.color.primary));
        compare(mark.height, Theme.borderWidth * 2);
        compare(mark.anchors.leftMargin, Theme.space.xs);
        compare(mark.anchors.rightMargin, Theme.space.xs);
    }

    // `ghost` (M47 D1): the bar strip behind the cell carries the fill and
    // the border, so a resting bar cell paints neither. Alpha rather than
    // Qt.colorEqual against a named colour: what has to be true is that
    // nothing is painted, whatever colour the layer nominally holds.
    function test_ghost_paints_nothing_at_rest() {
        var rects = layers(makeCell({ ghost: true }));
        compare(rects[1].color.a, 0);
        compare(rects[1].border.width, 0);
        compare(rects[2].opacity, 0);
        verify(!rects[0].visible);
        verify(!rects[3].visible);
    }

    function test_ghost_still_fades_in_the_hover_layer() {
        var rects = layers(makeCell({ ghost: true, hovered: true }));
        verify(Qt.colorEqual(rects[2].color, Theme.color.accent));
        tryCompare(rects[2], "opacity", 1);
        compare(rects[1].color.a, 0);
    }

    // A state that has something to say still says it, and the mark sits on
    // the cell's own bottom edge rather than inside a border that is no
    // longer drawn.
    function test_ghost_still_draws_the_panel_open_mark() {
        var mark = layers(makeCell({ ghost: true, panelOpen: true }))[3];
        verify(mark.visible);
        verify(Qt.colorEqual(mark.color, Theme.color.primary));
        compare(mark.anchors.bottomMargin, 0);
    }

    function test_ghost_still_draws_the_cursor_ring() {
        var rects = layers(makeCell({ ghost: true, cursor: true }));
        verify(rects[0].visible);
        compare(rects[1].border.width, Theme.borderWidth);
        verify(Qt.colorEqual(rects[1].border.color, Theme.color.ring));
    }

    function test_ghost_still_fills_when_active_and_bordered_when_destructive() {
        var activeCell = makeCell({ ghost: true, active: true });
        verify(Qt.colorEqual(layers(activeCell)[1].color, Theme.color.primary));
        var destructiveCell = makeCell({ ghost: true, destructive: true });
        var rects = layers(destructiveCell);
        compare(rects[1].border.width, Theme.borderWidth);
        verify(Qt.colorEqual(rects[1].border.color, Theme.color.destructive));
        compare(rects[1].color.a, 0);
    }
}
