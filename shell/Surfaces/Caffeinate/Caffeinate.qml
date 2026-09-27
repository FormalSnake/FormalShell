import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.Services

// Holds the Wayland idle inhibitor while IdleService.caffeinated is on.
// idle-inhibit-unstable-v1 ties an inhibitor to a surface and the compositor
// only honours it while that surface is mapped, so this maps a 1px
// transparent layer surface of its own rather than riding the bar, which
// unmaps under a fullscreen window. Hyprland counts a mapped layer surface
// that accepts input as inhibiting, which is why it keeps the default input
// region instead of an empty mask. Every ext-idle-notify listener that
// respects inhibitors then stays quiet: IdleService's own monitor, and an
// outside swayidle or hypridle.
//
// Hyprland (0.56) judges an inhibitor once, when it is created, and does not
// look again when a layer surface maps later. Quickshell creates it as soon
// as the wl_surface exists, before the first buffer, so it would be judged
// unmapped and ignored. It is enabled a second after the window is created
// instead, by which point the surface has mapped. Keying it off the
// window's frameSwapped was tried and never fired for this surface on the
// smoke rig.
Scope {
    id: root

    readonly property bool inhibiting: loader.active && loader.item !== null && loader.item.visible && loader.item.inhibitorEnabled

    LazyLoader {
        id: loader
        active: IdleService.caffeinated

        PanelWindow {
            id: win
            readonly property bool inhibitorEnabled: inhibitor.enabled

            color: "transparent"
            WlrLayershell.namespace: "formalshell:caffeinate"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors.top: true
            anchors.left: true
            implicitWidth: 1
            implicitHeight: 1

            IdleInhibitor {
                id: inhibitor
                window: win
                enabled: false
            }

            Timer {
                running: true
                interval: 1000
                onTriggered: inhibitor.enabled = true
            }
        }
    }
}
