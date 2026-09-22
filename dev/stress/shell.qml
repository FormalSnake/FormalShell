import QtQuick
import Quickshell

// Icon lookups on the main thread while the pixmap reader thread keeps
// resolving image://icon/ loads of its own: 80 images cycling through 300
// theme names with no pixmap cache, against a loop of check=true lookups.
// Prints MISSES <n> of <lookups> and quits.
ShellRoot {
    id: root
    property var names: {
        var out = [];
        for (var i = 0; i < 300; i++)
            out.push("stress-" + i);
        return out;
    }
    property int offset: 0
    property int misses: 0
    property int lookups: 0
    property bool async: Quickshell.env("STRESS_ASYNC") === "1"

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 400
        Grid {
            columns: 10
            Repeater {
                model: 80
                delegate: Image {
                    required property int index
                    width: 32
                    height: 32
                    asynchronous: root.async
                    cache: false
                    sourceSize.width: 32
                    sourceSize.height: 32
                    source: "image://icon/" + root.names[(index * 7 + root.offset) % root.names.length]
                }
            }
        }
    }

    Timer {
        interval: 8
        repeat: true
        running: true
        onTriggered: root.offset++
    }

    Timer {
        interval: 3
        repeat: true
        running: true
        onTriggered: {
            for (var k = 0; k < 60; k++) {
                var name = root.names[root.lookups % root.names.length];
                root.lookups++;
                if (Quickshell.iconPath(name, true) === "")
                    root.misses++;
            }
        }
    }

    Timer {
        interval: 4000
        running: true
        onTriggered: {
            console.log("MISSES", root.misses, "of", root.lookups);
            Qt.quit();
        }
    }
}
