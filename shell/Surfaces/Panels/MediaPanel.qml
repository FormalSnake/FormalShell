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
// The rest of what MPRIS actually defines hangs off that: shuffle and
// LoopStatus as the outer two cells of the transport cluster, the player's
// own Volume as a second track under it, Raise as a title-band label, and a
// row per registered player when more than one is registered at once. Each
// is gated on the player's own capability flag, so a player that implements
// none of them renders exactly the panel it rendered before.
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

    // MPRIS Raise: bring the player's own window up, the one transport verb
    // that isn't about the track. A bare label in the title band rather than
    // a sixth cell in the transport cluster (CardTitleBar's own contract,
    // DESIGN.md §1.1's ink promotion), and absent entirely on a player that
    // doesn't implement it.
    titleActions: MetaLabel {
        visible: MediaService.canRaise
        text: "RAISE"
        color: raiseHover.containsMouse ? Theme.color.foreground : Theme.color.mutedForeground

        MouseArea {
            id: raiseHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: MediaService.raise()
        }
    }

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
                    color: Theme.color.mutedForeground
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

    // Two players at once is the ordinary case (a browser tab plus a music
    // app) and MPRIS names them all, so the pick MediaService makes is worth
    // overriding by hand: one row per registered player, the active one
    // inverted, click to pin the whole shell to it. Hidden with a single
    // player, where a list of one would just repeat the identity line above.
    Cell {
        visible: MediaService.players.length > 1
        width: parent.width

        MetaLabel { text: "PLAYERS"; colon: true }
    }

    Repeater {
        model: MediaService.players.length > 1 ? MediaService.players : []

        delegate: Cell {
            id: playerCell
            required property var modelData
            width: parent.width
            selected: playerCell.modelData.id === MediaService.activeId

            Text {
                width: parent.width - (playingLabel.visible ? playingLabel.width + Theme.space.md : 0)
                anchors.verticalCenter: parent.verticalCenter
                text: playerCell.modelData.label
                color: playerCell.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
                elide: Text.ElideRight
            }

            MetaLabel {
                id: playingLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: playerCell.modelData.isPlaying
                text: "PLAYING"
                color: playerCell.dimForeground
            }

            interactive: true
            onClicked: MediaService.select(playerCell.modelData.id)
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
                    color: Theme.color.primary
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

            // MPRIS Shuffle and LoopStatus flank the transport, each present
            // only when the player implements it: three cells for a player
            // that does neither, five for one that does both. Their on-state
            // is the ledger's own inversion (DESIGN.md §1.1: inversion is
            // state, the alpha hover is the pointer), which is why these two
            // don't take the neighbouring cells' hover-inversion: an inverted
            // shuffle cell has to mean shuffle is on, not that the pointer is
            // over it.
            Cell {
                id: shuffleCell
                visible: MediaService.shuffleSupported
                width: implicitWidth
                height: implicitHeight
                selected: MediaService.shuffle

                Text {
                    anchors.centerIn: parent
                    text: MediaService.shuffle ? "󰒝" : "󰒞"
                    color: shuffleCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.heading
                }

                interactive: true
                onClicked: MediaService.toggleShuffle()
            }

            Cell {
                id: prevCell
                width: implicitWidth
                height: implicitHeight
                selected: prevCell.containsPointer
                enabled: MediaService.canGoPrevious

                Text {
                    anchors.centerIn: parent
                    text: "󰒮"
                    color: MediaService.canGoPrevious ? prevCell.foreground : Theme.color.mutedForeground
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
                    color: MediaService.canGoNext ? nextCell.foreground : Theme.color.mutedForeground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.heading
                }

                interactive: true
                onClicked: MediaService.next()
            }

            Cell {
                id: loopCell
                visible: MediaService.loopSupported
                width: implicitWidth
                height: implicitHeight
                selected: MediaService.loopState !== "none"

                Text {
                    anchors.centerIn: parent
                    text: MediaService.loopState === "track"
                        ? "󰑘"
                        : (MediaService.loopState === "playlist" ? "󰑖" : "󰑗")
                    color: loopCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.heading
                }

                interactive: true
                onClicked: MediaService.cycleLoop()
            }
        }

        Rectangle {
            anchors.top: transportRow.top
            anchors.left: transportRow.left
            anchors.right: transportRow.right
            height: Theme.borderWidth
            color: Theme.color.border
        }

        Rectangle {
            anchors.top: transportRow.top
            anchors.left: transportRow.left
            anchors.bottom: transportRow.bottom
            width: Theme.borderWidth
            color: Theme.color.border
        }
    }

    // The player's OWN volume (MPRIS Volume), not the sink's. AudioPanel
    // owns that one, and a browser at 30% here is still whatever the sink
    // says system-wide. Same header-line-plus-track rhythm as the progress
    // row above; absent on a player that doesn't implement Volume.
    Cell {
        visible: MediaService.available && MediaService.volumeSupported
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            Item {
                width: parent.width
                height: Math.max(volumeLabel.implicitHeight, volumeReadout.implicitHeight)

                MetaLabel {
                    id: volumeLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "VOLUME"
                }

                Text {
                    id: volumeReadout
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(MediaService.volume * 100) + "%"
                    color: Theme.color.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }
            }

            DitherFill {
                id: volumeTrack
                width: parent.width
                height: Theme.space.trackThickness

                Rectangle {
                    width: parent.width * MediaService.volume
                    height: parent.height
                    color: Theme.color.primary
                }

                MouseArea {
                    anchors.fill: parent
                    function _setFromX(x) {
                        MediaService.setVolume(x / volumeTrack.width);
                    }
                    onPressed: mouse => _setFromX(mouse.x)
                    onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
                }
            }
        }
    }
}
