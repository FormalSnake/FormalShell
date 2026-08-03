import QtQuick
import qs.Core
import qs.Components
import qs.Compositor
import "../../../Bar/workspaces.js" as WorkspacesModel

// One cell per visible workspace on this bar's output (DESIGN.md §3 Bar
// retrofit): a standalone Cell per workspace — borderless at rest,
// hover-cursor chrome on mouseover, the same discrete-module vocabulary
// every other bar widget uses. The focused workspace is a full-bleed accent
// fill (DESIGN.md §2.4) rather than a tinted border. Which workspaces show
// and in what order (sorted by the backend's `idx` ordinal, empty
// non-active ones hidden, all-workspaces fallback when none match
// `outputName`) is ../../../Bar/workspaces.js's call.
Item {
    id: root

    property string outputName: ""

    readonly property var visibleWorkspaces: WorkspacesModel.visibleModel(
        CompositorService.workspaces, CompositorService.windows, root.outputName)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        Repeater {
            model: root.visibleWorkspaces

            Cell {
                id: cell
                required property var modelData
                readonly property var ws: modelData

                standalone: true
                accent: ws.isFocused
                hovered: hoverArea.containsMouse

                Text {
                    anchors.centerIn: parent
                    text: ws.name !== "" ? ws.name : String(ws.idx)
                    color: cell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                }

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: CompositorService.focusWorkspace(ws.id)
                }
            }
        }
    }
}
