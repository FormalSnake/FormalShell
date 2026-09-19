import QtQuick
import qs.Core
import "keys.js" as Keys

// One key, on its own cap: shadcn's `<Kbd>`, drawn by the table's `keycap`
// role. A key is a name (`Enter`, `Shift`, `Esc`, `K`) or an arrow, and an
// arrow is an icon, never a glyph. A chord is several of these side by side
// (Chord.qml), never one cap carrying a `+`.
//
// The ink is the table's (`keycap`'s own `ink`) when it names one, and the
// muted ink otherwise: a cap is a legend beside the words it answers for.
Box {
    id: root

    property string key: ""

    readonly property var _cap: Keys.cap(root.key)
    readonly property string text: root._cap.text
    readonly property string icon: root._cap.icon

    readonly property color _tableInk: root.box.ink
    readonly property color ink: root._tableInk.a > 0 ? root._tableInk : Theme.color.mutedForeground

    role: "keycap"
    implicitHeight: Theme.space.keycapHeight
    implicitWidth: Math.max(Theme.space.keycapHeight,
        (root.icon !== "" ? glyph.width : label.implicitWidth) + Theme.space.sm * 2)

    Text {
        id: label
        anchors.centerIn: parent
        visible: root.icon === ""
        text: root.text
        color: root.ink
        font.family: Theme.fontFamilyMono
        font.pixelSize: Theme.fontSize.caption
        font.weight: Theme.weight.medium
    }

    Icon {
        id: glyph
        anchors.centerIn: parent
        visible: root.icon !== ""
        name: root.icon !== "" ? root.icon : "circle-help"
        size: Theme.fontSize.caption
        color: root.ink
    }
}
