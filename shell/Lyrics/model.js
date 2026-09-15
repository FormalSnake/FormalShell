.pragma library

// Pure lrclib glue and LRC parsing for the lyrics block (M55 Task 1,
// spec D1/D2/D5). Owns the lrclib.net URL builders, picking a usable
// synced hit out of /api/get's single-object body and /api/search's
// array body, and every bit of LRC math the panel needs: parsing,
// timing lookups, interlude placement and the depth-opacity ramp. No
// Process, no XMLHttpRequest, no Date.now() in here, LyricsService owns
// every network and disk side effect (curl, the cache read/write, the
// XDG_CACHE_HOME path), this file stays deterministic under test.
//
// Accepts plain LRC ([mm:ss], [mm:ss.xx], [mm:ss.xxx]) and enhanced LRC's
// inline <mm:ss.xx> stamps inside the line text. A line can carry several
// leading [..] stamps, one entry per stamp, all sharing the line's text
// and words; a stamp whose contents are not a bare number and a colon
// (metadata like [ar:..], [ti:..], [offset:..]) is skipped rather than
// read as a time, and a line with no valid stamp at all contributes
// nothing. Two entries landing on the same time merge: the first line's
// text and word timing are kept, the second is folded onto a new line
// below it, kopuz's translation-line rule. plainLyrics is never read,
// only syncedLyrics.
//
// `words` (M55 Task 9) is a list of chunks, not pre-grouped words: the
// raw text between one <..> stamp and the next, trimmed, so a source that
// stamps whole words yields one chunk per word and one that stamps inside
// a word (a syllable split) yields several. `chunkWords` groups a run of
// chunks joined by no whitespace (`joinsNext`) into the word the panel
// draws as one `Row`; `chunkEnd`/`chunkProgress` are the wipe's own span
// and its 0..1 fraction at a given position, capped at `WIPE_MAX_SECONDS`.

var INTERLUDE_MIN_SECONDS = 5;
var FUDGE_SECONDS = 0.1;
var MISS_TTL_DAYS = 7;
var LINE_ASSUMED_SECONDS = 7;
var WORD_FALLBACK_SECONDS = 0.35;
// A chunk runs until the next one starts, which over a pause or a line's
// own tail can be far longer than the syllable itself. The wipe caps there
// so it lands on the beat and holds instead of creeping through the
// silence (kopuz's MAX_WIPE_SECONDS).
var WIPE_MAX_SECONDS = 1.2;

var _DEPTH_OPACITY = [1, 0.7, 0.45, 0.25];

function cacheKey(artist, title, album, durationSeconds) {
    var raw = ((artist || "") + " " + (title || "") + " " + (album || "")).toLowerCase();
    var slug = raw.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    var seconds = Math.round(durationSeconds);
    if (!isFinite(seconds))
        seconds = 0;
    return slug + "-" + seconds;
}

function getUrl(artist, title, album, durationSeconds) {
    var url = "https://lrclib.net/api/get?track_name=" + encodeURIComponent(title || "")
        + "&artist_name=" + encodeURIComponent(artist || "");
    if (album)
        url += "&album_name=" + encodeURIComponent(album);
    if (typeof durationSeconds === "number" && isFinite(durationSeconds) && durationSeconds > 0)
        url += "&duration=" + Math.round(durationSeconds);
    return url;
}

function searchUrl(artist, title) {
    return "https://lrclib.net/api/search?track_name=" + encodeURIComponent(title || "")
        + "&artist_name=" + encodeURIComponent(artist || "");
}

function _usableSyncedFrom(entry) {
    if (!entry || typeof entry.syncedLyrics !== "string" || entry.syncedLyrics === "")
        return "";
    return hasUsableTiming(parseLrc(entry.syncedLyrics)) ? entry.syncedLyrics : "";
}

// Handles /api/get's single object and /api/search's array of
// candidates the same way: the first entry (the only one, for /api/get)
// whose syncedLyrics parses with usable timing. A non-JSON body or a
// body with nothing usable is "", never a thrown exception.
function pickSynced(bodyText) {
    var data;
    try {
        data = JSON.parse(bodyText);
    } catch (e) {
        return "";
    }
    if (Array.isArray(data)) {
        for (var i = 0; i < data.length; i++) {
            var synced = _usableSyncedFrom(data[i]);
            if (synced !== "")
                return synced;
        }
        return "";
    }
    return _usableSyncedFrom(data);
}

