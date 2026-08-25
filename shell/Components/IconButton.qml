import qs.Core

// A ghost Button carrying one Icon and no label, square at `controlHeight`:
// the panel header's refresh/close controls (DESIGN.md §2).
Button {
    id: root

    property string name: ""
    // Carried for the caller, drawn by nothing yet: Tooltip.qml anchors
    // itself under the bar and suppresses itself while a panel is open, and
    // every IconButton so far sits in a panel header. M44 gives the tooltip
    // an anchor that works anywhere.
    property string tooltipText: ""

    variant: "ghost"
    icon: root.name
    implicitWidth: Theme.space.controlHeight
    implicitHeight: Theme.space.controlHeight
}
