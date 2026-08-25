import QtQuick
import qs.Core
import qs.Components
import qs.Compositor
import "../../../Bar/workspaces.js" as WorkspacesModel

// The workspace row (DESIGN.md §3 Bar): one cell holding a dot per visible
// workspace on this bar's output. The focused one is a primary pill, an
// urgent one is destructive, every other one is a muted dot. Which
// workspaces show and in what order (sorted by the backend's `idx` ordinal,
// empty non-active ones hidden, all-workspaces fallback when none match
// `outputName`) is ../../../Bar/workspaces.js's call.
Cell {
    id: root

    property string outputName: ""

    readonly property var visibleWorkspaces: WorkspacesModel.visibleModel(
        CompositorService.workspaces, CompositorService.windows, root.outputName)

    readonly property var _focused: {
        for (var i = 0; i < root.visibleWorkspaces.length; i++) {
            if (root.visibleWorkspaces[i].isFocused)
                return root.visibleWorkspaces[i];
        }
        return null;
    }

    // Counted the same way workspaces.js decides a workspace is occupied at
    // all: by workspaceId over the windows list, ids compared as the opaque
    // strings they are.
    readonly property int _focusedWindows: root._focused
        ? CompositorService.windows.filter(function (w) {
            return w.workspaceId === root._focused.id;
        }).length
        : 0

    interactive: true

    // A row of dots says which workspace is live but nothing about what is
    // on it, and the occupancy filter means the numbers can skip.
    tooltipText: root._focused
        ? "WORKSPACE " + (root._focused.name !== "" ? root._focused.name : String(root._focused.idx))
            + " / " + root._focusedWindows + (root._focusedWindows === 1 ? " WINDOW" : " WINDOWS")
        : "WORKSPACES / " + root.visibleWorkspaces.length

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.sm

        Repeater {
            model: root.visibleWorkspaces

            Rectangle {
                id: dot
                required property var modelData
                readonly property var ws: modelData

                width: ws.isFocused ? Theme.space.lg * 2 : Theme.space.md
                height: Theme.space.md
                radius: height / 2
                color: ws.isUrgent
                    ? Theme.color.destructive
                    : (ws.isFocused ? Theme.color.primary : Theme.color.mutedForeground)

                Behavior on width {
                    NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                }

                // A dot is too small to aim at, so its own target reaches
                // out to the cell's padding band. Declared inside the dot
                // rather than on the cell: the cell holds several of these
                // and each focuses a different workspace.
                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -Theme.space.md
                    anchors.bottomMargin: -Theme.space.md
                    cursorShape: Qt.PointingHandCursor
                    onClicked: CompositorService.focusWorkspace(dot.ws.id)
                }
            }
        }
    }
}
