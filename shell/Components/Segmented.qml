import QtQuick
import qs.Core

// shadcn's segmented control (spec "Picker"): a `muted` group at `radiusMd`
// holding one segment per option, the selected one filled `background` behind
// a 1px `border`. The picker's DARK | LIGHT switcher is the first user.
//
// The control never takes focus of its own. The surface holding the keyboard
// owns the KeyCatcher and forwards Left/Right into step(), which is why
// `cursor` (the ring) is a plain property rather than an activeFocus read.
Item {
    id: root

    property var options: []
    property int index: 0
    property bool cursor: false

    // The gap between the group's edge and a segment. The concentric rule
    // (spec "Radius") takes the segment's own radius down by exactly this.
    property real padding: Theme.space.xxs

    signal changed(int index)

    readonly property int count: root.options ? root.options.length : 0
    readonly property int _segmentRadius: Math.max(Theme.radiusSm, Theme.radiusMd - root.padding)

    // Every segment is the width of the widest label, so the group reads as
    // one control rather than as labels of assorted lengths.
    readonly property real _segmentWidth: {
        var widest = 0;
        for (var i = 0; i < root.count; i++)
            widest = Math.max(widest, metrics.advanceWidth(String(root.options[i])));
        return Math.ceil(widest) + Theme.space.controlPaddingX * 2;
    }

    function select(next) {
        if (next < 0 || next >= root.count || next === root.index)
            return;
        root.index = next;
        root.changed(next);
    }

    // Clamped, not wrapped: the segments read as a row, and an arrow that
    // jumped from the last back to the first would move the selection the
    // opposite way to the key.
    function step(delta) {
        root.select(Math.max(0, Math.min(root.count - 1, root.index + delta)));
    }

    implicitWidth: root._segmentWidth * root.count + root.padding * 2
    implicitHeight: Theme.space.controlHeight

    FontMetrics {
        id: metrics
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.body
        font.weight: Theme.weight.medium
    }

    // The ring halo, drawn behind the group exactly as Cell and Button draw
    // it.
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
        color: Theme.color.muted
        border.width: root.cursor ? Theme.borderWidth : 0
        border.color: Theme.color.ring
    }

    Row {
        id: row
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 0

        Repeater {
            model: root.options

            delegate: Item {
                id: segment
                required property int index
                required property var modelData

                readonly property bool _on: segment.index === root.index

                width: root._segmentWidth
                height: row.height

                Rectangle {
                    anchors.fill: parent
                    visible: segment._on
                    radius: root._segmentRadius
                    color: Theme.color.background
                    border.width: Theme.borderWidth
                    border.color: Theme.color.border
                }

                Text {
                    anchors.centerIn: parent
                    text: String(segment.modelData)
                    color: segment._on ? Theme.color.foreground : Theme.color.mutedForeground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.select(segment.index)
                }
            }
        }
    }
}
