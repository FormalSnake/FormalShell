import QtQuick
import qs.Core
import qs.Components
import qs.Services

// MPRIS now-playing popout (DESIGN.md §Panels, spec §5, M7 Task 1): album art,
// title/artist, a flat accent-fill progress cell (no thumb, draggable to seek
// when the player supports it — same idiom as AudioPanel's volume track), and
// transport controls as inverted-on-hover cells: DESIGN's "selection =
// inversion" rule bound to hover instead of the usual alpha-hover, since
// these ARE the panel's primary controls, not passive rows. Glyph codepoints
// taken from the pinned nerd-fonts-jetbrains-mono cmap: md-play U+F040A,
// md-pause U+F03E4, md-skip_previous U+F04AE, md-skip_next U+F04AD.
Panel {
    id: root

    panelTitle: "NOW PLAYING"

    Cell {
        visible: !MediaService.available
        width: parent.width

        MetaLabel { text: "NO PLAYER" }
    }

    // Art + identity merged into one row cell (owner: the two-cell layout
    // left the art centered in its own mostly-empty row; omarchy's own
    // popup composition — read-only reference `omarchy/shell/plugins/
    // services/media/BarWidget.qml:111-180` — pairs them in a single row
    // instead). Rendered in our own ledger chrome, not omarchy's: radius 0,
    // no border on the art, the panel's usual shared Cell rule below it.
    Cell {
        id: infoCell
        visible: MediaService.available
        width: parent.width

        Row {
            id: infoRow
            width: parent.width
            spacing: Theme.space.md

            Item {
                id: artSlot
                width: 96
                height: 96
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    visible: MediaService.artUrl !== ""
                    source: MediaService.artUrl
                    width: 96
                    height: 96
                    // Decode capped near the slot size, and no pixmap cache
                    // (M16 Task 12): artUrl changes per track, so the
                    // default cache: true would accumulate full-res art
                    // across every track played this session instead of
                    // ever releasing the previous one.
                    //
                    // 2x the slot, not the slot itself: sourceSize with
                    // both dimensions set fits the decode inside that box
                    // (Qt's KeepAspectRatio) rather than covering it, so
                    // non-square art (rare, but not guaranteed square like
                    // typical covers) would decode short on one axis and
                    // PreserveAspectCrop would upscale it back out. 2x
                    // covers any art up to a 2:1 aspect ratio.
                    sourceSize.width: 192
                    sourceSize.height: 192
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                // Apple Music animated cover (M7 Task 2, opt-in): layered
                // over the static art above, which stays the permanent
                // fallback for every failure path — disabled, no match, no
                // animated art, download failure, or a missing
                // QtMultimedia module. Active only while the panel is open
                // and the track actually playing, per the spec. Rides the
                // art slot unchanged by this merge.
                Loader {
                    width: 96
                    height: 96
                    active: root.isOpen && MediaService.isPlaying && AppleMusicArtService.animatedArtUrl !== ""
                    source: "AnimatedAlbumArt.qml"
                }
            }

            Column {
                width: infoRow.width - artSlot.width - infoRow.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.xxs

                MetaLabel {
                    text: "NOW PLAYING / " + MediaService.identity
                }

                Text {
                    width: parent.width
                    text: MediaService.title !== "" ? MediaService.title : "UNKNOWN TITLE"
                    color: infoCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.subtitle
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: MediaService.artist !== ""
                    text: MediaService.artist
                    color: Theme.color.foregroundDim
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                    elide: Text.ElideRight
                }
            }
        }
    }

    Cell {
        visible: MediaService.available
        width: parent.width

        // Flat accent fill, no thumb — AudioPanel's volume-slider idiom.
        // Draggable only when the player actually supports seeking.
        Rectangle {
            id: progressTrack
            width: parent.width
            height: Theme.space.trackThickness
            color: Theme.color.rule

            readonly property real _fraction: MediaService.length > 0
                ? Math.max(0, Math.min(1, MediaService.position / MediaService.length))
                : 0

            Rectangle {
                width: parent.width * progressTrack._fraction
                height: parent.height
                color: Theme.color.accent
            }

            MouseArea {
                anchors.fill: parent
                enabled: MediaService.canSeek
                function _setFromX(x) {
                    MediaService.seek(x / progressTrack.width);
                }
                onPressed: mouse => _setFromX(mouse.x)
                onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
            }
        }
    }

    Row {
        visible: MediaService.available
        width: parent.width

        Cell {
            id: prevCell
            width: parent.width / 3
            selected: prevArea.containsMouse
            enabled: MediaService.canGoPrevious

            Text {
                anchors.centerIn: parent
                text: "󰒮"
                color: MediaService.canGoPrevious ? prevCell.foreground : Theme.color.foregroundFaint
                font.family: Theme.font.family
                font.pixelSize: Theme.fontSize.body
            }

            MouseArea {
                id: prevArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: MediaService.previous()
            }
        }

        Cell {
            id: playPauseCell
            width: parent.width / 3
            selected: playPauseArea.containsMouse

            Text {
                anchors.centerIn: parent
                text: MediaService.isPlaying ? "󰏤" : "󰐊"
                color: playPauseCell.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.fontSize.body
            }

            MouseArea {
                id: playPauseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: MediaService.playPause()
            }
        }

        Cell {
            id: nextCell
            width: parent.width / 3
            selected: nextArea.containsMouse
            enabled: MediaService.canGoNext

            Text {
                anchors.centerIn: parent
                text: "󰒭"
                color: MediaService.canGoNext ? nextCell.foreground : Theme.color.foregroundFaint
                font.family: Theme.font.family
                font.pixelSize: Theme.fontSize.body
            }

            MouseArea {
                id: nextArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: MediaService.next()
            }
        }
    }
}
