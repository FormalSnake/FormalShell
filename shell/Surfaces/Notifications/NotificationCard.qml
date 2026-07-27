import QtQuick
import qs.Core
import qs.Components

// One toast (DESIGN.md "stacked cells sharing rules"): meta row (app name /
// relative time) + summary + elided body, a dismiss cell, and — only when
// the notification carries them — a bottom row of action cells. Critical
// urgency (2) fills the whole card as an accent cell per DESIGN's "critical
// = accent-filled cell". Purely presentational: Toasts.qml owns fetching the
// entry from NotificationService and wiring the signals below to its verbs.
Cell {
    id: root

    required property var entry
    property double now: Date.now()

    accent: root.entry.urgency === 2
    width: 360

    signal dismiss
    signal bodyClicked
    signal actionInvoked(string key)

    readonly property string _relTime: {
        var minutes = Math.max(0, Math.floor((root.now - root.entry.arrivedAt) / 60000));
        return minutes < 1 ? "now" : minutes + "m ago";
    }

    Column {
        width: parent.width
        spacing: Theme.spacing.sm

        Row {
            width: parent.width
            spacing: Theme.spacing.sm

            Item {
                id: textArea
                width: parent.width - dismissCell.width - parent.spacing
                implicitHeight: textColumn.implicitHeight
                height: implicitHeight

                Column {
                    id: textColumn
                    width: parent.width
                    spacing: Theme.spacing.xs

                    MetaLabel {
                        color: root.foreground
                        text: root.entry.appName + " / " + root._relTime
                    }

                    Text {
                        width: parent.width
                        text: root.entry.summary
                        color: root.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.body
                        font.bold: true
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        visible: root.entry.body.length > 0
                        width: parent.width
                        text: root.entry.body
                        color: root.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.bodySmall
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.bodyClicked()
                }
            }

            Cell {
                id: dismissCell
                width: implicitWidth
                height: implicitHeight
                selected: dismissHover.containsMouse

                Text {
                    text: "✕"
                    color: dismissCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                }

                MouseArea {
                    id: dismissHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismiss()
                }
            }
        }

        Rectangle {
            visible: actionRow.visible
            width: parent.width
            height: Theme.borderWidth
            color: Theme.color.rule
        }

        Row {
            id: actionRow
            visible: root.entry.actions.length > 0
            width: parent.width
            spacing: 0

            Repeater {
                model: root.entry.actions

                delegate: Cell {
                    id: actionCell
                    required property var modelData
                    width: implicitWidth
                    height: implicitHeight
                    selected: actionHover.containsMouse

                    Text {
                        text: actionCell.modelData.label
                        color: actionCell.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.bodySmall
                    }

                    MouseArea {
                        id: actionHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.actionInvoked(actionCell.modelData.key)
                    }
                }
            }
        }
    }
}
