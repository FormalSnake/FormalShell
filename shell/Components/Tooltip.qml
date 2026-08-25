import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import "tooltip.js" as Placement

// The hover tooltip (DESIGN.md §2): a `popover` card at `radiusSm` with a
// 1px `border`, `Theme.space.md` off the item that owns it, carrying one
// caption line that names what that item is and what it currently reads. It
// enters with the same fade-plus-slide the panels and the OSD use rather
// than a transition of its own.
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

    readonly property var _place: root._screen
        ? Placement.placement(root._anchorRect,
            Qt.size(frame.width, frame.height),
            Qt.size(root._screen.width, root._screen.height),
            Theme.space.md, Theme.space.panelGap)
        : ({ x: 0, y: 0, above: false })

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
            root._anchorRect = Qt.rect(origin.x, origin.y,
                root.anchorItem.width, root.anchorItem.height);
            root.shown = true;
        }
    }

    screen: root._screen
    // Held mapped through the exit fade (DESIGN.md §1 "Motion"), same as
    // Panel.qml: the frame's opacity Behavior has to finish before the
    // surface unmaps.
    visible: root._visible || frame.opacity > 0
    color: "transparent"

    WlrLayershell.namespace: "formalshell:tooltip"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    mask: Region {}

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

        // Enter/exit (DESIGN.md §1 "Motion"): fade plus a slide toward the
        // anchor, so a card under its cell rises into place and a flipped
        // one drops into place. One animated scalar, so re-hovering mid-exit
        // reverses from wherever the fade is. motion.enabled=false zeroes
        // Theme.motion.standard (Theme/tokens.js's motionTokens), which
        // collapses both the fade and, since the translate is driven off
        // the same opacity, the slide to an instant swap, so this needs no
        // separate Theme.motionEnabled gate, same as Panel.qml/Osd.qml.
        opacity: root._visible ? 1 : 0
        transform: Translate {
            y: (1 - frame.opacity) * Theme.motion.slide * (root._place.above ? 1 : -1)
        }

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
        }

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
