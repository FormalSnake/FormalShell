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

    // Measured off the output rather than off this window: the window is
    // unmapped while the overlay is closed, and a card placed off a window
    // with no size yet would jump to the middle a frame after the open.
    readonly property real _outputWidth: root.width > 0 ? root.width : (root._screen ? root._screen.width : 0)
    readonly property real _outputHeight: root.height > 0 ? root.height : (root._screen ? root._screen.height : 0)

    // The card is as big as what it holds: the shell cannot know how big a
    // plugin's overlay wants to be, and forcing a size on it would make every
    // one of them full screen. A plugin whose entry failed to load leaves the
    // caption below as the only thing to measure.
    readonly property real _cardWidth: (root.loadFailed ? errorLabel.implicitWidth : contentLoader.width)
        + Theme.space.panelPadding * 2
    readonly property real _cardHeight: (root.loadFailed ? errorLabel.implicitHeight : contentLoader.height)
        + Theme.space.panelPadding * 2

    // And what the card is drawn at (Components/SizeMorph.qml, M57 D7). The
    // two above are what the plugin's own item measures, which arrives after
    // the overlay is up and changes again whenever the plugin relays itself
    // out: the card travels to each of those instead of stepping to it.
    readonly property real _morphWidth: morphWidth.value
    readonly property real _morphHeight: morphHeight.value

    SizeMorph {
        id: morphWidth
        target: root._cardWidth
        open: root.isOpen
        mapped: root.backingWindowVisible
    }

    SizeMorph {
        id: morphHeight
        target: root._cardHeight
        open: root.isOpen
        mapped: root.backingWindowVisible
    }

    screen: root._screen
    // Held visible through the exit (DESIGN.md §1 Motion), same as
    // every other summoned surface: close() drops isOpen, the drawer's own
    // Behavior runs its pose back to 0, and only then does the window
    // unmap. Keyboard focus releases on isOpen itself so nothing types into
    // a leaving overlay.
    visible: drawer.presence.shown
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

        // The modal scrim (Components/Scrim.qml): on the drawer's own pose,
        // and off the band the top line belongs to while the card is still
        // budding out of it.
        Scrim {
            anchors.fill: parent
            drawer: drawer
        }

        // Everything from the top line to the card's own padding is the
        // drawer's (Components/Drawer.qml, M57 D5): a plugin's overlay comes
        // out of the same line the launcher does, on the same clock, and is a
        // plain card holding whatever the plugin drew once it has let go.
        Drawer {
            id: drawer
            anchors.fill: parent
            owner: root
            open: root.isOpen
            mapped: root.backingWindowVisible
            edge: "top"
            screen: root._screen
            rect: Qt.rect(Math.round((root._outputWidth - root._morphWidth) / 2),
                Math.round((root._outputHeight - root._morphHeight) / 2),
                root._morphWidth, root._morphHeight)
            moving: morphWidth.running || morphHeight.running

            Loader {
                id: contentLoader
                anchors.centerIn: parent
                // The card carries every size change inside it (M53 D2), so a
                // control the plugin drew that would animate its own height
                // lays out at the target and lets the card travel to it.
                // cursor.js documents the walk this is read through.
                property bool ownsSizeMorph: true
                // Held loaded for as long as the card is on screen, not just
                // while it is open: the card is as big as what it holds, and
                // unloading on close() would collapse it to its own padding
                // half way through the exit.
                active: root.plugin ? (root.plugin.keepLoaded || drawer.presence.shown) : false
                source: root.plugin ? root.plugin.entryUrl : ""

                onStatusChanged: {
                    if (contentLoader.status === Loader.Error && root.plugin)
                        PluginService.reportError(root.plugin.id, "entry failed to load");
                }
            }

            // Unboxed, like every other empty state in the shell (DESIGN.md
            // §1's ladder, rung 5): the drawer around it is already the card.
            // The load outcome lands after the overlay is up, so this arrives
            // as a content change on an open surface (M53 D3) rather than a
            // caption popping into the middle of it.
            SectionLabel {
                id: errorLabel
                anchors.centerIn: parent
                visible: errorLabel.opacity > 0
                opacity: root.loadFailed ? 1 : 0
                Behavior on opacity {
                    Anim { kind: "effects" }
                }
                text: "PLUGIN ERROR"
            }
        }
    }
}
