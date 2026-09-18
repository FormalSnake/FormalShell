import QtQuick
import qs.Core
import qs.Components

// The strip's paint under `bar.kind: strip` (DESIGN.md §3 Bar, M47 D1, the
// habit split of M60 T3): a full-length `card` fill at `theme.surfaceOpacity`
// with a 1px `border` along its inner edge, and nothing else. The cells
// inside are ghosts, so this is the only fill and the only border the bar
// draws; the owner ran the floating-pill version on both boxes and asked
// for the shadcn navbar instead (2026-08-25).
//
// The paint alone: the window, its reservation, the three regions and every
// cell are Bar.qml's, either habit (BarWingpanel.qml is the other).
Item {
    id: root

    // The bar window this paints. Named `owner` rather than `bar`: the
    // Component that instantiates this sits inside that window, where a
    // property called `bar` would shadow the window's own id and the
    // assignment would be the property to itself.
    required property var owner

    // What a band hands its cells (BarWingpanel.qml): a strip hands them
    // nothing, and each cell's own state resolves its ink as it always has.
    readonly property color ink: "transparent"
    readonly property var inkShadow: []

    // The strip's own box in the theme's table: its fill, and the one line
    // it draws along the edge facing the desktop rather than a border round
    // all four sides (see the fill below).
    readonly property var _box: Theme.box("bar")
    readonly property var _edge: root._box.edge

    // The strip as drawn, less any cast the table hangs under the band:
    // the bar's window is exactly the strip's thickness and
    // `ExclusionMode.Auto` reserves that same thickness, so the room to
    // blur one into would have to come out of the reservation.
    readonly property var _stripBox: {
        var out = {};
        for (var key in root._box)
            out[key] = root._box[key];
        out.casts = [];
        return out;
    }

    // The card joined to THIS strip, if any (M54 D6, PanelRegistry.joins): a
    // join on another output or against another edge is somebody else's.
    readonly property var _join: PanelRegistry.joinOn(root.owner._position,
        root.owner.modelData ? root.owner.modelData.name : "")

    // The gap itself: one card's rect plus the fillets' `reach` at either
    // end, which is exactly the span Components/Shoulders.qml draws into. A
    // pure function of the join, with no clock of its own: the join is read
    // off the card's live rect, which the card's own clocks already carry,
    // and a second clock here left the line lagging the shoulders it has to
    // meet. Closed, the two segments meet at the start and the line is
    // whole.
    readonly property real _gapStart: root._join
        ? Math.max(0, Math.min(root.owner._along, root._join.x - root._join.reach))
        : 0
    readonly property real _gapEnd: root._join
        ? Math.max(root._gapStart, Math.min(root.owner._along, root._join.x + root._join.width + root._join.reach))
        : 0

    // The inward line's two segments in the bar window's own coordinates,
    // for `debug dump` (Ipc/DebugIpc.qml): a rig leg reads the gap a joined
    // card opened off the shell's own numbers instead of hunting for it in
    // pixels. A framed bar draws no hairline at all (FrameRing carries that
    // edge), so this is empty there rather than reporting a hidden rect.
    function lineRects() {
        if (root.owner._framed)
            return [];
        return [root._rectOf(hairlineStart), root._rectOf(hairlineEnd)];
    }

    // A strip has one paint and nothing under it to read, which is the
    // honest answer to `bar paint` here.
    function paintState() {
        return null;
    }

    function _rectOf(item) {
        var origin = item.mapToItem(null, 0, 0);
        return { x: origin.x, y: origin.y, width: item.width, height: item.height };
    }

    Box {
        anchors.fill: parent
        box: root._stripBox

        // The hairline that separates the strip from the desktop, and the
        // only edge the bar draws: the one facing inward. A `border` on the
        // fill above would ring all four sides, three of which are the
        // screen's own edges. With the screen frame on, the frame's own
        // stroke runs this side too, round the corners into its band, and
        // this whole fill is off (Bar.qml gates the Loader).
        //
        // Two segments rather than one (M54 D6): a card joined to the bar
        // opens a gap between them, its own rect plus a fillet's radius at
        // either end, and Components/Shoulders.qml draws the card's concave
        // shoulders into exactly that span, so the line runs into the card
        // instead of under it. The gap follows the join frame by frame (see
        // `_gapStart`) and is simply gone when none exists, which is what
        // leaves an ordinary session's line whole and still.
        Rectangle {
            id: hairlineStart
            width: root.owner._vertical ? root._edge.width : root._gapStart
            height: root.owner._vertical ? root._gapStart : root._edge.width
            x: root.owner._position === "left" ? parent.width - hairlineStart.width : 0
            y: root.owner._position === "top" ? parent.height - root._edge.width : 0
            color: root._edge.color
        }

        Rectangle {
            id: hairlineEnd
            width: root.owner._vertical ? root._edge.width : Math.max(0, parent.width - root._gapEnd)
            height: root.owner._vertical ? Math.max(0, parent.height - root._gapEnd) : root._edge.width
            x: root.owner._position === "left"
                ? parent.width - hairlineEnd.width
                : (root.owner._vertical ? 0 : root._gapEnd)
            y: root.owner._position === "top"
                ? parent.height - root._edge.width
                : (root.owner._vertical ? root._gapEnd : 0)
            color: root._edge.color
        }
    }
}
