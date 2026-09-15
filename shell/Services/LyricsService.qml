pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import qs.Services
import "../Lyrics/model.js" as Lyrics

// Auto-fetched synced lyrics for the media panel's karaoke-like block (M55
// Task 2, spec D1-D4/D9). Isolated behind `media.lyrics` in settings.json
// and hidden-work-gated on `panelWants` (MediaPanel sets it while open,
// Task 3): nothing runs while the panel is closed even with a track
// playing, and a cache hit costs one `cat`. Every step goes over `curl` in
// a `Process` (AppleMusicArtService's idiom: `--fail`, an 8s `--max-time`,
// stdout captured), never QML's XMLHttpRequest, so the whole chain (disk
// test, curl, disk write) is one uniform exit-code/stdout contract.
//
// lrclib.net alone (D1): `/api/get` by tag and duration, falling back to
// `/api/search` by tag alone, is the one open provider both caelestia and
// kopuz share; `plainLyrics` is never read, only synced. Every URL, the
// cache key and every bit of LRC parsing lives in Lyrics/model.js (M55); this
// file is pure side-effect orchestration plus the in-memory record of what
// has already resolved this session.
//
// Disk cache (D2): a hit is `<key>.lrc`, kept forever; a known miss is an
// empty `<key>.none` marker, re-asked once it is seven days old rather than
// on every open, so a track lrclib genuinely has nothing timed for doesn't
// cost a request every time the panel opens. Writes go through a temp name
// and `mv`, never `FileView.setText` (ThemeEngine.qml's own documented
// hazard: it silently skips both the write and its `saved()` signal when
// the new text is byte-identical to what's already on disk).
Singleton {
    id: root

    // Config.loaded gated so a fresh boot can't read the pre-load `false`
    // as a real disable, same guard AppleMusicArtService uses.
    readonly property bool enabled: Core.Config.loaded && Core.Config.get("media.lyrics", true)

    // MediaPanel sets this while it is open (Task 3); nothing else does,
    // so a closed panel never starts a lookup even with a track playing.
    property bool panelWants: false

    readonly property string _cacheDir: {
        const xdgCache = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache");
        return xdgCache + "/formalshell/lyrics";
    }

    readonly property string key: root.enabled && MediaService.title !== "" && MediaService.artist !== ""
        ? Lyrics.cacheKey(MediaService.artist, MediaService.title, MediaService.album, MediaService.length) : ""

    // key -> {state: "synced"|"none", lrc, source}. A track already
    // resolved this session is served straight from here on reopen,
    // no process spawned. "error" is deliberately never stored, so a
    // failed lookup is retried the next time the panel wants it.
    property var _resolved: ({})
    // Bumped on every key change so a lookup in flight for a track the
    // user has since left can never land (AppleMusicArtService's pattern).
    property int _serial: 0

    property string state: "off"
    property string source: ""
    property var lines: []
    readonly property bool hasWords: {
        for (var i = 0; i < root.lines.length; i++) {
            if (root.lines[i].words && root.lines[i].words.length > 0)
                return true;
        }
        return false;
    }

    onEnabledChanged: root._resolve()
    onPanelWantsChanged: root._resolve()
    onKeyChanged: root._resolve()
    // The bootstrap mkdir runs once, before anything else touches the
    // cache dir; _resolve() only fires afterwards so a lookup never races
    // a write against a directory that isn't there yet.
    Component.onCompleted: root._run(["mkdir", "-p", root._cacheDir], function () {
        root._resolve();
    })

    function _resolve() {
        root._serial++;
        const serial = root._serial;
        if (!root.enabled) {
            root.state = "off";
            root.source = "";
            root.lines = [];
            return;
        }
        if (root.key === "") {
            root.state = "idle";
            root.source = "";
            root.lines = [];
            return;
        }
        const cached = root._resolved[root.key];
        if (cached) {
            root._apply(cached.state, cached.lrc, cached.source);
            return;
        }
        // A new key with nothing resolved yet: clear the previous track's
        // lines before either sitting idle or starting a fresh lookup.
        root.lines = [];
        root.source = "";
        if (!root.panelWants) {
            root.state = "idle";
            return;
        }
        root.state = "loading";
        root._lookup(root.key, serial);
    }

    function _apply(state, lrc, source) {
        root.state = state;
        root.source = source;
        root.lines = state === "synced" ? Lyrics.parseLrc(lrc) : [];
    }

    // Stored only for "synced" and "none": a real answer worth remembering
    // for the rest of the session. "error" is never cached here, see
    // _resolved's own comment.
    function _store(key, serial, state, lrc, source) {
        if (state === "synced" || state === "none")
            root._resolved[key] = { state: state, lrc: lrc, source: source };
        if (serial === root._serial)
            root._apply(state, lrc, source);
    }

    function _fail(serial) {
        if (serial !== root._serial)
            return;
        root.state = "error";
        root.source = "";
        root.lines = [];
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

    function _curl(args, onDone) {
        root._run(["curl", "-sS", "--fail", "--max-time", "8", "-H", "User-Agent: FormalShell (https://github.com/FormalSnake/FormalShell)"].concat(args), onDone);
    }

    // Exit 0 with nothing usable in the body and exit 22 (--fail's HTTP
    // 404) both read as a plain miss, worth trying the next step of the
    // chain; anything else (no network, a timeout, a 5xx) is a real
    // failure, not a miss lrclib is entitled to report.
    function _curlOutcome(exitCode, body) {
        if (exitCode === 0) {
            const picked = Lyrics.pickSynced(body);
            return picked !== "" ? { kind: "synced", lrc: picked } : { kind: "miss" };
        }
        if (exitCode === 22)
            return { kind: "miss" };
        return { kind: "error" };
    }

    function _lookup(key, serial) {
        const lrcPath = root._cacheDir + "/" + key + ".lrc";
        const nonePath = root._cacheDir + "/" + key + ".none";
        root._run(["test", "-s", lrcPath], exitCode => {
            if (serial !== root._serial)
                return;
            if (exitCode === 0) {
                root._run(["cat", lrcPath], (catExit, text) => {
                    if (serial !== root._serial)
                        return;
                    if (catExit === 0) {
                        root._store(key, serial, "synced", text, "cache");
                        return;
                    }
                    root._checkNoneMarker(key, serial, lrcPath, nonePath);
                });
                return;
            }
            root._checkNoneMarker(key, serial, lrcPath, nonePath);
        });
    }

    // `find -mtime -7` is the portable "modified less than 7 days ago"
    // check on a Linux-only shell; the `grep -q .` turns "one line came
    // back" into a plain exit code.
    function _checkNoneMarker(key, serial, lrcPath, nonePath) {
        root._run(["sh", "-c", 'find "$1" -maxdepth 1 -name "$2" -mtime -7 | grep -q .', "sh", root._cacheDir, key + ".none"], exitCode => {
            if (serial !== root._serial)
                return;
            if (exitCode === 0) {
                root._store(key, serial, "none", "", "cache");
                return;
            }
            root._fetchGet(key, serial, lrcPath, nonePath);
        });
    }

    function _fetchGet(key, serial, lrcPath, nonePath) {
        const url = Lyrics.getUrl(MediaService.artist, MediaService.title, MediaService.album, MediaService.length);
        root._curl([url], (exitCode, body) => {
            if (serial !== root._serial)
                return;
            const outcome = root._curlOutcome(exitCode, body);
            if (outcome.kind === "synced")
                root._writeLrc(key, serial, lrcPath, outcome.lrc);
            else if (outcome.kind === "miss")
                root._fetchSearch(key, serial, lrcPath, nonePath);
            else
                root._fail(serial);
        });
    }

    function _fetchSearch(key, serial, lrcPath, nonePath) {
        const url = Lyrics.searchUrl(MediaService.artist, MediaService.title);
        root._curl([url], (exitCode, body) => {
            if (serial !== root._serial)
                return;
            const outcome = root._curlOutcome(exitCode, body);
            if (outcome.kind === "synced")
                root._writeLrc(key, serial, lrcPath, outcome.lrc);
            else if (outcome.kind === "miss")
                root._writeNoneMarker(key, serial, nonePath);
            else
                root._fail(serial);
        });
    }

    function _writeLrc(key, serial, lrcPath, lrcText) {
        root._run(["sh", "-c", 'printf %s "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", lrcPath, lrcText], exitCode => {
            if (exitCode !== 0)
                console.warn("LyricsService: could not write lyrics cache for", key);
            root._store(key, serial, "synced", lrcText, "lrclib");
        });
    }

    function _writeNoneMarker(key, serial, nonePath) {
        root._run(["sh", "-c", ': > "$1"', "sh", nonePath], exitCode => {
            if (exitCode !== 0)
                console.warn("LyricsService: could not write miss marker for", key);
            root._store(key, serial, "none", "", "lrclib");
        });
    }
}
