import QtQuick
import qs.Core
import qs.Components
import qs.Compositor

// One cell per workspace on this bar's output (DESIGN.md §3 Bar retrofit):
// a standalone Cell per workspace — borderless at rest, hover-cursor chrome
// on mouseover, the same discrete-module vocabulary every other bar widget
// uses. The focused workspace is a full-bleed accent fill (DESIGN.md §2.4)
// rather than a tinted border. Falls back to every workspace when none
// match `outputName` (e.g. the compositor's output name disagrees with
// Quickshell's screen name).
Item {
    id: root

    property string outputName: ""

    readonly property var onOutput: CompositorService.workspaces.filter(function (ws) {
        return ws.output === root.outputName;
    })
    readonly property var visibleWorkspaces: onOutput.length > 0 ? onOutput : CompositorService.workspaces

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.xs

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
