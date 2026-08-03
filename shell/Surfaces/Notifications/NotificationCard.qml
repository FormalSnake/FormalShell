import QtQuick
import Quickshell
import qs.Core
import qs.Components
import "../../Notifications/model.js" as Model

// One notification row (DESIGN.md §Notifications, M8b Task 5, M15 Task 2):
// meta row (app name / relative time) + summary + sanitized/styled body, an
// icon slot, a dismiss cell, and — only when the notification carries them —
// a bottom row of action cells. Critical urgency (2) fills the whole card as
// an urgent cell per DESIGN's §2.4 "critical severity is a full-bleed urgent
// fill" — never priority downgraded to the generic `accent` full-bleed,
// since the two are distinct matugen-driven palette roles. Purely
// presentational: Toasts.qml/Center.qml own fetching the entry from
// NotificationService and wiring the signals below to its verbs.
//
// `invertOnHover` (default false, keeping Toasts.qml's standalone popup
// cards as plain hover-tint) lets Center.qml opt a row into the ASCII-OS
// table's "highlighted row inverts" rule (§2.2) instead — the two surfaces
// share this component but not this one state, per DESIGN's own split
// between "each toast is its own card" and "the center is a table".
Cell {
    id: root

    required property var entry
    property double now: Date.now()
    property bool invertOnHover: false

    urgent: root.entry.urgency === 2
    hovered: cardHover.containsMouse
    selected: root.invertOnHover && cardHover.containsMouse
    width: 360

    signal dismiss
    signal bodyClicked
    signal actionInvoked(string key)

    // Declared first (behind everything painted after it) so it never
    // intercepts a click meant for textArea's or a Cell button's own
    // MouseArea below — Qt.NoButton means it only ever tracks hover, never
    // grabs a press.
    MouseArea {
        id: cardHover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // sanitizeBody/styledBody live once in model.js and are applied here at
    // the shared-component boundary, so both Toasts.qml's popups and
    // Center.qml's rows get the Chromium URL-prefix strip and the newline ->
    // <br/> conversion for free (DESIGN.md §Notifications, M15 origin: "GH
    // notifs are ugly").
    readonly property string _sanitizedBody: Model.sanitizeBody(root.entry.body, root.entry.appName, root.entry.appIcon)
    readonly property string _styledBody: Model.styledBody(root.entry.body, root.entry.appName, root.entry.appIcon)
    readonly property bool _singleLine: root._sanitizedBody.length === 0
    readonly property string _relTime: Model.relTime(root.now, root.entry.arrivedAt)

    // Icon slot (DESIGN.md's third sanctioned image-icon exception, added by
    // this task): the notification's own image wins when it resolved
    // (server already ran it through IconImageProvider, see
    // notification.cpp's updateProperties — always a usable Image.source or
    // ""); otherwise the sender's appIcon, which the server does NOT
    // pre-resolve, so it needs the same file://\image://\absolute-path\
    // themed-name branching M14's ActiveWindow uses for desktop-entry icons.
    function _appIconSource(icon) {
        var value = String(icon || "");
        if (value.length === 0)
            return "";
        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
            return value;
        if (value.charAt(0) === "/")
            return "file://" + value;
        return Quickshell.iconPath(value, true);
    }
    readonly property string _iconSource: root.entry.image.length > 0
        ? root.entry.image
        : root._appIconSource(root.entry.appIcon)

    Column {
        width: parent.width
        spacing: Theme.spacing.sm

        // Single-line entries (no body) skip both spacers and the two
        // spacing gaps they'd otherwise pull in, landing on Cell's own
        // baseline inset alone — the tighter padding a one-line toast reads
        // better with; a real body earns the extra breathing room.
        Item {
            visible: !root._singleLine
            height: Theme.spacing.xs
        }

        Row {
            id: contentRow
            width: parent.width
            spacing: Theme.spacing.sm

            Item {
                id: iconSlot
                width: 40
                height: 40
                anchors.verticalCenter: parent.verticalCenter
                // Hidden entirely — not a broken-image box — when neither
                // the notification's image nor the sender's app icon
                // resolves.
                visible: root._iconSource !== "" && iconImage.status !== Image.Error

                Image {
                    id: iconImage
                    anchors.fill: parent
                    source: root._iconSource
                    asynchronous: true
                    smooth: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: parent.width
                    sourceSize.height: parent.height
                }
            }

            Item {
                id: textArea
                width: parent.width - dismissCell.width - (iconSlot.visible ? iconSlot.width + contentRow.spacing : 0) - contentRow.spacing
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
                        font.pixelSize: Theme.fontSize.body
                        font.bold: true
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }

                    Text {
                        visible: root._styledBody.length > 0
                        width: parent.width
                        text: root._styledBody
                        textFormat: Text.StyledText
                        color: root.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.fontSize.bodySmall
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 3
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
                    // Not dismissCell.foreground: an unhovered nested Cell is
                    // transparent, so its actual painted background is
                    // whatever root drew (urgent fill, or the invertOnHover
                    // swap) — root.foreground already tracks that. Only once
                    // this cell is itself hovered does it paint its own
                    // inverted background, so only then does its own
                    // foreground apply.
                    color: dismissCell.selected ? dismissCell.foreground : root.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
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
                        // Same reasoning as the dismiss cell above.
                        color: actionCell.selected ? actionCell.foreground : root.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.fontSize.bodySmall
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

        Item {
            visible: !root._singleLine
            height: Theme.spacing.xs
        }
    }
}
