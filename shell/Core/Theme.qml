pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../Theme/palette.js" as Palette

Singleton {
    id: root

    property var color: Palette.fallback()

    readonly property int borderWidth: 2
    readonly property int radius: 0

    readonly property var font: ({
        family: "monospace",
        baseSize: 13,
        caption: Math.round(13 * 0.833), bodySmall: Math.round(13 * 0.917),
        body: 13, subtitle: Math.round(13 * 1.083),
        title: Math.round(13 * 1.167), heading: Math.round(13 * 1.333)
    })

    readonly property var spacing: ({ scale: 1.0, xs: 2, sm: 4, md: 8, lg: 16 })

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }

    // Re-attempt the watch until it actually attaches: FileView's underlying
    // QFileSystemWatcher silently fails to watch a path (or its parent dir)
    // when neither exists yet, which is the normal state at shell startup —
    // ThemeEngine hasn't written its first theme.json yet — so a bare
    // watchChanges: true here would watch nothing, forever, and never notice
    // ThemeEngine's later out-of-band Process writes (verified: theme.json
    // changed on disk with matugen colors, this FileView never reloaded).
    // reload() re-runs FileView's internal updateWatchedFiles(), so once the
    // state dir exists — which happens within ThemeEngine's very first
    // startup run — the watch attaches for real and takes over from here.
    Timer {
        id: rewatchTimer
        interval: 300
        onTriggered: themeJsonFile.reload()
    }

    // Live theme.json watch: ThemeEngine writes this file atomically, we just
    // read it. Absent or failing palette.validate() (e.g. mid-write, or no
    // engine run yet) falls back to the static Flexoki defaults.
    FileView {
        id: themeJsonFile
        path: root._stateDir + "/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applyThemeJson()
        onLoadFailed: error => {
            root.color = Palette.fallback();
            if (error === FileViewError.FileNotFound)
                rewatchTimer.restart();
        }
    }

    function _applyThemeJson() {
        var parsed = null;
        try {
            parsed = JSON.parse(themeJsonFile.text());
        } catch (e) {
            parsed = null;
        }
        root.color = Palette.validate(parsed).ok ? parsed : Palette.fallback();
    }

    function control(state) {
        switch (state) {
        case "hover":
        case "focus":    return { fill: color.foreground, fillAlpha: 0.08, border: color.foreground, borderWidth: borderWidth, borderAlpha: 0.35 }
        case "selected": return { fill: color.accent,     fillAlpha: 0.18, border: color.accent,     borderWidth: borderWidth, borderAlpha: 0.9 }
        default:         return { fill: "transparent",    fillAlpha: 0.0,  border: "transparent",    borderWidth: 0,           borderAlpha: 0.0 }
        }
    }
}
