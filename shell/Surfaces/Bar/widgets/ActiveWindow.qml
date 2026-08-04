import QtQuick
import Quickshell
import qs.Core
import qs.Compositor
import qs.Components

// Icon + app name of the focused window (DESIGN.md's launcher-row
// image-icon exception, extended to the bar in M14): the desktop entry
// behind the focused window's appId (DesktopEntries.heuristicLookup, the
// same DMS FocusedApp / launcher lookup) supplies the themed icon and the
// display name, which leads in foreground; the window title follows
// dimmed. No entry resolves → falls back to exactly today's rendering
// (dim raw appId, foreground title, no icon). No focused window → hidden.
// Elides once the combined label would exceed maxWidth (the bar sets this
// to ~40% of its own width).
Item {
    id: root

    property real maxWidth: 320
    // Set from Bar.qml (`windowVisible: bar.visible`) so the title marquee
    // below can gate on the bar's own PanelWindow actually being on screen —
    // same rationale as NowPlaying.qml's own windowVisible. Defaults true so
    // any other embedding still animates.
    property bool windowVisible: true

    readonly property var focusedWindow: {
        var id = CompositorService.focusedWindowId;
        if (id === "")
            return null;
        var windows = CompositorService.windows;
        for (var i = 0; i < windows.length; i++) {
            if (windows[i].id === id)
                return windows[i];
        }
        return null;
    }

    readonly property string appId: focusedWindow ? focusedWindow.appId : ""
    readonly property string title: focusedWindow ? focusedWindow.title : ""

    readonly property var desktopEntry: root.appId !== "" ? DesktopEntries.heuristicLookup(root.appId) : null

    // check=true so a theme that can't resolve the entry's icon name
    // yields "" — the Image slot below then simply doesn't render, the
    // same missing-texture-free contract as MenuRow's app rows.
    readonly property string iconSource: (root.desktopEntry && root.desktopEntry.icon)
        ? Quickshell.iconPath(root.desktopEntry.icon, true)
        : ""

    readonly property bool shown: root.focusedWindow !== null
    visible: root.shown

    implicitWidth: root.shown ? Math.min(row.implicitWidth, maxWidth) : 0
    implicitHeight: row.implicitHeight
    clip: true

    // Focus/title changes resize this cell (window switch, title rename) —
    // animate the width instead of shoving the bar's other widgets
    // instantly (DESIGN.md §4, M16 Task 2).
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        // Launcher-row image-icon exception (DESIGN.md §3 Bar), glyph-cell
        // sized, radius 0 — only when the entry resolves one.
        Image {
            id: appIcon
            visible: root.iconSource !== ""
            source: root.iconSource
            width: primaryText.implicitHeight
            height: primaryText.implicitHeight
            sourceSize.width: primaryText.implicitHeight
            sourceSize.height: primaryText.implicitHeight
            fillMode: Image.PreserveAspectFit
        }

        Text {
            id: primaryText
            visible: text !== ""
            // Entry found: its name leads in foreground. No entry: the raw
            // appId, dimmed — today's exact fallback rendering.
            text: root.desktopEntry ? (root.desktopEntry.name || root.appId) : root.appId
            color: root.desktopEntry ? Theme.color.foreground : Theme.color.foregroundDim
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }

        // M-polish batch item A: the window title scrolls on overflow via
        // the shared MarqueeText mechanism (Components/MarqueeText.qml,
        // extracted from NowPlaying.qml's M16 Task 11 now-playing ticker).
        // `leftPadding` widens the gap to the app name without touching
        // `row.spacing` — that stays tight (xxs) for the icon+name lockup.
        MarqueeText {
            id: titleText
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            // Roles swap once an entry is found: the title follows dimmed
            // instead of leading foreground.
            color: root.desktopEntry ? Theme.color.foregroundDim : Theme.color.foreground
            leftPadding: Theme.space.md
            windowVisible: root.windowVisible
            maxWidth: {
                var used = 0;
                if (appIcon.visible)
                    used += appIcon.width + row.spacing;
                if (primaryText.visible)
                    used += primaryText.width + row.spacing;
                return Math.max(0, root.maxWidth - used);
            }
        }
    }
}
