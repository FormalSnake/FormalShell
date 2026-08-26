import QtQuick
import qs.Core

// Omarchy's row of panel buttons, drawn as shadcn (DESIGN.md §2, M48 D1):
// one `muted` trough at `radiusMd` holding a `Button` per option, each ghost
// inside it so the trough carries the chrome and the row reads as one
// control. `exclusive` paints the button at `index` the way a segmented
// control paints its selected segment (`background` behind a 1px `border`);
// a non-exclusive group is a plain row of actions, and an option carrying
// `active: true` takes the `primary` fill a toggle's on-state does.
//
// Controlled, never self-writing, the same division `Switch.qml` documents:
// `index` is an input the owner binds to whatever it already stores
// (PowerPanel binds the live PowerProfiles profile), and a press emits
// `changed` with the index the owner should write. Flipping `index` here
// would break that binding on the first press.
//
// No keys of its own either. The surface holding the keyboard owns the
// `KeyCatcher` and drives `cursorIndex`/`step()`/`activate()`, which is why
// `cursor` (the ring) is a plain property rather than an activeFocus read.
// The ring halo is exactly `padding` wide when `padding` is `ringWidth`, so
// it lands inside the trough rather than outside the group.
//
// `options` entries are `{ icon, label, value, enabled, active }`, every
// field optional: `icon` is a name for Icon.qml, `label` a sans string,
// `value` whatever the owner wants back out of `valueAt()`, `enabled`
// defaults true and `active` false.
Item {
    id: root

    property var options: []
    property bool exclusive: true
    property int index: 0
    property int cursorIndex: 0
    property bool cursor: false

    // The gap between the trough's edge and a button, which is also the gap
    // between two buttons. The concentric rule (spec "Radius") takes the
    // button's own radius down by exactly this.
    property real padding: Theme.space.xs

    signal changed(int index)
    signal pressed(int index)
    // Pointer enter/leave on one button, so a surface carrying its own
    // keyboard cursor can move it under the mouse the way its rows already
    // do (MediaPanel's transport, PowerPanel's profiles).
    signal hovered(int index, bool isHovered)

    readonly property int count: root.options ? root.options.length : 0
    readonly property int _buttonRadius: Math.max(Theme.radiusSm, Theme.radiusMd - root.padding)

    function optionAt(i) {
        return (i >= 0 && i < root.count) ? root.options[i] : null;
    }

    function labelAt(i) {
        var o = root.optionAt(i);
        return (o && o.label !== undefined) ? String(o.label) : "";
    }

    function iconAt(i) {
        var o = root.optionAt(i);
        return (o && o.icon !== undefined) ? String(o.icon) : "";
    }

    function enabledAt(i) {
        var o = root.optionAt(i);
        return o ? o.enabled !== false : false;
    }

    function activeAt(i) {
        var o = root.optionAt(i);
        return !!(o && o.active);
    }

    function valueAt(i) {
        var o = root.optionAt(i);
        return o ? o.value : undefined;
    }

    // Every press reports through `pressed`; only a press that moves an
    // exclusive group's selection also reports through `changed`, so a
    // consumer that just wants "a button was hit" (the media transport)
    // takes one signal and a picker takes the other.
    function press(i) {
        if (!root.enabledAt(i))
            return;
        root.pressed(i);
        if (root.exclusive && i !== root.index)
            root.changed(i);
    }

    // What Enter on the owning surface presses.
    function activate() {
        root.press(root.cursorIndex);
    }

    // Clamped, not wrapped: the buttons read as a row, and an arrow that
    // jumped from the last back to the first would move the cursor the
    // opposite way to the key. Same rule as Segmented's own step().
    function step(delta) {
        if (root.count <= 0)
            return;
        root.cursorIndex = Math.max(0, Math.min(root.count - 1, root.cursorIndex + delta));
    }

    // The widest button's natural width, so every button in the group is the
    // same size and the row reads as one control rather than as labels of
    // assorted lengths. Measured here rather than read off the buttons: a
    // button's own implicit width would then depend on the width this hands
    // it, which is a binding loop.
    readonly property real _naturalButtonWidth: {
        var widest = 0;
        for (var i = 0; i < root.count; i++) {
            var content = 0;
            var label = root.labelAt(i);
            var icon = root.iconAt(i);
            if (label !== "")
                content += Math.ceil(metrics.advanceWidth(label));
            if (icon !== "")
                content += Theme.fontSize.body + (label !== "" ? Theme.space.iconGap : 0);
            widest = Math.max(widest, content);
        }
        return Math.max(root._buttonHeight, widest + root._buttonPaddingX * 2);
    }

    // The trough's own padding sits outside every button, so the buttons
    // take the tighter gutter (Button's `paddingX`).
    readonly property real _buttonPaddingX: Theme.space.md

    readonly property real _buttonHeight: Math.max(0, root.height - root.padding * 2)
    readonly property real _buttonWidth: root.count > 0
        ? Math.max(0, (buttonRow.width - root.padding * (root.count - 1)) / root.count)
        : 0

    implicitWidth: root.count > 0
        ? root._naturalButtonWidth * root.count + root.padding * (root.count + 1)
        : 0
    implicitHeight: Theme.space.controlHeight + root.padding * 2

    FontMetrics {
        id: metrics
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.body
        font.weight: Theme.weight.medium
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.color.muted
    }

    Row {
        id: buttonRow
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.padding

        Repeater {
            model: root.options

            delegate: Button {
                id: groupButton
                required property int index

                width: root._buttonWidth
                height: root._buttonHeight
                radius: root._buttonRadius
                paddingX: root._buttonPaddingX
                labelBudget: root._buttonWidth
                variant: (root.exclusive && groupButton.index === root.index)
                    ? "selected"
                    : (!root.exclusive && root.activeAt(groupButton.index) ? "default" : "ghost")
                icon: root.iconAt(groupButton.index)
                text: root.labelAt(groupButton.index)
                enabled: root.enabledAt(groupButton.index)
                cursor: root.cursor && groupButton.index === root.cursorIndex
                onClicked: root.press(groupButton.index)
                onHoveredChanged: root.hovered(groupButton.index, groupButton.hovered)
            }
        }
    }
}
