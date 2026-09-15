import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Lyrics/model.js" as Lyrics
import "../../Visualizer/model.js" as Visualizer

// MPRIS now-playing popout (DESIGN.md §3 "Panel", spec "Panels"). Four
// blocks, each a section of the panel's own content column and so
// `sectionGap` apart: the cover beside the source, title, artist and album,
// with a twelve-column spectrum inline at the row's trailing end (M55 A2):
// the same cava frame the bar cell shares, downsampled and smoothed toward
// it every screen frame by VisualizerService, absent whenever cava is off
// PATH or `media.visualizer` is false, and empty-troughed rather than
// hidden while the panel is open and the track is paused. Then the position
// track with its two times under it; the transport; the player's own
// volume. A `LYRICS` block follows once lrclib has synced timing for the
// track (M55 D4/D5): absent for every other state, no spinner and no
// placeholder. A chip per registered player follows once more than one is
// on the bus.
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
// cover slot out rather than showing an empty 96px square. The lyrics block
// carries the same honesty: gone whenever `LyricsService.state` is anything
// but `synced` (off, no track, loading, a known miss, a failed lookup), so
// a track lrclib has nothing timed for never flashes a placeholder.
//
// Keyboard (spec "Keyboard model"): Tab cycles whatever sections are
// present. Transport first, where Left/Right walk the buttons and Enter
// presses one; the two tracks next, where Left/Right seek five seconds or
// step the volume five percent and Enter plays/pauses; lyrics next, when
// synced, where Up/Down walk the lines, Enter seeks, and the column follows
// the cursor instead of the song for as long as it sits here; the player
// chips last, where Enter pins the shell to that player.
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

    // LyricsService's own hidden-work gate (spec D3): a lookup only ever
    // runs while this panel is open.
    Binding {
        target: LyricsService
        property: "panelWants"
        value: root.isOpen
    }

    // media.visualizer (spec D8): the panel's own opt-out for the spectrum
    // band, independent of the bar cell's bar.layout opt-in.
    readonly property bool _spectrumEnabled: Config.loaded && Config.get("media.visualizer", true)

    // The inline spectrum's own visibility (M55 A2) and footprint: twelve
    // fixed-width columns, never stretched to fill whatever room the
    // identity row has left, since it sits beside the title rather than
    // under it.
    readonly property bool _spectrumVisible: MediaService.available && root._spectrumEnabled
        && VisualizerService.state === "available"
    readonly property int _spectrumColumns: 12
    readonly property real _spectrumWidth: root._spectrumColumns * Theme.space.trackThickness
        + (root._spectrumColumns - 1) * Theme.space.xxs

    // VisualizerService's second gate consumer (spec D6): the shared cava
    // process runs for this panel's sake too while it is open and the band
    // is enabled, on top of whatever bar cells already want it for.
    Binding {
        target: VisualizerService
        property: "panelWants"
        value: root.isOpen && root._spectrumEnabled
    }

    // The lyrics block's position clock (spec D5, Quickshell's documented
    // MprisPlayer.position idiom): re-emits `positionChanged` every frame so
    // the active line and the word wipe track playback smoothly, running
    // only while there is a synced line to move. MediaService's own Timer
    // covers the progress track at a much coarser grain and is left alone.
    FrameAnimation {
        running: root.isOpen && MediaService.isPlaying && LyricsService.state === "synced"
        onTriggered: {
            if (MediaService.activePlayer)
                MediaService.activePlayer.positionChanged();
        }
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

    // Section 2, when lrclib has synced timing (spec D4/D5): interludes
    // spliced in beside the lines themselves, both carrying `time`, so
    // `Lyrics.indexForTime` addresses the two alike.
    readonly property bool _lyricsPresent: LyricsService.state === "synced"
    readonly property var _lyricsLines: root._lyricsPresent ? Lyrics.displayLines(LyricsService.lines) : []
    readonly property int _lyricsSection: root._lyricsPresent ? 2 : -1

    // The song's own place in `_lyricsLines`, -1 before the first entry.
    readonly property int _lyricsActiveIndex: Lyrics.indexForTime(root._lyricsLines, MediaService.position)

    // What the column centres: the keyboard cursor's row while it sits in
    // this section, the song's own row otherwise (spec D5), clamped to the
    // first entry before anything has started.
    readonly property int _lyricsAnchorIndex: (root.cursorActive && root.cursorSection === root._lyricsSection)
        ? root.cursorIndex
        : Math.max(0, root._lyricsActiveIndex)

    function _seekLyricLine(time) {
        if (!MediaService.canSeek || MediaService.length <= 0)
            return;
        MediaService.seek(time / MediaService.length);
    }

    // An interlude's three dots light in order as their third of its
    // `[time, end]` span elapses.
    function _interludeDotLit(interlude, dotIndex) {
        var span = interlude.end - interlude.time;
        if (span <= 0)
            return true;
        return MediaService.position >= interlude.time + span * (dotIndex + 1) / 3;
    }

    // Section 3 (2 without lyrics). A list of one would just repeat the
    // identity line above, so the whole section is absent with a single
    // player.
    readonly property var _playerRows: MediaService.players.length > 1 ? MediaService.players : []
    readonly property int _playersSection: root._playerRows.length > 0
        ? (2 + (root._lyricsPresent ? 1 : 0)) : -1

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

    sectionCount: 2 + (root._lyricsPresent ? 1 : 0) + (root._playerRows.length > 0 ? 1 : 0)

    cursorCount: root.cursorSection === 0
        ? root._transport.length
        : root.cursorSection === 1
            ? root._tracks.length
            : root.cursorSection === root._lyricsSection
                ? root._lyricsLines.length
                : root._playerRows.length

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
        } else if (root.cursorSection === root._lyricsSection) {
            var entry = root._lyricsLines[index];
            if (entry)
                root._seekLyricLine(entry.time);
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
        // One spacing value for both gaps: Row skips the gap around a
        // child whose `visible` is false, so this is `xxl` before the text
        // column when the cover is shown, `xxl` after it when the
        // spectrum is, and both or neither follow from the same rule.
        spacing: Theme.space.xxl

        Cover {
            id: coverSlot
            visible: root._hasArt
            // The slot closes and opens with the art rather than snapping,
            // and the row's own spacing follows the card's height morph
            // beside it (M54 D10).
            width: root._hasArt ? root._artSlotSize : 0
            height: root._artSlotSize
            anchors.verticalCenter: parent.verticalCenter
            source: MediaService.artUrl
            sourceSize.width: root._artSlotSize
            sourceSize.height: root._artSlotSize
            cache: false

            Behavior on width {
                Anim {}
            }

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
            width: infoRow.width - coverSlot.width - (root._hasArt ? infoRow.spacing : 0)
                - (root._spectrumVisible ? infoRow.spacing + root._spectrumWidth : 0)
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

        // The spectrum, inline at the row's trailing end rather than a band
        // of its own (M55 A2, the owner's own reference: Apple's now-playing
        // widget keeps its bars beside the title). The same cava frame the
        // bar cell reads, downsampled to twelve columns and smoothed toward
        // every screen frame by VisualizerService (M55 A3), so a 240Hz and a
        // 144Hz screen both draw the same motion at their own rate. Empty
        // troughs while the panel is open and the track is paused are the
        // honest state, the same one the bar cell draws when its own
        // process isn't running: no extra handling needed since
        // VisualizerService.levels is already the all-zero baseline then.
        Item {
            id: spectrumInline
            visible: root._spectrumVisible
            anchors.verticalCenter: parent.verticalCenter
            width: root._spectrumWidth
            height: Theme.space.controlHeight

            readonly property var _levels: Visualizer.downsample(VisualizerService.levels, root._spectrumColumns)

            Row {
                anchors.fill: parent
                spacing: Theme.space.xxs

                Repeater {
                    model: root._spectrumColumns

                    // primitive-exempt: one spectrum column's groove, the panel's own
                    // copy of the bar cell's vertical track.
                    Rectangle {
                        id: column
                        required property int index

                        width: Theme.space.trackThickness
                        height: parent.height
                        radius: Math.min(Theme.radiusSm, width / 2)
                        color: Theme.color.muted

                        readonly property real _level: spectrumInline._levels[column.index] || 0
                        readonly property string _band: Visualizer.levelColorBand(column._level)

                        // primitive-exempt: the column's fill, bottom-up like the bar
                        // cell's own track.
                        Rectangle {
                            y: parent.height - height
                            width: parent.width
                            height: column._level > 0
                                ? Math.max(parent.height * column._level, column.radius * 2)
                                : 0
                            radius: column.radius
                            color: column._band === "accent"
                                ? Theme.color.primary
                                : column._band === "content"
                                    ? Theme.color.foreground
                                    : Theme.color.mutedForeground
                        }
                    }
                }
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

    // Lines a word at a time under the active line, ranked by distance
    // otherwise: kopuz's blur and caelestia's mask, drawn here as the one
    // dimension DESIGN.md's ladder allows (spec D5). Every row is
    // interactive (a seek), so the section takes `Cell { ghost: true }` at
    // `spacing: 0` like any other uniform list (DESIGN.md §3 "Panel").
    Column {
        width: parent.width
        visible: root._lyricsPresent
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "LYRICS"
        }

        Item {
            id: lyricsViewport
            width: parent.width
            height: Theme.space.controlHeight * 5
            clip: true

            Column {
                id: lyricsColumn
                width: parent.width
                spacing: 0
                // The active (or cursored) item's vertical centre on the
                // viewport's own centre; before the first entry that is the
                // first item, `_lyricsAnchorIndex`'s own floor.
                y: {
                    var item = lyricsRepeater.itemAt(root._lyricsAnchorIndex);
                    var centre = lyricsViewport.height / 2;
                    return item ? centre - item.y - item.height / 2 : centre;
                }

                Behavior on y {
                    Anim {}
                }

                Repeater {
                    id: lyricsRepeater
                    model: root._lyricsLines

                    delegate: Cell {
                        id: lineCell
                        required property int index
                        required property var modelData

                        width: parent.width
                        ghost: true
                        interactive: true
                        cursor: root.cursorActive && root.cursorSection === root._lyricsSection
                            && root.cursorIndex === lineCell.index
                        onContainsPointerChanged: if (lineCell.containsPointer)
                            root._pointAt(root._lyricsSection, lineCell.index)
                        onClicked: root._seekLyricLine(lineCell.modelData.time)

                        readonly property bool _interlude: lineCell.modelData.interlude === true
                        readonly property bool _active: !lineCell._interlude
                            && lineCell.index === root._lyricsActiveIndex
                        readonly property bool _hasWordWipe: lineCell._active
                            && lineCell.modelData.words && lineCell.modelData.words.length > 0
                        readonly property int _activeWordIndex: lineCell._hasWordWipe
                            ? Lyrics.wordIndexForTime(lineCell.modelData.words, MediaService.position) : -1

                        Item {
                            width: parent.width
                            height: lineCell._interlude
                                ? interludeRow.implicitHeight
                                : (lineCell._hasWordWipe ? wordFlow.implicitHeight : lineText.implicitHeight)
                            // Depth alone carries the ramp (spec D5): 1 at
                            // the active line, then 0.7, 0.45, 0.25 and no
                            // lower, an interlude ranked exactly like a line.
                            opacity: Lyrics.depthOpacity(lineCell.index - root._lyricsActiveIndex)

                            Behavior on opacity {
                                Anim { kind: "effects" }
                            }

                            Row {
                                id: interludeRow
                                visible: lineCell._interlude
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.space.xxs

                                Repeater {
                                    model: 3

                                    delegate: Rectangle {
                                        id: interludeDot
                                        required property int index

                                        // primitive-exempt: one of an interlude's three timing
                                        // dots, a decorative indicator no primitive draws.
                                        width: 6
                                        height: 6
                                        radius: Theme.pillRadius(interludeDot.width)
                                        color: root._interludeDotLit(lineCell.modelData, interludeDot.index)
                                            ? Theme.color.foreground : Theme.color.mutedForeground

                                        Behavior on color {
                                            CAnim {}
                                        }
                                    }
                                }
                            }

                            TextMetrics {
                                id: spaceMetrics
                                font.family: Theme.fontFamilySans
                                font.pixelSize: Theme.fontSize.title
                                font.weight: Theme.weight.medium
                                text: " "
                            }

                            // Sung words light on their own crossing rather than the
                            // line's as a whole (spec D5): only the active line ever
                            // carries word timing worth drawing this way.
                            Flow {
                                id: wordFlow
                                visible: lineCell._hasWordWipe
                                width: parent.width
                                spacing: spaceMetrics.advanceWidth

                                Repeater {
                                    model: wordFlow.visible ? lineCell.modelData.words : []

                                    delegate: Text {
                                        required property int index
                                        required property var modelData

                                        text: modelData.text
                                        font.family: Theme.fontFamilySans
                                        font.pixelSize: Theme.fontSize.title
                                        font.weight: Theme.weight.medium
                                        color: index <= lineCell._activeWordIndex
                                            ? Theme.color.foreground : Theme.color.mutedForeground

                                        Behavior on color {
                                            CAnim {}
                                        }
                                    }
                                }
                            }

                            Text {
                                id: lineText
                                visible: !lineCell._interlude && !lineCell._hasWordWipe
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: lineCell.modelData.text || ""
                                font.family: Theme.fontFamilySans
                                font.pixelSize: lineCell._active ? Theme.fontSize.title : Theme.fontSize.body
                                font.weight: lineCell._active ? Theme.weight.medium : Theme.weight.normal
                                color: lineCell._active ? Theme.color.foreground : Theme.color.mutedForeground

                                Behavior on font.pixelSize {
                                    Anim { kind: "spatialFast" }
                                }
                                Behavior on color {
                                    CAnim {}
                                }
                            }
                        }
                    }
                }
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
                    cursor: root.cursorActive && root.cursorSection === root._playersSection
                        && root.cursorIndex === playerChip.index
                    interactive: true
                    onContainsPointerChanged: if (playerChip.containsPointer)
                        root._pointAt(root._playersSection, playerChip.index)
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
