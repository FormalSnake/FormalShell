pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import qs.Services
import "../Media/applemusic.js" as AppleMusic

// Apple Music animated album covers (M7 Task 2, spec §5): resolves the
// *currently playing* track's cover through iTunes Search + a scraped
// web-player token + amp-api's undocumented `editorialVideo` field, ported —
// with attribution — from AvengeMedia/DankMaterialShell PR #2918 (MIT).
// Isolated and off by default behind `media.appleMusicArt` in settings.json:
// `_schedule()` bails before touching the network the instant `enabled` is
// false, so flipping the setting off is a hard stop, not a slow one. Every
// step runs over `curl` — the chain ends in a binary mp4 download with an
// atomic rename, so curl's own file-output/exit-code idiom covers the whole
// pipeline uniformly rather than mixing in QML's text-only XMLHttpRequest.
// Every URL-building, response-parsing and staleness decision lives in
// applemusic.js (TDD'd first); this file is pure side-effect orchestration.
Singleton {
    id: root

    readonly property bool enabled: Core.Config.get("media.appleMusicArt", false)

    // file:// URL of the current track's downloaded animated cover, or "" —
    // MediaPanel/AnimatedAlbumArt.qml's own rule (never render anything but
    // this) does the rest, including every fallback-to-static-art path.
    property string animatedArtUrl: ""

    readonly property string _cacheDir: {
        const xdgCache = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache");
        return xdgCache + "/formalshell/applemusic-art";
    }

    property string _token: ""
    // cacheKey -> file:// url, or "" for a known miss — a track without
    // animated art is cached too, so it is never re-fetched every play.
    property var _cache: ({})
    // Bumped on every (re)schedule so a slow in-flight lookup for a track
    // the user has since skipped past can never clobber a newer result.
    property int _serial: 0

    readonly property string _cacheKey: root.enabled && MediaService.artist !== "" && MediaService.album !== ""
        ? AppleMusic.cacheKey(MediaService.artist, MediaService.album) : ""

    on_CacheKeyChanged: root._schedule()
    onEnabledChanged: root._schedule()
    Component.onCompleted: {
        if (root.enabled)
            root._prune();
        root._schedule();
    }

    function _schedule() {
        root._serial++;
        _debounce.stop();
        if (!root.enabled || root._cacheKey === "") {
            root.animatedArtUrl = "";
            return;
        }
        if (root._cacheKey in root._cache) {
            root.animatedArtUrl = root._cache[root._cacheKey];
            return;
        }
        root.animatedArtUrl = "";
        _debounce.restart();
    }

    // Rapid track-skip settles before spending a lookup on a track already
    // gone by the time it would resolve.
    Timer {
        id: _debounce
        interval: 1500
        onTriggered: root._lookup()
    }

    // A lookup that died offline stored nothing (only real answers land in
    // _cache), so re-scheduling on reconnect retries the current track's
    // art; a cached track short-circuits in _schedule() and costs nothing.
    Connections {
        target: ConnectivityService
        function onReconnected() {
            root._schedule();
        }
    }

    // One-shot child process -> (exitCode, stdoutText) callback. A fresh
    // Process per call (never one shared/reused instance) so overlapping
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
        root._run(["curl", "-sS", "--fail", "--connect-timeout", "5", "--max-time", "20", "--compressed"].concat(args), onDone);
    }

    function _artPath(key) {
        return root._cacheDir + "/" + key + ".mp4";
    }

    // Disk cache first: a hit needs no network at all.
    function _lookup() {
        const key = root._cacheKey;
        const serial = root._serial;
        const path = root._artPath(key);
        root._run(["test", "-s", path], exitCode => {
            if (serial !== root._serial)
                return;
            if (exitCode === 0) {
                root._store(key, serial, "file://" + path);
                return;
            }
            root._search(key, serial);
        });
    }

    function _search(key, serial) {
        const url = AppleMusic.searchUrl(MediaService.artist, MediaService.album);
        root._curl([url], (exitCode, output) => {
            if (serial !== root._serial)
                return;
            const parsed = AppleMusic.parseSearchResult(exitCode, output);
            if (!parsed.ok) {
                console.warn("AppleMusicArtService: itunes search failed:", parsed.error);
                return;
            }
            if (parsed.collectionId === null) {
                root._store(key, serial, "");
                return;
            }
            if (root._token !== "") {
                root._fetchEditorialVideo(key, serial, parsed.collectionId);
                return;
            }
            root._fetchToken(parsed.collectionId, () => {
                if (serial !== root._serial)
                    return;
                root._fetchEditorialVideo(key, serial, parsed.collectionId);
            });
        });
    }

    // The anonymous web-player JWT sits in the main JS bundle referenced by
    // any album page — fetch the page, find the bundle, fetch the bundle.
    function _fetchToken(collectionId, callback) {
        root._curl([AppleMusic.albumPageUrl(collectionId)], (pageExit, html) => {
            if (pageExit !== 0) {
                console.warn("AppleMusicArtService: web-player page fetch failed");
                return;
            }
            const assetPath = AppleMusic.extractAssetPath(html);
            if (!assetPath) {
                console.warn("AppleMusicArtService: no asset bundle referenced by album page");
                return;
            }
            root._curl(["https://music.apple.com" + assetPath], (bundleExit, bundleText) => {
                if (bundleExit !== 0) {
                    console.warn("AppleMusicArtService: asset bundle fetch failed");
                    return;
                }
                const token = AppleMusic.extractToken(bundleText);
                if (!token) {
                    console.warn("AppleMusicArtService: no web-player token found in asset bundle");
                    return;
                }
                root._token = token;
                callback();
            });
        });
    }

    function _fetchEditorialVideo(key, serial, collectionId) {
        const args = ["-H", "Authorization: Bearer " + root._token, "-H", "Origin: https://music.apple.com", AppleMusic.ampApiUrl(collectionId)];
        root._curl(args, (exitCode, output) => {
            if (serial !== root._serial)
                return;
            const parsed = AppleMusic.parseEditorialVideo(exitCode, output);
            if (!parsed.ok) {
                // A token can simply expire between plays; rescrape it on
                // the next lookup rather than caching this as a hard miss.
                if (parsed.error === "http_error")
                    root._token = "";
                console.warn("AppleMusicArtService: editorial video lookup failed:", parsed.error);
                return;
            }
            if (parsed.videoUrl === "") {
                root._store(key, serial, "");
                return;
            }
            root._fetchMaster(key, serial, parsed.videoUrl);
        });
    }

    function _fetchMaster(key, serial, m3u8Url) {
        root._curl([m3u8Url], (exitCode, output) => {
            if (serial !== root._serial)
                return;
            if (exitCode !== 0) {
                console.warn("AppleMusicArtService: master playlist fetch failed");
                return;
            }
            const variant = AppleMusic.pickVariant(output);
            if (!variant) {
                root._store(key, serial, "");
                return;
            }
            root._fetchVariant(key, serial, AppleMusic.resolveUrl(variant, m3u8Url));
        });
    }

    function _fetchVariant(key, serial, variantUrl) {
        root._curl([variantUrl], (exitCode, output) => {
            if (serial !== root._serial)
                return;
            if (exitCode !== 0) {
                console.warn("AppleMusicArtService: rendition playlist fetch failed");
                return;
            }
            const mp4Url = AppleMusic.extractMp4Url(output, variantUrl);
            if (!mp4Url) {
                root._store(key, serial, "");
                return;
            }
            root._download(key, serial, mp4Url);
        });
    }

    // Per-lookup temp file then atomic rename, so a concurrent download for
    // the same album (rapid track flip-flop) can never interleave writes
    // into one file — the temp is removed on failure or on being
    // superseded, rather than stranded as a .part.
    function _download(key, serial, url) {
        const path = root._artPath(key);
        const tmpPath = path + "." + serial + ".part";
        root._run(["mkdir", "-p", root._cacheDir], mkdirExit => {
            if (mkdirExit !== 0) {
                console.warn("AppleMusicArtService: could not create cache dir");
                return;
            }
            root._run(["curl", "-sSf", "--connect-timeout", "5", "--max-time", "60", "-o", tmpPath, url], curlExit => {
                if (serial !== root._serial || curlExit !== 0) {
                    if (curlExit !== 0)
                        console.warn("AppleMusicArtService: artwork download failed");
                    root._run(["rm", "-f", tmpPath], () => {});
                    return;
                }
                root._run(["mv", "-f", tmpPath, path], mvExit => {
                    if (serial !== root._serial)
                        return;
                    if (mvExit !== 0) {
                        console.warn("AppleMusicArtService: could not install downloaded artwork");
                        return;
                    }
                    root._store(key, serial, "file://" + path);
                });
            });
        });
    }

    function _store(key, serial, url) {
        root._cache[key] = url;
        if (serial === root._serial)
            root.animatedArtUrl = url;
    }

    // 30-day prune: list the cache dir's own mtimes and let pure
    // applemusic.js decide which files are stale, rather than trusting
    // `find -mtime`'s boundary semantics unverified. Runs once at startup,
    // gated on `enabled` so a disabled install spawns no process at all —
    // the disk cache simply stops growing along with everything else.
    function _prune() {
        root._run(["find", root._cacheDir, "-maxdepth", "1", "-type", "f", "-printf", "%T@ %p\n"], (exitCode, output) => {
            if (exitCode !== 0)
                return; // cache dir doesn't exist yet — nothing to prune
            const stale = AppleMusic.parsePruneListing(output, Date.now(), 30);
            if (stale.length > 0)
                root._run(["rm", "-f"].concat(stale), () => {});
        });
    }
}
