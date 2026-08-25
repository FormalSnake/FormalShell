import QtQuick
import qs.Core

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

    implicitHeight: line.implicitHeight
    height: root.implicitHeight

    Row {
        id: line
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.md

        Repeater {
            model: root._segments

            delegate: Item {
                id: segment
                required property var modelData

                implicitWidth: pair.implicitWidth
                implicitHeight: pair.implicitHeight

                Row {
                    id: pair
                    spacing: Theme.space.xs

                    Text {
                        text: segment.modelData.key
                        color: Theme.color.mutedForeground
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSize.caption
                        font.capitalization: Font.AllLowercase
                    }

                    Text {
                        text: segment.modelData.label
                        color: Theme.color.mutedForeground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.caption
                        font.capitalization: Font.AllLowercase
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: segment.modelData.primary === true
                    hoverEnabled: enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.primaryActivated()
                }
            }
        }
    }
}
