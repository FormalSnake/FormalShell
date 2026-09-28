import Quickshell.Io

import qs.Compositor
import qs.Core

// `qs ipc call workspaces peek <n>|status`, the Spaces cell's own target
// (M74). `peek` opens the preview of workspace `n` (its ordinal, the number
// on the slot) off the cell on the focused output, which is the pointer's
// hover open for a keybind or the rig. `status` is the slots that cell
// resolved, for the rig to read the icons and agent badges off rather than
// pixels. Both answer an error string when no bar carries a Spaces cell.
IpcHandler {
    id: root
    target: "workspaces"

    // Set from shell.qml, the single WorkspacePreview, which every bar's
    // cell registers itself with.
    property var preview: null

    function _cell() {
        if (!root.preview)
            return null;
        var cells = root.preview.cells;
        for (var i = 0; i < cells.length; i++) {
            if (cells[i].outputName === CompositorService.focusedOutputName)
                return cells[i];
        }
        return cells.length > 0 ? cells[0] : null;
    }

    function peek(n: int): string {
        var cell = root._cell();
        if (!cell)
            return "error: no workspaces cell on any bar";
        if (Config.get("workspaces.preview", true) === false)
            return "error: preview is off (workspaces.preview)";
        return cell.peek(n) ? "ok" : "error: no workspace " + n + " on " + cell.outputName;
    }

    function close(): string {
        if (root.preview)
            root.preview.close();
        return "ok";
    }

    function status(): string {
        var cell = root._cell();
        if (!cell)
            return "error: no workspaces cell on any bar";
        return JSON.stringify({
            output: cell.outputName,
            slots: cell.status(),
            preview: {
                open: !!root.preview && root.preview.isOpen,
                idx: root.preview && root.preview.isOpen ? root.preview.idx : -1,
                windows: root.preview && root.preview.isOpen ? root.preview.cursorCount : 0
            }
        });
    }
}
