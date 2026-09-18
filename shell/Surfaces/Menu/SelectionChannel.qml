import QtQuick
import Quickshell
import Quickshell.Io

// Write-only channel for the menu's two selection-file IPC contracts:
// select()/input() answers land at menuSelectionPath as `{token, value}` /
// `{token, cancelled: true}` JSON, and the picker's own answers land at
// pickerSelectionPath the same way. Every write goes through a Process
// (`printf '%s' "$content" > "$path"`), never FileView.setText(),
// ThemeEngine.qml documents FileView silently skipping the write *and* the
// saved() signal when the new text is byte-identical to what it has cached,
// which a repeated identical answer hits every time, and which a
// caller-side truncate can't work around either (FileView compares against
// its own cached text, not what's actually on disk). Callers poll/read the
// file themselves, see MenuIpc.qml's header comment for the full contract.
Item {
    id: root

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }

    readonly property string menuSelectionPath: root._stateDir + "/menu-selection.txt"
    readonly property string pickerSelectionPath: root._stateDir + "/picker-selection.txt"

    function writeFile(path, content) {
        var proc = _procComponent.createObject(root, {});
        proc.command = ["sh", "-c", 'printf \'%s\' "$2" > "$1"', "sh", path, content];
        proc.running = true;
    }

    // Deletes whatever's currently on disk. Used to invalidate a channel
    // before a brand-new request's UI opens.
    function clearFile(path) {
        var proc = _procComponent.createObject(root, {});
        proc.command = ["rm", "-f", path];
        proc.running = true;
    }

    Component {
        id: _procComponent

        Process {
            onExited: exitCode => {
                if (exitCode !== 0)
                    console.warn("Menu: selection-file write failed, code", exitCode);
                destroy();
            }
        }
    }
}
