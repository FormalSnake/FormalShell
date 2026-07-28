import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Core
import qs.Surfaces.Bar.widgets

// The bar (DESIGN.md §Bar, spec §1, M6 Tasks 1+3): three ledger regions —
// left (workspaces, active window), center (clock, now-playing joins it in
// M7), right (indicator/widget cells, starting with audio). Region
// boundaries are rules, never whitespace gaps — DESIGN's rule #2, "rules are
// the ONLY separation mechanism" — so the left|center and center|right
// boundaries are always drawn. Workspaces/ActiveWindow predate the Cell
// system (M1-M3) and stay as-is per CLAUDE.md's "do not restyle outside a
// plan that schedules it"; only the region scaffolding and the new widgets
// are Cell-based.
PanelWindow {
    id: bar
    required property var modelData
    property var audioPanel: null
    property var calendarPanel: null
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: 32
    color: Theme.color.background

    // Bottom edge: one rule against the desktop.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.borderWidth
        color: Theme.color.rule
    }

    Row {
        id: leftRegion
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.md

        Workspaces {
            outputName: bar.screen ? bar.screen.name : ""
        }

        ActiveWindow {
            maxWidth: bar.width * 0.4
        }
    }

    Rectangle {
        anchors.left: leftRegion.right
        anchors.leftMargin: Theme.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.borderWidth
        height: parent.height - Theme.spacing.sm * 2
        color: Theme.color.rule
    }

    Row {
        id: centerRegion
        anchors.centerIn: parent
        spacing: 0
        // Now-playing joins the clock here in M7.

        Clock {
            panel: bar.calendarPanel
        }
    }

    Rectangle {
        anchors.right: rightRegion.left
        anchors.rightMargin: Theme.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.borderWidth
        height: parent.height - Theme.spacing.sm * 2
        color: Theme.color.rule
    }

    Row {
        id: rightRegion
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        AudioWidget {
            panel: bar.audioPanel
        }
    }
}
