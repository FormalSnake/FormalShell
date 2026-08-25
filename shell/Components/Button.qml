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

    // Hover tooltip, the same contract Cell.qml carries: one short line
    // naming what this control does, after Tooltip.qml's own delay, dropped
    // the instant the pointer leaves. Empty (the default) means no tooltip.
    // Duplicated rather than shared because a QML type inherits from one
    // base and Cell and Button have nothing else in common.
    property string tooltipText: ""

    signal clicked()

    function _openTooltip() {
        if (!root.hovered || root.tooltipText === "")
            return;
        tooltipLoader.active = true;
        tooltipLoader.item.anchorItem = root;
        tooltipLoader.item.text = root.tooltipText;
        tooltipLoader.item.show();
    }

    onHoveredChanged: {
        if (root.hovered)
            root._openTooltip();
        else if (tooltipLoader.item)
            tooltipLoader.item.hide();
    }

    // Live while shown, never re-opened: a re-open would restart the show
    // delay and blink the card on every change. The else branch covers the
    // one case a text change IS an open, where the control had nothing to
    // say when the pointer arrived and now does.
    onTooltipTextChanged: {
        if (tooltipLoader.item)
            tooltipLoader.item.text = root.tooltipText;
        else
            root._openTooltip();
    }

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

    // Loaded by URL and activated imperatively, for the reasons Cell.qml's
    // own loader spells out: Tooltip.qml pulls in Quickshell, which
    // tests/tst_button.qml has no module for, and the load has to have
    // completed by the next statement in _openTooltip().
    Loader {
        id: tooltipLoader
        active: false
        source: "Tooltip.qml"
    }
}