// A tag's raw contents (bracket stripped) as a time in seconds, or null
// for anything that is not a bare "digits:digits[.digits]" pair, which
// is how a metadata tag's letters (ar, ti, offset, ...) fail out.
function _parseTimeTag(tag) {
    var m = /^(\d+):(\d+(?:\.\d+)?)$/.exec(tag);
    if (!m)
        return null;
    return parseInt(m[1], 10) * 60 + parseFloat(m[2]);
}

// Every leading [..] group off a line, in order, plus whatever text
// follows the last one. A metadata tag rides along in `tags` too, since
// only the caller knows which tags parsed as a time.
function _leadingTags(line) {
    var tags = [];
    var rest = line;
    var re = /^\[([^\]]*)\]/;
    var m;
    while ((m = re.exec(rest))) {
        tags.push(m[1]);
        rest = rest.slice(m[0].length);
    }
    return { tags: tags, rest: rest };
}

// Enhanced LRC's inline <mm:ss.xx> stamps, kept as raw chunks rather than
// pre-grouped into words (kopuz's parse_enhanced_words): each tag owns the
// raw text up to the next tag (or the end of the line), untrimmed, so a
// syllable split mid-word ("<0:01.0>Hel<0:01.2>lo") is two chunks rather
// than two words. `joinsNext` is true only when this chunk's own raw text
// carries no trailing whitespace AND the very next raw chunk carries no
// leading whitespace, which also covers a chunk that trims to nothing
// (a stray stamp with no text, or pure whitespace between two others): its
// own emptiness reads as `next.raw.trim() !== ""` failing, so the chunk
// before it is never joined across it even though it is dropped from the
// returned list. Returns the words plus the whole span's text (every raw
// chunk concatenated, then trimmed once), since the caller needs the raw
// concatenation rather than a join(" ") of the trimmed chunks to keep a
// mid-word split from gaining a space it never had.
function _parseWords(rest) {
    var re = /<(\d+):(\d+(?:\.\d+)?)>/g;
    var matches = [];
    var m;
    while ((m = re.exec(rest)))
        matches.push({ time: parseInt(m[1], 10) * 60 + parseFloat(m[2]), start: m.index, end: re.lastIndex });
    if (matches.length === 0)
        return { words: [], text: "" };

    var raw = [];
    for (var i = 0; i < matches.length; i++) {
        var textStart = matches[i].end;
        var textEnd = (i + 1 < matches.length) ? matches[i + 1].start : rest.length;
        raw.push({ time: matches[i].time, text: rest.slice(textStart, textEnd) });
    }

    var words = [];
    var joined = "";
    for (var j = 0; j < raw.length; j++) {
        joined += raw[j].text;
        var text = raw[j].text.trim();
        if (text === "")
            continue;
        var next = raw[j + 1];
        var joinsNext = next !== undefined
            && next.text.trim() !== ""
            && !/\s$/.test(raw[j].text)
            && !/^\s/.test(next.text);
        words.push({ time: raw[j].time, text: text, joinsNext: joinsNext });
    }
    return { words: words, text: joined.trim() };
}

// [{time, text, words: [{time, text}]}], sorted by time, equal times
// merged. A line with several leading stamps yields one entry per
// stamp; a line with no valid stamp yields nothing.
function parseLrc(text) {
    var rawLines = (text || "").split(/\r\n|\r|\n/);
    var entries = [];
    for (var i = 0; i < rawLines.length; i++) {
        var parsed = _leadingTags(rawLines[i]);
        var times = [];
        for (var j = 0; j < parsed.tags.length; j++) {
            var t = _parseTimeTag(parsed.tags[j]);
            if (t !== null)
                times.push(t);
        }
        if (times.length === 0)
            continue;
        var parsedWords = _parseWords(parsed.rest);
        var lineText = parsedWords.words.length > 0 ? parsedWords.text : parsed.rest.trim();
        for (var k = 0; k < times.length; k++)
            entries.push({ time: times[k], text: lineText, words: parsedWords.words });
    }
    entries.sort(function (a, b) { return a.time - b.time; });
    var merged = [];
    for (var i = 0; i < entries.length; i++) {
        var e = entries[i];
        var last = merged.length > 0 ? merged[merged.length - 1] : null;
        if (last && last.time === e.time)
            last.text = last.text + "\n" + e.text;
        else
            merged.push({ time: e.time, text: e.text, words: e.words });
    }
    return merged;
}

// One line is usable on its own (there is still a time to trigger on);
// several lines need a genuine increase somewhere, not just a run of
// entries stuck on the same time (a malformed or wholly-merged file).
// parseLrc's own output is already sorted with equal times merged away,
// so any increase at all shows up between neighbours, no need to check
// every pair.
function hasUsableTiming(lines) {
    if (!lines || lines.length === 0)
        return false;
    if (lines.length === 1)
        return true;
    for (var i = 0; i < lines.length - 1; i++) {
        if (lines[i + 1].time > lines[i].time)
            return true;
    }
    return false;
}

