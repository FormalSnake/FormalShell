.pragma library

// Pure lyrics glue: provider URL builders, LRC and paxsenix Apple Music
// parsing, match scoring, the normalised line model and kopuz's own lit-set
// and depth-of-field math (M56 Task 1, spec P1/P2/P4/P5, ported from
// ../kopuz's crates/utils/src/lyrics/{lrc,paxsenix}.rs and
// crates/components/src/playback/lyrics.rs). No Process, no
// XMLHttpRequest, no Date.now() in here; LyricsService owns every network
// and disk side effect (curl, the cache read/write, the XDG_CACHE_HOME
// path, provider ordering and timeouts), this file stays deterministic
// under test.
//
// Every line, from whichever provider, normalises to one shape (spec P1):
// {time, end, text, words: [{time, text, joinsNext}], parent, background,
// oppositeTurn, estimated}. `end` is a number or null; `parent` is the
// index of the main line a background line belongs to, or null; `estimated`
// is true when `words` were synthesised (synthesiseWords) rather than
// timed by a provider.
//
// LRC ([mm:ss], [mm:ss.xx], [mm:ss.xxx]) and enhanced LRC's inline
// <mm:ss.xx> word stamps parse the same as before: a line can carry
// several leading [..] stamps, one entry per stamp, all sharing the line's
// text and words; a stamp whose contents are not a bare number and a colon
// (metadata like [ar:..], [ti:..], [offset:..]) is skipped rather than read
// as a time, and a line with no valid stamp at all contributes nothing.
// Two entries landing on the same time merge: the first line's text and
// word timing are kept unless it has no words and the second does, and the
// second's text is folded onto a new line below the first's, wrapped in
// parentheses unless it already is one (kopuz's append_translation).
// plainLyrics/paxsenix's `plain` field are never read (spec D4).
//
// `words` is a list of chunks, not pre-grouped words: for LRC, the raw text
// between one <..> stamp and the next, trimmed, so a source that stamps
// whole words yields one chunk per word and one that stamps inside a word
// (a syllable split) yields several; for paxsenix Apple rows, one chunk per
// timed `text`/`backgroundText` part, also trimmed (the line's own `text`
// keeps paxsenix's inserted spacing, chunks don't need to). `chunkWords`
// groups a run of chunks joined by no whitespace (`joinsNext`) into the
// word the panel draws as one `Row`; `chunkEnd`/`chunkProgress` are the
// wipe's own span and its 0..1 fraction at a given position, capped at
// `WIPE_MAX_SECONDS` for a provider's own stamps and uncapped for
// synthesised ones, and `chunkGlow` is the sung chunk's own 0..1 glow.
// `synthesiseWords` fabricates chunks, proportioned by
// character count, for a line a provider left untimed, so the wipe always
// has something to draw (spec P4).
//
// The lit-set functions (`mainLineIndices` through `lineEndEstimate`,
// `displayLines`) are kopuz's own, ported under camelCase names with their
// tests; they take the playback position `t` as a plain argument, and every
// caller passes what `ledPosition` made of the player's clock. `blurFor` and
// `comfortY` are the depth-of-field ramp and the 42% comfort anchor (spec
// P7/P9). `depthOpacity` and `edgeFraction` are not superseded by the blur:
// the opacity ramp keeps running alongside it (spec P7), just no longer
// alone. `rowSpans` is how far those two ramps reach: the rows the pane has
// room for either side of the anchor, so the ramps are spent on the pane's
// own height rather than on a fixed count of rows. `chunkRowBands` and
// `rowWipe` are the wipe over a chunk the pane is too narrow to hold on one
// row.

var INTERLUDE_MIN_SECONDS = 5;
var MISS_TTL_DAYS = 7;
var LINE_ASSUMED_SECONDS = 7;
var WORD_FALLBACK_SECONDS = 0.35;
// A chunk runs until the next one starts, which over a pause or a line's
// own tail can be far longer than the syllable itself. The wipe caps there
// so it lands on the beat and holds instead of creeping through the
// silence (kopuz's MAX_WIPE_SECONDS).
var WIPE_MAX_SECONDS = 1.2;
// How long the glow on a chunk takes to fade once the chunk's own span is
// over (kopuz's GLOW_DECAY_SECONDS), and the step it is reported in, so a
// decaying glow rewrites the effect's properties twenty times rather than
// once a frame.
var GLOW_DECAY_SECONDS = 0.6;
var GLOW_QUANTUM = 0.05;
// How far ahead of the player's own clock every lyrics reader works. An
// MPRIS position is a single sample stamped when the player's D-Bus reply
// arrived and extrapolated from there, and the frame drawn off it reaches
// the display a refresh or two later, so a lit line and a wipe that land on
// the beat have to be drawn against a position read ahead of the number the
// player gives. kopuz needs none of this: it reads the audio clock it is
// decoding from.
var POSITION_LEAD_SECONDS = 0.1;

