import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Plugins
import "../../Plugins/manifest.js" as Manifest

// Host for a kind:"overlay" plugin: the summoned centered-card shape
// Menu.qml/Osd.qml already have, opened on the focused output rather than
// living on every screen. The plugin supplies a plain Item; this file owns
// every window property.
//
// The plugin never declares a layer-shell window of its own, and this is not
// a stylistic preference: Panel.qml:126-134 documents that a
// permanently-Exclusive surface makes Hyprland route every pointer event on
// every output to it, killing clicks shell-wide. Keeping
// layer/exclusiveZone/keyboardFocus here means a third-party file cannot
// reach them.
//
// Overlays join PanelRegistry's mutual-exclusion set (the same four-line
// handshake Panel.qml:81-96 performs, done by hand because this is not a
// Panel): two top-level surfaces fighting for the same screen reads as a bug,
// which is exactly why Toasts.qml already suppresses itself for the Center.
PanelWindow {
    id: root

    required property var modelData

    readonly property var plugin: root.modelData

    property bool isOpen: false

    readonly property bool loadFailed: contentLoader.status === Loader.Error

    function open() {
        if (PanelRegistry.current && PanelRegistry.current !== root)
            PanelRegistry.current.close();
        PanelRegistry.current = root;
        root.isOpen = true;
        Qt.callLater(function () { backdrop.forceActiveFocus(); });
    }

    function close() {
        root.isOpen = false;
        if (PanelRegistry.current === root)
            PanelRegistry.current = null;
    }

    function toggle() {
        if (root.isOpen) root.close();
        else root.open();
    }

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    Component.onCompleted: PluginService.registerSurface(Manifest.surfaceKey(root.plugin), root)
    Component.onDestruction: PluginService.unregisterSurface(Manifest.surfaceKey(root.plugin))

    screen: root._screen
    // Held visible through the exit fade (DESIGN.md §4), same as every other
    // summoned surface: close() drops isOpen, the card fades, then the window
    // unmaps. Keyboard focus releases on isOpen itself so nothing types into
    // a fading-out overlay.
    visible: root.isOpen || card.opacity > 0
    color: "transparent"

    WlrLayershell.namespace: "formalshell:plugin-overlay"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    // Exclusive, matching Menu.qml rather than Panel.qml's OnDemand prime: a
    // summoned centered card has no DismissTwins catchers on other outputs to
    // starve of pointer events, which is the one thing that forced the prime
    // dance there.
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    MouseArea {
        id: backdrop
        anchors.fill: parent
        enabled: root.isOpen
        focus: true
        Keys.onEscapePressed: root.close()
        onClicked: root.close()

        Item {
            id: card
            anchors.fill: parent

            // Enter/exit (DESIGN.md §4): fade plus a short slide, one
            // animated scalar so a resummon mid-exit reverses in place.
            opacity: root.isOpen ? 1 : 0
            transform: Translate { y: (card.opacity - 1) * Theme.motion.slide }

            Behavior on opacity {
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
            }

            // Declared before the content so the plugin's own interactive
            // items sit on top of it: clicks the plugin handles never reach
            // here, clicks anywhere inside its footprint that it ignores are
            // swallowed, and only clicks outside it fall through to the
            // backdrop's own close. Panel.qml's frame does exactly this.
            MouseArea {
                anchors.fill: contentLoader
                onClicked: {}
            }

            // Sized by the loaded item, never the other way round: the shell
            // cannot know how big a plugin's card wants to be, and forcing a
            // size on it would make every overlay full-screen.
            Loader {
                id: contentLoader
                anchors.centerIn: parent
                active: root.plugin ? (root.plugin.keepLoaded || root.isOpen) : false
                source: root.plugin ? root.plugin.entryUrl : ""

                onStatusChanged: {
                    if (contentLoader.status === Loader.Error && root.plugin)
                        PluginService.reportError(root.plugin.id, "entry failed to load");
                }
            }

            // The one empty state in the shell that keeps a card, and the
            // ladder's own rung-5 clause is why (DESIGN.md §1): this window
            // is transparent and full-screen, so the caption sits on the raw
            // wallpaper with nothing behind it. Every other empty state in
            // the shell is unboxed because it sits inside a surface that is
            // already a card; this one has no surface at all.
            Card {
                visible: root.loadFailed
                anchors.centerIn: parent
                radius: Theme.radiusMd

                SectionLabel {
                    text: "PLUGIN ERROR"
                }
            }
        }
    }
}
