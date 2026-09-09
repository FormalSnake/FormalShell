pragma Singleton
import QtQuick

// Test-only stand-in for shell/Core/TooltipRegistry.qml, which is a
// Quickshell Singleton and so cannot load under plain qmltestrunner. No test
// drives a real tooltip surface (the card is a layer-shell window; its own
// state machine is TooltipGroup.qml, which tst_tooltip_group.qml drives
// head-on), so this exists to keep the hover paths in Cell.qml and
// Button.qml resolvable when a test sets `hovered` on one.
QtObject {
    property var hosts: []

    function addHost(host) {}
    function removeHost(host) {}
    function show(item, text, barEdge) {}
    function hide(item) {}
}
