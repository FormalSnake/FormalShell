import QtQuick
import qs.Core
import qs.Components

// The notification under `notification: "bubble"` (the 2026-09-17 spec's
// Part 2, M60 T4): elementary's own bubble
// (`notifications/data/application.css`, `src/AbstractBubble.vala`,
// `src/Widgets/Bubble.vala`). `popupWidthBubble` wide, the app icon in a
// column of its own down the leading edge with the text a `md` gap off it,
// a bold title over a body that wraps at 33 characters, and a round close
// button in the top corner that is not there until the pointer is.
//
// The chrome is the table's `notification` box and nothing here: radius 9,
// the view fill at 0.8, the lit rim and the two casts, a `destructive` rim
// where urgency asked for one, and no fill at all inside the notification
// centre (the `flat` states). The role and the state both come off the
// facade, so a bubble and the peek shell Toasts.qml paints behind it cannot
// fall out of step.
//
// What elementary has that this drops: the 24px badge over the app icon (we
// have no second icon to put in it, and inventing one would be a faked
// state) and the icon at its own 48px, which beside a 13px title reads as
// the picture being the notification. A control-sized square instead, which
// is the one token that names a slot rather than a glyph.
Box {
    id: root

    // The facade this draws for; see NotificationCard.qml.
    required property var owner

    readonly property bool hovered: hover.hovered

    signal dismiss
    signal bodyClicked
    signal actionInvoked(string key)

    role: root.owner.role
    state: root.owner.state
    padding: Theme.space.panelPadding

    implicitWidth: Theme.space.popupWidthBubble
    implicitHeight: content.implicitHeight + root.padding * 2

    // elementary's `max-width-chars` on the body label, in the one unit that
    // survives a font change: the advance of that many digits at the body's
    // own size. A character count is the measurement, not a width, so the
    // number here is elementary's and the pixels are the font's.
    readonly property int _bodyChars: 33
    readonly property real _bodyMeasure: Math.ceil(bodyMetrics.advanceWidth("0") * root._bodyChars)

    FontMetrics {
        id: bodyMetrics
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.bodySmall
    }

    // Declared ahead of the content so every button over it keeps its own
    // clicks: this only ever answers a press that landed on text
    // (Cell.qml's `pointer` layer, same reason). The negative margins pull
    // it back out to the bubble's own edges, since the slot it sits in is
    // already inset by `padding`.
    MouseArea {
        anchors.fill: parent
        anchors.margins: -root.padding
        cursorShape: Qt.PointingHandCursor
        onClicked: root.bodyClicked()

        // A handler rather than this MouseArea's own containsMouse, which
        // drops out the moment the pointer crosses onto the close button:
        // that button's own appearance rides this, and so does the toast's
        // expiry pause (NotificationService.setPopupHovered, wired by
        // Toasts.qml).
        HoverHandler {
            id: hover
        }
    }

    Row {
        id: content
        anchors.fill: parent
        spacing: Theme.space.md

        Item {
            width: Theme.space.controlHeight
            height: Theme.space.controlHeight

            // The picture's own frame (DESIGN.md §1's ladder): a `Cover`,
            // the same component every other app icon and album art in the
            // shell sits in, so the bubble rounds its picture the way the
            // rest of the shell does.
            Cover {
                id: appImage
                anchors.fill: parent
                // Hidden entirely (not a broken-image box) when nothing in
                // the resolution order answers, and never in front of the
                // urgency icon, which outranks it.
                visible: !root.owner.critical && root.owner.iconSource !== ""
                    && appImage.status !== Image.Error
                source: root.owner.critical ? "" : root.owner.iconSource
                // An app icon is a whole glyph, not a crop: it letterboxes
                // in its slot rather than filling it.
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Theme.space.controlHeight
                sourceSize.height: Theme.space.controlHeight
            }

            Icon {
                anchors.centerIn: parent
                visible: !appImage.visible
                name: root.owner.critical ? "triangle-alert" : "bell"
                size: Theme.fontSize.heading
                color: root.owner.critical ? Theme.color.destructive : Theme.color.mutedForeground
            }
        }

        Column {
            id: column
            width: content.width - content.spacing - Theme.space.controlHeight
            spacing: Theme.space.rowGap

            // The sender line, and the corner the close button holds: the
            // button is the taller of the two, so the row is its height and
            // the meta sits centred against it.
            Item {
                width: parent.width
                height: closeButton.implicitHeight

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space.iconGap

                    SectionLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.owner.entry.appName
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.owner.meta
                        color: Theme.color.mutedForeground
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSize.caption
                    }
                }

                // elementary's own close affordance: nothing until the
                // pointer is on the bubble, round rather than square, in the
                // top corner. It crosses in and out rather than switching,
                // since a control appearing under a pointer that is already
                // moving reads as a flicker; `enabled` follows so an
                // invisible button cannot be clicked either.
                IconButton {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    name: "x"
                    radius: Theme.pillRadius(closeButton.implicitHeight)
                    opacity: root.hovered ? 1 : 0
                    visible: closeButton.opacity > 0
                    enabled: root.hovered
                    onClicked: root.dismiss()

                    Behavior on opacity {
                        Anim { kind: "effects" }
                    }
                }
            }

            Text {
                width: parent.width
                text: root.owner.entry.summary
                color: Theme.color.foreground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.body
                font.weight: Theme.weight.semibold
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }

            Text {
                visible: root.owner.styledBody.length > 0
                // The narrower of elementary's character measure and the
                // room the column actually has: the bubble is wide enough
                // for the measure at the default font size, and a larger
                // one wraps at the column instead of running out of it.
                width: Math.min(root._bodyMeasure, parent.width)
                text: root.owner.styledBody
                textFormat: Text.StyledText
                color: Theme.color.mutedForeground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.bodySmall
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }

            // The gap above the action row is the row's own, so a
            // notification carrying no drawable actions pays neither the gap
            // nor the height.
            Item {
                visible: root.owner.buttonActions.length > 0
                width: parent.width
                height: actionRow.implicitHeight + Theme.space.rowGap

                Row {
                    id: actionRow
                    anchors.bottom: parent.bottom
                    spacing: Theme.space.sm

                    Repeater {
                        model: root.owner.buttonActions

                        delegate: Button {
                            id: actionButton
                            required property var modelData

                            variant: "outline"
                            text: actionButton.modelData.label
                            onClicked: root.actionInvoked(actionButton.modelData.key)
                        }
                    }
                }
            }
        }
    }
}
