import QtQuick
import qs.Core
import "cursor.js" as Cursor

// shadcn's button (DESIGN.md §2), drawn as a `Box` over the table's own
// `button.<variant>` role: `default` and `destructive` carry a colour of
// their own, `outline` is transparent behind a border, `ghost` is
// transparent with no border at all, and `selected` is the segmented look
// `ButtonGroup` paints on the chosen option. What each of those looks like,
// and what the pointer does to it, is the theme's answer; this file states
// which role and which state it is in.
//
// `enabled` is QQuickItem's own: it gates the pointer target as well as
// dimming the button, so a disabled one neither hovers nor clicks.
Box {
    id: root

    property string variant: "default"
    property string text: ""
    // An icon name for Icon.qml, leading the label. Empty means no icon.
    property string icon: ""
    // The key that does what a click does, drawn after the label as a
    // keycap: a key is a value, so mono, a step down and dimmer than the
    // verb it answers for. Empty means no keycap.
    property string shortcut: ""
    property bool cursor: false
    property bool hovered: pointer.containsMouse

    // The concentric rule (spec "Radius"): a button nested inside a bordered
    // trough takes the outer radius minus the padding between them.
    // `radiusMd` is the free-standing case.
    radius: Theme.radiusMd

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
    // naming what this control does, after the group's own delay, dropped
    // the instant the pointer leaves. Empty (the default) means no tooltip.
    // Duplicated rather than shared because a QML type inherits from one
    // base and Cell and Button have nothing else in common.
    property string tooltipText: ""

    signal clicked()

    function _openTooltip() {
        if (!root.hovered || root.tooltipText === "")
            return;
        TooltipRegistry.show(root, root.tooltipText, "");
    }

    onHoveredChanged: {
        if (root.hovered)
            root._openTooltip();
        else
            TooltipRegistry.hide(root);
    }

    // Live while shown: a show for the control that already owns the card
    // updates the line without touching the delay, which also covers the one
    // case a text change IS an open, where the control had nothing to say
    // when the pointer arrived and now does. A control that runs out of
    // anything to say drops the card instead.
    onTooltipTextChanged: {
        if (root.tooltipText === "")
            TooltipRegistry.hide(root);
        else
            root._openTooltip();
    }

    // The role and the state the table answers. A variant carrying a colour
    // of its own blends toward `background` under the pointer and takes no
    // wash, which is the `tint` its hover and press states name; the three
    // that carry none take the ink wash instead. `selected` is deliberately
    // among those: its fill is `background`, and washing it is what keeps a
    // chosen option in a `ButtonGroup` reading as chosen while the pointer
    // sits on it.
    role: "button." + root.variant
    state: pointer.pressed ? "press" : root.hovered ? "hover" : "rest"
    box: Theme.withCursor(Theme.box(root.role, root.state), root._cursorRing, !root._haloOwned)

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

    // Whether something above this control draws the cursor halo for the
    // whole list it sits in (Panel.qml, M53 D4): one halo that travels
    // between rows needs there to be one of it, and only the halo is
    // suppressed, never the border swap that marks which row has it.
    // cursor.js carries the walk and why it runs when the row takes the
    // cursor rather than when it is built.
    property bool _haloOwned: false

    // Whether the ring draws for this button at all (DESIGN.md §1 "Ring"): the
    // list above it hands the ring to the keyboard and the wash to the
    // pointer, and a button with no such list above it draws both. cursor.js
    // carries the walk, resolved on the same hop `_haloOwned` is.
    property Item _ringOwner: null
    readonly property bool _cursorRing: root.cursor
        && (!root._ringOwner || root._ringOwner.cursorFromKeys)

    onCursorChanged: if (root.cursor) {
        root._haloOwned = Cursor.haloOwned(root);
        root._ringOwner = Cursor.ringOwner(root);
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

        Text {
            visible: root.shortcut !== ""
            anchors.verticalCenter: label.verticalCenter
            text: root.shortcut
            color: root._ink
            opacity: 0.6
            font.family: Theme.fontFamilyMono
            font.pixelSize: Theme.fontSize.caption
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
