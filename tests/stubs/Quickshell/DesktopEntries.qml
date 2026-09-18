pragma Singleton
import QtQuick

// Test-only stand-in for the `DesktopEntries` singleton (see Quickshell.qml
// beside this): no entries at all, which is what an isolated test session
// has, so both lookups miss and the caller's own fallback runs.
QtObject {
    function byId(id) {
        return null;
    }

    function heuristicLookup(name) {
        return null;
    }
}
