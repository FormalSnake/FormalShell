import QtQuick
import qs.Core
import "cursor.js" as Cursor

// The shadcn item (DESIGN.md §2), drawn from the `cell` role of the live
// table (shell/Theme/themes/). Every bar cell, list row and chip on every
// surface is one of these, so what a row looks like is one theme entry
// rather than a literal in this file.
//
// The box it hands the renderer is composed here rather than read off one
// state: the fill and the border answer different states, the pointer's
// wash only paints while it is the top layer, and the cursor's halo is
// dropped when a list above owns one. The open-panel mark, the pointer
// target and the content box are the cell's own and stay below.
Box {
    id: root

    default property alias data: contentBox.data

    // --- Pointer (the lit area is the hit area) --------------------------
    //
    // The cell owns the one pointer target that spans it, so no surface
    // builds its own. A MouseArea in the default slot cannot do this job:
    // that slot forwards into `contentBox`, which is inset by the control
    // padding, so the area lands short by controlPaddingX either side and
    // controlPaddingY top and bottom, and the cell lights up and reads as
    // clickable across a band that answers nothing. On the bar that band
    // includes the row of pixels against the screen edge.
    //
    // `interactive` arms it: hover tracking, the pointing-hand cursor, and
    // clicks. It doubles as the enable gate, so `interactive: outCell._canToggle`
    // says both things at once, and a cell that never sets it stays inert.
    property bool interactive: false

    // Widens what `clicked` reports (the bell's right-click DND, the tray's
    // three buttons) or empties it: `Qt.NoButton` makes a hover-only tracker,
    // which also drops the pointing-hand cursor, since nothing there answers
    // a click.
    property int acceptedButtons: Qt.LeftButton

    // `hovered` follows the pointer by default. A surface carrying its own
    // keyboard cursor (every panel list) ORs the two instead:
    // `hovered: root.containsPointer || index === panel.cursor`.
    readonly property bool containsPointer: pointer.containsMouse

    signal clicked(var mouse)
    signal wheeled(var wheel)
    // Local to the cell, which is the frame PointerMoveGate.moved() wants
    // (`pointer` spans it exactly).
    signal pointerMoved(real x, real y)

    // Escape hatch for a target that deliberately covers less than the cell,
    // a button on one half and a legend on the other. A whole-cell target
    // belongs on
    // `interactive` above, never here. Anchor to `parent` (this layer spans
    // the cell) and not to a content child.
    //
    // Declared ahead of `contentBox` deliberately: an interactive child inside
    // the content box (a slider track, a nested Cell) is then stacked above
    // both this and `pointer`, and keeps its own events.
    property alias hit: hitLayer.data

    // The keyboard cursor: the ring, and nothing else. The only place the
    // wallpaper colour reaches chrome that is neither selected nor active,
    // which is what makes the cursor findable at a glance. On while the row
    // holds the cursor however it got there; whether the ring draws is
    // `_ringOwner`'s answer below.
    property bool cursor: false

    // `radius` is Box's, and the table's own corner stands unless a consumer
    // states one: the concentric rule (spec "Radius") is geometry, so a cell
    // nested inside another bordered surface takes the outer radius minus
    // the padding between them, and the calendar's day grid, one level
    // deeper again, sets `radiusSm`.

    property bool active: false
    property bool destructive: false
    property bool warning: false
    property bool selected: false
    property bool hovered: root.containsPointer

    // A bar cell (DESIGN.md §3 Bar): the strip behind it already carries the
    // card fill and the border, so a resting ghost paints neither and the bar
    // reads as one surface. Every state that is not "resting" still draws
    // exactly as it does anywhere else: the hover fill, the active and
    // selected fills, the cursor ring, the destructive and warning borders,
    // and the open-panel mark, unless the table paints that one on the cell
    // itself (`_ghostOpenState` below). Bar.qml sets this on every cell it
    // hosts.
    property bool ghost: false

    // The ink the band under this cell decides, and the shadow that lifts it
    // off what it is drawn onto (M60 T3, Surfaces/Bar/BarWingpanel.qml):
    // white over a dark band, dark over a light one. Handed down by the bar
    // beside `ghost`, and transparent everywhere else, which leaves every
    // state's own ink standing. The band's ink comes with the band's weight
    // too, which is what `bandInk` below says to a label.
    //
    // The shadow is the table's own layer list (M63 O6), empty everywhere a
    // band does not reach and under any table declaring none, which is what
    // keeps the glow below from instantiating an effect.
    property color barInk: "transparent"
    property var barInkShadow: []

    readonly property bool bandInk: root.barInk.a > 0

    // The output edge the bar this cell sits on occupies (`bar.position`),
    // or empty for a cell anywhere else. Bar.qml sets it on every cell it
    // hosts, next to `ghost`. It decides which edge the open-panel mark
    // lands on (the one facing the desktop), which side the tooltip opens
    // to, and, on a left or right bar, that the cell's content stacks
    // along the strip instead of running across it.
    property string barEdge: ""

    // On a left or right bar. The content box then runs down the strip
    // rather than across it: a widget authored as a `CellRow` of icon and
    // label lays that row out as an upright column
    // (Components/CellRow.qml), and every glyph in it stands up exactly as
    // it does on a horizontal bar. Nothing rotates
    // (Bar/layout.js's labelRotation carries the one exception).
    readonly property bool vertical: root.barEdge === "left" || root.barEdge === "right"

    // How far a line of free text turns, in degrees, for the two cells that
    // carry one: the window title and the now-playing track
    // (Bar/layout.js's labelRotation documents why those two alone turn).
    // Everything else in the cell ignores it.
    readonly property int labelRotation: root.barEdge === "left" ? -90 : root.barEdge === "right" ? 90 : 0

    // The cell's chrome is two answers rather than one: which fill it
    // carries and which border. `ghost` drops both, but never a colour a
    // state asked for, so the two resolve from their own states: `active`
    // over a ghost is a primary fill and no border, `destructive` over one
    // is a destructive border and no fill.
    readonly property string _fillState: root.active
        ? "active"
        : (root.selected && !root._selectionOwned)
            ? "selected"
            : root.ghost ? (root._ghostOpenState || "ghost") : "rest"

    // The open-panel look where the theme paints it on the cell rather than
    // as a line along the bar's edge: wingpanel fills an open indicator, so
    // the table carries a `ghostOpen` state and the mark below stands down.
    // Empty for a table that describes none, which is the ghost's own box
    // and the mark.
    readonly property string _ghostOpenState: root.ghost && root.panelOpen
        && Theme.hasState(root.role, "ghostOpen") ? "ghostOpen" : ""

    readonly property string _borderState: root.destructive
        ? "destructive"
        : root.warning
            ? "warning"
            : root.ghost ? "ghost" : "rest"

    role: "cell"

    // The whole box: the fill state's own material (its face, its lines and
    // its casts) under the border state's line, the pointer's wash while it
    // is the top layer, and the cursor over both (M59 T6), which takes the
    // border whatever the state resolved and appends its halo unless a list
    // above draws one.
    //
    // A border a state drops is kept at width 0 in the resting colour rather
    // than removed, so a ghost cell taking the cursor travels from `border`
    // to `ring` instead of fading in out of nothing.
    box: {
        var composed = {};
        var base = Theme.box(root.role, root._fillState);
        for (var key in base)
            composed[key] = base[key];
        var line = Theme.box(root.role, root._borderState).border;
        composed.border = line || { color: root._restBorderColor, width: 0 };
        composed.wash = root._hoverFillActive ? Theme.box(root.role, "hover").wash : null;
        return Theme.withCursor(composed, root._cursorRing, !root._haloOwned);
    }

    readonly property color _restBorderColor: {
        var rest = Theme.box(root.role).border;
        return rest ? rest.color : "transparent";
    }

    readonly property real _borderWidth: root.box.border ? root.box.border.width : 0

    readonly property var _markBox: Theme.box("cell.mark")

    // A bar cell whose panel (or the launcher, or the notification center)
    // is open (DESIGN.md §3 Bar).
    property bool panelOpen: false

    // Arms the `Behavior on implicitWidth` a dozen bar cells carry over
    // their own changing content (Clock, Battery, Weather, NowPlaying and
    // the rest). False makes a width change land in one frame instead.
    // Bar.qml holds it false until the strip's entrance has settled, so a
    // session's first second of async service answers arrives as one layout
    // rather than as a dozen cells gliding open in sequence. Every cell
    // elsewhere in the shell keeps the default and is untouched.
    property bool animateSize: true

    // Hover paints below both fills (active > selected > hover).
    readonly property bool _hoverFillActive: root.hovered && !root.active && !root.selected

    // Hover tooltip: a short line naming what this cell is and what it
    // currently reads, shown after the group's own delay once the pointer
    // settles and dropped the instant it leaves. Empty (the default) means no
    // tooltip at all.
    //
    // ⚠️ Nothing here draws the card: the surface is one layer-shell window
    // per output (Tooltip.qml, reached through TooltipRegistry), so a cell
    // holds no card and no size for one. A tooltip drawn as a child item
    // would widen and heighten every cell it was attached to, since
    // _measure() below sizes the cell off EVERY direct child of `contentBox`
    // regardless of visibility.
    property string tooltipText: ""

    // Inert since the tooltip stopped uppercasing anything; tray items still
    // set it.
    property bool tooltipVerbatim: false

    // What a state resolves the content ink to, before any crossfade: the
    // band-2 ink below reads the same instant value rather than the animated
    // one, so it travels beside `foreground` instead of chasing it.
    readonly property color _ink: root.active
        ? Theme.color.primaryForeground
        : root.destructive
            ? Theme.color.destructive
            : root.warning
                ? Theme.color.warning
                : root.selected
                    ? Theme.color.accentForeground
                    : root.bandInk ? root.barInk : Theme.color.foreground

    // Not readonly, so the Behavior has a property to intercept: the ink a
    // cell's labels bind to crosses on the same clock its fill does, or the
    // words would snap to `primaryForeground` over a fill still on its way
    // to `primary`.
    property color foreground: root._ink

    Behavior on foreground {
        CAnim {}
    }

    // Band-2 (meta) ink. A dim caption drawn onto a filled cell measures
    // under 1.1:1 contrast, so a fill promotes it to the same ink
    // `foreground` resolves for content. A destructive or warning cell is not
    // filled (its colour is on the border and the label), so its captions
    // stay dim. A cell on a band takes the band's ink for both: a dim
    // caption over a wallpaper is not a caption.
    property color dimForeground: (root.active || root.selected || root.bandInk)
        ? root._ink
        : Theme.color.mutedForeground

    Behavior on dimForeground {
        CAnim {}
    }

    // A badge sitting inside a row (the process table's KERNEL cell) rather
    // than being one: it hugs its own label, since a badge as tall as the
    // row around it reads as a second row.
    property bool chip: false

    // The content's own two extents. `along` runs the way the content is
    // laid out (a row's length, or a vertical cell's column of stacked
    // children); `across` is the other side of it. Which screen axis each
    // lands on is the only thing `vertical` changes.
    readonly property real _contentAlong: root._measure(root.vertical)
    readonly property real _contentAcross: root._measure(!root.vertical)

    readonly property real _alongExtent: root._contentAlong + Theme.space.controlPaddingX * 2
    // A row is `controlHeight` tall (DESIGN.md §1 Padding). Content that
    // needs more (a two-line row, a clipboard thumbnail) still grows past
    // it; the padding alone never decides the height of a one-line row,
    // which is what left every list in the shell a few pixels short of the
    // controls beside it.
    readonly property real _acrossExtent: Math.max(root.chip ? 0 : Theme.space.controlHeight,
        root._contentAcross + Theme.space.controlPaddingY * 2)

    // A cell on a vertical bar is as tall as its stack is long, and as wide
    // as that stack is broad.
    implicitWidth: root.vertical ? root._acrossExtent : root._alongExtent
    implicitHeight: root.vertical ? root._alongExtent : root._acrossExtent

    // The cell's own extent across the content: its height, or on a
    // vertical bar its width.
    readonly property real _across: root.vertical ? root.width : root.height

    // Content is centred across the row (DESIGN.md §1 Padding), so the
    // inset grows past `controlPaddingY` whenever the cell is taller than
    // its content: a row floored at `controlHeight`, and a cell given an
    // explicit height (a calendar day, a bar cell). Equal insets either
    // side of the content box are what do the centring; the children
    // themselves need no anchor of their own.
    readonly property real _insetAcross: Math.max(Theme.space.controlPaddingY,
        (root._across - root._contentAcross) / 2)

    // How much room a child has across the content on a vertical bar, which
    // there is the whole question: the strip is a fixed width and a label
    // that does not fit it hides rather than overflowing
    // (Components/CellLabel.qml reads this, and CellRow.qml finds its cell
    // by it). The strip's own width, not this cell's: a cell's width is
    // what the children being measured decide, so reading it here would ask
    // a child how much room it has and answer with how much it took.
    readonly property real contentAcross: Math.max(0,
        Theme.space.barCellWidth - Theme.space.controlPaddingY * 2)

    // How big the content wants to be. This used to be `contentBox`'s own
    // childrenRect, which closes a cycle, since content is anchored to fill
    // the cell: childrenRect measures a fill-anchored child (a backdrop, an
    // overlay) at exactly the width of the cell the measurement is sizing,
    // and it measures each child's x/y, so a centered child's offset (half
    // the leftover room) lands back in the size that leftover room came
    // from. QML answers a looping binding by aborting it, which leaves the
    // cell at whatever size it had reached: never smaller than the widest
    // transient it ever saw, and on a first-pass abort, nothing at all.
    //
    // So measure each child's own extent and drop the two terms that feed
    // back. Nothing else changes: a child's position never described how
    // much room the content needs, and a child anchored to fill the cell
    // takes its size from the cell, so it can't be what determines it.
    //
    // `downward` picks the axis, one function, since the two differ by
    // nothing but the property pair.
    function _measure(downward) {
        var max = 0;
        for (var i = 0; i < contentBox.children.length; i++) {
            var child = contentBox.children[i];
            if (child.anchors.fill === contentBox)
                continue;
            var extent = downward ? child.height : child.width;
            if (extent > max)
                max = extent;
        }
        return max;
    }

    function _openTooltip() {
        if (!root.hovered || root.tooltipText === "")
            return;
        TooltipRegistry.show(root, root.tooltipText, root.barEdge);
    }

    onHoveredChanged: {
        if (root.hovered)
            root._openTooltip();
        else
            TooltipRegistry.hide(root);
    }

    // Live while shown: a cell's value moves under a parked pointer (volume
    // ticking, a battery estimate settling), and the card is meant to read
    // as the cell's own state, not a snapshot of when the pointer arrived.
    // A show for the cell that already owns the card updates the line
    // without touching the delay, which also covers the one case a text
    // change IS an open, where the cell had nothing to say when the pointer
    // arrived and now does. A cell that runs out of anything to say drops
    // the card instead.
    onTooltipTextChanged: {
        if (root.tooltipText === "")
            TooltipRegistry.hide(root);
        else
            root._openTooltip();
    }

    // Whether something above this cell draws the cursor halo for its whole
    // list instead (Panel.qml, M53 D4): one halo that travels between rows
    // needs there to be one of it. cursor.js carries the walk and why it
    // runs when the row takes the cursor rather than when it is built.
    property bool _haloOwned: false

    // Whether the ring draws for this cell at all (DESIGN.md §1 "Ring"): the
    // list above it hands the ring to the keyboard and the wash to the
    // pointer, and a cell with no such list above it draws both. cursor.js
    // carries the walk, resolved on the same hop `_haloOwned` is.
    property Item _ringOwner: null
    readonly property bool _cursorRing: root.cursor
        && (!root._ringOwner || root._ringOwner.cursorFromKeys)

    onCursorChanged: if (root.cursor) {
        root._haloOwned = Cursor.haloOwned(root);
        root._ringOwner = Cursor.ringOwner(root);
    }

    // The same walk for the selection fill: a group drawing one fill that
    // travels between its cells (RegionPicker's toolbar) needs there to be
    // one of it, so a cell under such a group keeps its selected ink and
    // leaves the fill to the group.
    property bool _selectionOwned: false

    function _resolveSelectionOwner() {
        root._selectionOwned = Cursor.ownedAbove(root, "ownsSelectionFill");
    }

    // A tick late, unlike the halo's walk: a toolbar's first selection is
    // set while its cell is still being created, and a Repeater parents a
    // delegate only after it completes, so the chain to walk is not there yet
    // at the moment `selected` first turns true.
    onSelectedChanged: if (root.selected) Qt.callLater(root._resolveSelectionOwner);

    // The open-panel mark (DESIGN.md §3 Bar), along the edge facing the
    // desktop: the bottom of a cell on a top bar, the top on a bottom bar,
    // the inner side on a vertical one. The end inset keeps the line's ends
    // clear of the cell's own rounded corners, which cut in at this height.
    Rectangle {
        id: panelMark
        // Drawn on its own clocks, not on `visible` (M53 D2): the panel it
        // stands for enters and leaves as a surface, so the mark grows out
        // of the cell's own centre along the bar and shrinks back into it
        // rather than being switched on under a card that is still on its
        // way in. Two terms, since the growth is geometry and the fade is
        // not (M54 D2): the scale takes `spatialFast` and carries the mark
        // a hair past full before it settles, the opacity takes `effects`
        // and never overshoots.
        property real _presence: root.panelOpen ? 1 : 0
        property real _fade: root.panelOpen ? 1 : 0
        visible: panelMark.opacity > 0 && root._ghostOpenState === ""
        opacity: panelMark._fade
        readonly property bool _sideways: root.vertical
        // Inside whatever border the cell actually draws, so the line sits
        // on the cell's own edge when there is none.
        readonly property real _edgeMargin: root._borderWidth
        width: panelMark._sideways ? Theme.borderWidth * 2 : root.width - Theme.space.xs * 2
        height: panelMark._sideways ? root.height - Theme.space.xs * 2 : Theme.borderWidth * 2
        x: root.barEdge === "right"
            ? panelMark._edgeMargin
            : root.barEdge === "left"
                ? root.width - panelMark.width - panelMark._edgeMargin
                : Theme.space.xs
        y: root.barEdge === "bottom"
            ? panelMark._edgeMargin
            : panelMark._sideways
                ? Theme.space.xs
                : root.height - panelMark.height - panelMark._edgeMargin
        radius: Theme.boxRadius(root._markBox, Math.min(panelMark.width, panelMark.height))
        color: root._markBox.fill

        Behavior on _presence {
            Anim { kind: "spatialFast" }
        }

        Behavior on _fade {
            Anim { kind: "effects" }
        }

        transform: Scale {
            origin.x: panelMark.width / 2
            origin.y: panelMark.height / 2
            xScale: panelMark._sideways ? 1 : panelMark._presence
            yScale: panelMark._sideways ? panelMark._presence : 1
        }
    }

    // The cell's own target. A sibling of `hitLayer` rather than its child,
    // so the `hit` alias assigns into an item this never shares: writing a
    // list property replaces what is already in it.
    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: root.interactive
        acceptedButtons: root.acceptedButtons
        cursorShape: root.acceptedButtons === Qt.NoButton ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: mouse => root.clicked(mouse)
        // Qt marks a wheel event accepted the moment anything is connected to
        // MouseArea.onWheel, so this handler existing at all swallowed every
        // notch that landed on a cell, before the flickable under it (the
        // launcher's grid, a panel's column) ever saw it. Only a consumer of
        // `wheeled` may put it back: the two that adjust something on scroll
        // (AudioWidget, NowPlaying) set it themselves.
        onWheel: wheel => {
            wheel.accepted = false;
            root.wheeled(wheel);
        }
        onPositionChanged: event => root.pointerMoved(event.x, event.y)
    }

    Item {
        id: hitLayer
        anchors.fill: parent
    }

    // The band's ink shadow, behind the content and never measured with it:
    // a sibling of `contentBox` rather than a child, so the padding the blur
    // needs never reaches `_measure`, and declared ahead of it so the crisp
    // glyphs the topmost effect draws land over every halo under them.
    InkGlow {
        x: contentBox.x
        y: contentBox.y
        width: contentBox.width
        height: contentBox.height
        source: contentBox
        shadows: root.barInkShadow
    }

    // The content box: the cell less `controlPaddingX` at both ends of the
    // content and `_insetAcross` either side of it. On a vertical bar the
    // two insets swap axes with the content, so the end padding runs down
    // the strip and the centring runs across it. Placed by x/y rather than
    // fill anchors, so the box is the measurement's own size on both axes
    // rather than the cell's on one of them.
    Item {
        id: contentBox
        width: root.width - (root.vertical ? root._insetAcross : Theme.space.controlPaddingX) * 2
        height: root.height - (root.vertical ? Theme.space.controlPaddingX : root._insetAcross) * 2
        x: (root.width - contentBox.width) / 2
        y: (root.height - contentBox.height) / 2

        // Drawn by the glow above while there is one: the effects render
        // this layer's texture back with their halos under it, so drawing it
        // here too would double it. `opacity` rather than `visible` (a layer
        // renders at opacity 1 and the item's own opacity applies to the
        // texture) because an interactive child in the content box keeps
        // answering the pointer either way.
        opacity: root.barInkShadow.length > 0 ? 0 : 1
        layer.enabled: root.barInkShadow.length > 0

        // Deliberately no implicit size of its own: root._measure() reads
        // the children directly, so nothing ever writes an implicit size
        // onto an item whose geometry those same children track.
    }
}
