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

    implicitWidth: root._measure(false) + Theme.space.controlPaddingX * 2
    implicitHeight: root._measure(true) + Theme.space.controlPaddingY * 2

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
    // `vertical` picks the axis, one function, since the two differ by
    // nothing but the property pair.
    function _measure(vertical) {
        var max = 0;
        for (var i = 0; i < content.children.length; i++) {
            var child = content.children[i];
            if (child.anchors.fill === content)
                continue;
            var extent = vertical ? child.height : child.width;
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

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.color.accent
        opacity: root._hoverFillActive ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
    }

    // The open-panel mark (DESIGN.md §3 Bar). The side inset keeps the
    // line's ends clear of the cell's own rounded corners, which cut in at
    // this height.
    Rectangle {
        visible: root.panelOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.space.xs
        anchors.rightMargin: Theme.space.xs
        anchors.bottomMargin: root._borderless ? 0 : Theme.borderWidth
        height: Theme.borderWidth * 2
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

    Item {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Theme.space.controlPaddingX
        anchors.topMargin: Theme.space.controlPaddingY
        anchors.rightMargin: Theme.space.controlPaddingX
        anchors.bottomMargin: Theme.space.controlPaddingY

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
