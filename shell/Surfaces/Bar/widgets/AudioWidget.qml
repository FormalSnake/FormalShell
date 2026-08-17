import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for AudioService's default sink (DESIGN.md §Bar, spec §1, M6
// Task 1): volume glyph + percentage, click toggles the audio panel
// anchored under this cell. The panel-open accent dot (Omarchy detail,
// spec §1) sits in the cell's corner while the panel is open — a flat
// square, not a glyph, per DESIGN's "accent is a block, not a tint" rule.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Icon-only by default (M23): matches omarchy, which never labels this
    // cell either. The glyph alone already distinguishes muted from a live
    // level, so the percentage the label used to show moves into
    // tooltipText below.
    readonly property bool _showLabel: Config.get("bar.widgets.audio.showLabel", false)

    standalone: true

    // Muted keeps showing the pre-mute percentage (Osd.qml makes the same
    // call, it's still the level you'll get back), which leaves the mute
    // state resting entirely on one glyph. This names it, and now that the
    // label defaults off, carries the percentage too so hiding it never
    // deletes information.
    tooltipText: (AudioService.muted ? "OUTPUT MUTED" : "OUTPUT VOLUME") + " / " + Math.round(AudioService.volume * 100) + "%"

    // Mute swaps the glyph and the percent label resizes this cell — glide
    // the width instead of shoving the bar's other widgets instantly
    // (DESIGN.md §4, M16 Task 2's contract, extended to every numeric bar
    // cell by M26 Task 7).
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        // Fixed-width slot (M26 Task 7): the mute glyph swap alone would
        // shift the label next to it, since a Nerd Font glyph's own advance
        // width varies by codepoint.
        Item {
            id: glyphSlot
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.space.huge
            height: glyphText.implicitHeight

            Text {
                id: glyphText
                anchors.centerIn: parent
                text: AudioService.muted ? "󰝟" : "󰕾"
                color: root.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }

        Text {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(AudioService.volume * 100) + "%"
            color: root.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }
    }

    PanelOpenDot {
        visible: root._panelOpen
        inverted: root.invertedNow
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
    }

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggleFrom(root);
    }
    // 5% steps, same as the panel's own tracks (M15 Task 4 parity) —
    // scrolling the bar cell adjusts the default sink without opening
    // the panel at all.
    onWheeled: wheel => {
        AudioService.setVolume(AudioService.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05));
        wheel.accepted = true;
    }
}
