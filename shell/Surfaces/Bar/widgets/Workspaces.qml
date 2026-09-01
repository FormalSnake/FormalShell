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
//
// Hover grows whichever shape is answering the pointer: the pill on the
// focused slot, a plain dot everywhere else. The dot under the pill never
// grows on its own, so the row only ever has to fit one grown shape at a
// time, and the row is `Theme.space.lg` tall (the grown size) rather than
// `_dotSize` so that shape never clips against it.
Cell {
    id: root

    property string outputName: ""

    // Maintained rather than a raw binding on CompositorService.workspaces/
    // windows: HyprlandBackend.qml keeps windows apart from workspaces so a
    // title-only tick can't republish the workspace list (its own header
    // comment says so), but visibleModel() reads both, so a raw binding here
    // would rebuild every dot on every title change anyway. Recomputed on
    // both inputs and published only when the resolved model actually
    // differs, closing that gap.
    property var visibleWorkspaces: []
    property string _visibleWorkspacesJson: "[]"

    function _updateVisibleWorkspaces() {
        var next = WorkspacesModel.visibleModel(
            CompositorService.workspaces, CompositorService.windows, root.outputName);
        var json = JSON.stringify(next);
        if (json === root._visibleWorkspacesJson)
            return;
        root._visibleWorkspacesJson = json;
        root.visibleWorkspaces = next;
    }

    onOutputNameChanged: root._updateVisibleWorkspaces()
    Component.onCompleted: root._updateVisibleWorkspaces()

    Connections {
        target: CompositorService
        function onWorkspacesChanged() { root._updateVisibleWorkspaces(); }
        function onWindowsChanged() { root._updateVisibleWorkspaces(); }
    }

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

    // The row's own height, sized to whichever shape is grown by hover
    // (the dot's own grown size), not to the resting dot.
    readonly property real _rowHeight: Theme.space.lg

    // Which slot the pointer is over, kept on the root since the Repeater's
    // delegates have no ids to reach each other by. -1 means no slot.
    property int _hoveredIndex: -1

    // The dot row is the one lockup on a vertical bar that turns as a whole
    // (Bar/layout.js's labelRotation covers what turning is for): dots and
    // a pill have no upright reading of their own, so turning them is the
    // same picture drawn the other way round rather than a readout on its
    // side, and the travelling pill keeps one set of geometry either way.
    //
    // A left bar turns anticlockwise, which would put the first workspace
    // at the bottom; the row is reversed there so the workspaces still read
    // top to bottom, the same order the bar's own regions run in. A right
    // bar turns the other way and needs no reversal.
    readonly property bool _reversed: root.labelRotation < 0

    function _slotX(index) {
        var slot = root._reversed ? root.visibleWorkspaces.length - 1 - index : index;
        return slot * (root._slotWidth + root._slotSpacing);
    }

    interactive: true

    // A row of dots says which workspace is live but nothing about what is
    // on it, and the occupancy filter means the numbers can skip.
    tooltipText: root._focused
        ? "WORKSPACE " + (root._focused.name !== "" ? root._focused.name : String(root._focused.idx))
            + " / " + root._focusedWindows + (root._focusedWindows === 1 ? " WINDOW" : " WINDOWS")
        : "WORKSPACES / " + root.visibleWorkspaces.length

    // The slot swaps the box, since a rotated item still measures by the
    // box it had before the turn.
    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: root.vertical ? strip.height : strip.width
        height: root.vertical ? strip.width : strip.height

        Item {
            id: strip
            anchors.centerIn: parent
            rotation: root.labelRotation
            width: dotRow.width
            height: root._rowHeight

            Row {
                id: dotRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: root._slotSpacing
                layoutDirection: root._reversed ? Qt.RightToLeft : Qt.LeftToRight

                Repeater {
                    model: root.visibleWorkspaces

                    Item {
                        id: slot
                        required property int index
                        required property var modelData
                        readonly property var ws: modelData

                        width: root._slotWidth
                        height: root._rowHeight

                        readonly property bool urgent: slot.ws.isUrgent
                        onUrgentChanged: if (slot.urgent) urgentPulse.restart()

                        // primitive-exempt: one workspace dot, an indicator at the size dots
                        // are, not a bordered box.
                        Rectangle {
                            id: dot
                            anchors.centerIn: parent
                            // The pointer's own answer that this is a target,
                            // a step the dot grows on hover. The focused slot's
                            // dot sits still: the pill over it is what answers
                            // the hover there instead.
                            width: (pointer.containsMouse && !slot.ws.isFocused) ? Theme.space.lg : root._dotSize
                            height: dot.width
                            radius: Theme.pillRadius(dot.height)
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
                            onContainsMouseChanged: {
                                if (pointer.containsMouse)
                                    root._hoveredIndex = slot.index;
                                else if (root._hoveredIndex === slot.index)
                                    root._hoveredIndex = -1;
                            }
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
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.pillRadius(pill.height)
                color: Theme.color.primary

                // The pointer's own answer that this is a target, same as a
                // plain dot's, since the focused slot's dot never grows: this
                // is the shape that has to carry the hover state instead.
                readonly property bool hovered: root._focusedIndex >= 0
                    && root._hoveredIndex === root._focusedIndex

                // Held apart from `lead`/`trail` below so hovering never
                // disturbs the pace those two set for the travel animation.
                property real growth: pill.hovered ? (Theme.space.lg - root._dotSize) : 0

                Behavior on growth {
                    NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                }

                height: root._dotSize + pill.growth

                readonly property real target: root._slotX(Math.max(0, root._focusedIndex))

                property real lead: pill.target
                property real trail: pill.target

                x: Math.min(pill.lead, pill.trail) - pill.growth / 2
                width: Math.abs(pill.lead - pill.trail) + root._slotWidth + pill.growth

                Behavior on lead {
                    NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.emphasizedEasing }
                }

                Behavior on trail {
                    NumberAnimation { duration: Theme.motion.emphasized; easing.type: Theme.motion.emphasizedEasing }
                }
            }
        }
    }
}
