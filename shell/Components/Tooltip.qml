import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Notifications

// The bar's hover tooltip (DESIGN.md §"Floating chrome (menu, panels,
// notifications, OSD, tooltips)", owner directive re-opening what the M16
// audit had filed under "deliberately NOT ported"): one omarchy card under
// the hovered cell carrying a single uppercase meta row that names what the
// cell is and what it currently reads.
//
// The audit's objection was to a generic floating rounded card with fade-in
// chrome of its own, so none of that is here: this is structurally Osd.qml's
// card — the frame draws the top and left rule, the one Cell inside draws
// its own bottom and right per Cell.qml's shared-rule contract — on the same
// tokens as every other surface (radius 0, borderWidth 2 in `rule`, no blur,
// no shadow, `background` fill), entering with the §4 fade-plus-slide the
// panels and the OSD already use rather than a transition of its own.
//
// Its own layer surface rather than an item inside the bar: the bar's
// PanelWindow is exactly one cell tall and carries an exclusive zone, so
// nothing drawn below the bar can live in it (Panel.qml's header makes the
// same point for popouts). Cell.qml loads one of these per cell, lazily, and
// drives it through show()/hide().
//
// Never takes input, on either axis. Keyboard: WlrKeyboardFocus.None, so it
// can never steal focus the way a primed panel deliberately does. Pointer:
// an empty `mask` — a Region with no item and no x/y/width/height builds an
// empty QRegion (src/core/region.cpp's PendingRegion::empty), which
// quickshell turns into an empty wayland input region plus
// Qt::WindowTransparentForInput (src/window/proxywindow.cpp's
// `setFlag(Qt::WindowTransparentForInput, mMask != nullptr &&
// mask.isEmpty())`), so clicks and hovers pass straight through this
// full-screen surface to the bar and the desktop underneath it.
PanelWindow {
    id: root

    // The cell this describes. Wayland hands clients no cross-window
    // geometry, so both the output and the anchor x resolve through the
    // anchor item's own window (`QsWindow.window`, the idiom omarchy's
    // popout cards use for exactly this) rather than being passed in as
    // screen coordinates by a caller that cannot know them.
    property Item anchorItem: null
    property string text: ""
    property bool shown: false

    // Set for text this shell did not author (a tray item's own title), which
    // is rendered exactly as its process published it. See the label below.
    property bool verbatim: false

    // A tray item's title is arbitrary text from another process, so the row
    // caps and elides rather than growing a card wider than the bar. Scales
    // with the type-scale root (DESIGN.md §1.3) like every other measured
    // width in the shell.
    readonly property real _maxTextWidth: 360 * Theme.fontScale

    // Suppressed while any popout is open: a panel anchors at exactly this y
    // under exactly this cell (Panel.qml's `_frameX`, `barHeight +
    // panelGap`), so the tooltip for the cell you just clicked would
    // otherwise land on top of the panel that click opened.
    //
    // The notification center needs its own term rather than riding on
    // PanelRegistry: it is a Top-layer card anchored top-right under the bar —
    // the same place a tooltip for any right-region cell lands — but it is not
    // a Panel and never registers. It also does not cover the bar, so every
    // right-region cell stays hoverable while it is up.
    readonly property bool _visible: root.shown && root.text !== ""
        && PanelRegistry.current === null && !NotificationService.centerOpen

    // omarchy's own tooltip delay, read as a reference
    // (omarchy/shell/Ui/PanelToolTip.qml's `delay: 400`). Deliberately not
    // motion — a card that appeared the instant the pointer crossed a cell
    // would flash on every pass along the bar — so it holds with
    // `motion.enabled: false` too; the fade below is what that setting
    // collapses. Nothing delays the way out: hide() is immediate.
    readonly property int _delay: 400

    // Captured when the delay elapses, not bound: mapToItem is not reactive
    // (quickshell documents that of the whole map* family), and the pointer
    // is parked on the cell for as long as this is up anyway.
    property real _anchorCenterX: -1

    readonly property var _screen: (root.anchorItem && root.anchorItem.QsWindow.window)
        ? root.anchorItem.QsWindow.window.screen
        : null

    readonly property real _frameX: {
        if (!root._screen)
            return 0;
        // Centered under the cell, then held inside the same panelGap margin
        // from the screen edges every other floating surface keeps — a cell
        // at either end of the bar would otherwise push the card off-output.
        var edge = Theme.space.panelGap;
        var maxX = Math.max(edge, root._screen.width - frame.width - edge);
        return Math.max(edge, Math.min(root._anchorCenterX - frame.width / 2, maxX));
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
            root._anchorCenterX = root.anchorItem.mapToItem(null, root.anchorItem.width / 2, 0).x;
            root.shown = true;
        }
    }

    screen: root._screen
    // Held mapped through the exit fade (DESIGN.md §4), same as Panel.qml:
    // the frame's opacity Behavior has to finish before the surface unmaps.
    visible: root._visible || frame.opacity > 0
    color: "transparent"

    WlrLayershell.namespace: "formalshell:tooltip"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    mask: Region {}

    Item {
        id: frame
        x: root._frameX
        y: Theme.barHeight + Theme.space.panelGap
        implicitWidth: labelCell.implicitWidth + Theme.borderWidth
        implicitHeight: labelCell.implicitHeight + Theme.borderWidth
        width: implicitWidth
        height: implicitHeight

        // Enter/exit (DESIGN.md §4): fade plus a slide down from under the
        // bar, one animated scalar so re-hovering mid-exit reverses from
        // wherever the fade is. motion.enabled=false zeroes
        // Theme.motion.standard (Theme/tokens.js's motionTokens), which
        // collapses both the fade and — since the translate is driven off
        // the same opacity — the slide to an instant swap, so this needs no
        // separate Theme.motionEnabled gate, same as Panel.qml/Osd.qml.
        opacity: root._visible ? 1 : 0
        transform: Translate { y: (frame.opacity - 1) * Theme.motion.slide }

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
        }

        // The window is transparent (it spans the output so the frame can be
        // placed anywhere under the bar), so the card paints its own surface
        // — Cell.qml's background only opaques on selected/accent/hovered.
        Rectangle {
            anchors.fill: parent
            color: Theme.color.background
        }

        // Outer top/left rule only: the Cell below draws its own bottom and
        // right, per its shared-rule contract, so the card closes on all
        // four edges with a single line each.
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.borderWidth
            color: Theme.color.border
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Theme.borderWidth
            color: Theme.color.border
        }

        Cell {
            id: labelCell
            x: Theme.borderWidth
            y: Theme.borderWidth

            MetaLabel {
                // Bound to its own implicit width so the card hugs short
                // text and only the overlong outliers elide; MetaLabel is a
                // Text, whose implicitWidth stays the unelided metric
                // regardless of the width assigned here.
                width: Math.min(implicitWidth, root._maxTextWidth)
                elide: Text.ElideRight
                color: labelCell.foreground
                text: root.text
                // DESIGN.md §2.3's uppercase meta convention covers labels
                // that NAME what a piece of content is. A tray item's title is
                // another process's own string — it is the content — so
                // uppercasing it would rewrite data that isn't ours to rewrite
                // ("OBS: 1080p60" -> "OBS: 1080P60"). The width cap still
                // applies: a card cannot grow past the bar, and an elide is
                // visibly a truncation rather than a silent edit.
                font.capitalization: root.verbatim ? Font.MixedCase : Font.AllUppercase
            }
        }
    }
}
