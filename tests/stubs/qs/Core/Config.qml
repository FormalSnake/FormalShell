pragma Singleton
import QtQuick

// Test-only stand-in for shell/Core/Config.qml, which reads settings.json
// through Quickshell and so cannot load under plain qmltestrunner. Every
// lookup answers the caller's own default, which is what an install with no
// settings.json gets, so a component instantiated against this stub behaves
// as it does out of the box.
QtObject {
    function get(path, fallback) {
        return fallback;
    }
}
