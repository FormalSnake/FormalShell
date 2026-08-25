pragma Singleton
import QtQuick

// Test-only stand-in for shell/Core/State.qml, which persists through
// Quickshell's FileView and so cannot load under plain qmltestrunner. Every
// value is the empty default a fresh install starts from; a test that needs a
// different one writes it, since nothing here is readonly.
QtObject {
    property string clockFormat: ""

    function setClockFormat(format) {
        clockFormat = format;
    }
}
