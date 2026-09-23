import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components

// Radio Atlas's host: the plugin overlay's summoned centred card
// (Surfaces/Plugins/PluginOverlay.qml), holding RadioAtlas.qml. Opened from
// the media panel's radio button, `panel toggle radio` and `radio open`.
// The atlas is built on the first open and kept after it, so a reopen lands
// on the globe where it was left rather than parsing the country outlines
// again.
PanelWindow {
    id: root

    property bool isOpen: false
    property bool _built: false

    function open() {
        if (PanelRegistry.current && PanelRegistry.current !== root)
            PanelRegistry.current.close();
        PanelRegistry.current = root;
        root._built = true;
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

    // Measured off the output rather than off this window: the window is
    // unmapped while the overlay is closed, and a card placed off a window
    // with no size yet would jump to the middle a frame after the open.
    readonly property real _outputWidth: root.width > 0 ? root.width : (root._screen ? root._screen.width : 0)
    readonly property real _outputHeight: root.height > 0 ? root.height : (root._screen ? root._screen.height : 0)

    readonly property real _cardWidth: contentLoader.width + Theme.space.panelPadding * 2
    readonly property real _cardHeight: contentLoader.height + Theme.space.panelPadding * 2

    // What the card is drawn at (Components/SizeMorph.qml, M57 D7): the atlas
    // measures itself after the overlay is up, and the card travels there.
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

    WlrLayershell.namespace: "formalshell:radio"
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
        // drawer's (Components/Drawer.qml, M57 D5): the atlas comes out of the
        // same line the launcher does, on the same clock.
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
                // cursor.js documents the walk this is read through.
                property bool ownsSizeMorph: true
                active: root._built

                sourceComponent: Component {
                    RadioAtlas {
                        host: root
                    }
                }
            }
        }
    }
}
