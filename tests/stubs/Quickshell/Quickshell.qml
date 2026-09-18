pragma Singleton
import QtQuick

// Test-only stand-in for the `Quickshell` singleton, which is native and so
// cannot load under plain qmltestrunner. Only what a component under test
// reaches for is here, and each answer is the honest one for a session with
// no icon theme at all: `iconPath` with `check` set answers "" for a name
// nothing carries, which is exactly what this returns for every name, so a
// card under test falls back to its own bell rather than to a stub picture.
QtObject {
    function iconPath(name, check) {
        return "";
    }
}
