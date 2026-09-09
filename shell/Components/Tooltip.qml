import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import "tooltip.js" as Placement

// The hover tooltip (DESIGN.md §2): a `popover` card at `radiusSm` with a
// 1px `border`, `Theme.space.md` off the item that owns it, carrying one
// caption line that names what that item is and what it currently reads. It
// enters through the same Presence recipe the panels and the OSD use,
// zoomed from the side facing its anchor rather than a transition of its
// own.
//
// Its own layer surface rather than an item inside the anchor's window: the
// bar's PanelWindow is exactly one cell tall and carries an exclusive zone,
// so nothing drawn below the bar can live in it (Panel.qml's header makes
// the same point for popouts).
//
// One of these per output (M53 D10), built by shell.qml's own Variants and
// registered with TooltipRegistry, which is how a cell finds the card for
// its screen. TooltipGroup.qml holds the delay, the grace window and which
// item currently owns the card; this draws it. A hand-off inside the grace
// window is one card travelling: the rect Behaviors below carry it to the
// next item while the two text slots crossfade under it, so walking the bar
// is one shape moving rather than a card per cell.
//
// Never takes input, on either axis. Keyboard: WlrKeyboardFocus.None, so it
// can never steal focus the way a primed panel deliberately does. Pointer:
// an empty `mask`. A Region with no item and no x/y/width/height builds an
// empty QRegion (src/core/region.cpp's PendingRegion::empty), which
// quickshell turns into an empty wayland input region plus
// Qt::WindowTransparentForInput (src/window/proxywindow.cpp's
// `setFlag(Qt::WindowTransparentForInput, mMask != nullptr &&
// mask.isEmpty())`), so clicks and hovers pass straight through this
// full-screen surface to the bar and the desktop underneath it.
PanelWindow {
    id: root

    required property var modelData

    // Whether this is the surface that answers for `item`. Wayland hands
    // clients no cross-window geometry, so an item's output resolves
    // through its own window (`QsWindow.window`, the idiom omarchy's popout
    // cards use for exactly this) rather than being passed in by a caller
    // that cannot know it.
    function accepts(item) {
        var window = item && item.QsWindow ? item.QsWindow.window : null;
        return !!window && window.screen === root.screen;
    }

    function show(item, text, barEdge) {
        group.show(item, text, barEdge);
    }

    function hide(item) {
        group.hide(item);
    }

    // A tray item's title is arbitrary text from another process, so the row
    // caps and elides rather than growing a card wider than the bar. Scales
    // with the type-scale root (DESIGN.md §1) like every other measured
    // width in the shell.
    readonly property real _maxTextWidth: 360 * Theme.fontScale

    readonly property bool _visible: group.shown && group.text !== ""

    // Captured on the group's commit, not bound: mapToItem is not reactive
    // (quickshell documents that of the whole map* family), and the pointer
    // is parked on the item for as long as this is up anyway.
    property rect _anchorRect: Qt.rect(0, 0, 0, 0)

    readonly property real _screenPadding: Theme.space.screenPadding

    // Placed against the card's implicit size rather than its drawn one:
    // while a hand-off morphs the width, the drawn size is still on its way
    // there, and a target that moved every frame under the x Behavior would
    // have the card chasing its own resize.
    readonly property var _place: root.screen
        ? Placement.placement(root._anchorRect,
            Qt.size(frame.implicitWidth, frame.implicitHeight),
            Qt.size(root.screen.width, root.screen.height),
            Theme.space.md, root._screenPadding,
            Placement.sideForBarEdge(group.barEdge))
        : ({ x: 0, y: 0, side: "below", slideX: 0, slideY: -1 })

    // Two text slots rather than one (M53 D3, the content rule), the same
    // pattern Icon.qml carries for a glyph: the card that travels between
    // two items has to change what it says on the way, and a line that cut
    // under a moving card is the one part of the hand-off that would read as
    // two cards after all. `_cross` drives both opacities, so a line that
    // changes again mid-fade retargets the same animation instead of
    // restarting it, and slot B stays unbuilt until the first swap.
    property real _cross: root._frontIsA ? 1 : 0
    property bool _frontIsA: true
    property bool _armed: false
    property string _textA: ""
    property string _textB: ""

    Behavior on _cross {
        Anim { kind: "effects" }
    }

    function _install(animate) {
        var text = group.text;
        // Nothing on screen to cross from: the front slot takes the line and
        // Presence's own fade brings the whole card in with it.
        if (!animate) {
            if (root._frontIsA)
                root._textA = text;
            else
                root._textB = text;
            return;
        }
        if (text === (root._frontIsA ? root._textA : root._textB))
            return;
        if (root._frontIsA)
            root._textB = text;
        else
            root._textA = text;
        root._armed = true;
        root._frontIsA = !root._frontIsA;
    }

    // The card's own edge facing the anchor item, Presence's zoom origin:
    // a card below its anchor grows from its top, one above grows from its
    // bottom, and so on around the other two sides.
    readonly property string _presenceEdge: {
        switch (root._place.side) {
        case "below": return "top";
        case "above": return "bottom";
        case "right": return "left";
        case "left": return "right";
        }
        return "center";
    }

    // The item's rect in its own output's space, which is this surface's
    // too (tooltip.js): every window that owns a tooltip-bearing item either
    // spans its output or hugs one of its edges, so where that window sits
    // follows from its anchors alone.
    function _measure() {
        var item = group.anchorItem;
        if (!item || !item.QsWindow.window)
            return;
        var origin = item.mapToItem(null, 0, 0);
        var window = item.QsWindow.window;
        var offset = Placement.windowOrigin(window.anchors,
            Qt.size(window.width, window.height),
            Qt.size(root.screen.width, root.screen.height));
        root._anchorRect = Qt.rect(origin.x + offset.x, origin.y + offset.y,
            item.width, item.height);
    }

    Component.onCompleted: TooltipRegistry.addHost(root)
    Component.onDestruction: TooltipRegistry.removeHost(root)

    TooltipGroup {
        id: group
        drawn: presence.shown
        onCommit: root._measure()
        // Covers both the commit's own line and a value ticking under a
        // parked pointer. A card that is not on screen yet installs its line
        // outright rather than crossfading out of an empty slot.
        onTextChanged: root._install(presence.shown)
    }

    screen: root.modelData
    // Held mapped through the exit fade (DESIGN.md §1 "Motion"), same as
    // Panel.qml: presence's own Behavior has to settle before the surface
    // unmaps.
    visible: presence.shown
    color: "transparent"

    WlrLayershell.namespace: "formalshell:tooltip"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    mask: Region {}

    Presence {
        id: presence
        open: root._visible
        edge: root._presenceEdge
    }

    Rectangle {
        id: frame
        x: root._place.x
        y: root._place.y
        // Only a card changing hands travels (M53 D10): one arriving at a
        // new item takes its rect in the frame it appears in, so nothing
        // ever glides in from where the last card stood. `spatialFast`, not
        // the default: this is a caption hopping between two neighbouring
        // buttons, a few tens of pixels, and the default clock spends that
        // distance in a drift.
        Behavior on x {
            enabled: group.travel
            Anim { kind: "spatialFast" }
        }
        Behavior on y {
            enabled: group.travel
            Anim { kind: "spatialFast" }
        }
        implicitWidth: (root._frontIsA ? slotA.width : slotB.width) + Theme.space.controlPaddingX * 2
        implicitHeight: (root._frontIsA ? slotA.implicitHeight : slotB.implicitHeight)
            + Theme.space.controlPaddingY * 2
        width: frame.implicitWidth
        Behavior on width {
            enabled: group.travel
            Anim { kind: "spatialFast" }
        }
        // No Behavior: every card is one elided caption line, so the height
        // only ever changes with the type scale.
        height: frame.implicitHeight
        radius: Theme.radiusSm
        color: Theme.surface(Theme.color.popover)
        border.width: Theme.borderWidth
        border.color: Theme.color.border

        // Enter/exit lives in Presence (DESIGN.md §1 "Motion", M51 D2/D4):
        // fade plus a zoom from the side facing the anchor item, no slide
        // travel, the card is small enough that the zoom alone carries it.
        opacity: presence.opacity
        scale: presence.scale
        transformOrigin: presence.transformOrigin

        // Each slot is bound to its own implicit width so the card hugs
        // short text and only the overlong outliers elide; implicitWidth
        // stays the unelided metric regardless of the width assigned here.
        Text {
            id: slotA
            anchors.centerIn: parent
            width: Math.min(implicitWidth, root._maxTextWidth)
            elide: Text.ElideRight
            text: root._textA
            opacity: root._cross
            color: Theme.color.popoverForeground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.caption
        }

        Text {
            id: slotB
            visible: root._armed
            anchors.centerIn: parent
            width: Math.min(implicitWidth, root._maxTextWidth)
            elide: Text.ElideRight
            text: root._textB
            opacity: 1 - root._cross
            color: Theme.color.popoverForeground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.caption
        }
    }
}
