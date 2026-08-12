import QtQuick
import Quickshell
import Quickshell.Wayland

// Cross-monitor click-to-dismiss (DESIGN.md, M16 Task 7): a summonable
// surface (Panel.qml, Menu.qml, Center.qml) only ever maps on the screen it
// opened on, and the compositor hit-tests pointer input per output — a
// click on any OTHER monitor never reaches that surface's own backdrop, so
// on a multi-monitor rig the surface just sits open forever until the user
// wanders back. Omarchy's fix (`shell/Ui/KeyboardPanel.qml`'s twin
// `Variants` block there) reimplemented generically: while `active`, spawn
// one transparent, input-catching PanelWindow per screen OTHER than
// `ownScreen`, whose only job is to fire `dismissed()` on press. Zero
// windows exist while closed.
Variants {
    id: root

    property bool active: false
    property var ownScreen: null
    signal dismissed()

    model: root.active ? Quickshell.screens : []

    delegate: Component {
        PanelWindow {
            required property var modelData

            screen: modelData
            // The twin for the surface's own output stays unmapped — that
            // output already has the surface's real backdrop (or, for the
            // keyboard-exclusive Menu, Escape) to handle local dismissal.
            visible: root.active && !!root.ownScreen && modelData.name !== root.ownScreen.name
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            // Overlay, not Top: on the other screen this must win the
            // click over that screen's own bar and any popout sitting on
            // Top, with nothing of its own to protect once it's mapped.
            WlrLayershell.namespace: "formalshell:dismiss-twin"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors { top: true; left: true; right: true; bottom: true }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: root.dismissed()
            }
        }
    }
}
