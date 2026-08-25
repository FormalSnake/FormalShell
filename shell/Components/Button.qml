import QtQuick
import qs.Core

// shadcn's button (DESIGN.md §2). `variant` picks the resting treatment:
// `default` fills with `primary`, `destructive` fills with `destructive`,
// `outline` is transparent behind a 1px `border`, `ghost` is transparent
// with no border at all.
//
// `enabled` is QQuickItem's own: it gates the pointer target as well as
// dimming the button, so a disabled one neither hovers nor clicks.
Item {
    id: root

    property string variant: "default"
    property string text: ""
    // An icon name for Icon.qml, leading the label. Empty means no icon.
    property string icon: ""
    property bool cursor: false
    property bool hovered: pointer.containsMouse

    signal clicked()

    readonly property bool _filled: root.variant === "default" || root.variant === "destructive"
    readonly property color _fill: root.variant === "default"
        ? Theme.color.primary
        : root.variant === "destructive"
            ? Theme.color.destructive
            : "transparent"
    readonly property color _ink: root.variant === "default"
        ? Theme.color.primaryForeground
        : root.variant === "destructive"
            ? Theme.color.destructiveForeground
            : Theme.color.foreground

    implicitWidth: row.implicitWidth + Theme.space.controlPaddingX * 2
    implicitHeight: Theme.space.controlHeight
    opacity: root.enabled ? 1 : 0.5

    // The focus ring's outer halo, drawn behind the body exactly as Cell
    // draws it.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.ringWidth
        visible: root.cursor
        radius: Theme.radiusMd + Theme.ringWidth
        color: Theme.color.ring
        opacity: Theme.ringAlpha
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: root._fill
        // A filled variant has no border of its own, so the cursor's border
        // swap is the only thing that gives it one.
        border.width: (root.cursor || root.variant === "outline") ? Theme.borderWidth : 0
        border.color: root.cursor ? Theme.color.ring : Theme.color.border
        // A fill cannot take the `accent` hover layer without losing its own
        // colour, so it dims instead.
        opacity: (root._filled && root.hovered) ? 0.9 : 1

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.color.accent
        opacity: (!root._filled && root.hovered) ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        visible: pointer.pressed
        color: Theme.color.accent
        opacity: 0.8
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.space.iconGap

        Icon {
            visible: root.icon !== ""
            name: root.icon
            size: Theme.fontSize.body
            color: root._ink
            height: label.implicitHeight
        }

        Text {
            id: label
            text: root.text
            color: root._ink
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
