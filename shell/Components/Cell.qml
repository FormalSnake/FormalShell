import QtQuick
import qs.Core

// The shadcn item (DESIGN.md §2): a `card` fill with a 1px `border` at
// `radiusMd`. Every bar cell, list row and chip on every surface is one of
// these, so the chrome lives in exactly one place.
Item {
    id: root

    default property alias data: content.data

    // --- Pointer (the lit area is the hit area) --------------------------
    //
    // The cell owns the one pointer target that spans it, so no surface
    // builds its own. A MouseArea in the default slot cannot do this job:
    // that slot forwards into `content`, which is inset by the control
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

    // Escape hatch for a target that deliberately covers less than the cell:
    // MenuActionBar's primary half is the only one, since its right half is a
    // legend rather than a button. A whole-cell target belongs on
    // `interactive` above, never here. Anchor to `parent` (this layer spans
    // the cell) and not to a content child.
    //
    // Declared ahead of `content` deliberately: an interactive child inside
    // the content box (a slider track, a nested Cell) is then stacked above
    // both this and `pointer`, and keeps its own events.
    property alias hit: hitLayer.data

    // The keyboard cursor: the ring, and nothing else. The only place the
    // wallpaper colour reaches chrome that is neither selected nor active,
    // which is what makes the cursor findable at a glance.
    property bool cursor: false

    // The concentric rule (spec "Radius"): a cell nested inside another
    // bordered surface takes the outer radius minus the padding between
    // them, floored at `radiusSm`. `radiusMd` is the free-standing case
    // (bar cell, panel row); the calendar's day grid sits one level deeper
    // and sets `radiusSm`.
    property int radius: Theme.radiusMd

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
    // and the open-panel mark. Bar.qml sets this on every cell it hosts.
    property bool ghost: false

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

    // The only border a ghost draws is one a state asked for.
    readonly property bool _borderless: root.ghost && !root.cursor
        && !root.destructive && !root.warning

    // A bar cell whose panel (or the launcher, or the notification center)
    // is open (DESIGN.md §3 Bar).
    property bool panelOpen: false

    // Hover paints below both fills (active > selected > hover).
    readonly property bool _hoverFillActive: root.hovered && !root.active && !root.selected

    // Hover tooltip: a short line naming what this cell is and what it
    // currently reads, shown after Tooltip.qml's own delay once the pointer
    // settles and dropped the instant it leaves. Empty (the default) means no
    // tooltip at all.
    //
    // ⚠️ The surface deliberately does not live in `content`: _measure()
    // below sizes the cell off EVERY direct child of `content` regardless of
    // visibility, so a tooltip drawn as a child item would widen (and
    // heighten) every cell it was attached to by its own card. Tooltip.qml
    // is a layer-shell window of its own instead, held by the Loader below,
    // which sits outside `content` and carries no size either way.
    property string tooltipText: ""

    // Inert since the tooltip stopped uppercasing anything; tray items still
    // set it.
    property bool tooltipVerbatim: false

    readonly property color foreground: root.active
        ? Theme.color.primaryForeground
        : root.destructive
            ? Theme.color.destructive
            : root.warning
                ? Theme.color.warning
                : root.selected
                    ? Theme.color.accentForeground
                    : Theme.color.foreground

    // Band-2 (meta) ink. A dim caption drawn onto a filled cell measures
    // under 1.1:1 contrast, so a fill promotes it to the same ink
    // `foreground` resolves for content. A destructive or warning cell is not
    // filled (its colour is on the border and the label), so its captions
    // stay dim.
    readonly property color dimForeground: (root.active || root.selected)
        ? foreground
        : Theme.color.mutedForeground

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

    // How big the content wants to be. This used to be `content`'s own
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
        for (var i = 0; i < content.children.length; i++) {
            var child = content.children[i];
            if (child.anchors.fill === content)
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
        tooltipLoader.active = true;
        tooltipLoader.item.anchorItem = root;
        tooltipLoader.item.barEdge = root.barEdge;
        tooltipLoader.item.verbatim = root.tooltipVerbatim;
        tooltipLoader.item.text = root.tooltipText;
        tooltipLoader.item.show();
    }

    onHoveredChanged: {
        if (root.hovered)
            root._openTooltip();
        else if (tooltipLoader.item)
            tooltipLoader.item.hide();
    }

    // Live while shown: a cell's value moves under a parked pointer (volume
    // ticking, a battery estimate settling), and the card is meant to read
    // as the cell's own state, not a snapshot of when the pointer arrived.
    // Never re-opens through _openTooltip() once the surface exists: that
    // would restart its show delay and blink the card on every tick. The
    // else branch covers the one case a text change IS an open, where the
    // cell had nothing to say when the pointer arrived and now does.
    onTooltipTextChanged: {
        if (tooltipLoader.item)
            tooltipLoader.item.text = root.tooltipText;
        else
            root._openTooltip();
    }

    // The focus ring's outer halo (shadcn's `ring-[3px] ring-ring/50`), drawn
    // as a larger rounded rectangle behind the body rather than a shader, so
    // only the band outside the body's own edge is ever visible.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.ringWidth
        visible: root.cursor
        radius: root.radius + Theme.ringWidth
        color: Theme.color.ring
        opacity: Theme.ringAlpha
    }

    // Fills snap; only the hover layer below fades.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.active
            ? Theme.color.primary
            : root.selected
                ? Theme.color.accent
                : root.ghost
                    ? "transparent"
                    : Theme.surface(Theme.color.card)
        border.width: root._borderless ? 0 : Theme.borderWidth
        border.color: root.cursor
            ? Theme.color.ring
            : root.destructive
                ? Theme.color.destructive
                : root.warning
                    ? Theme.color.warning
                    : Theme.color.border
    }

    // The pointer's own layer: a wash of the ink over whatever the cell
    // resolved to, never an opaque `accent` chip. A bar cell is a ghost over
    // a strip drawn at `surfaceOpacity`, so an opaque fill lands at a delta
    // the wallpaper decides and a bright one cancels it (Theme.hoverFill).
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.hoverFill
        opacity: root._hoverFillActive ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
    }

    // The open-panel mark (DESIGN.md §3 Bar), along the edge facing the
    // desktop: the bottom of a cell on a top bar, the top on a bottom bar,
    // the inner side on a vertical one. The end inset keeps the line's ends
    // clear of the cell's own rounded corners, which cut in at this height.
    Rectangle {
        id: panelMark
        visible: root.panelOpen
        readonly property bool _sideways: root.vertical
        readonly property real _edgeMargin: root._borderless ? 0 : Theme.borderWidth
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
        radius: Theme.radiusSm
        color: Theme.color.primary
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

    // The content box: the cell less `controlPaddingX` at both ends of the
    // content and `_insetAcross` either side of it. On a vertical bar the
    // two insets swap axes with the content, so the end padding runs down
    // the strip and the centring runs across it. Placed by x/y rather than
    // fill anchors, so the box is the measurement's own size on both axes
    // rather than the cell's on one of them.
    Item {
        id: content
        width: root.width - (root.vertical ? root._insetAcross : Theme.space.controlPaddingX) * 2
        height: root.height - (root.vertical ? Theme.space.controlPaddingX : root._insetAcross) * 2
        x: (root.width - content.width) / 2
        y: (root.height - content.height) / 2

        // Deliberately no implicit size of its own: root._measure() reads
        // the children directly, so nothing ever writes an implicit size
        // onto an item whose geometry those same children track.
    }

    // Loaded by URL rather than declared as a `Tooltip {}`: Tooltip.qml pulls
    // in Quickshell and Quickshell.Wayland, while Cell.qml is instantiated
    // head-on by tests/tst_cell_geometry.qml and tst_cell_states.qml under a
    // plain qmltestrunner that has no Quickshell module at all. A URL
    // resolves only when the Loader activates, which no test ever does.
    //
    // `active` starts false (Loader's own default is true) and is written
    // imperatively from onHoveredChanged above, never bound: that load has
    // to have completed by the next statement, which only a synchronous
    // activation guarantees. It then stays loaded, since unloading on pointer
    // exit would cut the exit fade short and re-pay the surface's creation on
    // every pass along the bar, while every cell in the shell loading one up
    // front would cost a layer-shell window per cell per output for cells
    // that may never be hovered at all.
    Loader {
        id: tooltipLoader
        active: false
        source: "Tooltip.qml"
    }
}