// A main line ending and the next one starting within this long reads as
// one continuous phrase rather than a gap; the earlier line (or its
// background) stays lit across it (kopuz's LYRIC_SEAMLESS_GAP_SECONDS).
var SEAMLESS_GAP_SECONDS = 3;

// The rightbar ramp from kopuz: per-line-of-distance blur step and cap, in
// px, sized for the panel's own (smaller) type.
var BLUR_STEP_PX = 1.1;
var BLUR_MAX_PX = 6;
var BLUR_QUANTUM_PX = 0.5;
// The lit line rests this far down the viewport rather than at its centre
// (kopuz's LYRIC_COMFORT_OFFSET_PERCENT).
var COMFORT_OFFSET_FRACTION = 0.42;

// lyrics_match_score's floor and the duration window: a candidate under the
// floor is dropped outright, one further than this many seconds from the
// track's own length loses regardless of how well its text matches.
var MATCH_SCORE_FLOOR = 55;
var DURATION_WINDOW_SECONDS = 12;

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

// iTunes' own search, the first paxsenix Apple Music step (spec P2.2):
// "title artist" is kopuz's own query order, entity/limit/country pinned to
// its values.
function itunesSearchUrl(artist, title) {
    var query = ((title || "") + " " + (artist || "")).trim();
    return "https://itunes.apple.com/search?term=" + encodeURIComponent(query)
        + "&entity=song&limit=8&country=US";
}

function paxsenixAppleLyricsUrl(trackId) {
    return "https://lyrics.paxsenix.org/apple-music/lyrics?id=" + encodeURIComponent(String(trackId));
}

function paxsenixYoutubeSearchUrl(artist, title) {
    var query = ((title || "") + " " + (artist || "")).trim();
    return "https://lyrics.paxsenix.org/youtube/search?q=" + encodeURIComponent(query);
}

