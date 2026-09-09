import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Services
import "icon.js" as OsdIcon

// Bottom-centred volume/brightness/media pill (DESIGN.md §3 "OSD", spec
// "OSD"): a `Card` holding one `Icon`, a `Track` and the percentage, no
// keyboard focus, auto-hiding `_hideDelay` after the last trigger.
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
    // Held visible through the exit fade (DESIGN.md §1 "Motion"): the timer
    // clears `kind`, presence's own Behavior runs its progress to 0, then
    // the window unmaps. No input concerns: this surface never takes any.
    visible: presence.shown
    color: "transparent"

    WlrLayershell.namespace: "formalshell:osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // A drawer out of the bottom edge (Presence.qml, DESIGN.md §1 Motion,
    // M53 addendum). This window is exactly the card, one `screenPadding`
    // off the bottom of the output, so the window's own bounds are the slit:
    // a pill displaced its own height downward is outside them and draws
    // nothing, and no clipping item of its own is needed.
    Presence {
        id: presence
        open: root.kind !== ""
        edge: "bottom"
        mapped: root.backingWindowVisible
        mode: "emerge"
        extent: frameHost.height
    }

    // The pill squashes into the edge it rises out of and springs back
    // (M54 D7), harder than a panel does: it is small, it travels its whole
    // height, and 0.25 is what caelestia gives an OSD. Sampled off the item
    // carrying its place rather than off the card the matrix goes on, which
    // would read its own transform back through `mapToItem`.
    Deform {
        id: deform
        target: frameHost
        edge: "bottom"
        amount: 0.25
        active: !presence.settled
    }

    readonly property real _screenPadding: Theme.space.screenPadding

    anchors.bottom: true
    margins.bottom: root._screenPadding

    implicitWidth: frameHost.width
    implicitHeight: frameHost.height

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

    // Where the pill is, and nothing drawn: the deform's matrix goes on the
    // card inside this, so the sampled item and the transformed one are never
    // the same.
    //
    // Enter/exit lives in Presence (DESIGN.md §1 "Motion", M53 addendum): the
    // pill rises out of the bottom edge and retreats behind it, with no fade
    // and no zoom, on one shared clock so a retrigger mid-exit reverses in
    // place. Kind-to-kind swaps while already showing (volume -> brightness)
    // stay instant: `open` never leaves true.
    //
    // A `Card` rather than the joined shape a panel takes (M54 D6): the
    // window sits one `screenPadding` off the bottom of the output, so this
    // pill meets no line and has nothing for a fillet to run out to.
    Item {
        id: frameHost
        width: frame.implicitWidth
        height: frame.implicitHeight
        opacity: presence.opacity
        transform: Translate { y: presence.emergeY }

        Card {
            id: frame
            // Opaque, unlike the panels and the bar: the OSD is not one of the
            // three surfaces Hyprland blurs behind (spec "Depth").
            color: Theme.color.card
            width: frameHost.width
            height: frameHost.height
            transform: Matrix4x4 { matrix: deform.matrix }

            Item {
                id: row
                // The pill lands before its readout does (Presence's own
                // `contentOpacity`).
                opacity: presence.contentOpacity
                width: Theme.space.popupWidthNarrow - frame.padding * 2
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
}
