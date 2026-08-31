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
// the same point for popouts). Cell.qml and Button.qml load one of these
// per item, lazily, and drive it through show()/hide().
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

    // The item this describes. Wayland hands clients no cross-window
    // geometry, so both the output and the anchor rect resolve through the
    // anchor item's own window (`QsWindow.window`, the idiom omarchy's
    // popout cards use for exactly this) rather than being passed in as
    // screen coordinates by a caller that cannot know them.
    property Item anchorItem: null
    property string text: ""
    property bool shown: false

    // Inert: nothing here uppercases any more, so a foreign process's own
    // string (a tray item's title) already renders as published. Cell.qml
    // still hands it over.
    property bool verbatim: false

    // The bar edge the anchor's cell sits on (Cell.barEdge), empty off the
    // bar: the card opens away from that edge, over the desktop.
    property string barEdge: ""

    // A tray item's title is arbitrary text from another process, so the row
    // caps and elides rather than growing a card wider than the bar. Scales
    // with the type-scale root (DESIGN.md §1) like every other measured
    // width in the shell.
    readonly property real _maxTextWidth: 360 * Theme.fontScale

    readonly property bool _visible: root.shown && root.text !== ""

    // omarchy's own tooltip delay, read as a reference
    // (omarchy/shell/Ui/PanelToolTip.qml's `delay: 400`). Deliberately not
    // motion (a card that appeared the instant the pointer crossed a cell
    // would flash on every pass along the bar) so it holds with
    // `motion.enabled: false` too; the fade below is what that setting
    // collapses. Nothing delays the way out: hide() is immediate.
    readonly property int _delay: 400

    // Captured when the delay elapses, not bound: mapToItem is not reactive
    // (quickshell documents that of the whole map* family), and the pointer
    // is parked on the item for as long as this is up anyway.
    property rect _anchorRect: Qt.rect(0, 0, 0, 0)

    readonly property var _screen: (root.anchorItem && root.anchorItem.QsWindow.window)
        ? root.anchorItem.QsWindow.window.screen
        : null

    readonly property real _screenPadding: Theme.space.screenPadding

    readonly property var _place: root._screen
        ? Placement.placement(root._anchorRect,
            Qt.size(frame.width, frame.height),
            Qt.size(root._screen.width, root._screen.height),
            Theme.space.md, root._screenPadding,
            Placement.sideForBarEdge(root.barEdge))
        : ({ x: 0, y: 0, side: "below", slideX: 0, slideY: -1 })

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

    function show() {
        delayTimer.restart();
    }

    function hide() {
        delayTimer.stop();
        root.shown = false;
    }

    Timer {
        id: delayTimer
        interval: root._delay
        onTriggered: {
            if (!root.anchorItem)
                return;
            var origin = root.anchorItem.mapToItem(null, 0, 0);
            var window = root.anchorItem.QsWindow.window;
            var offset = Placement.windowOrigin(window.anchors,
                Qt.size(window.width, window.height),
                Qt.size(root._screen.width, root._screen.height));
            root._anchorRect = Qt.rect(origin.x + offset.x, origin.y + offset.y,
                root.anchorItem.width, root.anchorItem.height);
            root.shown = true;
        }
    }

    screen: root._screen
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
        implicitWidth: label.width + Theme.space.controlPaddingX * 2
        implicitHeight: label.implicitHeight + Theme.space.controlPaddingY * 2
        width: implicitWidth
        height: implicitHeight
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

        Text {
            id: label
            anchors.centerIn: parent
            // Bound to its own implicit width so the card hugs short text and
            // only the overlong outliers elide; implicitWidth stays the
            // unelided metric regardless of the width assigned here.
            width: Math.min(implicitWidth, root._maxTextWidth)
            elide: Text.ElideRight
            text: root.text
            color: Theme.color.popoverForeground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.caption
        }
    }
}
