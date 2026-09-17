pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import qs.Services
import "../Lyrics/model.js" as Lyrics

// Auto-fetched lyrics for the media panel's karaoke-like block (M56 Task 2,
// spec P2/P3/P10/P11, replacing M55's lrclib-only chain). Isolated behind
// `media.lyrics` and hidden-work-gated on `panelWants` (MediaPanel sets it
// while open): nothing runs while the panel is closed even with a track
// playing. Every network step goes over `curl` in a `Process`
// (AppleMusicArtService's idiom: `--fail`, a per-step `--max-time`, stdout
// captured), never QML's XMLHttpRequest, so the whole chain (disk test,
// curl, disk write) is one uniform exit-code/stdout contract. Every URL,
// every body parser and the line model itself live in Lyrics/model.js; this
// file is pure side-effect orchestration plus the in-memory record of what
// has already resolved this session.
//
// The chain, in order (spec P2):
// 1. A sibling `.lrc` next to the MPRIS `xesam:url` (local tracks only). A
//    hit ends the chain with source "local" and is never written to the
//    disk cache: the file can change under a path this service has no way
//    to invalidate on, so caching it would risk a stale read surviving past
//    the file it came from.
// 2. The disk cache: `<key>.json` (a hit, kept forever) or `<key>.miss` (an
//    empty seven-day marker), both from a past run of step 3.
// 3. Three providers race concurrently: paxsenix Apple Music (iTunes search
//    then paxsenix's lyrics endpoint), paxsenix YouTube (its own search then
//    lyrics endpoint) and lrclib (get then search, M55's own chain). The
//    first to answer with quality 2 (real word or syllable timing) wins
//    outright and every later arrival is ignored; otherwise the chain waits
//    for all three and takes `Lyrics.pickBest`'s highest quality, ties
//    broken by the list order above. A result reaches disk only once every
//    provider that started has answered hit or miss with no network error
//    among them; a run where one erred is kept for the session only (in
//    `_resolved`), so a track that got lrclib's line timing during a
//    paxsenix outage asks again next session rather than freezing on the
//    weaker answer forever.
//
// `lines` is published already through `Lyrics.synthesiseWords`, so the
// panel's wipe always has chunks to draw; `quality` and `hasWords` are
// worked out from the PRE-synthesis lines, so a line whose chunks were
// fabricated here never claims real word timing.
Singleton {
    id: root

    // Config.loaded gated so a fresh boot can't read the pre-load `false`
    // as a real disable, same guard AppleMusicArtService uses.
    readonly property bool enabled: Core.Config.loaded && Core.Config.get("media.lyrics", true)

    // MediaPanel sets this while it is open; nothing else does, so a closed
    // panel never starts a lookup even with a track playing.
    property bool panelWants: false

    // spec P10, all Config.loaded gated the same way: the hard default reads
    // back until settings.json has actually resolved.
    readonly property bool blurEnabled: Core.Config.loaded && Core.Config.get("media.lyricsBlur", true)
    readonly property int blurStrength: Core.Config.loaded ? root._clampedConfigInt("media.lyricsBlurStrength", 100, 0, 200) : 100
    readonly property int offsetMs: Core.Config.loaded ? root._clampedConfigInt("media.lyricsOffsetMs", 0, -5000, 5000) : 0
    readonly property real offsetSeconds: root.offsetMs / 1000

    // Whether the lyrics column still follows the song (spec P9/P11). The
    // panel writes it (a wheel takes it off, its resync button and the
    // keyboard cursor entering the section put it back) and `media lyrics`
    // reads it: the panel owns no state the IPC handler can reach, and this
    // is the one fact about the pane a caller asks for.
    property bool follow: true

    function _clampedConfigInt(path, fallback, min, max) {
        var n = Number(Core.Config.get(path, fallback));
        if (!isFinite(n))
            n = fallback;
        return Math.max(min, Math.min(max, Math.round(n)));
    }

    readonly property string _cacheDir: {
        const xdgCache = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache");
        return xdgCache + "/formalshell/lyrics";
    }

    readonly property string key: root.enabled && MediaService.title !== "" && MediaService.artist !== ""
        ? Lyrics.cacheKey(MediaService.artist, MediaService.title, MediaService.album, MediaService.length) : ""

    // key -> {state, lines, source}, P1-shaped lines pre-synthesis. A track
    // already resolved this session is served straight from here on
    // reopen, no process spawned. "error" is deliberately never stored, so
    // a failed lookup is retried the next time the panel wants it.
    property var _resolved: ({})
    // Bumped on every key change so a lookup in flight for a track the user
    // has since left can never land (AppleMusicArtService's pattern); every
    // step of every provider chain below checks it before acting on its own
    // curl result.
    property int _serial: 0

    property string state: "off"
    property string source: ""
    // Pre-synthesis lines, the source of truth for `quality`/`hasWords`;
    // `lines` below is what the panel actually draws.
    property var _rawLines: []
    readonly property var lines: Lyrics.synthesiseWords(root._rawLines)
    readonly property int quality: Lyrics.quality(root._rawLines)
    readonly property bool hasWords: {
        for (var i = 0; i < root._rawLines.length; i++) {
            if (root._rawLines[i].words && root._rawLines[i].words.length > 0)
                return true;
        }
        return false;
    }

    onEnabledChanged: root._resolve()
    onPanelWantsChanged: root._resolve()
    onKeyChanged: root._resolve()
    // The bootstrap mkdir and the one-time sweep of M55's `.lrc`/`.none`
    // files run before anything else touches the cache dir; `_resolve()`
    // only fires afterwards so a lookup never races a write against a
    // directory that isn't there yet, or reads a marker the new `.json`/
    // `.miss` scheme doesn't know about.
    Component.onCompleted: root._run(["mkdir", "-p", root._cacheDir], function () {
        root._run(["find", root._cacheDir, "-maxdepth", "1", "(", "-name", "*.lrc", "-o", "-name", "*.none", ")", "-delete"], function () {
            root._resolve();
        });
    });

    function _resolve() {
        root._serial++;
        const serial = root._serial;
        // A new track parks the column back on the song, and so does the
        // panel opening on one, since both arrive here.
        root.follow = true;
        if (!root.enabled) {
            root._apply("off", [], "");
            return;
        }
        if (root.key === "") {
            root._apply("idle", [], "");
            return;
        }
        const cached = root._resolved[root.key];
        if (cached) {
            root._apply(cached.state, cached.lines, cached.source);
            return;
        }
        // A new key with nothing resolved yet: clear the previous track's
        // lines before either sitting idle or starting a fresh lookup.
        root._apply(root.panelWants ? "loading" : "idle", [], "");
        if (root.panelWants)
            root._lookup(root.key, serial);
    }

    function _apply(state, lines, source) {
        root.state = state;
        root.source = source;
        root._rawLines = lines || [];
    }

    function _storeSession(key, serial, state, lines, source) {
        root._resolved[key] = { state: state, lines: lines, source: source };
        if (serial === root._serial)
            root._apply(state, lines, source);
    }

    function _fail(serial) {
        if (serial !== root._serial)
            return;
        root._apply("error", [], "");
    }

    // One-shot child process -> (exitCode, stdoutText) callback. A fresh
    // Process per call (AppleMusicArtService's idiom) so overlapping
    // lookups for different tracks run concurrently without one call's
    // stdout clobbering another's.
    Component {
        id: _procComponent
        Process {
            id: proc
            property var onDone: null
            property bool _exited: false
            property int _exitCode: -1
            property bool _collected: false
            property string _text: ""

            function _maybeFinish() {
                if (!proc._exited || !proc._collected)
                    return;
                var cb = proc.onDone;
                proc.onDone = null;
                if (cb)
                    cb(proc._exitCode, proc._text);
                proc.destroy();
            }

            stdout: StdioCollector {
                onStreamFinished: {
                    proc._text = text;
                    proc._collected = true;
                    proc._maybeFinish();
                }
            }
            onExited: (code, status) => {
                proc._exitCode = code;
                proc._exited = true;
                proc._maybeFinish();
            }
        }
    }

    function _run(command, onDone) {
        var proc = _procComponent.createObject(root, { onDone: onDone });
        proc.exec({ command: command });
    }

    function _curl(args, timeoutSeconds, onDone) {
        root._run(["curl", "-sS", "--fail", "--max-time", String(timeoutSeconds), "-H", "User-Agent: FormalShell (https://github.com/FormalSnake/FormalShell)"].concat(args), onDone);
    }

    // Transport-level read on a curl exit code, ahead of any parsing of the
    // body it carried: exit 0 with nothing usable in the body and exit 22
    // (--fail's HTTP 404) both belong to the caller's own miss handling,
    // "error" is a network failure no provider is entitled to report as a
    // plain absence.
    function _stepOutcome(exitCode) {
        if (exitCode === 0)
            return "ok";
        if (exitCode === 22)
            return "miss";
        return "error";
    }

    function _linesFromLrclibBody(body) {
        const text = Lyrics.pickSynced(body);
        return text !== "" ? Lyrics.parseLrc(text) : [];
    }

    function _linesFromLrcText(text) {
        const lines = Lyrics.parseLrc(text);
        return Lyrics.hasUsableTiming(lines) ? lines : [];
    }

    // The sibling `.lrc` step (spec P2.1): same basename as the playing
    // file, one extension swapped for another. `cb(lines)` gets null for no
    // file, an unreadable one, or one with nothing usably timed.
    function _localFetch(serial, cb) {
        const fileUrl = MediaService.url;
        if (fileUrl.indexOf("file://") !== 0) {
            cb(null);
            return;
        }
        const path = decodeURIComponent(fileUrl.slice("file://".length));
        const lrcPath = path.replace(/\.[^/.]+$/, "") + ".lrc";
        root._run(["cat", lrcPath], (exitCode, text) => {
            if (serial !== root._serial)
                return;
            if (exitCode !== 0) {
                cb(null);
                return;
            }
            const lines = Lyrics.parseLrc(text);
            cb(Lyrics.hasUsableTiming(lines) ? lines : null);
        });
    }

    function _lookup(key, serial) {
        root._localFetch(serial, function (lines) {
            if (serial !== root._serial)
                return;
            if (lines) {
                root._storeSession(key, serial, "synced", lines, "local");
                return;
            }
            root._checkDiskCache(key, serial);
        });
    }

    function _checkDiskCache(key, serial) {
        const jsonPath = root._cacheDir + "/" + key + ".json";
        root._run(["cat", jsonPath], (exitCode, text) => {
            if (serial !== root._serial)
                return;
            if (exitCode === 0) {
                var parsed = null;
                try {
                    parsed = JSON.parse(text);
                } catch (e) {
                    parsed = null;
                }
                // A corrupt `.json` reads as a cache miss, not an error: it
                // falls straight through to the miss marker check below,
                // same as no file at all.
                if (parsed && Array.isArray(parsed.lines) && parsed.lines.length > 0) {
                    root._storeSession(key, serial, "synced", parsed.lines, "cache");
                    return;
                }
            }
            root._checkMissMarker(key, serial);
        });
    }

    // `find -mtime -7` is the portable "modified less than 7 days ago"
    // check on a Linux-only shell; the `grep -q .` turns "one line came
    // back" into a plain exit code.
    function _checkMissMarker(key, serial) {
        root._run(["sh", "-c", 'find "$1" -maxdepth 1 -name "$2" -mtime -7 | grep -q .', "sh", root._cacheDir, key + ".miss"], exitCode => {
            if (serial !== root._serial)
                return;
            if (exitCode === 0) {
                root._storeSession(key, serial, "none", [], "");
                return;
            }
            root._race(key, serial);
        });
    }

    // paxsenix Apple Music (spec P2.2): iTunes search at 5s, its own lyrics
    // endpoint at 10s. A search with no candidate clearing kopuz's match
    // floor/duration window is a miss, not an error; a malformed body reads
    // as no candidates rather than throwing.
    function _appleFetch(serial, cb) {
        const query = ((MediaService.title || "") + " " + (MediaService.artist || "")).trim();
        root._curl([Lyrics.itunesSearchUrl(MediaService.artist, MediaService.title)], 5, (exitCode, body) => {
            if (serial !== root._serial)
                return;
            const step = root._stepOutcome(exitCode);
            if (step === "error") {
                cb({ kind: "error" });
                return;
            }
            var songs = [];
            if (step === "ok") {
                try {
                    const data = JSON.parse(body);
                    songs = (data && Array.isArray(data.results)) ? data.results : [];
                } catch (e) {
                    songs = [];
                }
            }
            const best = Lyrics.bestItunesSong(songs, query, MediaService.length);
            if (!best) {
                cb({ kind: "miss" });
                return;
            }
            root._curl([Lyrics.paxsenixAppleLyricsUrl(best.trackId)], 10, (exitCode2, body2) => {
                if (serial !== root._serial)
                    return;
                const step2 = root._stepOutcome(exitCode2);
                if (step2 === "error") {
                    cb({ kind: "error" });
                    return;
                }
                const lines = step2 === "ok" ? Lyrics.fromPaxsenixApple(body2) : [];
                cb(lines.length > 0 ? { kind: "hit", lines: lines } : { kind: "miss" });
            });
        });
    }

    // paxsenix YouTube (spec P2.3): its own search at 5s, its lyrics
    // endpoint at 3s. The search response is a bare array, not an object.
    function _youtubeFetch(serial, cb) {
        const query = ((MediaService.title || "") + " " + (MediaService.artist || "")).trim();
        root._curl([Lyrics.paxsenixYoutubeSearchUrl(MediaService.artist, MediaService.title)], 5, (exitCode, body) => {
            if (serial !== root._serial)
                return;
            const step = root._stepOutcome(exitCode);
            if (step === "error") {
                cb({ kind: "error" });
                return;
            }
            var results = [];
            if (step === "ok") {
                try {
                    const data = JSON.parse(body);
                    results = Array.isArray(data) ? data : [];
                } catch (e) {
                    results = [];
                }
            }
            const best = Lyrics.bestYoutubeResult(results, query, MediaService.length);
            if (!best) {
                cb({ kind: "miss" });
                return;
            }
            root._curl([Lyrics.paxsenixYoutubeLyricsUrl(best.videoId)], 3, (exitCode2, body2) => {
                if (serial !== root._serial)
                    return;
                const step2 = root._stepOutcome(exitCode2);
                if (step2 === "error") {
                    cb({ kind: "error" });
                    return;
                }
                const lines = step2 === "ok" ? root._linesFromLrcText(body2) : [];
                cb(lines.length > 0 ? { kind: "hit", lines: lines } : { kind: "miss" });
            });
        });
    }

    // lrclib (spec P2.4, M55's own chain): get by tag and duration at 5s,
    // falling back to search by tag alone at 5s.
    function _lrclibFetch(serial, cb) {
        const getUrl = Lyrics.getUrl(MediaService.artist, MediaService.title, MediaService.album, MediaService.length);
        root._curl([getUrl], 5, (exitCode, body) => {
            if (serial !== root._serial)
                return;
            const step = root._stepOutcome(exitCode);
            if (step === "error") {
                cb({ kind: "error" });
                return;
            }
            if (step === "ok") {
                const lines = root._linesFromLrclibBody(body);
                if (lines.length > 0) {
                    cb({ kind: "hit", lines: lines });
                    return;
                }
            }
            const searchUrl = Lyrics.searchUrl(MediaService.artist, MediaService.title);
            root._curl([searchUrl], 5, (exitCode2, body2) => {
                if (serial !== root._serial)
                    return;
                const step2 = root._stepOutcome(exitCode2);
                if (step2 === "error") {
                    cb({ kind: "error" });
                    return;
                }
                const lines2 = step2 === "ok" ? root._linesFromLrclibBody(body2) : [];
                cb(lines2.length > 0 ? { kind: "hit", lines: lines2 } : { kind: "miss" });
            });
        });
    }

    // The three-way race (spec P2): first quality-2 hit wins outright and
    // publishes immediately, `decided` then keeps every later arrival from
    // touching state again. Either way `finalize` waits for the third
    // outcome before deciding what, if anything, reaches disk: a network
    // error anywhere in the three means session-only, no error at all means
    // the winner (the early one, or `pickBest`'s pick once every provider
    // is in) is worth remembering past this run.
    function _race(key, serial) {
        var outcomes = {};
        var decided = null;
        var settledCount = 0;
        const providers = ["apple", "youtube", "lrclib"];

        function finalize() {
            if (settledCount < providers.length || serial !== root._serial)
                return;
            var hasError = false;
            for (var i = 0; i < providers.length; i++) {
                if (outcomes[providers[i]].kind === "error")
                    hasError = true;
            }
            const winner = decided || Lyrics.pickBest(providers.map(function (name) {
                return { source: name, lines: (outcomes[name].lines || []) };
            }));
            if (!winner) {
                if (hasError) {
                    root._fail(serial);
                    return;
                }
                root._writeMissMarker(key, serial);
                return;
            }
            if (hasError) {
                root._storeSession(key, serial, "synced", winner.lines, winner.source);
                return;
            }
            root._writeJsonCache(key, serial, winner.source, winner.lines);
        }

        function onSettled(name, outcome) {
            if (serial !== root._serial)
                return;
            outcomes[name] = outcome;
            settledCount++;
            if (!decided && outcome.kind === "hit" && Lyrics.isDefinitive(outcome.lines)) {
                decided = { source: name, lines: outcome.lines };
                root._apply("synced", outcome.lines, name);
            }
            finalize();
        }

        root._appleFetch(serial, function (outcome) { onSettled("apple", outcome); });
        root._youtubeFetch(serial, function (outcome) { onSettled("youtube", outcome); });
        root._lrclibFetch(serial, function (outcome) { onSettled("lrclib", outcome); });
    }

    function _writeJsonCache(key, serial, source, lines) {
        const jsonPath = root._cacheDir + "/" + key + ".json";
        const payload = JSON.stringify({ source: source, lines: lines });
        root._run(["sh", "-c", 'printf %s "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", jsonPath, payload], exitCode => {
            if (exitCode !== 0)
                console.warn("LyricsService: could not write lyrics cache for", key);
            root._storeSession(key, serial, "synced", lines, source);
        });
    }

    function _writeMissMarker(key, serial) {
        const missPath = root._cacheDir + "/" + key + ".miss";
        root._run(["sh", "-c", ': > "$1"', "sh", missPath], exitCode => {
            if (exitCode !== 0)
                console.warn("LyricsService: could not write miss marker for", key);
            root._storeSession(key, serial, "none", [], "");
        });
    }
}
