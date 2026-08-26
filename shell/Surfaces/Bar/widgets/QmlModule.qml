import QtQuick
import qs.Core
import qs.Components

// Bar cell for a `bar.modules[]` entry with type "qml" (DESIGN.md §Bar,
// spec §Surfaces-1, M10 Task 3): loads `module.source` into a Loader,
// the same "isolate the failure of THIS component's creation, not the
// whole surface" idiom MediaPanel.qml already uses for
// AnimatedAlbumArt.qml. The real limit here, checked against Quickshell's
// own Loader behavior rather than assumed: this only isolates load-time
// failures (bad syntax, an unresolvable import) as Loader.status ===
// Loader.Error, rendered as the same "MODULE ERROR" text every other error
// path in this file uses, it is not a runtime sandbox. A loaded file that
// parses fine has the exact same engine access as any built-in widget
// (qs.Core, qs.Services, Process, …); nothing here contains what a
// *running* user component does.
Cell {
    id: root

    property var module: null


    Loader {
        id: loader
        anchors.verticalCenter: parent.verticalCenter
        source: (root.module && typeof root.module.source === "string" && root.module.source !== "")
            ? "file://" + root.module.source
            : ""
    }

    CellLabel {
        meta: true
        visible: loader.status === Loader.Error
        anchors.verticalCenter: parent.verticalCenter
        text: "MODULE ERROR"
        color: root.foreground
    }
}
