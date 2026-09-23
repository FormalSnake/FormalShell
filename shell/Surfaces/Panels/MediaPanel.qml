import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Lyrics/model.js" as Lyrics
import "../../Visualizer/styles.js" as Styles

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
// the rest of the same line, absent when the player has none). Above all of
// it, two small menus: the source (auto, every MPRIS player, the radio while
// a station is tuned, and any app with audio and no MPRIS) and the output
// that source plays on, the second only while there is more than one output
// and a stream to move. A menu opens inline under its trigger and the card
// grows to hold it, so nothing floats over the panel. The radio button in
// the header opens Radio Atlas (Surfaces/Radio/).
//
// Nothing inside either half is a second card (owner, 2026-08-26): the
// pane's own frame is `radiusMd`, a 1px `border`, `card` fill and nothing
// nested inside it, and the now-playing side keeps the same chrome it
// always did (the transport's trough, the menu triggers, the cover's own 1px
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
// the column; the menus last, the two triggers and then the open menu's
// rows, where Enter opens a menu or picks a row. The pointer never drives the lyrics cursor (M55 A5): hovering a
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
    // Radio Atlas's overlay (shell.qml): the header's radio button opens it.
    property var radio: null

    titleActions: [
        IconButton {
            name: "radio"
            visible: root.radio !== null
            tooltipText: "Radio"
            onClicked: root.radio.open()
        },
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

    // The source list's app streams and the output list both bind Pipewire
    // nodes, so they only exist while the panel is open.
    Binding {
        target: MediaService
        property: "routingWanted"
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
        if (!MediaService.available || MediaService.activeKind === "stream")
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
        var out = MediaService.hasTimeline ? ["progress"] : [];
        if (MediaService.volumeSupported)
            out.push("volume");
        return out;
    }

    // Section 2, when a provider has synced timing (spec D4/P5): the display
    // set, interludes spliced in beside the lines themselves and `parent`
    // remapped onto it, which is the array both the pane and `media lyrics`
    // index into. The service publishes it already spliced, since the wipe's
    // own span is measured against it. The resync control is the entry after
    // the last line for as long as the pane shows it.
    readonly property bool _lyricsPresent: LyricsService.state === "synced"
    readonly property var _lyricsLines: root._lyricsPresent ? LyricsService.lines : []
    readonly property int _lyricsSection: root._lyricsPresent ? 2 : -1
    readonly property int _lyricsRows: root._lyricsLines.length + (LyricsService.follow ? 0 : 1)

    function _seekLyricLine(time) {
        if (!MediaService.canSeek || MediaService.length <= 0)
            return;
        MediaService.seek(time / MediaService.length);
    }

    // Section 3 (2 without lyrics): the menu triggers, then the rows of
    // whichever menu is open.
    property string _menu: ""
    readonly property int _menuSection: MediaService.available ? (2 + (root._lyricsPresent ? 1 : 0)) : -1
    readonly property var _triggers: MediaService.canRoute ? ["source", "output"] : ["source"]

    function _sourceIcon(kind) {
        if (kind === "radio")
            return "radio";
        if (kind === "stream")
            return "audio-lines";
        return "music";
    }

    readonly property var _menuRows: {
        if (root._menu === "source")
            return [{ value: "", label: "Auto", icon: "", current: MediaService.selectedId === "", playing: false }]
                .concat(MediaService.players.map(function (p) {
                    return {
                        value: p.id,
                        label: p.label,
                        icon: root._sourceIcon(p.kind),
                        current: MediaService.selectedId === p.id,
                        playing: p.isPlaying
                    };
                }));
        if (root._menu === "output")
            return MediaService.outputs.map(function (o) {
                return { value: o.id, label: o.label, icon: "speaker", current: o.id === MediaService.outputId, playing: false };
            });
        return [];
    }

    readonly property string _outputLabel: {
        var outs = MediaService.outputs;
        for (var i = 0; i < outs.length; i++)
            if (outs[i].id === MediaService.outputId)
                return outs[i].label;
        return "Output";
    }

    // A menu with nothing to pick from closes rather than hanging open empty.
    readonly property bool _outputGone: root._menu === "output" && !MediaService.canRoute
    on_OutputGoneChanged: if (root._outputGone) root._menu = ""

    holdsEscape: root._menu !== ""
    onEscaped: root._menu = ""

    function _toggleMenu(name) {
        root._menu = root._menu === name ? "" : name;
    }

    function _pickRow(row) {
        if (root._menu === "source")
            MediaService.select(row.value);
        else
            MediaService.setOutput(row.value);
        root._menu = "";
        root._pointAt(root._menuSection, 0);
    }

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

    sectionCount: 2 + (root._lyricsPresent ? 1 : 0) + (root._menuSection >= 0 ? 1 : 0)

    cursorCount: root.cursorSection === 0
        ? root._transport.length
        : root.cursorSection === 1
            ? root._tracks.length
            : root.cursorSection === root._lyricsSection
                ? root._lyricsRows
                : root._triggers.length + root._menuRows.length

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
        } else if (index < root._triggers.length) {
            root._toggleMenu(root._triggers[index]);
        } else {
            var row = root._menuRows[index - root._triggers.length];
            if (row)
                root._pickRow(row);
        }
    }

    onCursorStepped: (index, direction) => {
        var id = root._tracks[index];
        if (id === "progress")
            root._seekBy(direction * root._seekStepSeconds);
        else if (id === "volume")
            MediaService.setVolume(MediaService.volume + direction * root._volumeStep);
    }

    // The wheel takeover is a reading session and closing the panel ends it
    // (owner, 2026-09-18: a wheel, a close, minutes of playback, and the
    // reopened pane still parked where the wheel had left it, which reads as
    // the song having run ahead of the lyrics). Spec P9's own re-arms, the
    // resync control, a new track and the keyboard cursor, all sit inside an
    // open panel, so none of them can fire while it is shut.
    onIsOpenChanged: {
        root._menu = "";
        if (!root.isOpen)
            return;
        LyricsService.follow = true;
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
                text: "No player"
            }

            // The two menu triggers: the source leading, named by what is
            // playing, the output trailing. Chips hugging their own labels,
            // so the line stays as quiet as the source caption it replaced.
            Item {
                width: parent.width
                visible: MediaService.available
                height: sourceTrigger.height

                MenuTrigger {
                    id: sourceTrigger
                    anchors.left: parent.left
                    maxWidth: parent.width - (outputTrigger.visible ? outputTrigger.width + Theme.space.xs : 0)
                    icon: root._sourceIcon(MediaService.activeKind)
                    label: MediaService.selectedId === "" ? "Auto · " + MediaService.activeLabel : MediaService.activeLabel
                    open: root._menu === "source"
                    cursor: root.cursorActive && root.cursorSection === root._menuSection && root.cursorIndex === 0
                    onContainsPointerChanged: if (sourceTrigger.containsPointer) root._pointAt(root._menuSection, 0)
                    onClicked: root._toggleMenu("source")
                }

                MenuTrigger {
                    id: outputTrigger
                    anchors.right: parent.right
                    visible: MediaService.canRoute
                    maxWidth: parent.width / 2
                    icon: "speaker"
                    label: root._outputLabel
                    open: root._menu === "output"
                    cursor: root.cursorActive && root.cursorSection === root._menuSection && root.cursorIndex === 1
                    onContainsPointerChanged: if (outputTrigger.containsPointer) root._pointAt(root._menuSection, 1)
                    onClicked: root._toggleMenu("output")
                }
            }

            // The open menu, inline: one row per choice, the current one
            // checked, a playing source marked.
            Column {
                width: parent.width
                visible: root._menuRows.length > 0

                Repeater {
                    model: root._menuRows

                    delegate: Cell {
                        id: menuRow
                        required property int index
                        required property var modelData

                        width: parent.width
                        selected: menuRow.modelData.current
                        cursor: root.cursorActive && root.cursorSection === root._menuSection
                            && root.cursorIndex === root._triggers.length + menuRow.index
                        interactive: true
                        onContainsPointerChanged: if (menuRow.containsPointer)
                            root._pointAt(root._menuSection, root._triggers.length + menuRow.index)
                        onClicked: root._pickRow(menuRow.modelData)

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.space.iconGap

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: menuRow.modelData.current ? "check" : menuRow.modelData.icon
                                size: Theme.fontSize.bodySmall
                                color: menuRow.foreground
                                opacity: name === "" ? 0 : 1
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: menuRow.modelData.label
                                color: menuRow.foreground
                                font.family: Theme.fontFamilySans
                                font.pixelSize: Theme.fontSize.bodySmall
                            }

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: menuRow.modelData.playing
                                name: "play"
                                size: Theme.fontSize.caption
                                color: Theme.color.mutedForeground
                            }
                        }
                    }
                }
            }

            // The now-playing block: the cover beside the title, the artist
            // and the album. Three sizes of type doing the ranking, so the
            // block leads the column without a box around it (DESIGN.md §1's
            // ladder, rung 5). The source trigger above names the player.
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
                // title). The same cava frame the bar cell reads, smoothed
                // toward every screen frame by VisualizerService (M55 A3),
                // drawn in the style VisualizerService.style names (M73). A
                // click steps to the next style and a wheel notch either
                // way, in memory only. Each style's resting state while the
                // panel is open and the track is paused is the honest one,
                // the same all-zero baseline the bar cell draws.
                Item {
                    id: spectrumInline
                    visible: root._spectrumVisible
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._spectrumWidth
                    height: Theme.space.controlHeight

                    VisualizerCanvas {
                        anchors.fill: parent
                        columns: root._spectrumColumns
                        active: root.isOpen
                    }

                    MouseArea {
                        id: spectrumPointer
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        readonly property string _tip: Styles.label(VisualizerService.style)
                        // A touchpad sends a notch in many small deltas.
                        property real _wheel: 0

                        onClicked: VisualizerService.setStyle("next")
                        onWheel: wheel => {
                            spectrumPointer._wheel += wheel.angleDelta.y;
                            while (Math.abs(spectrumPointer._wheel) >= 120) {
                                VisualizerService.setStyle(spectrumPointer._wheel > 0 ? "prev" : "next");
                                spectrumPointer._wheel -= spectrumPointer._wheel > 0 ? 120 : -120;
                            }
                            wheel.accepted = true;
                        }
                        onContainsMouseChanged: {
                            if (spectrumPointer.containsMouse)
                                TooltipRegistry.show(spectrumPointer, spectrumPointer._tip, "");
                            else
                                TooltipRegistry.hide(spectrumPointer);
                        }
                        on_TipChanged: {
                            if (spectrumPointer.containsMouse)
                                TooltipRegistry.show(spectrumPointer, spectrumPointer._tip, "");
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
                visible: MediaService.hasTimeline
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
                visible: MediaService.available && (root._transport.length > 0 || MediaService.volumeSupported)
                height: Theme.space.controlHeight

                ButtonGroup {
                    id: transportGroup
                    visible: root._transport.length > 0
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
                    anchors.left: transportGroup.visible ? transportGroup.right : parent.left
                    anchors.leftMargin: transportGroup.visible ? Theme.space.sectionGap : 0
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
