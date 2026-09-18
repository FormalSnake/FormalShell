import QtQuick
import QtQuick.Effects
import qs.Core
import qs.Components
import qs.Services
import "../../Lyrics/model.js" as Lyrics

// The media panel's lyrics pane (M56, spec P5 to P9), kopuz's
// crates/components/src/playback/lyrics.rs drawn on this shell's own tokens.
// A sibling file rather than another block inside MediaPanel.qml, the way
// Menu.qml keeps MenuRow beside it.
//
// Several lines are lit at once (spec P5): the active main line, plus every
// background or duet line whose own timing still covers the position. The
// position they all read is `LyricsService.positionSeconds`, the player's
// clock led by the model's own lead with `media.lyricsOffsetMs` on top, and
// the model answers the set; nothing here decides what is lit.
//
// Every line draws its chunks, lit or not (M69): a lit line is the same
// chunks with the sung copy masked over them, never a second form of the
// row. Drawing a dark line as one wrapped `Text` and a lit one as a `Flow`
// of chunks wraps the two differently, since a chunk carries no kerning
// across its own split, so a line change resized the row that lit and the
// row that went dark, shifted every row under them and moved the scroll's
// own target mid-travel (owner, 2026-09-18). `lineText` stays as the
// measuring rod an opposite line's right alignment needs, and as the form a
// line with no words at all falls back to.
//
// A chunk is the `mutedForeground` word under a `foreground` copy masked by
// a horizontal gradient sliding across it, the band between the two about a
// fifth of the chunk wide, so the wipe has a soft edge rather than the hard
// clip M55 drew. The mask is one such gradient per row the chunk's own text
// laid out on, never one across the whole box: a `Flow` breaks between its
// items and a chunk too wide for the pane breaks inside its own `Text`, and
// a single gradient over that box lit every row of it left of one x, so a
// second row read as sung before the first row had finished (owner,
// 2026-09-18). `chunkRowBands` and `rowWipe` carry the edge over the break
// in reading order instead.
// kopuz reads its own unsung half at 0.45 of the sung alpha
// and MultiEffect cannot: its mask thresholds rather than multiplies, so
// every alpha above the threshold is fully sung. The mask runs to 0 instead
// and the unsung reading is the copy underneath.
// The chunk being sung carries a glow (`shadowEnabled`, no offset)
// that decays once its own span is over, and the effect is off entirely at
// glow 0 so a chunk nobody is singing costs nothing.
//
// Depth of field (spec P7, the owner's exception to the no-blur rule): every
// line that is not lit blurs by its distance in rows from the anchor, on top
// of M55's opacity ramp rather than instead of it. Both ramps are spent over
// the rows the pane has room for (`rowSpans`), not over a fixed three: a
// ramp that bottomed out three rows from the anchor left everything past it
// at the floor, so a pane with room for ten lines still read as four (owner,
// 2026-09-18). The anchor is the active
// main line, else the highest lit secondary, else the last anchor, so a gap
// between lines holds the ramp where it was instead of flattening the list.
// A hovered row and the keyboard cursor's row lift to 0 so they can be read
// before they are chosen. The effect exists only on rows the viewport still
// shows whose blur is above 0: a row scrolled out, or one that has settled
// back on 0, carries no layer at all.
//
// Layout (spec P8): main lines at `title`, background lines at `body`
// indented one `controlPaddingX` on their voice's side, and, on a track with
// any duet turn, the opposite lines right-aligned and italic with every line
// capped at 90% of the pane. Activation stays a transform and never a
// relayout, so a line's own box is the same shape lit or dark.
//
// Scroll (spec P9): the lit main line's top rests 42% down the viewport, not
// at its centre. A wheel over the pane takes the column over, which parks the
// song's own travel until the resync button, a new track, the keyboard
// cursor entering the section, or the panel being opened again re-arms it.
// `LyricsService.follow` is where that state lives, so `media lyrics` can
// report it.
Card {
    id: root

    // The display set (interludes spliced in, `parent` remapped) and the
    // panel's own keyboard cursor, which counts these rows plus the resync
    // control after them.
    property var lines: []
    property bool cursorOn: false
    property int cursorIndex: 0

    signal seekRequested(real time)

    radius: Theme.radiusMd

    // The one per-frame read in the pane (spec P5): every lit-set function
    // and every chunk takes its time from here.
    readonly property real _position: LyricsService.positionSeconds

    readonly property var _mainIndices: Lyrics.mainLineIndices(root.lines)
    readonly property int _activeIndex: Lyrics.activeMainLineIndex(root.lines, root._mainIndices, root._position)

    // `activeSecondaryLines` builds a fresh array every frame the position
    // moves. Republishing it only when the set itself changes keeps every
    // row's own `_lit` binding off the per-frame clock; `_secondary` is what
    // the rows read.
    readonly property var _secondaryNow: Lyrics.activeSecondaryLines(root.lines, root._mainIndices,
        root._position, root._activeIndex)
    readonly property string _secondaryKey: root._secondaryNow.join(",")
    property var _secondary: []
    on_SecondaryKeyChanged: root._secondary = root._secondaryNow

    // The depth ramp's anchor holds its last value through a gap with
    // nothing lit (spec P5), and the keyboard cursor takes it over while it
    // sits in this section (M55's own rule).
    property int _lastAnchor: 0
    readonly property int _litAnchor: root._activeIndex >= 0
        ? root._activeIndex
        : (root._secondary.length > 0 ? Math.max.apply(null, root._secondary) : root._lastAnchor)
    on_LitAnchorChanged: root._lastAnchor = root._litAnchor
    readonly property int _anchorIndex: root.cursorOn ? root.cursorIndex : root._litAnchor

    // A track with one duet turn lays every line out as a side (spec P8), so
    // this is a property of the whole set rather than of a line.
    readonly property bool _hasOpposite: {
        for (var i = 0; i < root.lines.length; i++) {
            if (root.lines[i].oppositeTurn)
                return true;
        }
        return false;
    }

    // `blurFor` caps at 6px and the strength key reaches 200, so this is the
    // most px the ramp can ask for. Fixed rather than bound to the live
    // strength: MultiEffect rebuilds its shader when `blurMax` changes, which
    // is not something to do while a row is animating.
    readonly property int _blurMaxPx: 12

    // Chunks in `chunkWords`' own grouping, each carrying its absolute index
    // into the line's `words` so a delegate hands itself straight to
    // `chunkProgress` rather than searching the array every frame.
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

    // How far the two depth ramps reach, in rows, either side of the
    // anchored row. The pitch is the column's own settled height over its
    // row count rather than a font measurement, so a track whose lines wrap
    // is measured as it actually draws, and both re-evaluate whenever the
    // card morphs the viewport under them.
    readonly property real _rowPitch: (root.lines.length > 0 && lyricsColumn.height > 0)
        ? lyricsColumn.height / root.lines.length
        : 0
    readonly property var _rowSpans: Lyrics.rowSpans(lyricsViewport.height, root._rowPitch)

    // What one row of words costs, which is what the edge fade is spent
    // over. A measurement rather than the column's own average: the average
    // is the right unit for how many rows fit, and the wrong one for a fade
    // that belongs to a row, since one wrapped line in the track would make
    // every short row fade earlier than it should.
    readonly property real _edgeRamp: Math.max(Theme.space.controlHeight,
        mainSpaceMetrics.height + Theme.space.controlPaddingY * 2)

    // Where the column rests with row `index` parked at the comfort offset.
    // `itemAt` is a call rather than a dependency, so every caller re-reads
    // `lyricsColumn.height` to re-evaluate once a track change's row count
    // has settled.
    function _restingY(index) {
        var item = lyricsRepeater.itemAt(index);
        return item ? Lyrics.comfortY(lyricsViewport.height, item.y, item.height)
            : Lyrics.comfortY(lyricsViewport.height, 0, 0);
    }

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

        // The width of one space in each line font, shared by every row's
        // `Flow` rather than measured per delegate.
        TextMetrics {
            id: mainSpaceMetrics
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.title
            font.weight: Theme.weight.medium
            text: " "
        }

        TextMetrics {
            id: backgroundSpaceMetrics
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
            text: " "
        }

        // The wheel takes the column over (spec P9) and the song stops
        // moving it until something re-arms `follow`. Declared over the
        // viewport, so it is delivered before the panel's own WheelScroll
        // and the card behind this pane never scrolls instead.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: event => {
                var delta = event.pixelDelta.y !== 0
                    ? event.pixelDelta.y
                    : (event.angleDelta.y / 120) * Theme.space.controlHeight;
                if (LyricsService.follow) {
                    lyricsColumn.wheelY = lyricsColumn.y;
                    LyricsService.follow = false;
                }
                // Clamped to the two rows' own resting places rather than to
                // the column's raw extent, so the wheel walks exactly the
                // range the song itself walks.
                var top = root._restingY(0);
                var bottom = root._restingY(root.lines.length - 1);
                lyricsColumn.wheelY = Math.max(bottom, Math.min(top, lyricsColumn.wheelY + delta));
            }
        }

        Column {
            id: lyricsColumn
            width: parent.width
            spacing: 0

            // Where the wheel left the column; read only while `follow` is
            // off, so the song's own travel and the wheel never write one
            // value between them.
            property real wheelY: 0

            // The anchored row's top at the comfort offset (spec P9). Every
            // row renders at one font size for its kind, so `item.y` and
            // `item.height` never move on activation alone;
            // `lyricsColumn.height` is read purely so this re-evaluates once
            // a track change's row count has settled rather than mid
            // repopulation.
            readonly property real followY: {
                var _settled = lyricsColumn.height;
                return root._restingY(root._anchorIndex);
            }

            y: LyricsService.follow ? lyricsColumn.followY : lyricsColumn.wheelY

            Behavior on y {
                enabled: LyricsService.follow
                Anim {}
            }

            Repeater {
                id: lyricsRepeater
                model: root.lines

                delegate: Cell {
                    id: lineCell
                    required property int index
                    required property var modelData

                    width: parent.width
                    ghost: true
                    interactive: true
                    cursor: root.cursorOn && root.cursorIndex === lineCell.index
                    onClicked: root.seekRequested(lineCell.modelData.time)

                    // The two terms that move every frame: the edge fade
                    // tracks the column's own travel and the arrival fade is
                    // an animation in its own right. They multiply in here,
                    // uninterrupted, rather than inside `lineBox`'s animated
                    // opacity: a `Behavior` retargeted on every frame of a
                    // 500ms scroll never reaches a target, which read as the
                    // rows under the lit one arriving late and all at once
                    // (owner, 2026-09-18). `lineBox` keeps the Behavior for
                    // the depth ramp, which steps once per line change.
                    opacity: lineCell._edgeFraction * lineCell._arrival

                    readonly property bool _interlude: lineCell.modelData.interlude === true
                    readonly property bool _background: lineCell.modelData.background === true
                    readonly property bool _opposite: lineCell.modelData.oppositeTurn === true
                    readonly property bool _lit: lineCell.index === root._activeIndex
                        || root._secondary.indexOf(lineCell.index) !== -1
                    // The row's own form, which never depends on `_lit`: the
                    // chunks are laid out whether the line is lit or not, so
                    // the row's height and its wrap are the same either way.
                    readonly property bool _hasChunks: !lineCell._interlude
                        && lineCell.modelData.words && lineCell.modelData.words.length > 0
                    readonly property bool _chunked: lineCell._lit && lineCell._hasChunks
                    readonly property var _wordGroups: lineCell._hasChunks
                        ? root._chunkGroups(lineCell.modelData.words) : []

                    readonly property real _fontSize: lineCell._background
                        ? Theme.fontSize.body : Theme.fontSize.title
                    readonly property real _spaceWidth: lineCell._background
                        ? backgroundSpaceMetrics.advanceWidth : mainSpaceMetrics.advanceWidth

                    // The line's own end for the wipe: the provider's when it
                    // gave one, the next display entry's time otherwise, and
                    // undefined past the last entry so `chunkEnd` falls back
                    // to its own chunk-sized fudge.
                    readonly property var _lineEnd: {
                        if (typeof lineCell.modelData.end === "number" && isFinite(lineCell.modelData.end))
                            return lineCell.modelData.end;
                        var next = root.lines[lineCell.index + 1];
                        return next ? next.time : undefined;
                    }

                    // The fill only exists while the stretch is the one being
                    // played: a past interlude resets to the empty note the
                    // way kopuz's own `resetWords` leaves it
                    // (crates/components/src/playback/lyrics.rs), rather than
                    // sitting filled in the list behind the song. Only the
                    // lit one reads the position, per frame.
                    readonly property real _interludeProgress: (!lineCell._interlude || !lineCell._lit)
                        ? 0
                        : (lineCell.modelData.end > lineCell.modelData.time
                            ? Math.max(0, Math.min(1, (root._position - lineCell.modelData.time)
                                / (lineCell.modelData.end - lineCell.modelData.time)))
                            : (root._position >= lineCell.modelData.time ? 1 : 0))

                    // `edgeFraction` spends the fade before the viewport's
                    // clip reaches the row, caelestia's mask done with
                    // opacity rather than a shader: `top` is the row's place
                    // after the column's travel, so the fade tracks it frame
                    // by frame.
                    readonly property real _edgeFraction: Lyrics.edgeFraction(lyricsColumn.y + lineCell.y,
                        lineCell.height, lyricsViewport.height, root._edgeRamp)

                    // The row's place on both depth ramps: its distance from
                    // the anchor, and the room the pane has in that
                    // direction, which is what the ramps are spent over.
                    readonly property int _distance: lineCell.index - root._anchorIndex
                    readonly property real _rowSpan: lineCell._distance < 0
                        ? root._rowSpans.above : root._rowSpans.below

                    // Hover lifts a row clear of the depth of field so it can
                    // be read before it is clicked (spec P7); the cursor's own
                    // row is lifted for the same reason.
                    readonly property real _blurTarget: (!LyricsService.blurEnabled || lineCell._lit
                        || lineCell.containsPointer || lineCell.cursor)
                        ? 0
                        : Lyrics.blurFor(lineCell._distance, LyricsService.blurStrength, lineCell._rowSpan)
                    property real _blurPx: lineCell._blurTarget

                    Behavior on _blurPx {
                        Anim { kind: "effects" }
                    }

                    // A row the viewport no longer shows carries no layer,
                    // and neither does one that has settled back on 0.
                    readonly property bool _blurActive: lineCell._edgeFraction > 0 && lineCell._blurPx > 0

                    // A line arriving at lit fades from 0.68 (kopuz's
                    // fadeLineIn) rather than stepping to its depth opacity.
                    property real _arrival: 1
                    on_LitChanged: if (lineCell._lit) arrivalFade.restart()

                    Anim {
                        id: arrivalFade
                        target: lineCell
                        property: "_arrival"
                        from: 0.68
                        to: 1
                        kind: "effectsSlow"
                    }

                    Item {
                        id: lineBox
                        // Every line is capped at 90% of the pane on a track
                        // that has a duet turn, so the two voices read as
                        // sides rather than as one column (spec P8). Off the
                        // Cell's own content width, which is already inset by
                        // `controlPaddingX` either side.
                        width: parent.width * (root._hasOpposite ? 0.9 : 1)
                        x: lineCell._opposite ? parent.width - width : 0
                        height: lineCell._interlude
                            ? interludeRow.implicitHeight
                            : Math.max(lineText.implicitHeight, wordFlow.implicitHeight)

                        // The ramp (spec P5/P7): 1 at the lit lines, then
                        // 0.7, 0.45, 0.25 and no lower, sampled over the rows
                        // the pane has room for rather than over three, with
                        // a background line held at 0.7 of whatever its own
                        // rank gives it.
                        opacity: (lineCell._lit
                                ? 1
                                : Lyrics.depthOpacity(lineCell._distance, lineCell._rowSpan))
                            * (lineCell._background ? 0.7 : 1)
                        // The lit/dark tell is a transform, never a relayout,
                        // so a line's box never changes shape on activation.
                        // A background line activates to 0.9 (spec P8), and
                        // so does an interlude: kopuz pops its note less than
                        // a line of words (1.06 against 1.12), since the note
                        // is standing in for a stretch with nothing to sing
                        // rather than taking the song over.
                        scale: lineCell._lit
                            ? ((lineCell._background || lineCell._interlude) ? 0.9 : 1)
                            : 0.85
                        // The note is centred in the column, so it grows in
                        // place instead of walking out of its own row.
                        transformOrigin: lineCell._interlude && !root._hasOpposite
                            ? Item.Center
                            : (lineCell._opposite ? Item.Right : Item.Left)

                        Behavior on opacity {
                            Anim { kind: "effects" }
                        }
                        Behavior on scale {
                            Anim { kind: "spatialFast" }
                        }

                        Item {
                            id: lineContent
                            // A background line is indented one
                            // `controlPaddingX` on its own voice's side.
                            x: (lineCell._background && !lineCell._opposite) ? Theme.space.controlPaddingX : 0
                            width: lineBox.width - (lineCell._background ? Theme.space.controlPaddingX : 0)
                            height: lineBox.height
                            visible: !lineCell._blurActive

                            // An instrumental stretch is a `music` icon
                            // wiping left to right over the gap (M55 A4).
                            // kopuz's own note (crates/components/src/
                            // playback/lyrics.rs): a step larger than the
                            // line type it stands between, its unfilled copy
                            // at 0.35, and centred in the column unless the
                            // track has a duet turn, where the sides carry
                            // the meaning and it keeps the reading edge.
                            Item {
                                id: interludeRow
                                visible: lineCell._interlude
                                x: root._hasOpposite ? 0 : (lineContent.width - width) / 2
                                implicitWidth: noteIcon.implicitWidth
                                implicitHeight: noteIcon.implicitHeight

                                Icon {
                                    id: noteIcon
                                    name: "music"
                                    size: Theme.fontSize.heading
                                    color: Theme.color.mutedForeground
                                    opacity: 0.35
                                }

                                Item {
                                    anchors.left: noteIcon.left
                                    anchors.top: noteIcon.top
                                    width: lineCell._interludeProgress * noteIcon.width
                                    height: noteIcon.height
                                    clip: true

                                    Icon {
                                        name: "music"
                                        size: Theme.fontSize.heading
                                        color: Theme.color.foreground
                                    }
                                }
                            }

                            // The line's chunks: a word is a `Row` of the
                            // chunks `chunkWords` grouped for it, no spacing
                            // between them, and the `Flow` spaces the words
                            // at the font's own space advance. Laid out and
                            // drawn whether the line is lit or not, so a line
                            // change never rewraps a row or resizes it.
                            Flow {
                                id: wordFlow
                                visible: lineCell._hasChunks
                                // An opposite line is right-aligned, which a
                                // Flow can only be by being no wider than the
                                // text it holds: the plain copy below lays the
                                // same words out at the same font, so its own
                                // content width is that measurement.
                                width: lineCell._opposite
                                    ? Math.min(lineContent.width, Math.ceil(lineText.contentWidth) + 1)
                                    : lineContent.width
                                x: lineCell._opposite ? lineContent.width - width : 0
                                spacing: lineCell._spaceWidth

                                Repeater {
                                    model: lineCell._wordGroups

                                    delegate: Row {
                                        id: wordRow
                                        required property var modelData
                                        spacing: 0

                                        Repeater {
                                            model: wordRow.modelData

                                            delegate: Item {
                                                id: chunkItem
                                                required property var modelData

                                                // Both read the per-frame
                                                // position, so both are cut
                                                // off it entirely on a line
                                                // nobody is singing: the whole
                                                // set of chunks is laid out
                                                // now, and a dark line's own
                                                // chunks have no clock to
                                                // follow.
                                                readonly property real _progress: lineCell._chunked
                                                    ? Lyrics.chunkProgress(lineCell.modelData.words,
                                                        chunkItem.modelData.chunkIndex,
                                                        lineCell._lineEnd, root._position,
                                                        lineCell.modelData.estimated === true)
                                                    : 0
                                                readonly property real _glow: lineCell._chunked
                                                    ? Lyrics.chunkGlow(lineCell.modelData.words,
                                                        chunkItem.modelData.chunkIndex,
                                                        lineCell._lineEnd, root._position)
                                                    : 0

                                                // A `Flow` breaks between
                                                // its items and never inside
                                                // one, so a chunk the pane
                                                // cannot hold has to break
                                                // itself: a provider that
                                                // joins a whole phrase into
                                                // one word otherwise ran the
                                                // lit line off the pane's
                                                // edge, where the plain copy
                                                // below wraps it (owner,
                                                // 2026-09-18).
                                                width: Math.min(chunkBase.implicitWidth, wordFlow.width)
                                                height: chunkBase.height

                                                // The unsung word, and what a
                                                // chunk still reads as with
                                                // no effect over it.
                                                Text {
                                                    id: chunkBase
                                                    text: chunkItem.modelData.text
                                                    width: chunkItem.width
                                                    wrapMode: Text.Wrap
                                                    font.family: Theme.fontFamilySans
                                                    font.pixelSize: lineCell._fontSize
                                                    font.weight: Theme.weight.medium
                                                    font.italic: lineCell._opposite
                                                    color: Theme.color.mutedForeground

                                                    // The rows this chunk's
                                                    // own text wrapped onto,
                                                    // which the mask needs and
                                                    // nothing else can measure:
                                                    // where each one sits and
                                                    // how much ink it carries.
                                                    // Published as a fresh
                                                    // array per line so the
                                                    // mask rebuilds on the
                                                    // layout that produced it.
                                                    property var textRows: []

                                                    onLineLaidOut: line => {
                                                        var rows = line.number === 0
                                                            ? []
                                                            : chunkBase.textRows.slice(0, line.number);
                                                        rows.push({
                                                            y: line.y,
                                                            height: line.height,
                                                            width: line.implicitWidth
                                                        });
                                                        chunkBase.textRows = rows;
                                                    }
                                                }

                                                // The sung copy, its mask and
                                                // the effect over the two:
                                                // the whole wipe exists only
                                                // while the line is lit, so a
                                                // dark line's chunks cost the
                                                // one `Text` above and no
                                                // layer at all. The chunks
                                                // themselves stay, which is
                                                // what holds the row's shape
                                                // across the change.
                                                Loader {
                                                    id: sungLayer
                                                    active: lineCell._chunked
                                                    width: chunkItem.width
                                                    height: chunkItem.height

                                                    sourceComponent: Item {
                                                    Text {
                                                        id: chunkSung
                                                        text: chunkBase.text
                                                        font: chunkBase.font
                                                        width: chunkBase.width
                                                        wrapMode: chunkBase.wrapMode
                                                        color: Theme.color.foreground
                                                        visible: false
                                                    }

                                                    // kopuz's own gradient: 2.2
                                                    // chunk widths with a band
                                                    // between 46% and 54% of it,
                                                    // so the edge between sung and
                                                    // unsung is about a fifth of
                                                    // the chunk wide, and sliding
                                                    // it from just off the leading
                                                    // edge to just past the
                                                    // trailing one is the wipe.
                                                    // It runs to 0 rather than to
                                                    // kopuz's 0.45: MultiEffect
                                                    // thresholds its mask rather
                                                    // than multiplying by it, so
                                                    // the unsung reading is the
                                                    // `mutedForeground` copy under
                                                    // this one.
                                                    Item {
                                                        id: chunkMask
                                                        width: chunkItem.width
                                                        height: chunkItem.height
                                                        layer.enabled: true
                                                        visible: false

                                                        // One gradient per row
                                                        // the chunk wrapped
                                                        // onto, each run
                                                        // against that row's
                                                        // own ink width, so
                                                        // the edge finishes a
                                                        // row before the next
                                                        // one starts.
                                                        readonly property var bands: Lyrics.chunkRowBands(chunkBase.textRows,
                                                            chunkItem.height, chunkItem.width)

                                                        Repeater {
                                                            model: chunkMask.bands

                                                            delegate: Item {
                                                                id: maskBand
                                                                required property var modelData
                                                                required property int index

                                                                y: maskBand.modelData.top
                                                                width: chunkMask.width
                                                                height: maskBand.modelData.height

                                                                readonly property real _width: maskBand.modelData.width
                                                                readonly property real _progress: Lyrics.rowWipe(chunkMask.bands,
                                                                    maskBand.index, chunkItem._progress)

                                                                Rectangle {
                                                                    width: maskBand._width * 2.2
                                                                    height: maskBand.height
                                                                    x: -1.2 * (0.99 - maskBand._progress * 0.98) * maskBand._width
                                                                    gradient: Gradient {
                                                                        orientation: Gradient.Horizontal
                                                                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 1) }
                                                                        GradientStop { position: 0.46; color: Qt.rgba(1, 1, 1, 1) }
                                                                        GradientStop { position: 0.54; color: Qt.rgba(1, 1, 1, 0) }
                                                                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    MultiEffect {
                                                        width: chunkItem.width
                                                        height: chunkItem.height
                                                        source: chunkSung
                                                        maskEnabled: true
                                                        maskSource: chunkMask
                                                        // The mask's own alpha
                                                        // ramp is what the edge is
                                                        // made of: the threshold
                                                        // sits at the middle of it
                                                        // and the spread is wide
                                                        // enough to cover the
                                                        // whole 0..1, so the band
                                                        // grades instead of
                                                        // cutting (a spread of 0,
                                                        // the default, is a step).
                                                        maskThresholdMin: 0.5
                                                        maskSpreadAtMin: 1
                                                        // The glow is off rather
                                                        // than transparent once
                                                        // the chunk has decayed,
                                                        // which is what keeps an
                                                        // idle chunk on the plain
                                                        // shader.
                                                        shadowEnabled: chunkItem._glow > 0
                                                        shadowColor: Theme.color.foreground
                                                        shadowOpacity: 0.3 * chunkItem._glow
                                                        shadowBlur: (4 + chunkItem._glow * 6) / root._blurMaxPx
                                                        shadowHorizontalOffset: 0
                                                        shadowVerticalOffset: 0
                                                        blurMax: root._blurMaxPx
                                                    }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                id: lineText
                                // Laid out even while the chunks are drawn:
                                // its own content width is what an opposite
                                // line's Flow is measured against, and its
                                // height is the floor the row's own box takes.
                                // It only draws a line the provider gave no
                                // words for at all, which the chunks cannot
                                // render.
                                visible: !lineCell._interlude && !lineCell._hasChunks
                                width: lineContent.width
                                wrapMode: Text.Wrap
                                horizontalAlignment: lineCell._opposite ? Text.AlignRight : Text.AlignLeft
                                text: lineCell.modelData.text || ""
                                font.family: Theme.fontFamilySans
                                font.pixelSize: lineCell._fontSize
                                font.weight: Theme.weight.medium
                                font.italic: lineCell._opposite
                                color: lineCell._lit ? Theme.color.foreground : Theme.color.mutedForeground

                                Behavior on color {
                                    CAnim {}
                                }
                            }
                        }

                        Loader {
                            id: blurLayer
                            active: lineCell._blurActive
                            x: lineContent.x
                            y: lineContent.y
                            width: lineContent.width
                            height: lineContent.height
                            sourceComponent: MultiEffect {
                                source: lineContent
                                blurEnabled: true
                                blurMax: root._blurMaxPx
                                blur: Math.min(1, lineCell._blurPx / root._blurMaxPx)
                            }
                        }
                    }
                }
            }
        }
    }

    // The resync control (spec P9): present only once the wheel has taken
    // the column over, and the last entry in this section's own cursor order
    // while it is.
    IconButton {
        id: resyncButton
        name: "refresh-cw"
        tooltipText: "Follow the song"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        cursor: root.cursorOn && root.cursorIndex === root.lines.length
        opacity: LyricsService.follow ? 0 : 1
        visible: resyncButton.opacity > 0
        onClicked: LyricsService.follow = true

        Behavior on opacity {
            Anim { kind: "effects" }
        }
    }
}
