import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../../Compositor/keyboard.js" as Keyboard

// Bar cell for the active keyboard layout, opt-in via bar.layout and never
// part of layout.js's DEFAULT_LAYOUT. Glyph from the pinned
// nerd-fonts-jetbrains-mono cmap (nix/testvm.nix), read out of the font's
// own format-12 subtable rather than memory: md-keyboard U+F030C.
//
// State comes from KeyboardLayoutService, shared by every bar (Bar.qml is
// instantiated once per output): one `hyprctl devices -j` query plus
// Hyprland's `activelayout`/`configreloaded` events, no polling here.
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

    readonly property var layout: KeyboardLayoutService.layout

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment.
    readonly property bool shown: KeyboardLayoutService.answered && (!root.layout.available || Keyboard.hasChoice(root.layout))

    // Visible by default (M23): opt-in builtins absent from DEFAULT_LAYOUT
    // keep their reading unless a user who added the widget opts back out.
    readonly property bool _showLabel: Config.get("bar.widgets.keyboardLayout.showLabel", true)

    visible: root.shown
    tooltipText: Keyboard.tooltipText(root.layout)

    CellRow {
        spacing: Theme.space.xxs

        Icon {
            name: "keyboard"
            color: root.layout.available ? root.foreground : root.dimForeground
        }

        CellLabel {
            visible: root._showLabel && root.layout.available
            text: Keyboard.shortLabel(root.layout.current)
            color: root.dimForeground
        }

        CellLabel {
            meta: true
            visible: root._showLabel && !root.layout.available
            text: "NO LAYOUT"
        }
    }

    interactive: true
}
