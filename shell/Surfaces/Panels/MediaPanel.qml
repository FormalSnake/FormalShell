import QtQuick
import qs.Core
import qs.Components
import qs.Services

// MPRIS now-playing popout (DESIGN.md §Panels, spec §5, M7 Task 1; recomposed
// on PanelHero M28 Task 2): art or a glyph in the hero's leading slot, the
// track title as the hero's own noun, artist (or the player identity when
// there is no artist) as its meta line — never "Now playing" as the title,
// the card's own title band already says that. Elapsed/total on one header
// line (Task 1's rhythm), the flat accent-fill scrub track underneath, then
// transport as one small cluster of content-sized cells rather than three
// glyphs adrift in oversized ones.
//
// Play/pause stays in that transport cluster rather than moving to the
// hero's `trailing` slot: unlike Audio's MUTE, it has no sense on its own —
// prev/next only mean anything next to it, so splitting it out would orphan
// the other two and cost a row PanelHero's rail-less hero doesn't have room
// for anyway.
Panel {
    id: root

    panelTitle: "NOW PLAYING"
    panelWidth: Theme.space.popupWidthDefault

    // Plenty of players publish no `mpris:artUrl` at all (browsers, most
    // notably), so the hero falls back to a glyph rather than an empty slot.
    readonly property bool _hasArt: MediaService.artUrl !== ""
        || AppleMusicArtService.animatedArtUrl !== ""

    function _formatTime(seconds) {
        var total = Math.max(0, Math.floor(seconds));
        var pad = function (n) { return (n < 10 ? "0" : "") + n; };
        var s = total % 60;
        var m = Math.floor(total / 60) % 60;
        var h = Math.floor(total / 3600);
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s);
    }

    Cell {
        visible: !MediaService.available
        width: parent.width

        MetaLabel { text: "NO PLAYER" }
    }

    // The panel's own subject: the track itself. `leading` carries the
    // dithered cover (plus the Apple Music animated overlay, unchanged from
    // before this task) into the hero's own glyph slot when one exists,
    // falling back to a note glyph — same slot width either way (PanelHero's
    // own header comment), so the title lands at the same x whether or not
    // this track happens to publish art.
    PanelHero {
        visible: MediaService.available
        width: parent.width
        glyph: root._hasArt ? "" : "󰎇"
        leading: root._hasArt ? mediaArt : null
        title: MediaService.title !== "" ? MediaService.title : "UNKNOWN TITLE"
        meta: MediaService.artist !== "" ? MediaService.artist : MediaService.identity
    }

    Component {
        id: mediaArt

        Item {
            width: Theme.space.xxl * 2
            height: Theme.space.xxl * 2

            // Same DitherImage retro pass as every other named content
            // surface (DESIGN.md §2 item 12), just at the hero's slot size
            // instead of the old dedicated 96px art box.
            DitherImage {
                visible: MediaService.artUrl !== ""
                anchors.fill: parent
                source: MediaService.artUrl
                mode: "retro"
            }

            // Apple Music animated cover (M7 Task 2, opt-in), layered over
            // the static art above, which stays the permanent fallback for
            // every failure path — disabled, no match, no animated art,
            // download failure, or a missing QtMultimedia module.
            Loader {
                anchors.fill: parent
                active: root.isOpen && MediaService.isPlaying && AppleMusicArtService.animatedArtUrl !== ""
                source: "AnimatedAlbumArt.qml"
            }
        }
    }

    // Header-line pairing (Task 1's rhythm): elapsed left, total right, both
    // content ink since the row's whole point is these two numbers — track
    // underneath. Flat accent fill, no thumb, draggable when the player
    // supports seeking (AudioPanel's own volume-slider idiom).
    Cell {
        visible: MediaService.available
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            Item {
                width: parent.width
                height: Math.max(elapsedText.implicitHeight, totalText.implicitHeight)

                Text {
                    id: elapsedText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._formatTime(MediaService.position)
                    color: Theme.color.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                Text {
                    id: totalText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._formatTime(MediaService.length)
                    color: Theme.color.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }
            }

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
    }

    // One small cluster of touching, content-sized cells instead of three
    // glyphs stretched across equal 1/3-width cells — the controls read as
    // buttons, not as padding. Each inner Cell draws only its own
    // bottom/right rule (Cell's shared-rule contract), so the two explicit
    // Rectangles below close the group's top and left edge the way
    // Panel.qml's own frame closes it for the whole card — without them the
    // cluster is three verticals and an underline with no top or left edge.
    Cell {
        visible: MediaService.available
        width: parent.width

        Row {
            id: transportRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            Cell {
                id: prevCell
                width: implicitWidth
                height: implicitHeight
                selected: prevCell.containsPointer
                enabled: MediaService.canGoPrevious

                Text {
                    anchors.centerIn: parent
                    text: "󰒮"
                    color: MediaService.canGoPrevious ? prevCell.foreground : Theme.color.foregroundFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.heading
                }

                interactive: true
                onClicked: MediaService.previous()
            }

            Cell {
                id: playPauseCell
                width: implicitWidth
                height: implicitHeight
                selected: playPauseCell.containsPointer

                Text {
                    anchors.centerIn: parent
                    text: MediaService.isPlaying ? "󰏤" : "󰐊"
                    color: playPauseCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.heading
                }

                interactive: true
                onClicked: MediaService.playPause()
            }

            Cell {
                id: nextCell
                width: implicitWidth
                height: implicitHeight
                selected: nextCell.containsPointer
                enabled: MediaService.canGoNext

                Text {
                    anchors.centerIn: parent
                    text: "󰒭"
                    color: MediaService.canGoNext ? nextCell.foreground : Theme.color.foregroundFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.heading
                }

                interactive: true
                onClicked: MediaService.next()
            }
        }

        Rectangle {
            anchors.top: transportRow.top
            anchors.left: transportRow.left
            anchors.right: transportRow.right
            height: Theme.borderWidth
            color: Theme.color.rule
        }

        Rectangle {
            anchors.top: transportRow.top
            anchors.left: transportRow.left
            anchors.bottom: transportRow.bottom
            width: Theme.borderWidth
            color: Theme.color.rule
        }
    }
}
