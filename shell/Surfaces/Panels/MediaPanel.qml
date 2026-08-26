import QtQuick
import qs.Core
import qs.Components
import qs.Services

// MPRIS now-playing popout (DESIGN.md §3 "Panel", spec "Panels"). Four
// blocks, each a section of the panel's own content column and so
// `sectionGap` apart: the cover beside the source, title, artist and album;
// the position track with its two times under it; the transport; the
// player's own volume. A chip per registered player follows once more than
// one is on the bus.
//
// The whole panel is one card and nothing inside it is another (owner,
// 2026-08-26). The chrome left is the panel frame, the transport's trough,
// the player chips and the cover's own 1px frame, which is an outline on a
// picture rather than a box around a group. What ranks the now-playing block
// is type: `caption` source, `title` track, `body` artist, `bodySmall`
// album. The ring the keyboard cursor draws on a track comes from
// `Track.cursor` rather than from a Cell wrapped around it.
//
// The times sit under the groove, where every player that draws this puts
// them: the groove is what the eye tracks, and a number above it reads as a
// label for the block rather than as a readout of the line beneath.
//
// Everything below the title comes off MPRIS itself and is gated on the
// player's own capability flags, so a player that implements none of
// shuffle, loop, volume or seek renders the same three transport buttons and
// nothing else. Honest states: no registered player at all is `NO PLAYER`,
// and a player publishing no `mpris:artUrl` (browsers, mostly) leaves the
// cover slot out rather than showing an empty 96px square.
//
// Keyboard (spec "Keyboard model"): Tab cycles three sections. Transport
// first, where Left/Right walk the buttons and Enter presses one; the two
// tracks next, where Left/Right seek five seconds or step the volume five
// percent and Enter plays/pauses; the player chips last, where Enter pins
// the shell to that player.
Panel {
    id: root

    panelIcon: "music"
    panelTitle: "Media"
    panelWidth: Theme.space.popupWidthWide

    // MPRIS Raise: bring the player's own window up, the one transport verb
    // that isn't about the track. Absent entirely on a player that doesn't
    // implement it.
    titleActions: [
        IconButton {
            name: "external-link"
            visible: MediaService.canRaise
            onClicked: MediaService.raise()
        }
    ]

    // M35: the bar's mini cover (NowPlaying.qml) shares this panel's one
    // Video decode rather than running its own. AnimatedCoverFrameSource is
    // the single gate for that decode. `panelWants` is this panel's own half
    // of it (MediaPanel is a shell-wide singleton instance, shell.qml, so one
    // flag is enough), and `keepMapped` keeps this panel's window mapped for
    // grabToImage while the bar wants frames and the panel itself is closed
    // (Panel.qml's own click-through mask covers input during that state).
    // Staying mapped is only for the bar's frames, so it is behind
    // `media.animatedBarCover` too; off, closing this panel always unmaps it.
    keepMapped: AnimatedCoverFrameSource.barEnabled && AnimatedCoverFrameSource.active
    Binding {
        target: AnimatedCoverFrameSource
        property: "panelWants"
        value: root.isOpen
    }

    // The album-art slot, three control heights square so it scales with
    // everything else the panel draws.
    readonly property real _artSlotSize: Theme.space.controlHeight * 3

    readonly property bool _hasArt: MediaService.artUrl !== ""
        || AppleMusicArtService.animatedArtUrl !== ""

    readonly property int _seekStepSeconds: 5
    readonly property real _volumeStep: 0.05

    function _formatTime(seconds) {
        var total = Math.max(0, Math.floor(seconds));
        var pad = function (n) { return (n < 10 ? "0" : "") + n; };
        var s = total % 60;
        var m = Math.floor(total / 60) % 60;
        var h = Math.floor(total / 3600);
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s);
    }

    // ---- Cursor ---------------------------------------------------------

    // Section 0. Shuffle and loop only exist for a player that implements
    // them, so the list is built rather than fixed and the cursor addresses
    // whatever actually rendered.
    readonly property var _transport: {
        if (!MediaService.available)
            return [];
        var out = ["previous", "playpause", "next"];
        if (MediaService.shuffleSupported)
            out.push("shuffle");
        if (MediaService.loopSupported)
            out.push("loop");
        return out;
    }

    // Section 1.
    readonly property var _tracks: {
        if (!MediaService.available)
            return [];
        var out = ["progress"];
        if (MediaService.volumeSupported)
            out.push("volume");
        return out;
    }

    // Section 2. A list of one would just repeat the identity line above, so
    // the whole section is absent with a single player.
    readonly property var _playerRows: MediaService.players.length > 1 ? MediaService.players : []

    // The transport as `ButtonGroup` options, in the order `_transport`
    // built: icon only, no label, so the row stays a strip of controls.
    readonly property var _transportOptions: root._transport.map(function (id) {
        return {
            icon: root._transportIcon(id),
            value: id,
            enabled: root._transportEnabled(id),
            active: root._transportActive(id)
        };
    })

    function _trackIndex(id) {
        return root._tracks.indexOf(id);
    }

    function _transportIcon(id) {
        if (id === "previous")
            return "skip-back";
        if (id === "playpause")
            return MediaService.isPlaying ? "pause" : "play";
        if (id === "next")
            return "skip-forward";
        if (id === "shuffle")
            return "shuffle";
        return MediaService.loopState === "track" ? "repeat-1" : "repeat";
    }

    // The on-state of a toggle is the button's own `primary` fill (DESIGN.md
    // §5: fills are for buttons and the active toggle).
    function _transportActive(id) {
        if (id === "shuffle")
            return MediaService.shuffle;
        if (id === "loop")
            return MediaService.loopState !== "none";
        return false;
    }

    function _transportEnabled(id) {
        if (id === "previous")
            return MediaService.canGoPrevious;
        if (id === "next")
            return MediaService.canGoNext;
        return true;
    }

    function _pressTransport(id) {
        if (id === "previous")
            MediaService.previous();
        else if (id === "playpause")
            MediaService.playPause();
        else if (id === "next")
            MediaService.next();
        else if (id === "shuffle")
            MediaService.toggleShuffle();
        else if (id === "loop")
            MediaService.cycleLoop();
    }

    function _seekBy(seconds) {
        if (!MediaService.canSeek || MediaService.length <= 0)
            return;
        MediaService.seek((MediaService.position + seconds) / MediaService.length);
    }

    function _pointAt(section, index) {
        root.cursorActive = true;
        root.cursorSection = section;
        root.cursorIndex = index;
    }

    sectionCount: root._playerRows.length > 0 ? 3 : 2

    cursorCount: root.cursorSection === 0
        ? root._transport.length
        : (root.cursorSection === 1 ? root._tracks.length : root._playerRows.length)

    // Left/Right belongs to the track under the cursor in section 1, and to
    // the list itself in the other two.
    cursorStepsHorizontally: root.cursorSection === 1

    // Tab lands on the first row of the section it reached, never on
    // whatever index the previous section's cursor happened to hold.
    onCursorSectionChanged: root.cursorIndex = 0

    onCursorActivated: index => {
        if (root.cursorSection === 0) {
            var id = root._transport[index];
            if (id !== undefined && root._transportEnabled(id))
                root._pressTransport(id);
        } else if (root.cursorSection === 1) {
            if (root._tracks[index] === "progress")
                MediaService.playPause();
        } else {
            var player = root._playerRows[index];
            if (player)
                MediaService.select(player.id);
        }
    }

    onCursorStepped: (index, direction) => {
        var id = root._tracks[index];
        if (id === "progress")
            root._seekBy(direction * root._seekStepSeconds);
        else if (id === "volume")
            MediaService.setVolume(MediaService.volume + direction * root._volumeStep);
    }

    onIsOpenChanged: {
        if (!root.isOpen)
            return;
        root.cursorSection = 0;
        root.cursorIndex = 0;
    }

    SectionLabel {
        visible: !MediaService.available
        leftPadding: Theme.space.controlPaddingX
        text: "NO PLAYER"
    }

    // The now-playing block: the cover beside the source, the title, the
    // artist and the album. Four sizes of type doing the ranking, so the
    // block leads the panel without a box around it (DESIGN.md §1's ladder,
    // rung 5). The player's own name heads it as a `SectionLabel`, which
    // takes the `NOW PLAYING` label's slot: the panel header already says
    // Media, and naming the source is the thing that row can say instead.
    Row {
        id: infoRow
        width: parent.width
        visible: MediaService.available
        spacing: root._hasArt ? Theme.space.xxl : 0

        Cover {
            id: coverSlot
            visible: root._hasArt
            width: root._hasArt ? root._artSlotSize : 0
            height: root._artSlotSize
            anchors.verticalCenter: parent.verticalCenter
            source: MediaService.artUrl
            sourceSize.width: root._artSlotSize
            sourceSize.height: root._artSlotSize
            cache: false

            // Apple Music animated cover (opt-in): layered over the static
            // art, which stays the fallback for every path it doesn't cover
            // (disabled, no match, no animated art, download failure, a
            // missing QtMultimedia module). Inside the cover's own clip, so
            // it rounds with everything else.
            overlay: Loader {
                anchors.fill: parent
                active: AnimatedCoverFrameSource.active
                source: "AnimatedAlbumArt.qml"
            }
        }

        Column {
            width: infoRow.width - coverSlot.width - infoRow.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.xxs

            SectionLabel {
                width: parent.width
                visible: MediaService.identity !== ""
                text: MediaService.identity
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: MediaService.title !== "" ? MediaService.title : "Unknown title"
                color: Theme.color.foreground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.title
                font.weight: Theme.weight.medium
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: MediaService.artist !== ""
                text: MediaService.artist
                color: Theme.color.foreground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.body
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: MediaService.album !== ""
                text: MediaService.album
                color: Theme.color.mutedForeground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.bodySmall
                elide: Text.ElideRight
            }
        }
    }

    // Position: the track first, the two times under it. Every player that
    // draws this puts the numbers below the groove, because the groove is
    // what the eye tracks and a number above it reads as a label for the
    // block rather than as a readout of the line under it.
    Column {
        width: parent.width
        visible: MediaService.available
        spacing: Theme.space.xs

        Track {
            id: progressTrack
            width: parent.width
            value: MediaService.length > 0 ? MediaService.position / MediaService.length : 0
            cursor: root.cursorActive && root.cursorSection === 1 && root.cursorIndex === root._trackIndex("progress")
            interactive: true
            onContainsPointerChanged: if (progressTrack.containsPointer) root._pointAt(1, root._trackIndex("progress"))

            // Above the track's own hover tracker, which answers no button,
            // so this one still gets every press and drag.
            MouseArea {
                anchors.fill: parent
                enabled: MediaService.canSeek
                cursorShape: Qt.PointingHandCursor
                function _setFromX(x) {
                    MediaService.seek(x / progressTrack.width);
                }
                onPressed: mouse => _setFromX(mouse.x)
                onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
            }
        }

        Item {
            width: parent.width
            height: Math.max(elapsedText.implicitHeight, totalText.implicitHeight)

            Text {
                id: elapsedText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root._formatTime(MediaService.position)
                color: Theme.color.foreground
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize.bodySmall
            }

            Text {
                id: totalText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root._formatTime(MediaService.length)
                color: Theme.color.mutedForeground
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize.bodySmall
            }
        }
    }

    // The transport is a non-exclusive `ButtonGroup` (M48 D1): every button
    // is its own action rather than one of a set, and a supported toggle that
    // is on (shuffle, loop) carries the `primary` fill through the option's
    // own `active`. Its trough is a control's chrome, not a box around a
    // group, which is why it survives the no-nested-cards rule. Section 0's
    // cursor already walks this row with Left/Right, so the group takes
    // `cursorIndex` straight off the panel.
    ButtonGroup {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: MediaService.available
        height: Theme.space.controlHeight
        exclusive: false
        options: root._transportOptions
        cursorIndex: root.cursorIndex
        cursor: root.cursorActive && root.cursorSection === 0
        onPressed: index => root._pressTransport(root._transport[index])
        onHovered: (index, isHovered) => { if (isHovered) root._pointAt(0, index); }
    }

    // The player's OWN volume (MPRIS Volume), not the sink's. AudioPanel owns
    // that one, and a browser at 30% here is still whatever the sink says
    // system-wide. Drawn in the OSD's grammar (DESIGN.md §3 "OSD"): an
    // `Icon`, a `Track` and a tabular percentage on one `controlHeight` row,
    // rather than the labelled two-line block it used to take.
    Item {
        width: parent.width
        visible: MediaService.available && MediaService.volumeSupported
        height: Theme.space.controlHeight

        Icon {
            id: volumeIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            name: MediaService.volume > 0 ? (MediaService.volume < 0.5 ? "volume-1" : "volume-2") : "volume-x"
            size: Theme.fontSize.body
            color: Theme.color.mutedForeground
        }

        Text {
            id: volumeReadout
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(MediaService.volume * 100) + "%"
            color: Theme.color.mutedForeground
            font.family: Theme.fontFamilyMono
            font.pixelSize: Theme.fontSize.bodySmall
        }

        Track {
            id: volumeTrack
            anchors.left: volumeIcon.right
            anchors.leftMargin: Theme.space.iconGap
            anchors.right: volumeReadout.left
            anchors.rightMargin: Theme.space.iconGap
            anchors.verticalCenter: parent.verticalCenter
            value: MediaService.volume
            cursor: root.cursorActive && root.cursorSection === 1 && root.cursorIndex === root._trackIndex("volume")
            interactive: true
            onContainsPointerChanged: if (volumeTrack.containsPointer) root._pointAt(1, root._trackIndex("volume"))

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function _setFromX(x) {
                    MediaService.setVolume(x / volumeTrack.width);
                }
                onPressed: mouse => _setFromX(mouse.x)
                onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
            }
        }
    }

    // Two players at once is the ordinary case (a browser tab plus a music
    // app) and MPRIS names them all, so the pick MediaService makes is worth
    // overriding by hand.
    Column {
        width: parent.width
        visible: root._playerRows.length > 0
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "PLAYERS"
            count: root._playerRows.length
        }

        Flow {
            width: parent.width
            spacing: Theme.space.xs

            Repeater {
                model: root._playerRows

                delegate: Cell {
                    id: playerChip
                    required property int index
                    required property var modelData

                    // A badge sitting in a row rather than being one, so it
                    // hugs its own label (DESIGN.md §2).
                    chip: true
                    radius: Theme.radiusSm
                    selected: playerChip.modelData.id === MediaService.activeId
                    cursor: root.cursorActive && root.cursorSection === 2 && root.cursorIndex === playerChip.index
                    interactive: true
                    onContainsPointerChanged: if (playerChip.containsPointer) root._pointAt(2, playerChip.index)
                    onClicked: MediaService.select(playerChip.modelData.id)

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.xs

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: playerChip.modelData.isPlaying
                            name: "play"
                            size: Theme.fontSize.bodySmall
                            color: playerChip.foreground
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: playerChip.modelData.label
                            color: playerChip.foreground
                            font.family: Theme.fontFamilySans
                            font.pixelSize: Theme.fontSize.bodySmall
                            font.weight: Theme.weight.medium
                        }
                    }
                }
            }
        }
    }
}
