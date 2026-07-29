pragma Singleton
import QtQuick
import Quickshell

// Shared drawer-expand state for the bar's SNI tray (M10 Task 1). Bar.qml is
// instantiated once per screen (Variants over Quickshell.screens), but
// Quickshell.Services.SystemTray's item list is one global thing — the
// overflow drawer follows suit rather than forking per monitor. TrayIpc has
// no per-screen Tray.qml instance of its own to reach into, so this
// singleton is the one place both the widget's own overflow-cell click and
// `qs ipc call tray expand/collapse` (the smoke rig's stand-in for a
// synthetic pointer click, which doesn't exist here) can act on.
Singleton {
    property bool drawerExpanded: false

    function toggleDrawer() {
        drawerExpanded = !drawerExpanded;
    }

    function collapseDrawer() {
        drawerExpanded = false;
    }
}
