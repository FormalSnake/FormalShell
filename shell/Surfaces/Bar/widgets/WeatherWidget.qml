import QtQuick
import qs.Core
import qs.Components
import "../../../Weather/openmeteo.js" as Openmeteo

// Bar cell for the weather panel (DESIGN.md §Bar, spec §2's Location→
// Weather chain, M6 Task 8, M15 Task 3): a live glyph + rounded temperature
// once WeatherPanel's poll has data, mirroring GithubWidget/UsageWidget's
// own pollEnabled/bind-to-panel pattern (the poll itself lives in
// WeatherPanel.qml — see that file's header for the rationale) rather than
// M6's original static "WEATHER" label. Before the first fetch lands, or
// with no location fix, the cell stays a dim glyph — openmeteo.js's
// glyphForCode falls back to the same weather-thermometer_exterior
// (U+E34E, pinned nerd-fonts-jetbrains-mono cmap) the M6 version hardcoded
// for any code it doesn't recognize, so there's no second "no data" glyph
// literal to keep in sync here. Click toggles the panel anchored under
// this cell, same panel-open accent dot idiom as every other M6 widget.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    readonly property bool _hasCurrent: root.panel ? root.panel.hasCurrent : false
    readonly property string _glyph: Openmeteo.glyphForCode(root.panel ? root.panel.currentCode : -1, root.panel ? root.panel.currentIsDay : true)

    standalone: true
    hovered: hoverArea.containsMouse

    // The glyph carries the condition and the label the temperature, but a
    // glyph is a guess until it's named. "UNAVAILABLE" is WeatherPanel.qml's
    // own honest-empty string for a forecast that hasn't resolved.
    tooltipText: "WEATHER / " + (root._hasCurrent ? Openmeteo.conditionLabel(root.panel.currentCode) : "UNAVAILABLE")

    Component.onCompleted: {
        if (root.panel)
            root.panel.pollEnabled = true;
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root._glyph
            color: root._hasCurrent ? root.foreground : root.dimForeground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }

        MetaLabel {
            visible: root._hasCurrent
            anchors.verticalCenter: parent.verticalCenter
            text: root._hasCurrent ? Math.round(root.panel.currentTemp) + "°" : ""
            color: root.dimForeground
        }
    }

    PanelOpenDot {
        visible: root._panelOpen
        inverted: root.invertedNow
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.panel)
                root.panel.toggle(root.mapToItem(null, 0, 0).x);
        }
    }
}
