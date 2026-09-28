import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for IphoneService (DESIGN.md §3 "Bar", M75 Task 3): a phone
// glyph, an unread dot riding it the way BellWidget's own bell carries one,
// and the battery percentage in mono when the matched Bluetooth device (or
// the bridge's own poll) has one to report. Hidden entirely (Bar.qml's
// `shown` pattern) while `IphoneService.installed` is false, so a host with
// no bridge on PATH pays nothing for an opt-in cell; once the bridge answers
// at all the cell stays up and dims instead of disappearing while the phone
// is out of ANCS range, since a disappearing cell would read as "nothing
// paired" rather than "not reachable right now". Click toggles the iphone
// panel anchored under this cell, marked open by the same `panelOpen`
// underline as every other panel-bearing cell.
Cell {
    id: root

    property var panel: null

    readonly property bool _connected: IphoneService.connected
    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Visible by default (M23 precedent, Battery/Github/Usage/SystemUpdate):
    // the percentage is content, not a repeat of the icon.
    readonly property bool _showLabel: Config.get("bar.widgets.iphone.showLabel", true)

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment.
    readonly property bool shown: IphoneService.installed

    visible: root.shown
    // Out of range rather than hidden: the badge and the last known battery
    // reading stay legible, only dimmed, so they are never mistaken for a
    // live connection.
    opacity: root._connected ? 1 : 0.6

    tooltipText: {
        var parts = [IphoneService.deviceName !== "" ? IphoneService.deviceName : "IPHONE"];
        parts.push(root._connected ? "CONNECTED" : "OUT OF RANGE");
        if (IphoneService.batteryAvailable)
            parts.push(Math.round(IphoneService.battery * 100) + "%");
        if (IphoneService.unread > 0)
            parts.push(IphoneService.unread + " UNREAD");
        return parts.join(" / ");
    }

    // The battery percentage resizes this cell as it ticks: glide the width
    // instead of shoving the bar's other widgets instantly (DESIGN.md §1
    // "Motion").
    Behavior on implicitWidth {
        enabled: root.animateSize
        Anim {}
    }

    CellRow {
        spacing: Theme.space.xs

        Icon {
            name: "smartphone"
            color: root.foreground

            // primitive-exempt: the unread dot riding the phone glyph, same
            // mark BellWidget's own bell carries.
            Rectangle {
                visible: IphoneService.unread > 0
                anchors.right: parent.right
                anchors.top: parent.top
                width: Theme.space.md
                height: Theme.space.md
                radius: Theme.pillRadius(height)
                color: Theme.color.primary
            }
        }

        CellLabel {
            visible: root._showLabel && IphoneService.batteryAvailable
            text: Math.round(IphoneService.battery * 100) + "%"
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggleFrom(root);
    }
}
