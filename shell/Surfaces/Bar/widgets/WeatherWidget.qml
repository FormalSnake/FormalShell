import QtQuick
import qs.Core
import qs.Components
import "../../../Weather/openmeteo.js" as Openmeteo

// Bar cell for the weather panel (DESIGN.md §3 "Bar", M6 Task 8, M15 Task
// 3): the live condition icon plus the rounded temperature in mono once
// WeatherPanel's poll has data, mirroring GithubWidget/UsageWidget's own
// pollEnabled/bind-to-panel pattern (the poll itself lives in
// WeatherPanel.qml, see that file's header for the rationale). Before the
// first fetch lands, or with no location fix, the cell stays a dim
// thermometer: openmeteo.js's iconForCode falls back to it for any code it
// doesn't recognize, so there is no second "no data" branch to keep in sync
// here. Click toggles the panel anchored under this cell, same open-panel
// underline as every other panel-bearing cell.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    readonly property bool _hasCurrent: root.panel ? root.panel.hasCurrent : false
    readonly property string _icon: Openmeteo.iconForCode(root.panel ? root.panel.currentCode : -1, root.panel ? root.panel.currentIsDay : true)

    // Icon-only by default (M23, owner named weather directly): the icon
    // carries the condition, and with the label suppressed the temperature
    // it used to show moves into tooltipText below instead of disappearing.
    readonly property bool _showLabel: Config.get("bar.widgets.weather.showLabel", false)

    // The icon carries the condition and the label the temperature, but an
    // icon is a guess until it's named. "UNAVAILABLE" is WeatherPanel.qml's
    // own honest-empty string for a forecast that hasn't resolved. Carries
    // the temperature too now that the label defaults off, so hiding it
    // never deletes information. The trailing segment states the M26 Task 9
    // right-click action, otherwise it's undiscoverable.
    tooltipText: (root._hasCurrent
        ? "WEATHER / " + Openmeteo.conditionLabel(root.panel.currentCode) + " / " + Math.round(root.panel.currentTemp) + "°"
        : "WEATHER / UNAVAILABLE") + " / RIGHT REFRESH"

    Component.onCompleted: {
        if (root.panel)
            root.panel.pollEnabled = true;
    }

    // The condition icon and temperature label both change on poll, so glide
    // the width instead of shoving the bar's other cells instantly
    // (DESIGN.md §1 "Motion", M16 Task 2's contract).
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xs

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root._icon
            color: root._hasCurrent ? root.foreground : root.dimForeground
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root._showLabel && root._hasCurrent
            text: root._hasCurrent ? Math.round(root.panel.currentTemp) + "°" : ""
            color: root.foreground
            font.family: Theme.fontFamilyMono
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    // M26 Task 9: right click refetches the forecast, middle also opens the
    // panel (upstream's redundant left/middle idiom, `manual/
    // 05-the-top-bar.md`'s Audio row).
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            if (root.panel)
                root.panel.refresh();
        } else if (root.panel) {
            root.panel.toggleFrom(root);
        }
    }
}