function paxsenixYoutubeLyricsUrl(videoId) {
    return "https://lyrics.paxsenix.org/youtube/lyrics?id=" + encodeURIComponent(videoId);
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

// A merged-in translation line (an equal stamp, or a second raw line with
// no stamp of its own) wraps in parentheses unless it already is one
// (kopuz's append_translation); an empty translation contributes nothing.
function _appendTranslation(existingText, text) {
    var trimmed = (text || "").trim();
    if (trimmed === "")
        return existingText;
    var wrapped = (trimmed.charAt(0) === "(" && trimmed.charAt(trimmed.length - 1) === ")")
        ? trimmed
        : "(" + trimmed + ")";
    return existingText === "" ? wrapped : existingText + "\n" + wrapped;
}

// [{time, end, text, words, parent, background, oppositeTurn, estimated}],
// sorted by time, equal times merged. A line with several leading stamps
// yields one entry per stamp; a line with no valid stamp yields nothing.
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
    for (var e = 0; e < entries.length; e++) {
        var entry = entries[e];
        var last = merged.length > 0 ? merged[merged.length - 1] : null;
        if (last && last.time === entry.time) {
            if (last.words.length === 0 && entry.words.length > 0)
                last.words = entry.words;
            last.text = _appendTranslation(last.text, entry.text);
        } else {
            merged.push({
                time: entry.time,
                end: null,
                text: entry.text,
                words: entry.words,
                parent: null,
                background: false,
                oppositeTurn: false,
                estimated: false
            });
        }
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

// paxsenix's punctuation rule (should_insert_apple_space): no space before
// the very first part, none after a part flagged `part: true` (it joins
// the next one with nothing between), and none before a leading
// punctuation character on the next part.
var _APPLE_NO_SPACE_BEFORE = [",", ".", "?", "!", ":", ";", ")", "]", "}", "'", "’"];

function _paxsenixNeedsSpace(currentText, previousPartContinues, nextText) {
    if (currentText === "" || previousPartContinues)
        return false;
    if (!nextText || nextText.length === 0)
        return false;
    return _APPLE_NO_SPACE_BEFORE.indexOf(nextText.charAt(0)) === -1;
}

// One paxsenix `text`/`backgroundText` array to a line: the line's `text`
// keeps every inserted space (trimmed once at the end), each timed part
// becomes a chunk with its OWN text trimmed instead (the panel spaces
// chunks itself through `chunkWords`), and `joinsNext` mirrors the part's
// own `part` flag: a part marked `part: true` means the next part joins it
// with no space. Returns null for a row with nothing but blank parts.
function _paxsenixPartsToLine(parts, startTime, endTime, parentIndex, background, oppositeTurn) {
    var text = "";
    var words = [];
    var previousContinues = false;
    for (var i = 0; i < (parts || []).length; i++) {
        var part = parts[i];
        if (!part || !part.text || part.text.trim() === "")
            continue;
        var prefix = _paxsenixNeedsSpace(text, previousContinues, part.text) ? " " : "";
        var displayText = prefix + part.text;
        text += displayText;
        if (typeof part.timestamp === "number") {
            words.push({
                time: part.timestamp / 1000,
                text: displayText.trim(),
                joinsNext: part.part === true
            });
        }
        previousContinues = part.part === true;
    }
    text = text.trim();
    if (text === "")
        return null;
    return {
        time: startTime,
        end: (typeof endTime === "number" && isFinite(endTime)) ? endTime : null,
        text: text,
        words: words,
        parent: (parentIndex === undefined) ? null : parentIndex,
        background: background,
        oppositeTurn: oppositeTurn,
        estimated: false
    };
}

function _paxsenixHasTiming(rows) {
    for (var i = 0; i < (rows || []).length; i++) {
        var row = rows[i];
        if (row.timestamp > 0)
            return true;
        if (typeof row.endtime === "number" && row.endtime > 0)
            return true;
        var text = row.text || [];
        for (var t = 0; t < text.length; t++) {
            if (typeof text[t].timestamp === "number" && text[t].timestamp > 0)
                return true;
        }
        var bg = row.backgroundText || [];
        for (var g = 0; g < bg.length; g++) {
            if (typeof bg[g].timestamp === "number" && bg[g].timestamp > 0)
                return true;
        }
    }
    return false;
}

// paxsenix's `content` rows to display lines (paxsenix_apple_to_lines): a
// row's `text` becomes a foreground line unless the row is `background`
// with no `backgroundText` of its own, in which case it IS the background
// line; a row's `backgroundText`, when present, becomes its own
// `background: true` line right after its parent with `parent` pointing
// back at it, starting at its first timed part (or the row's own stamp
// with none). Returns null when nothing in `rows` carries real timing.
function paxsenixAppleToLines(rows) {
    if (!_paxsenixHasTiming(rows))
        return null;

    var lines = [];
    for (var i = 0; i < (rows || []).length; i++) {
        var row = rows[i];
        var rowStart = row.timestamp / 1000;
        var rowEnd = (typeof row.endtime === "number") ? row.endtime / 1000 : null;
        var oppositeTurn = row.oppositeTurn === true;
        var backgroundParts = row.backgroundText || [];
        var hasBackgroundText = backgroundParts.length > 0;
        var mainIsBackground = row.background === true && !hasBackgroundText;
        var parentIndex = null;

        var mainLine = _paxsenixPartsToLine(row.text, rowStart, rowEnd, null, mainIsBackground, oppositeTurn);
        if (mainLine) {
            lines.push(mainLine);
            if (!mainIsBackground)
                parentIndex = lines.length - 1;
        }

        var backgroundStart = rowStart;
        for (var b = 0; b < backgroundParts.length; b++) {
            if (typeof backgroundParts[b].timestamp === "number") {
                backgroundStart = backgroundParts[b].timestamp / 1000;
                break;
            }
        }
        var backgroundLine = _paxsenixPartsToLine(backgroundParts, backgroundStart, rowEnd, parentIndex, true, oppositeTurn);
        if (backgroundLine)
            lines.push(backgroundLine);
    }

    return lines.length > 0 ? lines : null;
}

// The paxsenix Apple Music lyrics endpoint's whole body
// (paxsenix_apple_to_lyrics): `content` wins when it carries usable
// timing, else the fallback is `lrc` parsed the same way lrclib's own text
// is. `plain` is never read (spec D4); a bad JSON body or a response with
// nothing usable is [], never a thrown exception.
function fromPaxsenixApple(bodyText) {
    var data;
    try {
        data = JSON.parse(bodyText);
    } catch (e) {
        return [];
    }
    var rows = (data && Array.isArray(data.content)) ? data.content : [];
    var lines = paxsenixAppleToLines(rows);
    if (lines && hasUsableTiming(lines))
        return lines;

    var lrc = (data && typeof data.lrc === "string") ? data.lrc : "";
    if (lrc.trim() === "")
        return [];
    var parsed = parseLrc(lrc);
    return hasUsableTiming(parsed) ? parsed : [];
}

// lyrics_match_score's own tokeniser: lowercased, "(feat."/"(ft."/
// "(featuring" stripped (a featured artist shouldn't cost a match its
// score), split on anything that isn't ASCII alphanumeric (mirrors
// `cacheKey`'s own slug, not full Unicode word-splitting), duplicates
// collapsed (the score is a token-set overlap, not a bag-of-words one).
function _matchTokens(value) {
    var normalized = (value || "").toLowerCase()
        .replace(/\(feat\./g, " ")
        .replace(/\(ft\./g, " ")
        .replace(/\(featuring/g, " ");
    var parts = normalized.split(/[^a-z0-9]+/);
    var seen = {};
    var tokens = [];
    for (var i = 0; i < parts.length; i++) {
        var token = parts[i];
        if (token === "" || seen[token])
            continue;
        seen[token] = true;
        tokens.push(token);
    }
    return tokens;
}

// Twice the shared token count over the combined token count, as a
// percentage: 0 when either side tokenises to nothing.
function matchScore(candidate, query) {
    var candidateTokens = _matchTokens(candidate);
    var queryTokens = _matchTokens(query);
    if (candidateTokens.length === 0 || queryTokens.length === 0)
        return 0;
    var querySet = {};
    for (var i = 0; i < queryTokens.length; i++)
        querySet[queryTokens[i]] = true;
    var shared = 0;
    for (var j = 0; j < candidateTokens.length; j++) {
        if (querySet[candidateTokens[j]])
            shared++;
    }
    return (2 * shared) * 100 / (candidateTokens.length + queryTokens.length);
}

// A candidate's combined score, or null when it should be dropped
// outright: below the match floor, or both a duration and a candidate
// length are known and they differ by more than the window.
function _rankCandidate(textScore, durationSeconds, candidateSeconds) {
    if (textScore < MATCH_SCORE_FLOOR)
        return null;
    var durationScore = 0;
    if (durationSeconds && typeof candidateSeconds === "number" && isFinite(candidateSeconds)) {
        var delta = Math.abs(candidateSeconds - durationSeconds);
        if (delta > DURATION_WINDOW_SECONDS)
            return null;
        durationScore = DURATION_WINDOW_SECONDS - delta;
    }
    return textScore + durationScore;
}

// The best iTunes search hit for "title artist" against a track's own
// duration (best_itunes_song): `trackTimeMillis` beats a pure text match,
// but only within the window. Null when nothing clears the floor.
function bestItunesSong(songs, query, durationSeconds) {
    var best = null;
    var bestScore = -Infinity;
    for (var i = 0; i < (songs || []).length; i++) {
        var song = songs[i];
        var candidate = (song.trackName || "") + " " + (song.artistName || "");
        var candidateSeconds = (typeof song.trackTimeMillis === "number") ? song.trackTimeMillis / 1000 : undefined;
        var score = _rankCandidate(matchScore(candidate, query), durationSeconds, candidateSeconds);
        if (score !== null && score > bestScore) {
            bestScore = score;
            best = song;
        }
    }
    return best;
}

// "m:ss" or "h:mm:ss" to whole seconds (parse_colon_duration); null for
// anything that isn't a run of colon-separated non-negative integers.
function parseColonDuration(duration) {
    if (typeof duration !== "string" || duration === "")
        return null;
    var parts = duration.split(":");
    var total = 0;
    for (var i = 0; i < parts.length; i++) {
        if (!/^\d+$/.test(parts[i]))
            return null;
        total = total * 60 + parseInt(parts[i], 10);
    }
    return total;
}

// best_youtube_result's own scoring: title+author text match, duration
// parsed out of paxsenix's "m:ss" string.
function bestYoutubeResult(results, query, durationSeconds) {
    var best = null;
    var bestScore = -Infinity;
    for (var i = 0; i < (results || []).length; i++) {
        var result = results[i];
        var candidate = (result.title || "") + " " + (result.author || "");
        var candidateSeconds = parseColonDuration(result.duration);
        var score = _rankCandidate(matchScore(candidate, query), durationSeconds, candidateSeconds === null ? undefined : candidateSeconds);
        if (score !== null && score > bestScore) {
            bestScore = score;
            best = result;
        }
    }
    return best;
}

// lyrics_quality: 2 when any line carries more than one word chunk
// (syllable or word timing), 1 for line timing alone, 0 for nothing usable.
function quality(lines) {
    if (!lines || lines.length === 0)
        return 0;
    for (var i = 0; i < lines.length; i++) {
        if (lines[i].words && lines[i].words.length > 1)
            return 2;
    }
    return 1;
}

// True for a result the chain can stop on immediately (spec P2: "the first
// quality-2 answer wins outright"), sparing the caller its own
// quality(...) === 2 check.
function isDefinitive(lines) {
    return quality(lines) === 2;
}

// The best of several provider results (spec P2's tie order): highest
// quality wins, a tie goes to the earlier entry (the caller's own
// priority order), and quality 0 never wins even when it's all there is.
// `results` is [{source, lines}, ...]; returns one of them, or null when
// none clear quality 0.
function pickBest(results) {
    var best = null;
    var bestQuality = 0;
    for (var i = 0; i < (results || []).length; i++) {
        var candidate = results[i];
        var q = quality(candidate.lines);
        if (q === 0)
            continue;
        if (best === null || q > bestQuality) {
            bestQuality = q;
            best = candidate;
        }
    }
    return best;
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
//
// `estimated` is the line's own flag, and it turns the cap off. The cap is
// there for a provider's own stamp held over a pause, where the syllable is
// long over and the wipe would creep through the silence after it;
// synthesised chunks have no such silence in them, since `synthesiseWords`
// laid them across the line's whole sung stretch by character count. Capping
// them wiped every word in 1.2s and then waited, which is what read as one
// rate for a line held two seconds and a line held twelve (owner,
// 2026-09-18).
function chunkProgress(words, index, lineEnd, t, estimated) {
    var chunk = words[index];
    if (!chunk)
        return 0;
    var start = chunk.time;
    var end = chunkEnd(words, index, lineEnd);
    if (estimated !== true)
        end = Math.min(end, start + WIPE_MAX_SECONDS);
    if (end <= start)
        return t >= start ? 1 : 0;
    return Math.max(0, Math.min(1, (t - start) / (end - start)));
}

// The 0..1 glow on chunk `index` at `t`: full while the chunk is the one
// being sung, then linear to 0 over GLOW_DECAY_SECONDS. Off its raw span
// rather than the capped wipe (kopuz's own reading): a chunk held over a
// pause keeps its glow for as long as it is the chunk being sung.
function chunkGlow(words, index, lineEnd, t) {
    var chunk = words[index];
    if (!chunk || t < chunk.time)
        return 0;
    var end = chunkEnd(words, index, lineEnd);
    var glow = t <= end ? 1 : 1 - (t - end) / GLOW_DECAY_SECONDS;
    return Math.round(Math.max(0, Math.min(1, glow)) / GLOW_QUANTUM) * GLOW_QUANTUM;
}

// A line's own words if it has any (not synthesised), the whole main-line
// run's span otherwise: from `line.time` to `line.end` when the provider
// gave one, else to the smaller of the next main line's own start and
// `time + LINE_ASSUMED_SECONDS` (spec P4). That span is the same number
// `displayLines` clamps a gap's own start to, which is the instant the line
// stops being lit, so the last chunk's wipe lands exactly as the next line
// (or the note over an instrumental) takes over. Skips an interlude and a merged
// translation line (its text carries a "\n", and synthesising only the
// first physical line would desync the second's own wipe).
function synthesiseWords(lines) {
    if (!lines || lines.length === 0)
        return lines || [];
    var main = mainLineIndices(lines);
    var out = new Array(lines.length);
    for (var i = 0; i < lines.length; i++)
        out[i] = lines[i];

    for (var idx = 0; idx < lines.length; idx++) {
        var line = lines[idx];
        if (line.interlude || (line.words && line.words.length > 0))
            continue;
        if (!line.text || line.text.indexOf("\n") !== -1)
            continue;
        var words = line.text.split(/\s+/).filter(function (w) { return w.length > 0; });
        if (words.length === 0)
            continue;

        var spanEnd;
        if (typeof line.end === "number" && isFinite(line.end)) {
            spanEnd = line.end;
        } else {
            var nextStart = nextMainLineStart(lines, main, idx);
            var assumed = line.time + LINE_ASSUMED_SECONDS;
            spanEnd = (nextStart !== undefined) ? Math.min(nextStart, assumed) : assumed;
        }
        var span = spanEnd - line.time;

        var totalChars = 0;
        for (var w = 0; w < words.length; w++)
            totalChars += words[w].length;

        var wordsOut = [];
        var charsSoFar = 0;
        for (var w2 = 0; w2 < words.length; w2++) {
            var time = span > 0 ? line.time + span * (charsSoFar / totalChars) : line.time;
            wordsOut.push({ time: time, text: words[w2], joinsNext: false });
            charsSoFar += words[w2].length;
        }

        var next = {};
        for (var key in line)
            next[key] = line[key];
        next.words = wordsOut;
        next.estimated = true;
        out[idx] = next;
    }
    return out;
}

// The one position the lit set, the wipe and the interlude ramp are all read
// against: the player's clock led by POSITION_LEAD_SECONDS, then
// `media.lyricsOffsetMs` on top of the lead, positive holding the lyrics
// back. Every caller goes through here, so the pane and `media lyrics` can
// never disagree about which line is lit.
function ledPosition(position, offsetSeconds) {
    var offset = Number(offsetSeconds);
    return position + POSITION_LEAD_SECONDS - (isFinite(offset) ? offset : 0);
}

// The foreground lines (main_line_indices): every non-background line, or
// every line at all when the whole set is background (no foreground to
// anchor on).
function mainLineIndices(lines) {
    var foreground = [];
    for (var i = 0; i < lines.length; i++) {
        if (!lines[i].background)
            foreground.push(i);
    }
    if (foreground.length > 0)
        return foreground;
    var all = [];
    for (var j = 0; j < lines.length; j++)
        all.push(j);
    return all;
}

// The start time of the main line right after `lineIndex` in `mainIndices`,
// or undefined past the last one.
function nextMainLineStart(lines, mainIndices, lineIndex) {
    var position = mainIndices.indexOf(lineIndex);
    if (position === -1)
        return undefined;
    var next = mainIndices[position + 1];
    return (next === undefined || next >= lines.length) ? undefined : lines[next].time;
}

// Whether `line` is lit at `t`: not yet started is never active; no end
// time runs until the next main line starts (or forever, with none);
// within its own end is active; past its end it stays lit only through
// the seamless gap into a main line that starts soon enough after it.
function lineActiveAt(line, t, nextMainStart) {
    if (t < line.time)
        return false;
    var end = line.end;
    if (typeof end !== "number" || !isFinite(end))
        return nextMainStart === undefined ? true : t < nextMainStart;
    if (t <= end)
        return true;
    if (nextMainStart === undefined)
        return false;
    return nextMainStart > end && nextMainStart - end <= SEAMLESS_GAP_SECONDS && t < nextMainStart;
}

// The last main line at or before `t` that is still active there, -1 when
// none is (before the first line, or in a gap with no seamless carry).
function activeMainLineIndex(lines, mainIndices, t) {
    var result = -1;
    for (var i = 0; i < mainIndices.length; i++) {
        var index = mainIndices[i];
        // `mainIndices` can be one property binding behind `lines` for a
        // single evaluation (LyricsPane's `_mainIndices` and `_activeIndex`
        // are separate bindings on the same `lines`, and QML settles a
        // whole batch of property changes before either is read again), so
        // an index past the current array shows up here as a real
        // transient rather than a bug in the caller: skip it instead of
        // indexing into `undefined`.
        if (index >= lines.length)
            continue;
        if (lines[index].time > t)
            break;
        if (lineActiveAt(lines[index], t, nextMainLineStart(lines, mainIndices, index)))
            result = index;
    }
    return result;
}

// A background line carries its own timing and often outlasts the line it
// was attached to, or overlaps the next one (Apple starts the next main
// row while the backing vocal is still going). Judged on that timing
// alone: with no end time of its own it runs until the next main line
// starts after it, undefined when there is none.
function backgroundLineBound(lines, mainIndices, line) {
    if (typeof line.end === "number" && isFinite(line.end))
        return undefined;
    for (var i = 0; i < mainIndices.length; i++) {
        if (mainIndices[i] >= lines.length)
            continue;
        var start = lines[mainIndices[i]].time;
        if (start > line.time)
            return start;
    }
    return undefined;
}

// Every line lit at `t` besides `mainLineIndex` itself: a background line
// judged on `backgroundLineBound`, any other (a duet's opposite line) only
// while a main line is active at all.
function activeSecondaryLines(lines, mainIndices, t, mainLineIndex) {
    var result = [];
    for (var i = 0; i < lines.length; i++) {
        if (i === mainLineIndex)
            continue;
        var line = lines[i];
        var nextStart = line.background
            ? backgroundLineBound(lines, mainIndices, line)
            : nextMainLineStart(lines, mainIndices, i);
        if (!lineActiveAt(line, t, nextStart))
            continue;
        if (line.background || mainLineIndex !== -1)
            result.push(i);
    }
    return result;
}

// A line's own estimated end when it has none: its last word plus the
// chunk fallback, or the assumed line length off its own start when it
// has no words either. Synthesised words are not an answer here: they are
// spread over this very estimate, so reading them back would report a line
// as ending wherever its own fabricated last word happened to land and
// close a real instrumental gap to nothing. kopuz has no such branch to
// fall into, since it never synthesises (crates/components/src/playback/
// lyrics.rs line_end_estimate).
function lineEndEstimate(line) {
    if (typeof line.end === "number" && isFinite(line.end))
        return line.end;
    if (!line.estimated && line.words && line.words.length > 0)
        return line.words[line.words.length - 1].time + WORD_FALLBACK_SECONDS;
    return line.time + LINE_ASSUMED_SECONDS;
}

// `lines` with a synthetic interlude line spliced in wherever a gap of
// INTERLUDE_MIN_SECONDS or more opens between one main line's run (itself
// plus any background lines riding along after it) and the next: before
// the first line when it starts that late, and between two main lines
// whose gap from the whole run's own estimated end is that wide (kopuz's
// build_display_lines). Every original line's `parent` is remapped onto
// its new index; nothing is mutated in place.
function displayLines(lines) {
    if (!lines || lines.length === 0)
        return [];
    var main = mainLineIndices(lines);
    var gaps = [];

    // Nothing is lit before the first line, so the run-in is judged on the
    // dark rule alone rather than on kopuz's wider one.
    if (main.length > 0 && lines[main[0]].time > SEAMLESS_GAP_SECONDS)
        gaps.push({ at: main[0], start: 0, end: lines[main[0]].time });

    for (var w = 0; w + 1 < main.length; w++) {
        var current = main[w];
        var next = main[w + 1];
        var nextStart = lines[next].time;
        var gapStart = -Infinity;
        // Whether the whole run (the main line and any background line
        // riding after it) carries an end of its own, which is what decides
        // whether it goes dark at all: `lineActiveAt` runs a line with no end
        // until the next main line starts, so such a run is never dark and
        // needs no note over it however wide the gap reads.
        var runEnds = true;
        for (var k = current; k < next; k++) {
            if (typeof lines[k].end !== "number" || !isFinite(lines[k].end))
                runEnds = false;
            gapStart = Math.max(gapStart, lineEndEstimate(lines[k]));
        }
        gapStart = Math.max(lines[current].time, Math.min(gapStart, nextStart));
        // Two rules, not one. kopuz's own threshold marks an instrumental
        // stretch, and the second one closes the hole it leaves: a run that
        // ends 3 to 5 seconds before the next line goes dark (the seamless
        // carry only reaches SEAMLESS_GAP_SECONDS) and drew nothing at all,
        // so the pane sat between two lines with no lit row and no note
        // (owner, 2026-09-18). Past this, the row that goes dark and the note
        // that lights answer one rule: the note's own start IS the instant
        // `lineActiveAt` stops holding the line before it.
        if (nextStart - gapStart >= INTERLUDE_MIN_SECONDS
            || (runEnds && nextStart - gapStart > SEAMLESS_GAP_SECONDS))
            gaps.push({ at: next, start: gapStart, end: nextStart });
    }

    if (gaps.length === 0)
        return lines.slice();

    var display = [];
    var remap = new Array(lines.length);
    var gapIndex = 0;

    for (var i = 0; i < lines.length; i++) {
        while (gapIndex < gaps.length && gaps[gapIndex].at === i) {
            display.push({
                interlude: true,
                time: gaps[gapIndex].start,
                end: gaps[gapIndex].end,
                text: "",
                words: [],
                parent: null,
                background: false,
                oppositeTurn: false,
                estimated: false
            });
            gapIndex++;
        }
        remap[i] = display.length;
        display.push(lines[i]);
    }

    for (var j = 0; j < display.length; j++) {
        var entry = display[j];
        if (entry.parent !== null && entry.parent !== undefined)
            display[j] = Object.assign({}, entry, { parent: remap[entry.parent] });
    }

    return display;
}

// The depth ramp at `distance` rows from the anchor, spread over `rowSpan`
// rows instead of the table's own four entries: `rowSpan` is how many rows
// the pane actually has room for on that side of the anchor, so the ramp
// reaches its floor at the viewport's edge rather than three rows in with
// the rest of the pane left holding rows nobody can read (owner,
// 2026-09-18). The table is sampled rather than replaced, so the curve is
// the one spec P5 asked for whatever the pane's height turns out to be, and
// an omitted span reproduces the four entries exactly.
function depthOpacity(distance, rowSpan) {
    var last = _DEPTH_OPACITY.length - 1;
    var span = (typeof rowSpan === "number" && isFinite(rowSpan) && rowSpan > 0) ? rowSpan : last;
    // Multiplied before the divide, so an integer distance against the
    // default span lands on a table entry exactly rather than a float
    // hair away from one.
    var at = Math.min(last, Math.abs(distance) * last / span);
    var low = Math.floor(at);
    if (low >= last)
        return _DEPTH_OPACITY[last];
    return _DEPTH_OPACITY[low] + (_DEPTH_OPACITY[low + 1] - _DEPTH_OPACITY[low]) * (at - low);
}

// How many rows fit between the anchored row's own resting place (the
// comfort offset) and each end of a `viewportHeight`-tall viewport, at
// `rowPitch` px a row. The two ramps above and `blurFor` below span these
// rather than a fixed row count, so a taller pane reads more of the song.
// Never under 1: a pane with room for less than one row either side still
// has to put its neighbours somewhere on the ramp.
function rowSpans(viewportHeight, rowPitch) {
    if (!(viewportHeight > 0) || !(rowPitch > 0))
        return { above: 1, below: 1 };
    var top = viewportHeight * COMFORT_OFFSET_FRACTION;
    return {
        above: Math.max(1, top / rowPitch),
        below: Math.max(1, (viewportHeight - top) / rowPitch)
    };
}

// The 0..1 fade a `height`-tall row starting at `top` carries for its
// clearance from the ends of a `viewportHeight`-tall viewport: 1 while it
// clears both by its own height, ramping to 0 as either end reaches it.
// The ramp is spent BEFORE the viewport's clip rather than across it: an
// overlap ramp left the row that the clip cut still painting its visible
// half, so the pane ended on half a glyph (owner, 2026-09-18). `top` is the
// item's position after the column's own travel, so the caller adds the
// column's animated `y` to the item's own.
function edgeFraction(top, height, viewportHeight) {
    if (!(height > 0))
        return 0;
    var clearance = Math.min(top, viewportHeight - (top + height));
    return Math.max(0, Math.min(1, clearance / height));
}

// A line's depth-of-field blur for its distance (in display rows, not
// seconds) from the anchor: kopuz's rightbar ramp, capped before the
// strength scale is applied, quantised to BLUR_QUANTUM_PX so the effect's
// own cache doesn't rebuild every frame over a sub-pixel change. `rowSpan`
// is the row count the pane has room for on that side (`rowSpans` above),
// so the cap lands at the viewport's edge; omitting it keeps the ramp's own
// BLUR_STEP_PX slope, which is where the default span comes from.
function blurFor(distance, strengthPercent, rowSpan) {
    var span = (typeof rowSpan === "number" && isFinite(rowSpan) && rowSpan > 0)
        ? rowSpan : (BLUR_MAX_PX / BLUR_STEP_PX);
    var capped = Math.min(Math.abs(distance) / span, 1) * BLUR_MAX_PX;
    var scaled = capped * (strengthPercent / 100);
    return Math.round(scaled / BLUR_QUANTUM_PX) * BLUR_QUANTUM_PX;
}

// A chunk's own text rows as bands over its box. A `Flow` breaks between
// its items and never inside one, so a chunk wider than the pane wraps
// inside its own `Text` instead, and the wipe over it has to cross that
// break the way reading does. `rows` is what `Text.onLineLaidOut` handed
// over ({y, height, width} per laid-out line, in order); the bands returned
// tile the whole box top to bottom (a band runs to the next row's own top,
// and the last to the box's floor) so the mask never leaves a sliver of a
// glyph uncovered, and each carries the row's own ink width for `rowWipe`.
function chunkRowBands(rows, boxHeight, boxWidth) {
    if (!rows || rows.length === 0)
        return [{ top: 0, height: boxHeight, width: boxWidth }];
    var out = [];
    for (var i = 0; i < rows.length; i++) {
        var top = (i === 0) ? 0 : rows[i].y;
        var bottom = (i + 1 < rows.length) ? rows[i + 1].y : boxHeight;
        out.push({
            top: top,
            height: Math.max(0, bottom - top),
            width: rows[i].width > 0 ? rows[i].width : boxWidth
        });
    }
    return out;
}

// The 0..1 wipe on one band of a wrapped chunk at the chunk's own
// `progress`: band N finishes at its own right end before band N+1 starts at
// its left, so the lit run reads in reading order rather than as one
// horizontal cut across every row of the block at once (owner, 2026-09-18).
// The travel is weighted by each band's own ink width, so the edge crosses a
// full row and a short last one at one speed instead of spending the same
// time on each.
function rowWipe(bands, index, progress) {
    if (!bands || index < 0 || index >= bands.length)
        return 0;
    if (bands.length === 1)
        return progress;
    var total = 0;
    for (var i = 0; i < bands.length; i++)
        total += Math.max(0, bands[i].width);
    var own = Math.max(0, bands[index].width);
    if (!(total > 0) || !(own > 0))
        return progress >= 1 ? 1 : 0;
    var before = 0;
    for (var j = 0; j < index; j++)
        before += Math.max(0, bands[j].width);
    return Math.max(0, Math.min(1, (progress * total - before) / own));
}

// The column `y` that rests an item starting at `itemY` with its own top
// COMFORT_OFFSET_FRACTION down a `viewportHeight`-tall viewport (kopuz's
// comfort scroll offset, translated from a scrollTop into a translated
// column's own y since the pane never has real scroll content). Anchored
// on the item's top rather than its centre, so `itemHeight` doesn't figure
// into the offset; the panel still passes it, matching every other
// position helper's own signature.
function comfortY(viewportHeight, itemY, itemHeight) {
    return viewportHeight * COMFORT_OFFSET_FRACTION - itemY;
}
