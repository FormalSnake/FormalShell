import QtQuick
import qs.Core
import qs.Components
import qs.Compositor
import "../../../Bar/workspaces.js" as WorkspacesModel

// The workspace row (DESIGN.md §3 Bar): one cell holding a dot per visible
// workspace on this bar's output, with a single `primary` pill layered over
// them marking the focused one. Which workspaces show and in what order
// (sorted by the backend's `idx` ordinal, empty non-active ones hidden,
// all-workspaces fallback when none match `outputName`) is
// ../../../Bar/workspaces.js's call.
//
// The pill is one item that moves rather than a per-dot width (M48): the
// dots hold fixed slots and never reflow, and a switch reads as the pill
// travelling from the old slot to the new one. Its two edges take different
// durations (`standard` for the edge arriving, `emphasized` for the edge
// leaving), so the pill stretches across the gap and closes up behind
// itself, which is what makes the travel legible rather than a jump. Both
// are zeroed by `motion.enabled=false` like every other transition, and at
// zero the pill simply appears at the new slot.
Cell {
    id: root

    property string outputName: ""

    readonly property var visibleWorkspaces: WorkspacesModel.visibleModel(
        CompositorService.workspaces, CompositorService.windows, root.outputName)

    readonly property int _focusedIndex: {
        for (var i = 0; i < root.visibleWorkspaces.length; i++) {
            if (root.visibleWorkspaces[i].isFocused)
                return i;
        }
        return -1;
    }

    readonly property var _focused: root._focusedIndex >= 0
        ? root.visibleWorkspaces[root._focusedIndex]
        : null

    // Counted the same way workspaces.js decides a workspace is occupied at
    // all: by workspaceId over the windows list, ids compared as the opaque
    // strings they are.
    readonly property int _focusedWindows: root._focused
        ? CompositorService.windows.filter(function (w) {
            return w.workspaceId === root._focused.id;
        }).length
        : 0

    // Every slot is the pill's own width, so the row's geometry never
    // depends on which workspace is focused and the pill has a fixed
    // destination to travel to.
    readonly property real _slotWidth: Theme.space.xxl
    readonly property real _slotSpacing: Theme.space.xs
    readonly property real _dotSize: Theme.space.md

    function _slotX(index) {
        return index * (root._slotWidth + root._slotSpacing);
    }

    interactive: true

    // A row of dots says which workspace is live but nothing about what is
    // on it, and the occupancy filter means the numbers can skip.
    tooltipText: root._focused
        ? "WORKSPACE " + (root._focused.name !== "" ? root._focused.name : String(root._focused.idx))
            + " / " + root._focusedWindows + (root._focusedWindows === 1 ? " WINDOW" : " WINDOWS")
        : "WORKSPACES / " + root.visibleWorkspaces.length

    Item {
        id: strip
        anchors.verticalCenter: parent.verticalCenter
        width: dotRow.width
        height: root._dotSize

        Row {
            id: dotRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: root._slotSpacing

            Repeater {
                model: root.visibleWorkspaces

                Item {
                    id: slot
                    required property var modelData
                    readonly property var ws: modelData

                    width: root._slotWidth
                    height: root._dotSize

                    readonly property bool urgent: slot.ws.isUrgent
                    onUrgentChanged: if (slot.urgent) urgentPulse.restart()

                    // primitive-exempt: one workspace dot, an indicator at the size dots
                    // are, not a bordered box.
                    Rectangle {
                        id: dot
                        anchors.centerIn: parent
                        // A hovered dot grows a step, the pointer's own
                        // answer that this is a target.
                        width: pointer.containsMouse ? Theme.space.lg : root._dotSize
                        height: dot.width
                        radius: dot.height / 2
                        color: slot.ws.isUrgent
                            ? Theme.color.destructive
                            : (slot.ws.isFocused ? Theme.color.primary : Theme.color.mutedForeground)

                        Behavior on width {
                            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                        }

                        // The dot under the pill takes the pill's own colour
                        // so the two read as one shape while the pill is
                        // arriving, and fades back once it has left.
                        Behavior on color {
                            ColorAnimation { duration: Theme.motion.emphasized; easing.type: Theme.motion.emphasizedEasing }
                        }

                        // One pulse when a workspace turns urgent, not a
                        // loop: the destructive colour is the standing
                        // state, the pulse is the thing that just happened.
                        SequentialAnimation {
                            id: urgentPulse
                            NumberAnimation { target: dot; property: "opacity"; to: 0.3; duration: Theme.motion.standard; easing.type: Theme.motion.easing }
                            NumberAnimation { target: dot; property: "opacity"; to: 1; duration: Theme.motion.emphasized; easing.type: Theme.motion.emphasizedEasing }
                        }

                    }

                    // A dot is too small to aim at, so its own target reaches
                    // out to the cell's padding band. Declared inside the slot
                    // rather than on the cell: the cell holds several of these
                    // and each focuses a different workspace.
                    MouseArea {
                        id: pointer
                        anchors.fill: parent
                        anchors.topMargin: -Theme.space.md
                        anchors.bottomMargin: -Theme.space.md
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: CompositorService.focusWorkspace(slot.ws.id)
                    }
                }
            }
        }

        // The moving pill. `_lead` and `_trail` chase the same slot at
        // different speeds, so the span between them opens on the way out
        // and closes on the way in; which of the two is the leading edge
        // falls out of the arithmetic rather than needing the direction.
        // primitive-exempt: the focused-workspace indicator itself. A moving
        // pill is not a surface, and nothing else in the shell draws one.
        Rectangle {
            id: pill
            visible: root._focusedIndex >= 0
            height: root._dotSize
            anchors.verticalCenter: parent.verticalCenter
            radius: pill.height / 2
            color: Theme.color.primary

            readonly property real target: root._slotX(Math.max(0, root._focusedIndex))

            property real lead: pill.target
            property real trail: pill.target

            x: Math.min(pill.lead, pill.trail)
            width: Math.abs(pill.lead - pill.trail) + root._slotWidth

            Behavior on lead {
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.emphasizedEasing }
            }

            Behavior on trail {
                NumberAnimation { duration: Theme.motion.emphasized; easing.type: Theme.motion.emphasizedEasing }
            }
        }
    }
}
