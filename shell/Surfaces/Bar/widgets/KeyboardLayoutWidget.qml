import QtQuick
import Quickshell.Io
import qs.Core
import qs.Components
import qs.Compositor
import "../../../Compositor/keyboard.js" as Keyboard

// Bar cell for the active keyboard layout, opt-in via bar.layout and never
// part of layout.js's DEFAULT_LAYOUT. Glyph from the pinned
// nerd-fonts-jetbrains-mono cmap (nix/testvm.nix), read out of the font's
// own format-12 subtable rather than memory: md-keyboard U+F030C.
//
// The poll lives here rather than in a compositor backend. niri's event
// stream does carry KeyboardLayoutsChanged/KeyboardLayoutSwitched and
// reducer.js is where those belong; until that lands this cell asks
// `niri msg --json keyboard-layouts` on a timer, and `hyprctl devices -j`
// on Hyprland, which has no reducer at all. Both replies go through
// Compositor/keyboard.js, the only place the two wire shapes are
// normalized.
//
// Known cost of that placement, stated rather than hidden: Bar.qml is
// instantiated once per output, so an N-monitor session runs N of these
// timers and spawns N processes every interval. Moving the niri leg onto
// the reducer's two existing events (they are already on the wire, swallowed
// by reducer.js's default case) removes the timer entirely on that backend
// and is the intended fix.
//
// Two honest states, both required:
//   - the compositor cannot be asked at all (unrecognized session, or the
//     query failed): one dim NO LAYOUT cell. The cell is opt-in, so the
//     user asked for it and hiding it would be the lie.
//   - fewer than two layouts configured: `shown` false. A single-layout
//     session has nothing to report and a permanently static cell is
//     noise, the same judgement Battery.qml makes with no battery.
//
// Read-only in v1: no click-to-cycle. niri has the action, Hyprland's
// equivalent needs a device name and was never verified against a real
// Hyprland, and a control that silently no-ops on one backend is exactly
// what the honest-unavailable rule bans.
Cell {
    id: root

    property var layout: Keyboard.unavailable()

    readonly property string _compositor: CompositorService.compositor
    property bool _answered: false

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment.
    readonly property bool shown: root._answered && (!root.layout.available || Keyboard.hasChoice(root.layout))

    visible: root.shown
    standalone: true
    hovered: hoverArea.containsMouse
    tooltipText: Keyboard.tooltipText(root.layout)

    function _poll() {
        if (layoutProc.running || root._compositor === "unknown")
            return;
        layoutProc.command = (root._compositor === "niri")
            ? ["niri", "msg", "--json", "keyboard-layouts"]
            : ["hyprctl", "devices", "-j"];
        layoutProc.running = true;
    }

    // An unrecognized compositor has nothing to spawn, so it settles on the
    // honest state immediately rather than waiting on a poll that never runs.
    Component.onCompleted: {
        if (root._compositor === "unknown")
            root._answered = true;
        else
            root._poll();
    }

    Timer {
        interval: 2000
        repeat: true
        running: root._compositor !== "unknown"
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
            root.layout = (root._compositor === "niri")
                ? Keyboard.parseNiriLayouts(layoutCollector.text)
                : Keyboard.parseHyprlandLayouts(layoutCollector.text);
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰌌"
            color: root.layout.available ? root.foreground : root.dimForeground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }

        MetaLabel {
            anchors.verticalCenter: parent.verticalCenter
            text: root.layout.available ? Keyboard.shortLabel(root.layout.current) : "NO LAYOUT"
            color: root.dimForeground
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
    }
}
