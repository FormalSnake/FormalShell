import QtQuick
import qs.Core
import qs.Components
import "../../Menu/rowsync.js" as RowSync

// The command palette's footer (M43 D2): one `caption` `mutedForeground`
// line reading `↑↓ move  ⏎ open  esc back`. No key caps, no fills, no
// frame: the footer is a legend, and the only loud thing in a modal surface
// is the cursor row.
//
// Chords are values, so each key is mono and its verb is sans
// (spec "Type"). Menu/actions.js decides the wording; this file only lays
// it out. The primary verb is the one segment that answers a click, doing
// exactly what Enter does; every hint stays inert.
Item {
    id: root

    property var primary: null
    property var hints: []

    signal primaryActivated

    // The verb sits after the move hint, so the line reads move, act,
    // leave. Sized off the whole line rather than off the verb alone: the
    // verb disappears whenever the cursor sits on something that can't be
    // activated, and a footer that changed height as the cursor moved would
    // resize the card under it.
    readonly property var _segments: {
        var out = (root.hints || []).map(function (h) {
            return { key: h.key, label: h.label, primary: false };
        });
        if (!root.primary)
            return out;
        out.splice(out.length > 0 ? 1 : 0, 0, {
            key: root.primary.key,
            label: root.primary.label,
            primary: true
        });
        return out;
    }

    // --- The keyed segment model (M53 D2/D6) -----------------------------
    //
    // `_segments` is a fresh array on every cursor move, and a fresh array
    // handed to a Repeater is a model reset: the positioner sees every
    // segment destroyed and every one rebuilt where it stood, so nothing in
    // the line can travel and an `add` transition would flash the whole
    // footer on each arrow key. Synced by what a segment says instead, the
    // ones that did not change keep their items and slide when the verb
    // beside them grows or goes.
    //
    // A segment's identity IS its text: two segments reading the same thing
    // are the same segment, and one whose verb changed is a different one
    // that arrives where the old one stood.
    ListModel {
        id: segmentModel
    }

    function _segmentId(s) {
        return s.key + "\t" + s.label;
    }

    readonly property var _segmentsById: {
        var by = {};
        for (var i = 0; i < root._segments.length; i++)
            by[root._segmentId(root._segments[i])] = root._segments[i];
        return by;
    }

    // What a delegate draws for the frame between an id leaving the model
    // and the Repeater destroying its item.
    readonly property var _blankSegment: ({ key: "", label: "", primary: false })

    on_SegmentsChanged: root._syncSegments()
    // The first fill, for the case where the handler above has already run
    // by the time this object is complete. A second sync over an unchanged
    // line is no ops at all, so calling both costs nothing.
    Component.onCompleted: root._syncSegments()

    function _syncSegments() {
        var ids = [];
        var i;
        for (i = 0; i < root._segments.length; i++)
            ids.push(root._segmentId(root._segments[i]));
        var held = [];
        for (i = 0; i < segmentModel.count; i++)
            held.push(segmentModel.get(i).segmentId);
        // No reset threshold worth the name on a line of four: a change
        // bigger than the line itself is still one line being replaced.
        var plan = RowSync.plan(held, ids, ids.length + held.length);
        if (plan.reset) {
            segmentModel.clear();
            for (i = 0; i < ids.length; i++)
                segmentModel.append({ segmentId: ids[i] });
            return;
        }
        for (i = 0; i < plan.ops.length; i++) {
            var op = plan.ops[i];
            if (op.op === "remove")
                segmentModel.remove(op.index);
            else if (op.op === "insert")
                segmentModel.insert(op.index, { segmentId: op.id });
            else
                segmentModel.move(op.from, op.to, 1);
        }
    }

    implicitHeight: line.implicitHeight
    height: root.implicitHeight

    Row {
        id: line
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.md

        move: MoveTransition {}

        Repeater {
            model: segmentModel

            delegate: Item {
                id: segment
                required property string segmentId
                readonly property var spec: root._segmentsById[segment.segmentId] || root._blankSegment

                implicitWidth: body.implicitWidth
                implicitHeight: body.implicitHeight

                // The arrival is a Behavior on an inner item rather than the
                // positioner's own `add` transition: a Transition animating an
                // item's opacity takes that property over, and a run cancelled
                // by the next sync can leave the segment sitting at whatever
                // opacity it had reached. Nothing binds this item's opacity,
                // so the Behavior owns it outright.
                Item {
                    id: body
                    property bool entered: false

                    implicitWidth: pair.implicitWidth
                    implicitHeight: pair.implicitHeight
                    opacity: body.entered ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.motion.standard
                            easing.type: Theme.motion.easing
                        }
                    }
                    Component.onCompleted: body.entered = true

                    Row {
                        id: pair
                        spacing: Theme.space.xs

                        Text {
                            text: segment.spec.key
                            color: Theme.color.mutedForeground
                            font.family: Theme.fontFamilyMono
                            font.pixelSize: Theme.fontSize.caption
                            font.capitalization: Font.AllLowercase
                        }

                        Text {
                            text: segment.spec.label
                            color: Theme.color.mutedForeground
                            font.family: Theme.fontFamilySans
                            font.pixelSize: Theme.fontSize.caption
                            font.capitalization: Font.AllLowercase
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: segment.spec.primary === true
                    hoverEnabled: enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.primaryActivated()
                }
            }
        }
    }
}
