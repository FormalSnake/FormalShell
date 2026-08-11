import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../../Audio/model.js" as Audio

// Bar cell for the default capture source: one glyph, click toggles its
// mute. Opt-in via bar.layout, never part of layout.js's DEFAULT_LAYOUT.
// AudioWidget.qml is the structural template; the differences are
// deliberate. No percentage beside the glyph (input gain is a panel
// concern, and a mic reads as on or off) and no wheel handler for the same
// reason.
//
// Honest unavailable state: with no default source at all (real on the mac
// VM rig, which has no capture device) the cell renders one dim NO MIC
// label instead of a glyph, and stays visible. It is opt-in, so the user
// asked for it and hiding it would be the lie. `shown` is therefore not
// declared at all: Bar.qml's regionDelegate treats an absent `shown` as
// always-visible.
//
// Every branch here reads Audio.sourceState(), so the three states live in
// one tested function rather than in QML conditionals. Glyph codepoints
// from the pinned nerd-fonts-jetbrains-mono cmap (nix/testvm.nix), read out
// of the font's own format-12 subtable rather than memory: md-microphone
// U+F036C, md-microphone_off U+F036D.
Cell {
    id: root

    readonly property string _state: Audio.sourceState(AudioService.sourceAvailable, AudioService.sourceMuted)

    standalone: true
    hovered: hoverArea.containsMouse

    tooltipText: {
        switch (root._state) {
        case "muted": return "MIC MUTED";
        case "live": return "MIC LIVE";
        }
        return "NO INPUT DEVICE";
    }

    // A Row rather than two siblings dropped straight into the cell: Cell's
    // own _measure() sizes off every direct child regardless of visibility,
    // so the glyph state would otherwise stay as wide as the NO MIC label.
    // Row measures only its visible children.
    Row {
        anchors.verticalCenter: parent.verticalCenter

        Text {
            visible: root._state !== "unavailable"
            anchors.verticalCenter: parent.verticalCenter
            text: root._state === "muted" ? "󰍭" : "󰍬"
            color: root.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }

        MetaLabel {
            visible: root._state === "unavailable"
            anchors.verticalCenter: parent.verticalCenter
            text: "NO MIC"
            color: root.dimForeground
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: AudioService.toggleSourceMute()
    }
}
