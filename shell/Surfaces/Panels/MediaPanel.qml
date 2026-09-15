import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Lyrics/model.js" as Lyrics
import "../../Visualizer/model.js" as Visualizer

// MPRIS now-playing popout (DESIGN.md §3 "Panel", spec "Panels", M55 A1-A5).
// Two columns while lrclib has synced timing for the track: a `LYRICS` pane
// on the left, the panel's one card (DESIGN.md §1's ladder, rung 5, the
// launcher's own preview-pane exception), and the now-playing column on the
// right, the two sharing the content width equally; one column, full width,
// otherwise. `panelWidth` follows which of those it is
// (`popupWidthMenuSplit`/`popupWidthWide`) and morphs on `spatial` like any
// other panel resize.
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
// track lrclib has nothing timed for never flashes a placeholder.
//
// The pane's active line wipes a chunk at a time rather than a word at a
// time (M55 A3b, kopuz's `parse_enhanced_words`/`paintChunks`): a run of
// chunks joined by no whitespace (`Lyrics.chunkWords`) draws as one word, a
// `Row` of `Text`s with a clipped `foreground` copy over each one, its clip
// width the chunk's own 0..1 progress (`Lyrics.chunkProgress`, capped at
// 1.2s so a pause holds the wipe rather than creeping through it). A
// syllable-stamped source reads as a sweep through the letters of each word,
// a word-stamped one as a sweep word by word, with no colour crossfade
// anywhere in it: the clip's own width is the only thing that moves. An
// instrumental gap draws a `music` icon the same way, a foreground copy
// clipped left to right over the gap (M55 A4); the three dots are gone.
//
// Every line, active or not, renders at ONE font size (`Theme.fontSize.title`,
// `medium` weight) so a line's own layout box never changes shape when it
// takes or loses the cursor (the choppiness the owner reported on a 240Hz
// screen, 2026-09-15): what tells an inactive line apart is `scale: 0.85`
// from its own left edge, a paint-only transform under `Behavior on scale`,
// never `font.pixelSize`. With every row's height therefore constant, the
// column's own `y` is exact rather than chased: computed straight off the
// anchored row's `y` and `height`, re-evaluated whenever the column's own
// height changes too so a track change's row count settles before the next
// travel starts. Per-frame reads of `MediaService.position` are confined to
// the active row; every other row's progress is a static 0 or 1 (already
// sung or not yet reached), so a delegate holds no per-frame dependency at
// all until the position actually reaches it.
//
// Keyboard (spec "Keyboard model"): Tab cycles whatever sections are
// present. Transport first, where Left/Right walk the buttons and Enter
// presses one; the two tracks next, where Left/Right seek five seconds or
// step the volume five percent and Enter plays/pauses; lyrics next, when
// synced, where Up/Down walk the lines, Enter seeks, and the column follows
// the cursor instead of the song for as long as it sits here; the player
// chips last, where Enter pins the shell to that player. The pointer never
// drives the lyrics cursor (M55 A5): hovering a line draws the row's own
// hover wash and nothing else, the ring and the follow-the-cursor anchor
// staying the keyboard's alone.
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

    // Chunks in `chunkWords`' own grouping, each annotated with its own
    // absolute index into the line's `words` so a delegate can hand itself
    // straight to `Lyrics.chunkProgress` rather than searching for its own
    // place in the array every frame.
    function _chunkGroups(words) {
        var groups = Lyrics.chunkWords(words);
        var out = [];
        var index = 0;
        for (var g = 0; g < groups.length; g++) {
            var word = [];
            for (var c = 0; c < groups[g].length; c++) {
                word.push({ text: groups[g][c].text, chunkIndex: index });
                index++;
            }
            out.push(word);
        }
        return out;
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
    // The one per-frame read the panel itself does; every delegate below
    // reads this rather than `MediaService.position` directly.
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

    // The two-column layout (M55 A1): the lyrics pane on the left when
    // synced, the now-playing column on the right, sharing the content
    // width equally; the column alone, full width, otherwise. `Row` skips
    // the spacing gap around an invisible child, so the column's own width
    // binding is the only place that needs to know which case it is.
    Row {
        id: contentRow
        width: parent.width
        spacing: Theme.space.sm

        readonly property real _paneWidth: (contentRow.width - contentRow.spacing) / 2

        // The pane is the one card this panel spends inside its own frame
        // (DESIGN.md §1's ladder, rung 5): the launcher preview pane's own
        // chrome, `radiusMd` over `Card`'s usual `radiusXl`, nothing drawn
        // inside it beyond the label and the viewport.
        Card {
            id: lyricsPane
            visible: root._lyricsPresent
            width: contentRow._paneWidth
            height: Math.max(nowPlayingColumn.implicitHeight, Theme.space.controlHeight * 6)
            radius: Theme.radiusMd

            SectionLabel {
                id: lyricsPaneLabel
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                text: "LYRICS"
            }

            Item {
                id: lyricsViewport
                anchors.top: lyricsPaneLabel.bottom
                anchors.topMargin: Theme.space.rowGap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true

                // The width of one space in the line font, shared by every
                // row's `Flow` rather than measured per delegate.
                TextMetrics {
                    id: spaceMetrics
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.title
                    font.weight: Theme.weight.medium
                    text: " "
                }

                Column {
                    id: lyricsColumn
                    width: parent.width
                    spacing: 0
                    // The anchored item's vertical centre on the viewport's
                    // own centre; before the first entry that is the first
                    // item, `_lyricsAnchorIndex`'s own floor. Every row
                    // renders at one font size (see the header comment), so
                    // `item.y`/`height` never move on activation alone;
                    // `lyricsColumn.height` is read too, purely so this
                    // re-evaluates once a track change's row count has
                    // settled rather than mid-repopulation.
                    y: {
                        var item = lyricsRepeater.itemAt(root._lyricsAnchorIndex);
                        var centre = lyricsViewport.height / 2;
                        var _settled = lyricsColumn.height;
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
                            onClicked: root._seekLyricLine(lineCell.modelData.time)

                            readonly property bool _interlude: lineCell.modelData.interlude === true
                            readonly property bool _active: !lineCell._interlude
                                && lineCell.index === root._lyricsActiveIndex
                            readonly property bool _hasChunks: lineCell._active
                                && lineCell.modelData.words && lineCell.modelData.words.length > 0
                            readonly property var _wordGroups: lineCell._hasChunks
                                ? root._chunkGroups(lineCell.modelData.words) : []
                            // The next entry's own time (spec: a line's end
                            // is the next line's time when there is one),
                            // undefined for the last entry so chunkEnd/
                            // chunkProgress fall back to their own fudge.
                            readonly property var _lineEnd: {
                                var next = root._lyricsLines[lineCell.index + 1];
                                return next ? next.time : undefined;
                            }
                            // A past interlude sits fully lit, a future one
                            // fully dark, no clock needed for either; only
                            // the active one reads the position, per frame.
                            readonly property real _interludeProgress: !lineCell._interlude
                                ? 0
                                : lineCell._active
                                    ? (lineCell.modelData.end > lineCell.modelData.time
                                        ? Math.max(0, Math.min(1, (MediaService.position - lineCell.modelData.time)
                                            / (lineCell.modelData.end - lineCell.modelData.time)))
                                        : (MediaService.position >= lineCell.modelData.time ? 1 : 0))
                                    : (lineCell.index < root._lyricsActiveIndex ? 1 : 0)

                            Item {
                                id: lineItem
                                width: parent.width
                                height: lineCell._interlude
                                    ? interludeRow.implicitHeight
                                    : (lineCell._hasChunks ? wordFlow.implicitHeight : lineText.implicitHeight)
                                // Depth carries the ramp (spec D5): 1 at the
                                // active line, then 0.7, 0.45, 0.25 and no
                                // lower, an interlude ranked exactly like a
                                // line. `edgeFraction` fades a row the
                                // viewport's own top or bottom edge slices,
                                // caelestia's mask done with opacity rather
                                // than a shader, so a cut-off line reads as
                                // fading out under the LYRICS label instead
                                // of a hard clip (owner, 2026-09-15): `top`
                                // is the row's own position after the
                                // column's travel, so the fade tracks it
                                // frame by frame during that Behavior.
                                opacity: Lyrics.depthOpacity(lineCell.index - root._lyricsActiveIndex)
                                    * Lyrics.edgeFraction(lyricsColumn.y + lineCell.y, lineCell.height, lyricsViewport.height)
                                // The active/inactive tell (owner,
                                // 2026-09-15): a transform, never a relayout,
                                // so a line's box never changes shape on
                                // activation. Left-anchored so the row reads
                                // as growing from where it already starts.
                                scale: lineCell._active ? 1 : 0.85
                                transformOrigin: Item.Left

                                Behavior on opacity {
                                    Anim { kind: "effects" }
                                }
                                Behavior on scale {
                                    Anim { kind: "spatialFast" }
                                }

                                // M55 A4: an instrumental stretch is a
                                // `music` icon wiping left to right over the
                                // gap instead of the three dots it replaces.
                                Item {
                                    id: interludeRow
                                    visible: lineCell._interlude
                                    implicitWidth: noteIcon.implicitWidth
                                    implicitHeight: noteIcon.implicitHeight

                                    Icon {
                                        id: noteIcon
                                        name: "music"
                                        size: Theme.fontSize.title
                                        color: Theme.color.mutedForeground
                                    }

                                    Item {
                                        anchors.left: noteIcon.left
                                        anchors.top: noteIcon.top
                                        width: lineCell._interludeProgress * noteIcon.width
                                        height: noteIcon.height
                                        clip: true

                                        Icon {
                                            name: "music"
                                            size: Theme.fontSize.title
                                            color: Theme.color.foreground
                                        }
                                    }
                                }

                                // M55 A3/A3b: the active line's chunk wipe.
                                // A word is a `Row` of the chunks
                                // `chunkWords` grouped for it, no spacing
                                // between them; every other line, word
                                // timing or not, paints as plain text below,
                                // since the wipe only means something as it
                                // happens.
                                Flow {
                                    id: wordFlow
                                    visible: lineCell._hasChunks
                                    width: parent.width
                                    spacing: spaceMetrics.advanceWidth

                                    Repeater {
                                        model: wordFlow.visible ? lineCell._wordGroups : []

                                        delegate: Row {
                                            id: wordRow
                                            required property var modelData
                                            spacing: 0

                                            Repeater {
                                                model: wordRow.modelData

                                                delegate: Item {
                                                    id: chunkItem
                                                    required property var modelData

                                                    readonly property real _progress: lineCell._active
                                                        ? Lyrics.chunkProgress(lineCell.modelData.words,
                                                            chunkItem.modelData.chunkIndex, lineCell._lineEnd, MediaService.position)
                                                        : 0

                                                    width: chunkBase.implicitWidth
                                                    height: chunkBase.implicitHeight

                                                    Text {
                                                        id: chunkBase
                                                        text: chunkItem.modelData.text
                                                        font.family: Theme.fontFamilySans
                                                        font.pixelSize: Theme.fontSize.title
                                                        font.weight: Theme.weight.medium
                                                        color: Theme.color.mutedForeground
                                                    }

                                                    // The sung copy, clipped to the chunk's
                                                    // own progress: no colour crossfade
                                                    // anywhere in the wipe, only this width.
                                                    Item {
                                                        anchors.left: chunkBase.left
                                                        anchors.top: chunkBase.top
                                                        width: chunkItem._progress * chunkBase.width
                                                        height: chunkBase.height
                                                        clip: true

                                                        Text {
                                                            text: chunkBase.text
                                                            font: chunkBase.font
                                                            color: Theme.color.foreground
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    id: lineText
                                    visible: !lineCell._interlude && !lineCell._hasChunks
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: lineCell.modelData.text || ""
                                    font.family: Theme.fontFamilySans
                                    font.pixelSize: Theme.fontSize.title
                                    font.weight: Theme.weight.medium
                                    color: lineCell._active ? Theme.color.foreground : Theme.color.mutedForeground

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
    }
}
