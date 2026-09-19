import QtQuick
import qs.Core
import "keys.js" as Keys

// Keys pressed together, or the keys a legend offers side by side, one
// Keycap each: `keys` takes a chord string (`Super+Alt+Space`) or an array
// (`["Up", "Down"]`).
Row {
    id: root

    property var keys: []
    readonly property var list: Keys.split(root.keys)

    spacing: Theme.space.xxs

    Repeater {
        model: root.list

        delegate: Keycap {
            required property var modelData
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            key: modelData
        }
    }
}
