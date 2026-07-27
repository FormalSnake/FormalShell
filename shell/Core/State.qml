pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Runtime-mutable session state (wallpaper, mode) — the shell owns and
// rewrites this file; settings.json stays read-only. Quickshell.statePath()
// resolves under quickshell/by-shell/<shellId>/, not the spec-mandated
// $XDG_STATE_HOME/formalshell/, so the path is built by hand instead.
Singleton {
    id: root

    property alias wallpaper: adapter.wallpaper
    property alias mode: adapter.mode

    function setWallpaper(path) {
        adapter.wallpaper = path;
        stateFile.writeAdapter();
    }

    function setMode(newMode) {
        adapter.mode = newMode;
        stateFile.writeAdapter();
    }

    function toggleMode() {
        root.setMode(root.mode === "dark" ? "light" : "dark");
    }

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }

    FileView {
        id: stateFile
        path: root._stateDir + "/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: adapter
            property string wallpaper: ""
            property string mode: "dark"
        }
    }
}
