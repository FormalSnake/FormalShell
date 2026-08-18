import QtQuick
import Quickshell
import qs.Core
import qs.Components
import "../../Notifications/model.js" as Model

// One notification row (DESIGN.md §Notifications, M8b Task 5, M15 Task 2):
// meta row (app name / relative time, plus the repeat count when the row
// stands for a group) + summary + sanitized/styled body, an
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
    // Way-compacter toast rendering (DESIGN.md §Notifications, M34 Task 2):
    // one width step narrower, a caption-height icon slot instead of
    // 40x40, body clamped to one line, actions as bare labels instead of
    // ink cells. Center.qml never sets this — its own rendering stays
    // byte-identical to pre-M34.
    property bool compact: false
    // Toasts.qml's collapsed-stack peek levels (M34 Task 2): the card's own
    // chrome (fill, border, dog-ear) still paints so the depth stack reads
    // as real cards, but the text/icon/action content underneath is
    // invisible AND non-interactive — a sliver of card, not a squeezed
    // layout. Content stays laid out (opacity only) so the card's own
    // implicit height never jumps when it later becomes the front card.
    property bool contentVisible: true

    urgent: root.entry.urgency === 2
    selected: root.invertOnHover && root.containsPointer
    width: root.compact ? Theme.space.popupWidthNarrow : Theme.space.popupWidthWide

    signal dismiss
    signal bodyClicked
    signal actionInvoked(string key)

    // Hover only: the cell's own target sits under its content, and taking no
    // buttons means it never grabs a press meant for textArea's or a nested
    // Cell button's own MouseArea below.
    interactive: true
    acceptedButtons: Qt.NoButton

    // sanitizeBody/styledBody live once in model.js and are applied here at
    // the shared-component boundary, so both Toasts.qml's popups and
    // Center.qml's rows get the Chromium URL-prefix strip and the newline ->
    // <br/> conversion for free (DESIGN.md §Notifications, M15 origin: "GH
    // notifs are ugly").
    readonly property string _sanitizedBody: Model.sanitizeBody(root.entry.body, root.entry.appName, root.entry.appIcon)
    readonly property string _styledBody: Model.styledBody(root.entry.body, root.entry.appName, root.entry.appIcon)
    readonly property bool _singleLine: root._sanitizedBody.length === 0
    readonly property string _relTime: Model.relTime(root.now, root.entry.arrivedAt)

    // `count` only exists on a row that came through Model.groupEntries; both
    // surfaces render every row that way, but an entry handed in directly
    // carries no such key and `undefined > 1` is false, so no default is
    // needed. MetaLabel uppercases, so this paints as "X3".
    readonly property string _countLabel: root.entry.count > 1 ? " / x" + root.entry.count : ""

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
        spacing: Theme.space.sm
        // Toasts.qml's collapsed peek levels (see contentVisible above):
        // opacity only, never `visible`, so this Column keeps reporting its
        // real implicit height — the card's own size never jumps the
        // moment it becomes (or stops being) the front card.
        opacity: root.contentVisible ? 1 : 0
        enabled: root.contentVisible

        // Single-line entries (no body) skip both spacers and the two
        // spacing gaps they'd otherwise pull in, landing on Cell's own
        // baseline inset alone — the tighter padding a one-line toast reads
        // better with; a real body earns the extra breathing room.
        Item {
            visible: !root._singleLine
            height: Theme.space.xxs
        }

        Row {
            id: contentRow
            width: parent.width
            spacing: Theme.space.sm

            Item {
                id: iconSlot
                // Compact mode's icon slot (DESIGN.md §Notifications, M34
                // Task 2): a caption-height square instead of the full
                // 40x40 structural slot — "way compacter" per the owner
                // ask, matching the caption-sized meta row directly above.
                width: root.compact ? Theme.fontSize.caption : 40
                height: root.compact ? Theme.fontSize.caption : 40
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
                    spacing: Theme.space.xxs

                    MetaLabel {
                        color: root.dimForeground
                        text: root.entry.appName + " / " + root._relTime + root._countLabel
                    }

                    Text {
                        width: parent.width
                        text: root.entry.summary
                        color: root.foreground
                        font.family: Theme.fontFamily
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
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.bodySmall
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: root.compact ? 1 : 3
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
                selected: dismissCell.containsPointer

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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                interactive: true
                onClicked: root.dismiss()
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
            // Ink cells are borderless (DESIGN.md §2 item 11) — the shared
            // rule that used to separate adjacent action cells is gone, so
            // this gap is what keeps them reading as distinct buttons
            // instead of one merged fill, the same standalone-cell gap
            // Bar.qml's own row of cells uses (DESIGN.md §3).
            spacing: Theme.space.sm

            // Full mode: the ink button (DESIGN.md §2 item 11, M19 Task
            // 4) — a notification action commits something, so it rests
            // as a full-bleed foreground fill with background ink. Hover
            // still inverts to the accent pair — Cell.qml handles that
            // itself once `ink` is set.
            Repeater {
                model: root.compact ? [] : root.entry.actions

                delegate: Cell {
                    id: actionCell
                    required property var modelData
                    width: implicitWidth
                    height: implicitHeight
                    ink: true

                    Text {
                        text: actionCell.modelData.label
                        color: actionCell.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.bodySmall
                    }

                    interactive: true
                    onClicked: root.actionInvoked(actionCell.modelData.key)
                }
            }

            // Compact mode: bare labels (DESIGN.md §1.1's ink-promotion
            // amendment) — no cell chrome, hover promotes foregroundDim to
            // foreground, same idiom Center.qml's own title-bar actions
            // (DND / CLEAR ALL) already use.
            Repeater {
                model: root.compact ? root.entry.actions : []

                delegate: Item {
                    id: actionLabel
                    required property var modelData
                    width: label.implicitWidth
                    height: label.implicitHeight

                    Text {
                        id: label
                        text: actionLabel.modelData.label
                        color: actionHover.containsMouse ? root.foreground : root.dimForeground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.bodySmall
                    }

                    MouseArea {
                        id: actionHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.actionInvoked(actionLabel.modelData.key)
                    }
                }
            }
        }

        Item {
            visible: !root._singleLine
            height: Theme.space.xxs
        }
    }
}
