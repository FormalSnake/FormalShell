import QtQuick
import qs.Core

// shadcn's button (DESIGN.md §2). `variant` picks the resting treatment:
// `default` fills with `primary`, `destructive` fills with `destructive`,
// `outline` is transparent behind a 1px `border`, `ghost` is transparent
// with no border at all, `selected` fills with `background` behind a 1px
// `border` (the segmented look `ButtonGroup` paints on the chosen option).
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

    // The concentric rule (spec "Radius"): a button nested inside a bordered
    // trough takes the outer radius minus the padding between them.
    // `radiusMd` is the free-standing case.
    property int radius: Theme.radiusMd

    // A ceiling for the label, for a button whose width its owner decides
    // (`ButtonGroup` divides its trough evenly). -1 leaves the label at its
    // natural width, which is what keeps a free-standing button's implicit
    // width from depending on the width that implicit width asks for.
    property real labelBudget: -1

    // The gutter either side of the content. A button inside a trough takes
    // less than a free-standing one: the trough's own padding already sits
    // outside it, and at `controlPaddingX` a three-option group on a
    // `Default`-width panel elides "Performance" by two characters.
    property real paddingX: Theme.space.controlPaddingX

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

    // A variant carrying a colour of its own. `selected` is deliberately not
    // one: its fill is `background`, which the ink wash sits on exactly as it
    // sits on a ghost, and washing it is what keeps a chosen option in a
    // `ButtonGroup` reading as chosen while the pointer is on it.
    readonly property bool _solid: root.variant === "default"
        || root.variant === "destructive"
    readonly property color _fill: root.variant === "default"
        ? Theme.color.primary
        : root.variant === "destructive"
            ? Theme.color.destructive
            : root.variant === "selected"
                ? Theme.color.background
                : "transparent"
    readonly property color _ink: root.variant === "default"
        ? Theme.color.primaryForeground
        : root.variant === "destructive"
            ? Theme.color.destructiveForeground
            : Theme.color.foreground

    implicitWidth: row.implicitWidth + root.paddingX * 2
    implicitHeight: Theme.space.controlHeight
    opacity: root.enabled ? 1 : 0.5

    // What is left of the budget once the icon and the gap beside it have
    // taken their share.
    readonly property real _labelWidth: {
        if (root.labelBudget < 0)
            return label.implicitWidth;
        var taken = root.paddingX * 2;
        if (root.icon !== "")
            taken += Theme.fontSize.body + (root.text !== "" ? Theme.space.iconGap : 0);
        return Math.max(0, Math.min(label.implicitWidth, root.labelBudget - taken));
    }

    // The focus ring's outer halo, drawn behind the body exactly as Cell
    // draws it.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.ringWidth
        visible: root.cursor
        radius: root.radius + Theme.ringWidth
        color: Theme.color.ring
        opacity: Theme.ringAlpha
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        // `default` and `destructive` carry no border of their own, so the
        // cursor's border swap is the only thing that gives them one;
        // `outline` and `selected` are bordered at rest and the swap only
        // recolours what is already there.
        border.width: (root.cursor || root.variant === "outline" || root.variant === "selected")
            ? Theme.borderWidth : 0
        border.color: root.cursor ? Theme.color.ring : Theme.color.border
        // A variant carrying its own colour blends toward `background` and
        // stays opaque (shadcn's `hover:bg-primary/90`). Dropping this
        // rectangle's opacity instead, which is what `/90` means on an opaque
        // page, makes a primary button on a translucent panel see-through and
        // the wallpaper reads straight through its label.
        color: !root._solid
            ? root._fill
            : pointer.pressed
                ? Theme.pressFilled(root._fill)
                : root.hovered
                    ? Theme.hoverFilled(root._fill)
                    : root._fill

        Behavior on color {
            ColorAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
    }

    // The wash every other variant takes, over whatever is behind it: an
    // opaque `accent` chip on a panel drawn at `surfaceOpacity` lands at a
    // delta the wallpaper decides (Theme.hoverFill). Press is the same wash
    // one step on, and lands without a fade, since the pointer is already
    // there.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: pointer.pressed ? Theme.pressFill : Theme.hoverFill
        opacity: (!root._solid && (root.hovered || pointer.pressed)) ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
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
            width: root._labelWidth
            elide: root.labelBudget >= 0 ? Text.ElideRight : Text.ElideNone
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
