import QtQuick
import qs.Core
import qs.Components
import qs.Plugins

// Bar cell for a kind:"bar" plugin: loads the plugin's entry file into a
// Loader, the same "isolate the failure of THIS component's creation, not the
// whole surface" idiom MediaPanel.qml uses for AnimatedAlbumArt.qml.
//
// The real limit, stated plainly rather than implied away: this only isolates
// LOAD-TIME failures (bad syntax, an unresolvable import) as Loader.status ===
// Loader.Error, rendered as the PLUGIN ERROR text below. It is not a runtime
// sandbox. A plugin file that parses fine has the exact same engine access as
// any built-in widget (qs.Core, qs.Services, Process, Quickshell.Io) and can
// wedge or crash this single-process shell outright. Nothing here contains
// what a *running* plugin does.
Cell {
    id: root

    property var plugin: null

    // Forwarded up so Bar.qml's Row slot contract keeps working: a plugin
    // that hides itself sets `shown` on its own root, and Bar.qml reads that
    // off this cell. `visible` is deliberately never read through a Loader
    // boundary in either direction, for the reason Bar.qml's own delegate
    // comment documents.
    readonly property bool shown: loader.item && loader.item.shown !== undefined ? loader.item.shown : true

    standalone: true

    Loader {
        id: loader
        anchors.verticalCenter: parent.verticalCenter
        source: root.plugin ? root.plugin.entryUrl : ""

        onStatusChanged: {
            if (loader.status === Loader.Error && root.plugin)
                PluginService.reportError(root.plugin.id, "entry failed to load");
        }
    }

    Text {
        visible: loader.status === Loader.Error
        anchors.verticalCenter: parent.verticalCenter
        text: "PLUGIN ERROR"
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.body
    }
}
