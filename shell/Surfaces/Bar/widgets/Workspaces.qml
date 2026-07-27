import QtQuick
import qs.Core
import qs.Compositor

// One cell per workspace on this bar's output. Falls back to every
// workspace when none match `outputName` (e.g. the compositor's output
// name disagrees with Quickshell's screen name).
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

            Rectangle {
                id: cell
                required property var modelData
                readonly property var ws: modelData
                readonly property string state: ws.isFocused ? "selected" : (hoverArea.containsMouse ? "hover" : "normal")
                readonly property var style: Theme.control(state)
                property color fillColor: style.fill
                property color borderColor: style.border

                radius: Theme.radius
                color: Qt.rgba(fillColor.r, fillColor.g, fillColor.b, style.fillAlpha)
                border.width: style.borderWidth
                border.color: Qt.rgba(borderColor.r, borderColor.g, borderColor.b, style.borderAlpha)
                implicitWidth: label.implicitWidth + Theme.spacing.md * 2
                implicitHeight: label.implicitHeight + Theme.spacing.sm * 2

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: ws.name !== "" ? ws.name : String(ws.idx)
                    color: Theme.color.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
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
