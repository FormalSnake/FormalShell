pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Read-only watched ~/.config/formalshell/settings.json — the shell's user
// config surface. Per CLAUDE.md's hard rule the shell never writes this file;
// State.qml (runtime-mutable, $XDG_STATE_HOME) is the writable counterpart.
// v1 keys: menu.customPowerButtons: [{ label, icon, command, confirm? }],
// bar.position (reserved), theme.fontDisplay (reserved).
Singleton {
    id: root

    property var settings: ({})

    readonly property string _configDir: {
        const xdgConfig = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config");
        return xdgConfig + "/formalshell";
    }

    // Same bounded-retry rationale as Theme.qml's theme.json watch: at first
    // launch settings.json (and its parent dir) may not exist yet, and a bare
    // watchChanges: true never attaches to a path whose parent dir is also
    // missing — retry until the dir shows up (e.g. ThemeEngine creates it)
    // and the real QFileSystemWatcher takes over from here.
    Timer {
        id: rewatchTimer
        interval: 300
        onTriggered: settingsFile.reload()
    }

    FileView {
        id: settingsFile
        path: root._configDir + "/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applySettings()
        onLoadFailed: error => {
            root.settings = {};
            if (error === FileViewError.FileNotFound)
                rewatchTimer.restart();
        }
    }

    function _applySettings() {
        try {
            root.settings = JSON.parse(settingsFile.text());
        } catch (e) {
            console.warn("Config: failed to parse settings.json:", e.message);
            // Keep the last good value rather than falling back to {}.
        }
    }

    // Dotted-path lookup: Config.get("menu.customPowerButtons", [])
    function get(path, fallback) {
        var node = root.settings;
        var parts = path.split(".");
        for (var i = 0; i < parts.length; i++) {
            if (node === undefined || node === null || typeof node !== "object")
                return fallback;
            node = node[parts[i]];
        }
        return node === undefined ? fallback : node;
    }
}
