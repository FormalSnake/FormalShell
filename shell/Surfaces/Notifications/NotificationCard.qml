import QtQuick
import Quickshell
import qs.Core
import qs.Components
import "../../Notifications/model.js" as Model
import "../../Notifications/icon.js" as NotificationIcon

// One notification as shadcn's toast card (DESIGN.md §3 "Toasts", M44 D2):
// a `Card` holding a header row (the sender's icon, its name as a
// `SectionLabel`, the arrival time in mono), the summary, the sanitized body
// clamped to two lines, and the notification's own actions as `outline`
// buttons beside a close `IconButton`.
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
// Purely presentational: Toasts.qml and Center.qml own fetching the entry
// from NotificationService and wiring the three signals below to its verbs.
Card {
    id: root

    required property var entry
    property double now: Date.now()

    // Both are Center.qml's, both paint nothing here: its rows still spell
    // the pre-shadcn hover inversion and pending marker this way, and M44
    // Task 2 rewrites them along with the rest of that surface.
    property bool invertOnHover: false
    property bool pending: false

    readonly property bool hovered: hover.hovered

    signal dismiss
    signal bodyClicked
    signal actionInvoked(string key)

    readonly property bool _critical: root.entry.urgency === 2
    readonly property real _iconSize: Theme.fontSize.body
    // The slot is a step wider than the glyph in it: an app's own raster
    // icon is a picture, not a glyph, and DESIGN.md §1's "size equals the
    // neighbouring text" rule is about the latter. Fixed either way, so the
    // header row's left edge does not shift between a card that resolved a
    // picture and one that fell back to the bell.
    readonly property real _iconSlot: Theme.fontSize.heading

    color: Theme.color.card
    border.color: root._critical ? Theme.color.destructive : Theme.color.border

    implicitWidth: Theme.space.popupWidthNarrow
    implicitHeight: column.implicitHeight + root.padding * 2

    // sanitizeBody/styledBody live once in model.js and are applied here at
    // the shared-component boundary, so both Toasts.qml's popups and
    // Center.qml's rows get the Chromium URL-prefix strip and the newline ->
    // <br/> conversion for free (M15 origin: "GH notifs are ugly").
    readonly property string _styledBody: Model.styledBody(root.entry.body, root.entry.appName, root.entry.appIcon)
    readonly property string _relTime: Model.relTime(root.now, root.entry.arrivedAt)

    // `count` only exists on a row that came through Model.groupEntries; both
    // surfaces render every row that way, but an entry handed in directly
    // carries no such key and `undefined > 1` is false, so no default is
    // needed.
    readonly property string _meta: root.entry.count > 1
        ? root._relTime + "  x" + root.entry.count
        : root._relTime

    // The image, the app icon, the sender's desktop entry, then nothing
    // (M48 D4). The order and the path/url/themed-name branching live in
    // icon.js; this is only the wiring of the two lookups it needs. Both are
    // check-resolved, so a name no icon theme carries answers "" and the
    // bell below takes over, rather than the icon provider's own
    // missing-texture pixmap rendering as a healthy Image.
    readonly property string _iconSource: NotificationIcon.resolve(root.entry, {
        themed: function (name) { return Quickshell.iconPath(name, true); },
        entry: function (desktopId, appName) {
            return (desktopId.length > 0 ? DesktopEntries.byId(desktopId) : null)
                ?? (appName.length > 0 ? DesktopEntries.heuristicLookup(appName) : null);
        }
    })

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

        // Hover has to keep reporting with a button under the pointer:
        // this MouseArea's own containsMouse drops out the moment the
        // pointer crosses onto the close button, and the toast's expiry
        // pause rides this (same reason Toasts.qml's stack hover is a
        // handler).
        HoverHandler {
            id: hover
        }
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

                    // The picture's frame (M48 D4): a `radiusSm` bordered
                    // box, MediaPanel's album-art slot one radius step down,
                    // so an app's own icon reads as a thumbnail rather than
                    // as a glyph that happens to be in colour.
                    Rectangle {
                        id: appImageFrame
                        anchors.fill: parent
                        // Hidden entirely (not a broken-image box) when
                        // nothing in the resolution order answers, and never
                        // in front of the urgency icon, which outranks it.
                        visible: !root._critical && root._iconSource !== "" && appImage.status !== Image.Error
                        radius: Theme.radiusSm
                        color: Theme.color.muted
                        border.width: Theme.borderWidth
                        border.color: Theme.color.border
                        clip: true

                        Image {
                            id: appImage
                            anchors.fill: parent
                            anchors.margins: Theme.borderWidth
                            source: root._critical ? "" : root._iconSource
                            asynchronous: true
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                            sourceSize.width: root._iconSlot
                            sourceSize.height: root._iconSlot
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: !appImageFrame.visible
                        name: root._critical ? "triangle-alert" : "bell"
                        size: root._iconSize
                        color: root._critical ? Theme.color.destructive : Theme.color.mutedForeground
                    }
                }

                SectionLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.entry.appName
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._meta
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
            text: root.entry.summary
            color: Theme.color.foreground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }

        Text {
            visible: root._styledBody.length > 0
            width: parent.width
            text: root._styledBody
            textFormat: Text.StyledText
            color: Theme.color.mutedForeground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.bodySmall
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }

        // The gap above the action row is the row's own, so a notification
        // carrying no actions pays neither the gap nor the height.
        Item {
            visible: root.entry.actions.length > 0
            width: parent.width
            height: actionRow.implicitHeight + Theme.space.rowGap

            Row {
                id: actionRow
                anchors.bottom: parent.bottom
                spacing: Theme.space.sm

                Repeater {
                    model: root.entry.actions

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
