import QtQuick
import qs.Core
import "cursor.js" as Cursor

// shadcn's segmented control (spec "Picker"): the table's `trough` holding
// one segment per option, with its `segmented.chip` on the chosen one. The
// picker's DARK | LIGHT switcher is the first user.
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

    // The concentric rule (spec "Radius") measured off the trough the
    // segments actually sit in, floored at `radiusSm`.
    readonly property real _troughRadius: Theme.boxRadius(Theme.box("trough"), root.height)
    readonly property int _segmentRadius: Math.max(Theme.radiusSm, root._troughRadius - root.padding)

    // What the pointer paints on an unchosen segment: a segment is a ghost
    // button sitting in a trough, so it takes that role's own washes.
    readonly property color _hoverWash: Theme.box("button.ghost", "hover").wash || "transparent"
    readonly property color _pressWash: Theme.box("button.ghost", "press").wash || "transparent"

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


    // Whether something above this control draws the cursor halo for the
    // whole list it sits in (Panel.qml, M53 D4): one halo that travels
    // between rows needs there to be one of it. cursor.js carries the walk
    // and why it runs when the row takes the cursor rather than when it is
    // built.
    property bool _haloOwned: false

    onCursorChanged: if (root.cursor) root._haloOwned = Cursor.haloOwned(root);

    // The trough, with the cursor composed over it: the ring takes its
    // border, and the halo outside it belongs to whatever owns one.
    Box {
        anchors.fill: parent
        role: "trough"
        box: Theme.withCursor(Theme.box("trough"), root.cursor, !root._haloOwned)
    }

    // One selection, outside the Repeater (M53 D2): the chosen segment used
    // to be a fill inside each delegate switched on `visible`, so a Left or
    // Right arrow put the border down in the next place rather than moving
    // it there. Its x is the only thing the index decides, which is what
    // makes the travel a single Behavior.
    Box {
        id: selection
        role: "segmented.chip"
        visible: root.count > 0
        x: root.padding + root.index * root._segmentWidth
        y: root.padding
        width: root._segmentWidth
        height: root.height - root.padding * 2
        radius: root._segmentRadius

        Behavior on x {
            Anim { kind: "spatialFast" }
        }
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

                // An unhoverable segment was the one control in the shell
                // that took the hand cursor and answered nothing. The wash
                // and the ink lift are what shadcn's own tabs do to an
                // inactive trigger; the chosen one already states itself.
                Rectangle {
                    anchors.fill: parent
                    radius: root._segmentRadius
                    color: segmentPointer.pressed ? root._pressWash : root._hoverWash
                    opacity: (!segment._on && (segmentPointer.containsMouse || segmentPointer.pressed)) ? 1 : 0

                    Behavior on opacity {
                        Anim { kind: "effects" }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: String(segment.modelData)
                    color: (segment._on || segmentPointer.containsMouse)
                        ? Theme.color.foreground
                        : Theme.color.mutedForeground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                }

                MouseArea {
                    id: segmentPointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.select(segment.index)
                }
            }
        }
    }
}
