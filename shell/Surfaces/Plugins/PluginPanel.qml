import QtQuick
import qs.Core
import qs.Components
import qs.Plugins
import "../../Plugins/manifest.js" as Manifest

// Host for a kind:"panel" plugin. Being a real Panel is the whole point: the
// card frame, the title band, the dog-ear, the content gutter and its edge
// erasers, the enter/exit fade, Escape, click-outside, DismissTwins and
// PanelRegistry mutual exclusion are all inherited rather than reimplemented,
// so a plugin popout is indistinguishable from a builtin one.
//
// The plugin never declares a window of its own. Its entry root is a plain
// Item loaded into this card, and WlrLayershell.layer/exclusiveZone/
// keyboardFocus stay shell-side: Panel.qml:126-134 documents what a
// permanently-Exclusive surface does to pointer routing compositor-wide, and
// a third-party file getting that wrong would brick the session.
//
// `keepLoaded` gates the CONTENT only. The window exists either way, because
// it has to be in PanelIpc's registry to be openable at all.
Panel {
    id: root

    required property var modelData

    readonly property var plugin: root.modelData

    // Load failures are honest, never a blank card: the surface still opens
    // and still closes on Escape, with one dim row saying so.
    readonly property bool loadFailed: contentLoader.status === Loader.Error

    panelTitle: root.plugin ? root.plugin.name : ""

    panelWidth: {
        switch (root.plugin ? root.plugin.width : "default") {
        case "narrow": return Theme.space.popupWidthNarrow;
        case "wide": return Theme.space.popupWidthWide;
        case "menu": return Theme.space.popupWidthMenu;
        }
        return Theme.space.popupWidthDefault;
    }

    Component.onCompleted: PluginService.registerSurface(Manifest.surfaceKey(root.plugin), root)
    Component.onDestruction: PluginService.unregisterSurface(Manifest.surfaceKey(root.plugin))

    // Gallery.qml's own gate: with keepLoaded false, closing destroys the
    // plugin's content and its state, and a plugin that polls or holds scroll
    // position opts out by asking for keepLoaded in its manifest.
    Loader {
        id: contentLoader
        width: parent.width
        active: root.plugin ? (root.plugin.keepLoaded || root.isOpen) : false
        source: root.plugin ? root.plugin.entryUrl : ""

        onStatusChanged: {
            if (contentLoader.status === Loader.Error && root.plugin)
                PluginService.reportError(root.plugin.id, "entry failed to load");
        }
    }

    // Unboxed, and inset to where a row's text sits rather than to where a
    // row's border would (DESIGN.md §1 Padding).
    SectionLabel {
        visible: root.loadFailed
        leftPadding: Theme.space.controlPaddingX
        text: "PLUGIN ERROR"
    }
}
