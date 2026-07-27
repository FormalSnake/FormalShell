import QtQuick
import qs.Core
import qs.Compositor

// Title of the focused window, appId dimmed ahead of it. Elides once the
// combined label would exceed maxWidth (the bar sets this to ~40% of its
// own width).
Item {
    id: root

    property real maxWidth: 320

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

    implicitWidth: Math.min(row.implicitWidth, maxWidth)
    implicitHeight: row.implicitHeight
    clip: true

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.xs

        Text {
            id: appIdText
            visible: root.appId !== ""
            text: root.appId
            color: Theme.color.foregroundDim
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
        }

        Text {
            id: titleText
            text: root.title
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
            elide: Text.ElideRight
            width: Math.min(implicitWidth, Math.max(0, root.maxWidth - (appIdText.visible ? appIdText.width + row.spacing : 0)))
        }
    }
}
