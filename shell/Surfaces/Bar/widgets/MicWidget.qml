import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../../Audio/model.js" as Audio

// Bar cell for the default capture source: one icon, click toggles its
// mute, middle click opens the audio panel (M26 Task 9, the mic has no
// panel of its own, so this reaches AudioPanel like upstream's own
// Microphone row does). Opt-in via bar.layout, never part of layout.js's
// DEFAULT_LAYOUT. AudioWidget.qml is the structural template; the
// differences are deliberate. No percentage beside the icon (input gain is
// a panel concern, and a mic reads as on or off) and no wheel handler for
// the same reason. No right-click mute: left already mutes, and a second
// button doing the same thing is noise rather than a genuine secondary
// action (M26 Task 9's own "adjust with reasons" allowance, upstream's real
// table has no right-click here either, only left/middle).
//
// Honest unavailable state: with no default source at all (real on the mac
// VM rig, which has no capture device) the cell renders one dim NO MIC
// label instead of an icon, and stays visible. It is opt-in, so the user
// asked for it and hiding it would be the lie. `shown` is therefore not
// declared at all: Bar.qml's regionDelegate treats an absent `shown` as
// always-visible.
//
// Every branch here reads Audio.sourceState(), so the three states live in
// one tested function rather than in QML conditionals.
Cell {
    id: root

    property var panel: null

    readonly property string _state: Audio.sourceState(AudioService.sourceAvailable, AudioService.sourceMuted)

    // The trailing segment states the M26 Task 9 middle-click action,
    // otherwise it's undiscoverable.
    tooltipText: {
        var head;
        switch (root._state) {
        case "muted": head = "MIC MUTED"; break;
        case "live": head = "MIC LIVE"; break;
        default: head = "NO INPUT DEVICE";
        }
        return head + " / MIDDLE AUDIO PANEL";
    }

    // A CellRow rather than two siblings dropped straight into the cell:
    // Cell's own _measure() sizes off every direct child regardless of
    // visibility, so the icon state would otherwise stay as wide as the NO
    // MIC label. A positioner lays out only its visible children.
    CellRow {
        Icon {
            visible: root._state !== "unavailable"
            name: root._state === "muted" ? "mic-off" : "mic"
            color: root.foreground
        }

        CellLabel {
            meta: true
            visible: root._state === "unavailable"
            text: "NO MIC"
        }
    }

    interactive: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) {
            if (root.panel)
                root.panel.toggleFrom(root);
        } else {
            AudioService.toggleSourceMute();
        }
    }
}
