import QtQuick
import qs.Core
import qs.Components
import qs.Services
import qs.Notifications

// Bar region for transient session-state glyphs (DESIGN.md §3 Bar's
// "indicators slot", spec §Surfaces-1, M10 Task 2): DND straight off
// NotificationService.dnd (no second DND state machine — Core.State.dnd
// via NotificationsIpc's setDnd/toggleDnd is still the only place that
// writes it) and idle-inhibit off IdleService.inhibited (see that
// property's own header comment for exactly what it covers today and why
// recording has no glyph here: nothing in this shell or a reachable
// service reports screen recording — no screencast portal, no compositor
// IPC surfaces it — checked 2026-07-29, not wired rather than invented; the
// breathing pulse DESIGN.md §4 reserves for genuinely in-progress states
// is the sanctioned idiom whenever a real source shows up). Each glyph is
// its own standalone Cell, shown only while its condition holds; the whole
// row disappears when neither does — never an empty box. Glyph codepoints
// taken from the pinned nerd-fonts-jetbrains-mono cmap (nix/testvm.nix) via
// fonttools ttx, not memory: md-bell_off U+F009B, md-coffee U+F0176.
Row {
    id: root

    readonly property bool _dnd: NotificationService.dnd
    readonly property bool _idleInhibited: IdleService.inhibited

    spacing: Theme.space.sm
    visible: root._dnd || root._idleInhibited

    Cell {
        id: dndCell
        visible: root._dnd
        height: root.height
        standalone: true

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰂛"
            color: dndCell.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }
    }

    Cell {
        id: idleInhibitCell
        visible: root._idleInhibited
        height: root.height
        standalone: true

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅶"
            color: idleInhibitCell.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }
    }
}
