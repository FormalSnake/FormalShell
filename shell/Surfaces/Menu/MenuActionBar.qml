import QtQuick
import qs.Core
import qs.Components

// The launcher's bottom action bar (M23) — the Raycast footer, in ledger
// terms: one Cell spanning the card's content width, carrying the primary
// action for the row under the cursor on the left and the always-applicable
// keys on the right. Menu/actions.js decides the wording; this file only
// paints it.
//
// The primary key cap is a full-bleed accent block (DESIGN.md §2.4: accent
// reads as a fill with onAccent ink, never a tinted label) and its verb sits
// in band 1; every hint cap is a bordered box carrying `rule` at band 2
// dim, so the one action Enter will actually take is the only loud thing in
// the row. Clicking the primary does exactly what Enter does — the hints are
// legends, not buttons, and stay inert.
Cell {
    id: root

    property var primary: null
    property var hints: []

    signal primaryActivated

    // Sized off the hint row, never off the primary row: the primary half
    // hides itself whenever the cursor sits on something that can't be
    // activated, and a bar that changed height as the cursor moved would
    // resize the whole card under it.
    height: hintsRow.implicitHeight + Theme.space.controlPaddingY * 2 + Theme.borderWidth

    Row {
        id: barRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.labelGap

        // Nothing to activate (an honest-empty note row under the cursor,
        // an empty result set) simply leaves the left half blank rather
        // than offering a verb that would do nothing.
        visible: !!root.primary

        Rectangle {
            id: primaryCap
            anchors.verticalCenter: parent.verticalCenter
            width: primaryKey.implicitWidth + Theme.space.sm * 2
            height: primaryKey.implicitHeight + Theme.space.xxs * 2
            color: Theme.color.accent

            Text {
                id: primaryKey
                anchors.centerIn: parent
                text: root.primary ? root.primary.key : ""
                color: Theme.color.onAccent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.caption
            }
        }

        ActionLabel {
            anchors.verticalCenter: parent.verticalCenter
            text: root.primary ? root.primary.label : ""
            color: root.foreground
        }
    }

    Row {
        id: hintsRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.lg

        Repeater {
            model: root.hints

            delegate: Row {
                id: hint
                required property var modelData

                spacing: Theme.space.labelGap

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: hintKey.implicitWidth + Theme.space.sm * 2
                    height: hintKey.implicitHeight + Theme.space.xxs * 2
                    color: "transparent"
                    border.width: Theme.borderWidth
                    border.color: Theme.color.rule
                    radius: Theme.radius

                    Text {
                        id: hintKey
                        anchors.centerIn: parent
                        text: hint.modelData.key
                        color: root.dimForeground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.caption
                    }
                }

                MetaLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: hint.modelData.label
                    color: root.dimForeground
                }
            }
        }
    }

    // Cell's `hit` escape hatch rather than its own `interactive`, which is
    // the whole-cell target: only the primary half of this bar is a button,
    // and the hint caps to its right are a legend that has to stay inert.
    hit: MouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        // barRow plus the cell's padding on both sides: this layer spans the
        // cell, not the padded content box barRow sits in, so the left inset
        // has to be paid for here too.
        width: barRow.width + Theme.space.controlPaddingX * 2
        enabled: !!root.primary
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.primaryActivated()
    }
}
