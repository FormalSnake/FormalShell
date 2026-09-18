import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Lyrics/model.js" as Lyrics
import "../../Visualizer/model.js" as Visualizer

// MPRIS now-playing popout (DESIGN.md §3 "Panel", spec "Panels", M55 A1-A5,
// M56 P13). Two columns while a provider has synced timing for the track:
// the now-playing column leads and a `LYRICS` pane trails it, the panel's
// one card (DESIGN.md §1's ladder, rung 5, the launcher's own preview-pane
// exception), the two sharing the content width equally; one column, full
// width, otherwise. `panelWidth` follows which of those it is
// (`popupWidthMenuSplit`/`popupWidthWide`) and morphs on `spatial` like any
// other panel resize.
//
// The pane trails the now-playing column so that lyrics arriving mid-track
// add their width after what the eye is already reading (owner,
// 2026-09-17). The card itself stays centred on the bar cell that opened it
// through the morph, like every other panel: holding the narrow width's own
// place instead left the wide card visibly off its cell (owner,
// 2026-09-18). Near either end of the bar the screen's padding takes the
// centring over and the growth goes the other way.
//
// The now-playing column runs horizontal (M55 A2): the cover beside the
// source, title, artist and album, with a twelve-column spectrum inline at
// the row's trailing end, the same cava frame the bar cell shares,
// downsampled and smoothed toward it every screen frame by
// VisualizerService, absent whenever cava is off PATH or `media.visualizer`
// is false. Then the position row (elapsed, the track, total, one line) and
// the transport row (the transport leading, the player's own volume filling
// the rest of the same line, absent when the player has none). A chip per
// registered player follows once more than one is on the bus.
//
// Nothing inside either half is a second card (owner, 2026-08-26): the
// pane's own frame is `radiusMd`, a 1px `border`, `card` fill and nothing
// nested inside it, and the now-playing side keeps the same chrome it
// always did (the transport's trough, the player chips, the cover's own 1px
// frame). What ranks the now-playing block is type: `caption` source,
// `title` track, `body` artist, `bodySmall` album. The ring the keyboard
// cursor draws on a track comes from `Track.cursor` rather than from a Cell
// wrapped around it.
//
// Everything below the title comes off MPRIS itself and is gated on the
// player's own capability flags, so a player that implements none of
// shuffle, loop, volume or seek renders the same three transport buttons and
// nothing else. Honest states: no registered player at all is `NO PLAYER`,
// and a player publishing no `mpris:artUrl` (browsers, mostly) leaves the
// cover slot out rather than showing an empty 96px square. The lyrics pane
// carries the same honesty: gone whenever `LyricsService.state` is anything
// but `synced` (off, no track, loading, a known miss, a failed lookup), so a
// track no provider has timing for never flashes a placeholder.
//
// Everything the pane itself draws (the lit set, the soft wipe and its
// glow, the depth of field, the duet layout, the comfort anchor and the
// wheel takeover) lives in LyricsPane.qml beside this file. What stays here
// is the display set the cursor counts and the seek a row activation makes.
//
// Keyboard (spec "Keyboard model"): Tab cycles whatever sections are
// present. Transport first, where Left/Right walk the buttons and Enter
// presses one; the two tracks next, where Left/Right seek five seconds or
// step the volume five percent and Enter plays/pauses; lyrics next, when
// synced, where Up/Down walk the lines, Enter seeks, and the column follows
// the cursor instead of the song for as long as it sits here, with the
// pane's resync control the entry after the last line while a wheel has
// the column; the player chips last, where Enter pins the shell to that
// player. The pointer never drives the lyrics cursor (M55 A5): hovering a
// line draws the row's own hover wash and lifts it clear of the blur, and
// nothing else, the ring and the follow-the-cursor anchor staying the
// keyboard's alone.
Panel {
    id: root

    panelIcon: "music"
    panelTitle: "Media"
    panelWidth: LyricsService.state === "synced" ? Theme.space.popupWidthMenuSplit : Theme.space.popupWidthWide

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
    // Gated on `playing` rather than `active` (A6): a paused track has
    // nothing left to grab, so staying mapped for the bar's sake would hold
    // a window open for no new frames.
    keepMapped: AnimatedCoverFrameSource.barEnabled && AnimatedCoverFrameSource.playing
    Binding {
        target: AnimatedCoverFrameSource
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

    // The lyrics pane's position clock (spec D5, Quickshell's documented
    // MprisPlayer.position idiom): re-emits `positionChanged` every frame so
    // the active line's wipe tracks playback smoothly, running only while
    // there is a synced line to move. MediaService's own Timer covers the
    // progress track at a much coarser grain and is left alone.
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

    // Section 2, when a provider has synced timing (spec D4/P5): the display
    // set, interludes spliced in beside the lines themselves and `parent`
    // remapped onto it, which is the array both the pane and `media lyrics`
    // index into. The resync control is the entry after the last line for as
    // long as the pane shows it.
    readonly property bool _lyricsPresent: LyricsService.state === "synced"
    readonly property var _lyricsLines: root._lyricsPresent ? Lyrics.displayLines(LyricsService.lines) : []
    readonly property int _lyricsSection: root._lyricsPresent ? 2 : -1
    readonly property int _lyricsRows: root._lyricsLines.length + (LyricsService.follow ? 0 : 1)

    function _seekLyricLine(time) {
        if (!MediaService.canSeek || MediaService.length <= 0)
            return;
        MediaService.seek(time / MediaService.length);
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
                ? root._lyricsRows
                : root._playerRows.length

    // Left/Right belongs to the track under the cursor in section 1, and to
    // the list itself in the other two.
    cursorStepsHorizontally: root.cursorSection === 1

    // Tab lands on the first row of the section it reached, never on
    // whatever index the previous section's cursor happened to hold.
    // Reaching the lyrics parks the column back on the song (spec P9): the
    // cursor is about to drive it, and a column still sitting where a wheel
    // left it would answer the first Up with a jump.
    onCursorSectionChanged: {
        root.cursorIndex = 0;
        if (root.cursorSection === root._lyricsSection)
            LyricsService.follow = true;
    }

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
            else
                LyricsService.follow = true;
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

    // The two-column layout (M55 A1, reversed by M56 P13): the
    // now-playing column leads and the lyrics pane trails it when a
    // provider has synced timing, the two sharing the content width
    // equally; the column alone, full width, otherwise.
    Row {
        id: contentRow
        width: parent.width
        spacing: Theme.space.sm

        readonly property real _paneWidth: (contentRow.width - contentRow.spacing) / 2

        // The now-playing column (M55 A2): the identity row, the position
        // row, the transport/volume row and the player chips, in that
        // order, `sectionGap` apart.
        Column {
            id: nowPlayingColumn
            width: root._lyricsPresent ? contentRow._paneWidth : contentRow.width
            spacing: Theme.space.sectionGap

            SectionLabel {
                visible: !MediaService.available
                leftPadding: Theme.space.controlPaddingX
                text: "NO PLAYER"
            }

            // The now-playing block: the cover beside the source, the title,
            // the artist and the album. Four sizes of type doing the
            // ranking, so the block leads the column without a box around it
            // (DESIGN.md §1's ladder, rung 5). The player's own name heads
            // it as a `SectionLabel`, which takes the `NOW PLAYING` label's
            // slot: the panel header already says Media, and naming the
            // source is the thing that row can say instead.
            Row {
                id: infoRow
                width: parent.width
                visible: MediaService.available
                // One spacing value for both gaps: Row skips the gap around
                // a child whose `visible` is false, so this is `xxl` before
                // the text column when the cover is shown, `xxl` after it
                // when the spectrum is, and both or neither follow from the
                // same rule.
                spacing: Theme.space.xxl

                Cover {
                    id: coverSlot
                    visible: root._hasArt
                    // The slot closes and opens with the art rather than
                    // snapping, and the row's own spacing follows the
                    // card's height morph beside it (M54 D10).
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

                    // Apple Music animated cover (opt-in): layered over the
                    // static art, which stays the fallback for every path it
                    // doesn't cover (disabled, no match, no animated art,
                    // download failure, a missing QtMultimedia module).
                    // Inside the cover's own clip, so it rounds with
                    // everything else.
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

                // The spectrum, inline at the row's trailing end rather than
                // a band of its own (M55 A2, the owner's own reference:
                // Apple's now-playing widget keeps its bars beside the
                // title). The same cava frame the bar cell reads,
                // downsampled to twelve columns and smoothed toward every
                // screen frame by VisualizerService (M55 A3), so a 240Hz and
                // a 144Hz screen both draw the same motion at their own
                // rate. Empty troughs while the panel is open and the track
                // is paused are the honest state, the same one the bar cell
                // draws when its own process isn't running: no extra
                // handling needed since VisualizerService.levels is already
                // the all-zero baseline then.
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

            // The position row (M55 A2): elapsed, the track, total, one
            // line, `iconGap` apart. Every player that draws this puts the
            // numbers either side of the groove, because the groove is what
            // the eye tracks and a number above it reads as a label for the
            // block rather than as a readout of the line beside it.
            Item {
                id: positionRow
                width: parent.width
                visible: MediaService.available
                height: Theme.space.controlHeight

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

                Track {
                    id: progressTrack
                    anchors.left: elapsedText.right
                    anchors.leftMargin: Theme.space.iconGap
                    anchors.right: totalText.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    value: MediaService.length > 0 ? MediaService.position / MediaService.length : 0
                    // Playback sweeps this rather than stepping it, and the
                    // clock above re-emits `positionChanged` every frame
                    // while the lyrics pane is up.
                    swept: true
                    cursor: root.cursorActive && root.cursorSection === 1 && root.cursorIndex === root._trackIndex("progress")
                    interactive: true
                    onContainsPointerChanged: if (progressTrack.containsPointer) root._pointAt(1, root._trackIndex("progress"))

                    // Above the track's own hover tracker, which answers no
                    // button, so this one still gets every press and drag.
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
            }

            // The transport and the player's own volume share one line
            // (M55 A2): a non-exclusive `ButtonGroup` (M48 D1) leading, the
            // volume's icon, track and readout filling the rest, absent
            // whole when the player has none. Every button in the group is
            // its own action rather than one of a set, and a supported
            // toggle that is on (shuffle, loop) carries the `primary` fill
            // through the option's own `active`. Its trough is a control's
            // chrome, not a box around a group, which is why it survives the
            // no-nested-cards rule. Section 0's cursor already walks this
            // row with Left/Right, so the group takes `cursorIndex` straight
            // off the panel. The volume readout is drawn in the OSD's
            // grammar (DESIGN.md §3 "OSD"): an `Icon`, a `Track` and a
            // tabular percentage.
            Item {
                id: transportRow
                width: parent.width
                visible: MediaService.available
                height: Theme.space.controlHeight

                ButtonGroup {
                    id: transportGroup
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: Theme.space.controlHeight
                    exclusive: false
                    options: root._transportOptions
                    cursorIndex: root.cursorIndex
                    cursor: root.cursorActive && root.cursorSection === 0
                    onPressed: index => root._pressTransport(root._transport[index])
                    onHovered: (index, isHovered) => { if (isHovered) root._pointAt(0, index); }
                }

                Icon {
                    id: volumeIcon
                    visible: MediaService.volumeSupported
                    anchors.left: transportGroup.right
                    anchors.leftMargin: Theme.space.sectionGap
                    anchors.verticalCenter: parent.verticalCenter
                    name: MediaService.volume > 0 ? (MediaService.volume < 0.5 ? "volume-1" : "volume-2") : "volume-x"
                    size: Theme.fontSize.body
                    color: Theme.color.mutedForeground
                }

                Text {
                    id: volumeReadout
                    visible: MediaService.volumeSupported
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(MediaService.volume * 100) + "%"
                    color: Theme.color.mutedForeground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.bodySmall
                }

                Track {
                    id: volumeTrack
                    visible: MediaService.volumeSupported
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

            // Two players at once is the ordinary case (a browser tab plus a
            // music app) and MPRIS names them all, so the pick MediaService
            // makes is worth overriding by hand.
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

                            // A badge sitting in a row rather than being one,
                            // so it hugs its own label (DESIGN.md §2).
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

        // The lyrics pane (M56 P13, LyricsPane.qml): the panel's one card,
        // trailing the column so a lyrics arrival grows the panel away from
        // what is already on screen. Gone whenever `LyricsService.state` is
        // anything but `synced`, so a track nothing has timing for never
        // flashes a placeholder; `Row` skips the spacing gap around an
        // invisible child, so the column's own width binding is the only
        // place that needs to know which case it is.
        LyricsPane {
            visible: root._lyricsPresent
            width: contentRow._paneWidth
            height: Math.max(nowPlayingColumn.implicitHeight, Theme.space.controlHeight * 6)
            lines: root._lyricsLines
            cursorOn: root.cursorActive && root.cursorSection === root._lyricsSection
            cursorIndex: root.cursorIndex
            onSeekRequested: time => root._seekLyricLine(time)
        }
    }
}
