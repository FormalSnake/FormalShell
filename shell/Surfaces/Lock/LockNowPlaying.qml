import QtQuick
import Quickshell.Services.Mpris
import qs.Core
import qs.Components
import qs.Services

// The now-playing block under the lock prompt: the cover, the title and the
// artist, a progress line and the three transport buttons, fed by
// MediaService exactly as the media panel is. Drawn straight onto the
// wallpaper like the clock, so its words take the same `lock.ink` the
// clock does, decided off the wallpaper under this block's own rect
// (LockSurface.qml samples it). The cover, the track and the button trough
// carry their own chrome and read on any backdrop.
//
// Absent entirely unless something is playing or paused: no player, a
// stopped one, or an app stream with no transport of its own leaves no slot.
//
// It never takes focus. The keyboard reaches it through the password
// field's own key filter (LockSurface.qml, Lock/model.js's `transportKey`),
// and `cursorIndex` is the ring that filter moves; a click presses through
// ButtonGroup and hands focus straight back to the field.
//
// The cover's animated overlay is the bar's own: the frames the media
// panel's single decode publishes (AnimatedCoverFrameSource), over the
// static art, which is what shows whenever nothing is publishing.
Item {
    id: root

    property color ink: Theme.color.foreground
    property color subInk: Theme.color.mutedForeground
    property var inkShadow: []
    property int cursorIndex: -1

    // Pressed through the pointer; the surface puts focus back on the field.
    signal pressed()

    readonly property bool _stopped: MediaService.activePlayer !== null
        && MediaService.activePlayer.playbackState === MprisPlaybackState.Stopped
    readonly property bool shown: MediaService.available && MediaService.activeKind !== "stream" && !root._stopped

    readonly property var transport: root.shown ? ["previous", "playpause", "next"] : []

    readonly property bool _hasArt: MediaService.artUrl !== ""
    readonly property real _artSize: Theme.space.controlHeight * 2

    function press(index) {
        var id = root.transport[index];
        if (id === "previous")
            MediaService.previous();
        else if (id === "playpause")
            MediaService.playPause();
        else if (id === "next")
            MediaService.next();
    }

    function _enabled(id) {
        if (id === "previous")
            return MediaService.canGoPrevious;
        if (id === "next")
            return MediaService.canGoNext;
        return MediaService.canPlayPause;
    }

    function _icon(id) {
        if (id === "previous")
            return "skip-back";
        if (id === "next")
            return "skip-forward";
        return MediaService.isPlaying ? "pause" : "play";
    }

    visible: root.shown
    implicitWidth: Theme.space.popupWidthNarrow
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: Theme.space.md

        Row {
            id: infoRow
            width: parent.width
            spacing: Theme.space.lg

            Cover {
                id: cover
                visible: root._hasArt
                width: root._artSize
                height: root._artSize
                anchors.verticalCenter: parent.verticalCenter
                source: MediaService.artUrl
                sourceSize.width: root._artSize
                sourceSize.height: root._artSize
                cache: false

                overlay: Picture {
                    anchors.fill: parent
                    visible: AnimatedCoverFrameSource.active && AnimatedCoverFrameSource.frameUrl !== ""
                    source: AnimatedCoverFrameSource.frameUrl
                    sourceSize.width: cover.width
                    sourceSize.height: cover.height
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                }
            }

            // The words and their shadow, the same arrangement AuthPrompt's
            // clock block takes (Components/InkGlow.qml).
            Item {
                width: infoRow.width - (root._hasArt ? cover.width + infoRow.spacing : 0)
                height: words.implicitHeight
                anchors.verticalCenter: parent.verticalCenter

                InkGlow {
                    anchors.fill: words
                    source: words
                    shadows: root.inkShadow
                }

                Column {
                    id: words
                    width: parent.width
                    spacing: Theme.space.xxs
                    opacity: root.inkShadow.length > 0 ? 0 : 1
                    layer.enabled: root.inkShadow.length > 0

                    Text {
                        width: parent.width
                        text: MediaService.title !== "" ? MediaService.title : "Unknown title"
                        color: root.ink
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: MediaService.artist !== ""
                        text: MediaService.artist
                        color: root.subInk
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.bodySmall
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Track {
            width: parent.width
            visible: MediaService.hasTimeline && MediaService.length > 0
            value: MediaService.length > 0 ? MediaService.position / MediaService.length : 0
            swept: true
        }

        ButtonGroup {
            anchors.horizontalCenter: parent.horizontalCenter
            height: Theme.space.controlHeight
            exclusive: false
            options: root.transport.map(function (id) {
                return { icon: root._icon(id), value: id, enabled: root._enabled(id) };
            })
            cursorIndex: Math.max(0, root.cursorIndex)
            cursor: root.cursorIndex >= 0
            onPressed: index => {
                root.press(index);
                root.pressed();
            }
        }
    }
}
