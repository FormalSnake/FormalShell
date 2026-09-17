import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Services
import "icon.js" as OsdIcon

// Bottom-centred volume/brightness/media pill (DESIGN.md §3 "OSD", spec
// "OSD"): one `Icon`, a `Track` and the percentage in a `Drawer` out of the
// bottom edge, no keyboard focus, no pointer input at all, auto-hiding
// `_hideDelay` after the last trigger.
//
// The card is exactly `popupWidthNarrow` wide whatever it is showing, and
// the readout column is measured off "100%" rather than the live value, so
// volume ticking 3% -> 97% or a long media title swapping in never reflows
// it (plan-wide no-jitter contract).
//
// One instance, opened on the focused screen at trigger time (same
// reasoning as Menu/Center: summoned, not per-output).
PanelWindow {
    id: root

    readonly property int _hideDelay: 1600

    property string kind: ""          // "" | "volume" | "brightness" | "media"
    property string mediaText: ""

    function showVolume() {
        root.kind = "volume";
        hideTimer.restart();
    }

    function showBrightness() {
        root.kind = "brightness";
        hideTimer.restart();
    }

    function showMedia(text) {
        root.mediaText = text;
        root.kind = "media";
        hideTimer.restart();
    }

    function close() {
        hideTimer.stop();
        root.kind = "";
    }

    Timer {
        id: hideTimer
        interval: root._hideDelay
        onTriggered: root.kind = ""
    }

    // AudioService fires this on ANY volume/mute change, ours or external
    // (wpctl, pavucontrol, hardware keys routed through it) is the only
    // trigger wired automatically. Brightness/media only ever show via
    // OsdIpc: BrightnessService has no polling loop to hook a signal off
    // (see its own header), and media has no such signal either.
    Connections {
        target: AudioService
        function onChanged() { root.showVolume(); }
    }

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    // Muted keeps showing the pre-mute number (still informative) but drops
    // the fill to 0: the track is the "how much will I actually hear"
    // signal.
    readonly property bool _hasValue: root.kind === "volume" || root.kind === "brightness"
    readonly property real _fraction: root.kind === "brightness"
        ? BrightnessService.percent / 100
        : (AudioService.muted ? 0 : AudioService.volume)
    readonly property int _percent: root.kind === "brightness"
        ? Math.round(BrightnessService.percent)
        : Math.round(AudioService.volume * 100)

    screen: root._screen
    // Held visible through the exit (DESIGN.md §1 "Motion"): the timer clears
    // `kind`, the drawer's presence runs its travel back behind the line,
    // then the window unmaps. No input concerns: this surface never takes
    // any.
    visible: drawer.presence.shown
    color: "transparent"
    // An empty Region resolves to an empty QRegion, which QsWindow.mask turns
    // into WindowTransparentForInput (Tooltip.qml's own precedent): the pill
    // reports what a key just did and is never something to click, and the
    // band it now sits in covers a stretch of desktop the pointer has to keep
    // reaching.
    mask: Region {}

    WlrLayershell.namespace: "formalshell:osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property real _screenWidth: root._screen ? root._screen.width : 0
    readonly property real _screenHeight: root._screen ? root._screen.height : 0

    // The pill's own rect: `popupWidthNarrow` wide, its content tall, centred
    // on the output and one `screenPadding` off whatever the bottom edge
    // carries, which is the bar's strip on a bottom bar, the frame ring's
    // band with a frame, and nothing at all on a bare edge (DESIGN.md §1:
    // toasts, the OSD pill, the centre and the tooltip all take those same
    // numbers).
    readonly property real _cardWidth: Theme.space.popupWidthNarrow
    readonly property real _cardHeight: row.height + Theme.space.panelPadding * 2
    readonly property real _rest: Theme.edgeInset.bottom + Theme.space.screenPadding

    // The window is a band along that edge rather than the whole output: it
    // has to reach the line the pill buds off and cover the silhouette, which
    // is the pill, the room it rests off the line and a fillet either side
    // along it, and nothing above that. The pill's own height again on top is
    // room for the travel's overshoot and the deform's stretch, both of which
    // are a fraction of it.
    readonly property real _bandHeight: Math.min(root._screenHeight,
        root._rest + root._cardHeight * 2)

    anchors { left: true; right: true; bottom: true }
    implicitHeight: root._bandHeight

    // Off-screen calibration: the widest readout this card can ever show,
    // rendered at the live font so the column is real metrics rather than a
    // guessed constant.
    Item {
        visible: false

        Text {
            id: percentMetric
            text: "100%"
            font.family: Theme.fontFamilyMono
            font.pixelSize: Theme.fontSize.bodySmall
        }
    }

    // Everything from the bottom line to the pill's own padding is the
    // drawer's (Components/Drawer.qml, M57 D8): the pill buds off a bottom
    // bar's hairline or the frame ring's bottom line the way a panel buds off
    // the bar's, comes out on the same clock and is a plain card once it has
    // let go. A bare bottom edge has no line to join and the pill simply
    // comes out from behind the output.
    //
    // Kind-to-kind swaps while already showing (volume -> brightness) stay
    // instant: `open` never leaves true.
    Drawer {
        id: drawer
        anchors.fill: parent
        owner: root
        open: root.kind !== ""
        mapped: root.backingWindowVisible
        edge: "bottom"
        screen: root._screen
        origin: Qt.point(0, root._screenHeight - root._bandHeight)
        rect: Qt.rect(Math.round((root._screenWidth - root._cardWidth) / 2),
            root._screenHeight - root._rest - root._cardHeight,
            root._cardWidth, root._cardHeight)
        // Harder than a panel: the pill is small, it travels its whole
        // height, and 0.25 is what caelestia gives an OSD.
        deformAmount: 0.25

        Item {
            id: row
            // The pill lands before its readout does (Presence's own
            // `contentOpacity`).
            opacity: drawer.presence.contentOpacity
            width: parent.width
            height: Math.max(kindIcon.height, readout.implicitHeight, mediaLabel.implicitHeight,
                Theme.space.trackThickness)

            Icon {
                id: kindIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                name: OsdIcon.iconName(root.kind, AudioService.volume, AudioService.muted)
                size: Theme.fontSize.title
                color: Theme.color.foreground
            }

            Text {
                id: readout
                visible: root._hasValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: percentMetric.implicitWidth
                horizontalAlignment: Text.AlignRight
                text: root._percent + "%"
                color: Theme.color.foreground
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize.bodySmall
            }

            Track {
                visible: root._hasValue
                anchors.left: kindIcon.right
                anchors.leftMargin: Theme.space.iconGap
                anchors.right: readout.left
                anchors.rightMargin: Theme.space.iconGap
                anchors.verticalCenter: parent.verticalCenter
                value: root._fraction
            }

            // The media kind has no scalar to put in a track, so the title
            // takes the whole run of the pill instead and elides.
            Text {
                id: mediaLabel
                visible: root.kind === "media"
                anchors.left: kindIcon.right
                anchors.leftMargin: Theme.space.iconGap
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.mediaText
                color: Theme.color.foreground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.body
            }
        }
    }
}
