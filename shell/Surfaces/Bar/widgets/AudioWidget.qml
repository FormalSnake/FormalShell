import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for AudioService's default sink (DESIGN.md §3 Bar, spec
// "Surfaces"): the volume icon and, opt-in, the percentage in mono. Click
// toggles the audio panel anchored under this cell, and the open-panel line
// runs along the cell's bottom edge while it is open.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Icon-only by default (M23): matches omarchy, which never labels this
    // cell either. The icon alone already distinguishes muted from a live
    // level, so the percentage the label used to show moves into
    // tooltipText below.
    readonly property bool _showLabel: Config.get("bar.widgets.audio.showLabel", false)

    // Muted keeps showing the pre-mute percentage (Osd.qml makes the same
    // call, it's still the level you'll get back), which leaves the mute
    // state resting entirely on one icon. This names it, and now that the
    // label defaults off, carries the percentage too so hiding it never
    // deletes information. The trailing segment states the M26 Task 9
    // right-click action, otherwise it's undiscoverable.
    tooltipText: (AudioService.muted ? "OUTPUT MUTED" : "OUTPUT VOLUME") + " / " + Math.round(AudioService.volume * 100) + "% / RIGHT MUTE"

    // The percent label resizes this cell as it ticks: glide the width
    // instead of shoving the bar's other widgets instantly (DESIGN.md §1
    // "Motion", M16 Task 2's contract, extended to every numeric bar cell
    // by M26 Task 7).
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easingInOut }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xs

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: AudioService.muted ? "volume-x" : "volume-2"
            color: root.foreground
        }

        Text {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(AudioService.volume * 100) + "%"
            color: root.foreground
            font.family: Theme.fontFamilyMono
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    // M26 Task 9: right click mutes the default sink, left opens the panel.
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            AudioService.toggleMute();
        } else if (root.panel) {
            root.panel.toggleFrom(root);
        }
    }
    // 5% steps, same as the panel's own tracks (M15 Task 4 parity):
    // scrolling the bar cell adjusts the default sink without opening the
    // panel at all.
    onWheeled: wheel => {
        AudioService.setVolume(AudioService.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05));
        wheel.accepted = true;
    }
}
