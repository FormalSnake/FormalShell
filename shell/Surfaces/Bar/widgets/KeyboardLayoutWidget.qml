import QtQuick
import Quickshell.Io
import qs.Core
import qs.Components
import "../../../Compositor/keyboard.js" as Keyboard

// Bar cell for the active keyboard layout, opt-in via bar.layout and never
// part of layout.js's DEFAULT_LAYOUT. Glyph from the pinned
// nerd-fonts-jetbrains-mono cmap (nix/testvm.nix), read out of the font's
// own format-12 subtable rather than memory: md-keyboard U+F030C.
//
// The poll lives here rather than in the compositor backend: Hyprland
// publishes no layout event, so the cell asks `hyprctl devices -j` on a
// timer and the reply goes through Compositor/keyboard.js.
//
// Known cost of that placement, stated rather than hidden: Bar.qml is
// instantiated once per output, so an N-monitor session runs N of these
// timers and spawns N processes every interval.
//
// Two honest states, both required:
//   - the compositor cannot be asked at all (the query failed, or the
//     session is not Hyprland): one dim NO LAYOUT cell. The cell is opt-in,
//     so the user asked for it and hiding it would be the lie.
//   - fewer than two layouts configured: `shown` false. A single-layout
//     session has nothing to report and a permanently static cell is
//     noise, the same judgement Battery.qml makes with no battery.
//
// Read-only in v1: no click-to-cycle. Hyprland's switchxkblayout needs a
// device name and was never verified against a real Hyprland, and a control
// that silently no-ops is exactly what the honest-unavailable rule bans.
Cell {
    id: root

    property var layout: Keyboard.unavailable()

    property bool _answered: false

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment.
    readonly property bool shown: root._answered && (!root.layout.available || Keyboard.hasChoice(root.layout))

    // Visible by default (M23): opt-in builtins absent from DEFAULT_LAYOUT
    // keep their reading unless a user who added the widget opts back out.
    readonly property bool _showLabel: Config.get("bar.widgets.keyboardLayout.showLabel", true)

    visible: root.shown
    tooltipText: Keyboard.tooltipText(root.layout)

    function _poll() {
        if (layoutProc.running)
            return;
        layoutProc.command = ["hyprctl", "devices", "-j"];
        layoutProc.running = true;
    }

    Component.onCompleted: root._poll()

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: root._poll()
    }

    Process {
        id: layoutProc
        stdout: StdioCollector {
            id: layoutCollector
        }
        onExited: exitCode => {
            root._answered = true;
            if (exitCode !== 0) {
                root.layout = Keyboard.unavailable();
                return;
            }
            root.layout = Keyboard.parseHyprlandLayouts(layoutCollector.text);
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "keyboard"
            color: root.layout.available ? root.foreground : root.dimForeground
        }

        Text {
            visible: root._showLabel && root.layout.available
            anchors.verticalCenter: parent.verticalCenter
            text: Keyboard.shortLabel(root.layout.current)
            color: root.dimForeground
            font.family: Theme.fontFamilyMono
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
        }

        SectionLabel {
            visible: root._showLabel && !root.layout.available
            anchors.verticalCenter: parent.verticalCenter
            text: "NO LAYOUT"
            color: root.dimForeground
        }
    }

    interactive: true
}
