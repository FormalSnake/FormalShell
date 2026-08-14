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

    // The one named image-slot size (DESIGN.md §1.3's structural-size
    // exceptions, audit "token hygiene strays" — was three repeated bare
    // `96`s below).
    readonly property real _artSlotSize: 96

    // Plenty of players publish no `mpris:artUrl` at all (browsers, most
    // notably), so the slot collapses out of the row rather than reserving
    // 96px of blank next to the title.
    readonly property bool _hasArt: MediaService.artUrl !== ""
        || AppleMusicArtService.animatedArtUrl !== ""

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
                visible: root._hasArt
                width: root._artSlotSize
                height: root._artSlotSize
                anchors.verticalCenter: parent.verticalCenter

                // DitherImage owns the hidden source Image itself (decode
                // capped near the slot size, no pixmap cache — M16 Task
                // 12's artUrl-changes-per-track rationale still applies,
                // just moved inside the shared component) and repaints the
                // retro color dither (DESIGN.md §2 item 12) whenever
                // artUrl changes — content imagery, so it keeps the
                // cover's own colors rather than reducing to theme roles.
                DitherImage {
                    visible: MediaService.artUrl !== ""
                    source: MediaService.artUrl
                    mode: "retro"
                    width: root._artSlotSize
                    height: root._artSlotSize
                }

                // Apple Music animated cover (M7 Task 2, opt-in): layered
                // over the static art above, which stays the permanent
                // fallback for every failure path — disabled, no match, no
                // animated art, download failure, or a missing
                // QtMultimedia module. Active only while the panel is open
                // and the track actually playing, per the spec. Rides the
                // art slot unchanged by this merge.
                Loader {
                    width: root._artSlotSize
                    height: root._artSlotSize
                    active: root.isOpen && MediaService.isPlaying && AppleMusicArtService.animatedArtUrl !== ""
                    source: "AnimatedAlbumArt.qml"
                }
            }

            Column {
                // Row drops an invisible child's spacing too, so the text
                // takes the whole cell when the art slot is gone.
                width: root._hasArt ? infoRow.width - artSlot.width - infoRow.spacing : infoRow.width
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.xxs

                MetaLabel {
                    text: "NOW PLAYING / " + MediaService.identity
                }

                Text {
                    width: parent.width
                    text: MediaService.title !== "" ? MediaService.title : "UNKNOWN TITLE"
                    color: infoCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.subtitle
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: MediaService.artist !== ""
                    text: MediaService.artist
                    color: Theme.color.foregroundDim
                    font.family: Theme.fontFamily
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
        DitherFill {
            id: progressTrack
            width: parent.width
            height: Theme.space.trackThickness

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
            selected: prevCell.containsPointer
            enabled: MediaService.canGoPrevious

            Text {
                anchors.centerIn: parent
                text: "󰒮"
                color: MediaService.canGoPrevious ? prevCell.foreground : Theme.color.foregroundFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }

            interactive: true
            onClicked: MediaService.previous()
        }

        Cell {
            id: playPauseCell
            width: parent.width / 3
            selected: playPauseCell.containsPointer

            Text {
                anchors.centerIn: parent
                text: MediaService.isPlaying ? "󰏤" : "󰐊"
                color: playPauseCell.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }

            interactive: true
            onClicked: MediaService.playPause()
        }

        Cell {
            id: nextCell
            width: parent.width / 3
            selected: nextCell.containsPointer
            enabled: MediaService.canGoNext

            Text {
                anchors.centerIn: parent
                text: "󰒭"
                color: MediaService.canGoNext ? nextCell.foreground : Theme.color.foregroundFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }

            interactive: true
            onClicked: MediaService.next()
        }
    }
}