// The last index whose time is at or before t plus the fudge, -1 before
// the first entry.
function indexForTime(lines, t) {
    if (!lines)
        return -1;
    var result = -1;
    for (var i = 0; i < lines.length; i++) {
        if (lines[i].time <= t + FUDGE_SECONDS)
            result = i;
    }
    return result;
}

function wordIndexForTime(words, t) {
    return indexForTime(words, t);
}

// A line's estimated end: its last word's time plus the word fallback
// when it has word timing, else its own time plus the assumed line
// length, never past the next line's own start.
function _estimatedEnd(line, nextTime) {
    var end = line.words && line.words.length > 0
        ? line.words[line.words.length - 1].time + WORD_FALLBACK_SECONDS
        : line.time + LINE_ASSUMED_SECONDS;
    if (nextTime !== undefined && end > nextTime)
        end = nextTime;
    return end;
}

// `lines` with an interlude entry (`interlude: true`, `time`, `end`)
// spliced in wherever a gap of INTERLUDE_MIN_SECONDS or more opens up:
// before the first line when it starts that late, and between two
// lines whose gap from the earlier line's estimated end is that wide.
function displayLines(lines) {
    var out = [];
    if (!lines || lines.length === 0)
        return out;
    if (lines[0].time >= INTERLUDE_MIN_SECONDS)
        out.push({ interlude: true, time: 0, end: lines[0].time });
    for (var i = 0; i < lines.length; i++) {
        out.push(lines[i]);
        if (i + 1 < lines.length) {
            var end = _estimatedEnd(lines[i], lines[i + 1].time);
            var gap = lines[i + 1].time - end;
            if (gap >= INTERLUDE_MIN_SECONDS)
                out.push({ interlude: true, time: end, end: lines[i + 1].time });
        }
    }
    return out;
}

function depthOpacity(distance) {
    var d = Math.abs(distance);
    if (d > 3)
        d = 3;
    return _DEPTH_OPACITY[d];
}

// The 0..1 fraction of a `height`-tall item starting at `top` that falls
// inside `[0, viewportHeight]`: 1 fully in, 0 fully out either side, and
// linear in between (a line sliced by the viewport's own edge fades out
// rather than reading as a cut-off line under whatever sits above the
// viewport). `top` is the item's position after the column's own travel,
// so the caller adds the column's animated `y` to the item's own.
function edgeFraction(top, height, viewportHeight) {
    if (!(height > 0))
        return 0;
    var overlap = Math.min(top + height, viewportHeight) - Math.max(top, 0);
    return Math.max(0, Math.min(1, overlap / height));
}

// Runs of chunks joined by `joinsNext` grouped into one word each, so a
// syllable-stamped file reads as several chunks per word and a
// word-stamped one as one chunk per word once the caller draws each group
// as a `Row` of chunks with no spacing between them.
function chunkWords(words) {
    var out = [];
    var current = [];
    for (var i = 0; i < (words || []).length; i++) {
        current.push(words[i]);
        if (!words[i].joinsNext) {
            out.push(current);
            current = [];
        }
    }
    if (current.length > 0)
        out.push(current);
    return out;
}

// A chunk's own span ends where the next one starts; the last chunk of a
// line has no next, so it runs to the line's end, and a line with no end
// of its own (the last display entry) falls back to a chunk-sized fudge
// past its own stamp (kopuz's chunk_end_time).
function chunkEnd(words, index, lineEnd) {
    var next = words[index + 1];
    if (next)
        return next.time;
    if (typeof lineEnd === "number" && isFinite(lineEnd))
        return lineEnd;
    return words[index].time + WORD_FALLBACK_SECONDS;
}

// The 0..1 fraction of chunk `index`'s own wipe elapsed at `t`: 0 before
// its stamp, 1 once its (capped) span has passed. The cap runs off the
// span's own start rather than off `chunkEnd`'s raw answer, so a chunk
// whose next stamp (or line end) is far in the future still finishes its
// wipe at WIPE_MAX_SECONDS instead of creeping toward it.
function chunkProgress(words, index, lineEnd, t) {
    var chunk = words[index];
    if (!chunk)
        return 0;
    var start = chunk.time;
    var end = Math.min(chunkEnd(words, index, lineEnd), start + WIPE_MAX_SECONDS);
    if (end <= start)
        return t >= start ? 1 : 0;
    return Math.max(0, Math.min(1, (t - start) / (end - start)));
}
