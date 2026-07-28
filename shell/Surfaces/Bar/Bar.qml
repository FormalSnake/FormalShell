import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Core
import qs.Surfaces.Bar.widgets

// The bar (DESIGN.md §Bar, spec §1, M6 Tasks 1+3): three ledger regions —
// left (workspaces, active window), center (clock, now-playing), right
// (indicator/widget cells: battery, audio, network, bluetooth, weather —
// per the spec's own bar-widget ordering). Region
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
    property var networkPanel: null
    property var bluetoothPanel: null
    property var powerPanel: null
    property var weatherPanel: null
    property var mediaPanel: null
    screen: modelData
    anchors { top: true; left: true; right: true }
    // Height tracks the tallest cell actually present instead of a fixed
    // literal — a Cell's implicitHeight is content-derived (Clock's two-line
    // TIME label needs more than a one-line widget does), and a fixed bar
    // height shorter than that clips the cell and strands its bottom rule
    // outside the bar, while a cell shorter than the bar leaves its bottom
    // rule floating above the bar's own (DESIGN.md rule #1, "no double
    // rules"). Every Cell-based widget below binds its own `height` back to
    // this value so its bottom rule always lands exactly on the bar's.
    readonly property real _cellHeight: Math.max(leftRegion.implicitHeight, clockCell.implicitHeight, nowPlayingCell.implicitHeight, batteryCell.implicitHeight, audioCell.implicitHeight, networkCell.implicitHeight, bluetoothCell.implicitHeight, weatherCell.implicitHeight)
    implicitHeight: bar._cellHeight
    color: Theme.color.background

    // Panel.qml anchors every popout's top edge under the bar — it has no
    // other way to know this bar's actual (content-derived) height, since
    // Wayland gives clients no cross-window geometry.
    Binding {
        target: Theme
        property: "barHeight"
        value: bar._cellHeight
    }

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

        Clock {
            id: clockCell
            panel: bar.calendarPanel
            height: bar._cellHeight
        }

        NowPlaying {
            id: nowPlayingCell
            panel: bar.mediaPanel
            height: bar._cellHeight
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

        Battery {
            id: batteryCell
            panel: bar.powerPanel
            height: bar._cellHeight
        }

        AudioWidget {
            id: audioCell
            panel: bar.audioPanel
            height: bar._cellHeight
        }

        NetworkWidget {
            id: networkCell
            panel: bar.networkPanel
            height: bar._cellHeight
        }

        BluetoothWidget {
            id: bluetoothCell
            panel: bar.bluetoothPanel
            height: bar._cellHeight
        }

        WeatherWidget {
            id: weatherCell
            panel: bar.weatherPanel
            height: bar._cellHeight
        }
    }
}
