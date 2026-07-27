pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root

    readonly property var color: ({
        background: "#100F0F", backgroundAlt: "#1C1B1A",
        foreground: "#CECDC3", foregroundDim: "#878580",
        accent: "#4385BE", urgent: "#D14D41"
    })

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

    function control(state) {
        switch (state) {
        case "hover":
        case "focus":    return { fill: color.foreground, fillAlpha: 0.08, border: color.foreground, borderWidth: borderWidth, borderAlpha: 0.35 }
        case "selected": return { fill: color.accent,     fillAlpha: 0.18, border: color.accent,     borderWidth: borderWidth, borderAlpha: 0.9 }
        default:         return { fill: "transparent",    fillAlpha: 0.0,  border: "transparent",    borderWidth: 0,           borderAlpha: 0.0 }
        }
    }
}
