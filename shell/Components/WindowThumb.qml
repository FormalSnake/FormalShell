import QtQuick
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Core
import qs.Compositor
import qs.Components

// One window's picture: a ScreencopyView on its toplevel handle
// (hyprland-toplevel-export-v1) rounded and bordered the way any picture is,
// over a schematic box, the window's icon and title on the cell fill, that
// stands in until the first frame lands. Used by the Spaces preview
// (Surfaces/Panels/WorkspacePreview.qml) and the Alt+Tab switcher
// (Surfaces/Switcher/Switcher.qml), the only two places the shell captures a
// window (owner, 2026-09-28 and 2026-09-29): LockSurface.qml's header is why
// no other surface, and the lock least of all, may ever host one.
//
// The owner sets `capturing` while its card is up or fading out, which holds
// the handle and the last frame, and `live` while it is open, which is what
// keeps frames coming. Both false and the source is null, so a closed card
// holds no capture at all.
Item {
    id: root

    // The compositor window this draws, or null for an empty schematic.
    property var win: null
    property string iconSource: ""
    property bool capturing: false
    property bool live: false
    // The pointer or keyboard cursor is on it: the border lights in `ring`.
    property bool lit: false
    // The schematic's cell state, and its own cursor ring.
    property bool selected: false
    property bool cursor: false
    // The schematic carries the title; off where the owner draws one itself.
    property bool showTitle: true
    // The app's icon in the captured picture's corner, for a small thumbnail
    // that would otherwise be nameless.
    property bool badge: false

    readonly property bool captured: capture.hasContent
    // Whether a capture source is set at all, for the owners that report it.
    readonly property bool sourced: capture.captureSource !== null
    readonly property real radius: Theme.coverRadius(Math.min(root.width, root.height))

    Cell {
        id: box
        anchors.fill: parent
        visible: !root.captured
        selected: root.selected
        cursor: root.cursor

        readonly property real _iconSize: Math.min(Theme.space.huge * 2, box.width / 2, box.height / 2)

        Column {
            anchors.centerIn: parent
            spacing: Theme.space.xs

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: box._iconSize
                height: box._iconSize

                Picture {
                    id: boxIcon
                    anchors.fill: parent
                    visible: root.iconSource !== "" && boxIcon.status !== Image.Error
                    source: root.iconSource
                    sourceSize.width: box._iconSize * 2
                    sourceSize.height: box._iconSize * 2
                    fillMode: Image.PreserveAspectFit
                }

                Icon {
                    anchors.centerIn: parent
                    visible: !boxIcon.visible
                    name: "app-window"
                    size: box._iconSize * 0.75
                    color: box.dimForeground
                }
            }

            // Dropped rather than squeezed on a box too short to carry it;
            // the icon still says which window it is.
            Text {
                visible: root.showTitle
                    && box.height >= box._iconSize + Theme.space.xs + implicitHeight + Theme.space.md * 2
                width: Math.max(0, box.width - Theme.space.md * 2)
                horizontalAlignment: Text.AlignHCenter
                text: root.win ? root.win.title : ""
                elide: Text.ElideRight
                color: box.foreground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.caption
            }
        }
    }

    ClippingRectangle {
        anchors.fill: parent
        color: "transparent"
        radius: root.radius
        border.width: Theme.borderWidth
        border.color: root.lit ? Theme.color.ring : Theme.color.border
        contentInsideBorder: true
        opacity: root.captured ? 1 : 0

        Behavior on opacity {
            Anim { kind: "effects" }
        }

        ScreencopyView {
            id: capture
            anchors.fill: parent
            captureSource: root.capturing && root.win ? CompositorService.toplevelHandle(root.win.id) : null
            live: root.live
        }
    }

    Box {
        visible: root.badge && root.captured && root.iconSource !== ""
            && root.width > Theme.space.controlHeight * 2 && root.height > Theme.space.controlHeight * 1.5
        role: "cell"
        state: "rest"
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Theme.space.sm
        width: Theme.space.controlHeight - Theme.space.sm
        height: width

        Picture {
            anchors.centerIn: parent
            width: parent.width - Theme.space.sm * 2
            height: width
            source: root.iconSource
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            fillMode: Image.PreserveAspectFit
        }
    }
}
