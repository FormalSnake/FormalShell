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

    // Live theme.json watch: ThemeEngine writes this file atomically, we just
    // read it. Absent or failing palette.validate() (e.g. mid-write, or no
    // engine run yet) falls back to the static Flexoki defaults.
    FileView {
        id: themeJsonFile
        path: root._stateDir + "/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applyThemeJson()
        onLoadFailed: error => root.color = Palette.fallback()
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
