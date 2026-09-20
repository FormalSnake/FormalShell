import QtQuick
import qs.Core
import qs.Components

// One notification as shadcn's toast card (DESIGN.md §3 "Toasts", M44 D2),
// and since M60 T4 the `notification: "row"` habit rather than the only
// shape a notification takes: a `Card` holding a header row (the sender's
// icon, its name as a `SectionLabel`, the arrival time in mono), the
// summary, the sanitized body clamped to two lines, and the notification's
// own actions as `outline` buttons beside a close `IconButton`.
//
// Urgency is chrome, never a fill (DESIGN.md §5): critical swaps the border
// to `destructive` and the icon to a `destructive` `triangle-alert`. Normal
// and low differ by nothing at all.
//
// The fill is `card` rather than `Theme.surface(card)`: only the bar, the
// panels and the launcher sit over the compositor's blur, and a toast that
// let the desktop through would be unreadable over a bright wallpaper
// (spec "Depth").
//
// `flat` is the same trade Cell.ghost makes: a consumer that already draws a
// card around this one drops the fill and the resting border, so N of these
// inside one frame read as rows rather than as tiles. A toast has nothing
// behind it and keeps both. The flag itself, the entry, the derived strings
// and the box's own role and state all belong to the facade
// (NotificationCard.qml); this file draws them and nothing else.
Card {
    id: root

    // The facade this draws for; see NotificationCard.qml.
    required property var owner

    readonly property bool hovered: hover.hovered

    signal dismiss
    signal bodyClicked
    signal actionInvoked(string key)

    readonly property real _iconSize: Theme.fontSize.body
    // The slot is a step wider than the glyph in it: an app's own raster
    // icon is a picture, not a glyph, and DESIGN.md §1's "size equals the
    // neighbouring text" rule is about the latter. Fixed either way, so the
    // header row's left edge does not shift between a card that resolved a
    // picture and one that fell back to the bell.
    readonly property real _iconSlot: Theme.fontSize.heading

    // The `notification` box rather than a panel's `card`: a toast has
    // nothing blurred behind it, so its fill is opaque. A flat card paints
    // neither fill nor border, except the one urgency asked for (Cell.qml's
    // ghost state, same rule): critical is a `destructive` border and
    // icon, so the border has to survive the flattening.
    role: root.owner.role
    state: root.owner.state

    implicitWidth: Theme.space.popupWidthNarrow
    implicitHeight: column.implicitHeight + root.padding * 2

    // Declared ahead of `column` so every button inside it keeps its own
    // clicks: this only ever answers a press that landed on text, which
    // accepts none of its own (Cell.qml's `pointer` layer, same reason).
    // The negative margins pull it back out to the card's own edges, since
    // the default slot is already inset by `padding`.
    MouseArea {
        anchors.fill: parent
        anchors.margins: -root.padding
        cursorShape: Qt.PointingHandCursor
        onClicked: root.bodyClicked()
    }

    // On the content slot rather than inside the MouseArea above: a button's
    // own hover area is that MouseArea's sibling, and Qt hands a hover it
    // accepted on to ancestors only, so a handler in there went false with
    // the pointer on the close button. The toast's expiry pause rides this.
    // The margin takes it back out to the card's own edges.
    HoverHandler {
        id: hover
        margin: root.padding
    }

    Column {
        id: column
        anchors.fill: parent
        spacing: Theme.space.rowGap

        Item {
            width: parent.width
            height: closeButton.implicitHeight

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.iconGap

                Item {
                    width: root._iconSlot
                    height: root._iconSlot
                    anchors.verticalCenter: parent.verticalCenter

                    // The picture's own frame (M48 D4, DESIGN.md §1's
                    // ladder): a `Cover`, the same component the bar and the
                    // media panel draw album art in, so an app's own icon
                    // reads as a thumbnail rather than as a glyph that
                    // happens to be in colour. An outline on imagery, not a
                    // box around a group, so it survives the one-card rule.
                    Cover {
                        id: appImage
                        anchors.fill: parent
                        // Hidden entirely (not a broken-image box) when
                        // nothing in the resolution order answers, and never
                        // in front of the urgency icon, which outranks it.
                        visible: !root.owner.critical && root.owner.iconSource !== ""
                            && appImage.status !== Image.Error
                        source: root.owner.critical ? "" : root.owner.iconSource
                        // An app icon is a whole glyph, not a crop: it
                        // letterboxes in its slot rather than filling it.
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: root._iconSlot
                        sourceSize.height: root._iconSlot
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: !appImage.visible
                        name: root.owner.critical ? "triangle-alert" : "bell"
                        size: root._iconSize
                        color: root.owner.critical ? Theme.color.destructive : Theme.color.mutedForeground
                    }
                }

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

            IconButton {
                id: closeButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                name: "x"
                onClicked: root.dismiss()
            }
        }

        Text {
            width: parent.width
            text: root.owner.entry.summary
            color: Theme.color.foreground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }

        Text {
            visible: root.owner.styledBody.length > 0
            width: parent.width
            text: root.owner.styledBody
            textFormat: Text.StyledText
            color: Theme.color.mutedForeground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.bodySmall
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }

        // The gap above the action row is the row's own, so a notification
        // carrying no drawable actions pays neither the gap nor the height.
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
