import qs.Core

// A ghost Button carrying one Icon and no label, square at `controlHeight`:
// the panel header's refresh/close controls (DESIGN.md §2).
Button {
    id: root

    property string name: ""

    variant: "ghost"
    icon: root.name
    implicitWidth: Theme.space.controlHeight
    implicitHeight: Theme.space.controlHeight
}
