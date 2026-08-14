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
        spacing: Theme.space.sm

        Repeater {
            model: root.visibleWorkspaces

            Cell {
                id: cell
                required property var modelData
                readonly property var ws: modelData
                readonly property string label: ws.name !== "" ? ws.name : String(ws.idx)
                // Counted the same way workspaces.js decides a workspace is
                // occupied at all: by workspaceId over the windows list, ids
                // compared as the opaque strings they are.
                readonly property int windowCount: CompositorService.windows.filter(function (w) {
                    return w.workspaceId === cell.ws.id;
                }).length

                // Bar.qml's regionDelegate Loader forces `root.height` (this
                // file's outer Item) to the bar's shared content height —
                // but Row only positions children's x, never their size, so
                // without this each pill would fall back to its own
                // content-derived implicitHeight instead. Bound to `root`,
                // not `Theme.barHeight`: that token is itself sourced from
                // this same implicitHeight chain (Bar.qml's `_regionHeight`
                // reads `implicitHeight`, and `root.implicitHeight` above is
                // `row.implicitHeight`, computed from these very cells'
                // `height`), so routing through it would close a binding
                // loop. `root.height` is the already-decoupled, externally
                // forced value the direct-widget case relies on too.
                height: root.height
                standalone: true
                accent: ws.isFocused
                // A bare ordinal says nothing about what is on it, and the
                // occupancy filter means the numbers can skip.
                tooltipText: "WORKSPACE " + cell.label + " / " + cell.windowCount
                    + (cell.windowCount === 1 ? " WINDOW" : " WINDOWS")

                Text {
                    anchors.centerIn: parent
                    text: cell.label
                    color: cell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                interactive: true
                onClicked: CompositorService.focusWorkspace(ws.id)
            }
        }
    }
}
