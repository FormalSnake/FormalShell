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

    // The cell is a `Box`, so its chrome is the rectangles Box draws
    // (tst_box.qml walks the same shape): the cursor's halo when the box
    // carries one, then the body, then the pointer's wash. They carry no ids
    // reachable from here, so they are picked out by being the box's only
    // Rectangle children; test_cell_paints_its_box_and_its_mark below is
    // what fails if that changes.
    function boxRects(cell) {
        var out = [];
        for (var i = 0; i < cell.children.length; i++) {
            var child = cell.children[i];
            if (child.radius !== undefined && child.border !== undefined)
                out.push(child);
        }
        return out;
    }

    function bodyOf(cell) {
        var all = boxRects(cell);
        return all[all.length - 2];
    }

    function washOf(cell) {
        var all = boxRects(cell);
        return all[all.length - 1];
    }

    function haloOf(cell) {
        var all = boxRects(cell);
        return all.length > 2 ? all[0] : null;
    }

    // The open-panel mark is the cell's own, so it sits in the box's content
    // slot ahead of the pointer target and the content box.
    function markOf(cell) {
        var kids = cell.contentItem.children;
        for (var i = 0; i < kids.length; i++) {
            if (kids[i].radius !== undefined)
                return kids[i];
        }
        return null;
    }

    function makeCell(props) {
        var cell = createTemporaryObject(cellComponent, testCase, props);
        verify(cell);
        settle(cell);
        return cell;
    }

    // The cell composes one `Box` on the `cell` role (M60 T1b), so every
    // layer that role's entry declares is drawn rather than only its fill
    // and its border.
    function test_the_cell_is_a_box_on_the_cell_role() {
        var cell = makeCell({});
        compare(cell.role, "cell");
        verify(cell.contentItem);
        verify(Qt.colorEqual(bodyOf(cell).color, Theme.box(cell.role).fill));
    }

    function test_cell_paints_its_box_and_its_mark() {
        var cell = makeCell({});
        // At rest the box is the body and the pointer's wash; the body is
        // the one that draws a border, and the mark is the cell's own.
        compare(boxRects(cell).length, 2);
        compare(bodyOf(cell).border.width, Theme.borderWidth);
        verify(!markOf(cell).visible);
        compare(haloOf(cell), null);

        // The halo is instantiated by the cursor alone, and it is the only
        // layer that reaches outside the cell.
        var ringed = makeCell({ cursor: true });
        compare(boxRects(ringed).length, 3);
        compare(haloOf(ringed).anchors.margins, -Theme.ringWidth);
    }

    function test_rest_is_card_over_border() {
        var cell = makeCell({});
        compare(haloOf(cell), null);
        verify(Qt.colorEqual(bodyOf(cell).color, Theme.surface(Theme.color.card)));
        verify(Qt.colorEqual(bodyOf(cell).border.color, Theme.color.border));
        compare(washOf(cell).opacity, 0);
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
        var body = bodyOf(makeCell({}));
        compare(body.color.a, Theme.surfaceOpacity);
        verify(Theme.surfaceOpacity < 1);
        compare(Math.round(body.color.r * 255), 0x15);
        compare(Math.round(body.color.g * 255), 0x15);
        compare(Math.round(body.color.b * 255), 0x15);
    }

    // The wash, not an opaque `accent` chip: the cell's rest fill already
    // carries `surfaceOpacity`, so a fill on top of it lands at a delta the
    // wallpaper behind the blur decides.
    function test_hover_fades_in_the_ink_wash() {
        var cell = makeCell({ hovered: true });
        var wash = washOf(cell);
        verify(Qt.colorEqual(wash.color, Theme.hoverFill));
        verify(wash.color.a < 1);
        // The layer fades on the effects clock, so it is still climbing
        // when settle() returns.
        tryCompare(wash, "opacity", 1);
        verify(Qt.colorEqual(bodyOf(cell).color, Theme.surface(Theme.color.card)));
        verify(Qt.colorEqual(cell.foreground, Theme.color.foreground));
    }

    function test_active_fills_with_primary() {
        var cell = makeCell({ active: true });
        verify(Qt.colorEqual(bodyOf(cell).color, Theme.color.primary));
        verify(Qt.colorEqual(cell.foreground, Theme.color.primaryForeground));
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.primaryForeground));
    }

    function test_selected_fills_with_accent() {
        var cell = makeCell({ selected: true });
        verify(Qt.colorEqual(bodyOf(cell).color, Theme.color.accent));
        verify(Qt.colorEqual(cell.foreground, Theme.color.accentForeground));
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.accentForeground));
    }

    function test_active_wins_over_selected() {
        var cell = makeCell({ active: true, selected: true });
        verify(Qt.colorEqual(bodyOf(cell).color, Theme.color.primary));
        verify(Qt.colorEqual(cell.foreground, Theme.color.primaryForeground));
    }

    function test_a_filled_cell_takes_no_hover_layer() {
        var activeCell = makeCell({ active: true, hovered: true });
        var selectedCell = makeCell({ selected: true, hovered: true });
        compare(washOf(activeCell).opacity, 0);
        compare(washOf(selectedCell).opacity, 0);
    }

    // Colour on the border and the ink, never a fill (DESIGN.md §5).
    function test_destructive_colours_the_border_and_the_ink() {
        var cell = makeCell({ destructive: true });
        verify(Qt.colorEqual(bodyOf(cell).color, Theme.surface(Theme.color.card)));
        verify(Qt.colorEqual(bodyOf(cell).border.color, Theme.color.destructive));
        verify(Qt.colorEqual(cell.foreground, Theme.color.destructive));
        verify(Qt.colorEqual(cell.dimForeground, Theme.color.mutedForeground));
    }

    function test_warning_colours_the_border_and_the_ink() {
        var cell = makeCell({ warning: true });
        verify(Qt.colorEqual(bodyOf(cell).color, Theme.surface(Theme.color.card)));
        verify(Qt.colorEqual(bodyOf(cell).border.color, Theme.color.warning));
        verify(Qt.colorEqual(cell.foreground, Theme.color.warning));
    }

    // The halo is the table's own ring layer (M59 T6): filled at that
    // layer's alpha rather than painted opaque under a 0.5 opacity, which is
    // the same band of pixels either way.
    function test_cursor_draws_the_ring() {
        var cell = makeCell({ cursor: true });
        var halo = haloOf(cell);
        verify(halo.visible);
        verify(Qt.colorEqual(halo.color, Qt.alpha(Theme.color.ring, testCase.ringAlpha)));
        compare(halo.opacity, 1);
        compare(halo.radius, Theme.radiusMd + Theme.ringWidth);
        verify(Qt.colorEqual(bodyOf(cell).border.color, Theme.color.ring));
    }

    function test_cursor_ring_beats_a_destructive_border() {
        var cell = makeCell({ cursor: true, destructive: true });
        verify(Qt.colorEqual(bodyOf(cell).border.color, Theme.color.ring));
        verify(Qt.colorEqual(cell.foreground, Theme.color.destructive));
    }

    // The bar's open-panel mark: 18 cells set `panelOpen` while their panel,
    // the launcher or the notification center is open.
    function test_panel_open_draws_a_primary_line_on_the_bottom_edge() {
        var cell = makeCell({ panelOpen: true });
        var mark = markOf(cell);
        verify(mark.visible);
        verify(Qt.colorEqual(mark.color, Theme.color.primary));
        compare(mark.height, Theme.borderWidth * 2);
        compare(mark.x, Theme.space.xs);
        compare(mark.width, cell.width - Theme.space.xs * 2);
        compare(mark.y, cell.height - mark.height - Theme.borderWidth);
    }

    // On a left bar the same mark stands along the cell's inner edge, the
    // right one, and a ghost cell has no border to sit inside of.
    function test_panel_open_on_a_left_bar_marks_the_inner_edge() {
        var cell = makeCell({ panelOpen: true, barEdge: "left", ghost: true });
        var mark = markOf(cell);
        verify(mark.visible);
        compare(mark.width, Theme.borderWidth * 2);
        compare(mark.height, cell.height - Theme.space.xs * 2);
        compare(mark.x, cell.width - mark.width);
        compare(mark.y, Theme.space.xs);
    }

    // `ghost` (M47 D1): the bar strip behind the cell carries the fill and
    // the border, so a resting bar cell paints neither. Alpha rather than
    // Qt.colorEqual against a named colour: what has to be true is that
    // nothing is painted, whatever colour the layer nominally holds.
    function test_ghost_paints_nothing_at_rest() {
        var cell = makeCell({ ghost: true });
        compare(bodyOf(cell).color.a, 0);
        compare(bodyOf(cell).border.width, 0);
        compare(washOf(cell).opacity, 0);
        compare(haloOf(cell), null);
        verify(!markOf(cell).visible);
    }

    function test_ghost_still_fades_in_the_hover_layer() {
        var cell = makeCell({ ghost: true, hovered: true });
        verify(Qt.colorEqual(washOf(cell).color, Theme.hoverFill));
        tryCompare(washOf(cell), "opacity", 1);
        compare(bodyOf(cell).color.a, 0);
    }

    // A state that has something to say still says it, and the mark sits on
    // the cell's own bottom edge rather than inside a border that is no
    // longer drawn.
    function test_ghost_still_draws_the_panel_open_mark() {
        var mark = markOf(makeCell({ ghost: true, panelOpen: true }));
        verify(mark.visible);
        verify(Qt.colorEqual(mark.color, Theme.color.primary));
        compare(mark.anchors.bottomMargin, 0);
    }

    function test_ghost_still_draws_the_cursor_ring() {
        var cell = makeCell({ ghost: true, cursor: true });
        verify(haloOf(cell).visible);
        compare(bodyOf(cell).border.width, Theme.borderWidth);
        verify(Qt.colorEqual(bodyOf(cell).border.color, Theme.color.ring));
    }

    function test_ghost_still_fills_when_active_and_bordered_when_destructive() {
        var activeCell = makeCell({ ghost: true, active: true });
        verify(Qt.colorEqual(bodyOf(activeCell).color, Theme.color.primary));
        var destructiveCell = makeCell({ ghost: true, destructive: true });
        compare(bodyOf(destructiveCell).border.width, Theme.borderWidth);
        verify(Qt.colorEqual(bodyOf(destructiveCell).border.color, Theme.color.destructive));
        compare(bodyOf(destructiveCell).color.a, 0);
    }
}
