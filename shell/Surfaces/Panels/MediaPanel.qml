import QtQuick
import qs.Core
import qs.Components
import qs.Services

// MPRIS now-playing popout (DESIGN.md §Panels, spec §5, M7 Task 1; art+
// identity row restored M31 Task 1 after M28 Task 2's brief PanelHero
// recomposition): when art exists the panel opens with its own 96x96
// dithered cover beside a "NOW PLAYING / <identity>" meta line, the track
// title, and the artist (DESIGN.md §1.3's 96x96 exception, §2.13's dated
// exception to "every panel opens with the shared hero"). No art (most
// browsers publish none) falls back to the plain PanelHero: glyph, title,
// meta. Elapsed/total on one header line (Task 1's rhythm), the flat
// accent-fill scrub track underneath, then transport as one small cluster
// of content-sized cells rather than three glyphs adrift in oversized ones.
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

    // M35: the bar's mini cover (NowPlaying.qml) shares this panel's one
    // Video decode rather than running its own. AnimatedCoverFrameSource
    // is the single gate for that decode — panelWants is this panel's own
    // half of it (MediaPanel is a shell-wide singleton instance,
    // shell.qml, so one flag is enough), keepMapped keeps this panel's
    // window mapped for grabToImage while the bar wants frames and the
    // panel itself is closed (Panel.qml's own click-through mask covers
    // input during that state).
    keepMapped: AnimatedCoverFrameSource.active
    Binding {
        target: AnimatedCoverFrameSource
        property: "panelWants"
        value: root.isOpen
    }

    // The one named image-slot size (DESIGN.md §1.3's structural-size
    // exceptions names "the media panel's 96x96 album-art slot" by name).
    readonly property real _artSlotSize: 96

    // Plenty of players publish no `mpris:artUrl` at all (browsers, most
    // notably), so the panel falls back to the ordinary hero with a glyph
    // rather than a 96px blank slot.
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

    // The panel's own subject: the track itself. When art exists the
    // panel's point IS the artwork, so it opens with the restored 96x96
    // art+identity row (DESIGN.md §2 item 13's dated exception) instead of
    // the shared hero — the analogue of a number panel's oversized readout.
    // Art + identity share one row cell (owner: a two-cell layout left the
    // art centered in its own mostly-empty row) rendered in our own ledger
    // chrome: radius 0, no border on the art, the panel's usual shared Cell
    // rule below it.
    Cell {
        id: infoCell
        visible: MediaService.available && root._hasArt
        width: parent.width

        Row {
            id: infoRow
            width: parent.width
            spacing: Theme.space.md

            Item {
                id: artSlot
                width: root._artSlotSize
                height: root._artSlotSize
                anchors.verticalCenter: parent.verticalCenter

                // DitherImage owns the hidden source Image itself (decode
                // capped near the slot size, no pixmap cache) and repaints
                // the retro color dither (DESIGN.md §2 item 12) whenever
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
                // QtMultimedia module. Active whenever AnimatedCoverFrameSource
                // says either this panel or the bar's mini cover wants
                // frames (M35) — not just `root.isOpen` any more, since the
                // Video this Loader owns is the bar's decode too.
                Loader {
                    width: root._artSlotSize
                    height: root._artSlotSize
                    active: AnimatedCoverFrameSource.active
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

    // No art (most browsers publish none): the ordinary hero with a note
    // glyph, never a 96px blank slot.
    PanelHero {
        visible: MediaService.available && !root._hasArt
        width: parent.width
        glyph: "󰎇"
        title: MediaService.title !== "" ? MediaService.title : "UNKNOWN TITLE"
        meta: MediaService.artist !== "" ? MediaService.artist : MediaService.identity
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
