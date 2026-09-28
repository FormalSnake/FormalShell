.pragma library

// Pure Apple Music animated-cover glue (M7 Task 2, spec §5's opt-in
// animated-art feature, ported, with attribution, from
// AvengeMedia/DankMaterialShell PR #2918, MIT). Owns URL construction,
// every response-parsing step of the undocumented chain (iTunes artist
// search matched by exact artist name → that artist's album list matched by
// exact album name → scraped web-player token → amp-api `editorialVideo` →
// HLS master/rendition playlists → the one progressive-mp4 byterange), and
// the cache-key/prune-decision logic. No Process/XMLHttpRequest/Date.now() in here,
// AppleMusicArtService.qml owns every network and disk side effect, this
// file stays deterministic under test. Every parse function takes the raw
// process exit code alongside the output text, mirroring openmeteo.js's
// XHR-status convention, so a curl failure and a 200-with-garbage-body both
// get an honest, distinct error rather than a thrown exception.

function cacheKey(artist, album) {
    var raw = (artist + " " + album).toLowerCase();
    return raw.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

function cachePath(cacheDir, artist, album) {
    return cacheDir + "/" + cacheKey(artist, album) + ".mp4";
}

// Loosely matches iTunes' own album-title conventions: case, punctuation and
// whitespace are folded, and a trailing "- Single"/"- EP" marker or a
// trailing "(Deluxe)"/"[Remastered]"-style edition tag is stripped (in
// either order, repeatedly, so "Anti (Deluxe) - Single" and "Anti - Single
// (Deluxe)" both collapse to "anti"). Used to compare both sides of an
// artist/album match, never to build a URL.
function normalizeName(name) {
    var s = (name || "").trim();
    var changed = true;
    while (changed) {
        changed = false;
        var withoutTag = s.replace(/\s*[\(\[][^\(\)\[\]]*[\)\]]\s*$/, "").trim();
        if (withoutTag !== s) {
            s = withoutTag;
            changed = true;
            continue;
        }
        var withoutSuffix = s.replace(/\s*-\s*(single|ep)\s*$/i, "").trim();
        if (withoutSuffix !== s) {
            s = withoutSuffix;
            changed = true;
        }
    }
    return s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function artistSearchUrl(artist) {
    if (!artist)
        return null;
    return "https://itunes.apple.com/search?media=music&entity=musicArtist&limit=5&term=" + encodeURIComponent(artist);
}

// iTunes' artist search is a name search, not an id lookup, so it returns
// every artist sharing the term ("Tyler, The Creator" alongside "Not Tyler,
// The Creator" and "Tyla"). A hit is the result whose normalised artistName
// equals the player's normalised artist exactly; anything else, including a
// same-named result the search didn't surface at all, is a miss
// (artistId: null), never a guess.
function parseArtistSearchResult(exitCode, output, artist) {
    if (exitCode !== 0)
        return { ok: false, error: "http_error" };
    var data;
    try {
        data = JSON.parse(output);
    } catch (e) {
        return { ok: false, error: "malformed_json" };
    }
    var results = data && Array.isArray(data.results) ? data.results : [];
    var target = normalizeName(artist);
    for (var i = 0; i < results.length; i++) {
        var r = results[i];
        if (r && normalizeName(r.artistName) === target)
            return { ok: true, artistId: (r.artistId === undefined ? null : r.artistId) };
    }
    return { ok: true, artistId: null };
}

function artistAlbumsUrl(artistId) {
    return "https://itunes.apple.com/lookup?id=" + artistId + "&entity=album&limit=200";
}

// The artist lookup echoes the artist itself (wrapperType "artist") ahead of
// every album (wrapperType "collection"), so only collections are
// considered. An exact raw collectionName match wins over a normalised one,
// so a plain "IGOR" search picks the plain edition over a "(Deluxe)"-suffixed
// reissue sitting earlier in the list. No matching album is a miss
// (collectionId: null): the artist is real but iTunes doesn't carry this
// particular album under this title.
function parseArtistAlbumsResult(exitCode, output, album) {
    if (exitCode !== 0)
        return { ok: false, error: "http_error" };
    var data;
    try {
        data = JSON.parse(output);
    } catch (e) {
        return { ok: false, error: "malformed_json" };
    }
    var results = data && Array.isArray(data.results) ? data.results : [];
    var target = normalizeName(album);
    var normalizedMatch = null;
    for (var i = 0; i < results.length; i++) {
        var r = results[i];
        if (!r || r.wrapperType !== "collection")
            continue;
        if (r.collectionName === album)
            return { ok: true, collectionId: r.collectionId };
        if (normalizedMatch === null && normalizeName(r.collectionName) === target)
            normalizedMatch = r.collectionId;
    }
    return { ok: true, collectionId: normalizedMatch };
}

function albumPageUrl(collectionId) {
    return "https://music.apple.com/us/album/" + collectionId;
}

// The anonymous web-player JWT sits in the main JS bundle referenced by any
// album page, the asset path first, then the token out of that bundle.
function extractAssetPath(html) {
    var m = /\/assets\/index~[A-Za-z0-9]+\.js/.exec(html || "");
    return m ? m[0] : null;
}

function extractToken(jsText) {
    var m = /"(eyJ[A-Za-z0-9._-]+)"/.exec(jsText || "");
    return m ? m[1] : null;
}

function ampApiUrl(collectionId) {
    return "https://amp-api.music.apple.com/v1/catalog/us/albums/" + collectionId + "?extend=editorialVideo";
}

// A hit is a non-empty HLS master-playlist URL; a miss (no editorialVideo,
// or one with neither known video field) still parses ok with an empty
// videoUrl so the caller caches "no animated art" rather than retrying every
// play. An http_error leaves the token untouched for the caller to decide
// whether to rescrape (it may simply have expired).
function parseEditorialVideo(exitCode, output) {
    if (exitCode !== 0)
        return { ok: false, error: "http_error" };
    var data;
    try {
        data = JSON.parse(output);
    } catch (e) {
        return { ok: false, error: "malformed_json" };
    }
    var entry = data && Array.isArray(data.data) ? data.data[0] : null;
    var attributes = entry ? entry.attributes : null;
    if (!attributes)
        return { ok: false, error: "missing_fields" };
    var ev = attributes.editorialVideo;
    if (!ev)
        return { ok: true, videoUrl: "" };
    var video = (ev.motionDetailSquare && ev.motionDetailSquare.video)
        || (ev.motionSquareVideo1x1 && ev.motionSquareVideo1x1.video)
        || "";
    return { ok: true, videoUrl: video };
}

function resolveUrl(maybeRelative, baseUrl) {
    if (maybeRelative.indexOf("http") === 0)
        return maybeRelative;
    return baseUrl.slice(0, baseUrl.lastIndexOf("/") + 1) + maybeRelative;
}

// Highest-bandwidth avc1 rendition at or below 768px, hvc1 is skipped for
// decoder compatibility. Returns the (possibly relative) variant playlist
// path, or null when the master has no eligible stream at all.
function pickVariant(masterPlaylistText) {
    var lines = (masterPlaylistText || "").split("\n");
    var best = null;
    var bestBandwidth = -1;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line.indexOf("#EXT-X-STREAM-INF:") !== 0 || line.indexOf("avc1") === -1)
            continue;
        var resolution = /RESOLUTION=(\d+)x/.exec(line);
        if (!resolution || parseInt(resolution[1], 10) > 768)
            continue;
        var j = i + 1;
        while (j < lines.length && (lines[j].indexOf("#") === 0 || lines[j].trim() === ""))
            j++;
        if (j >= lines.length)
            continue;
        var bandwidth = /AVERAGE-BANDWIDTH=(\d+)/.exec(line);
        var bandwidthValue = bandwidth ? parseInt(bandwidth[1], 10) : 0;
        if (bandwidthValue > bestBandwidth) {
            bestBandwidth = bandwidthValue;
            best = lines[j].trim();
        }
    }
    return best;
}

// The rendition playlist is BYTERANGE segments over one progressive mp4
// named by EXT-X-MAP, that mp4 is the actual download target.
function extractMp4Url(renditionPlaylistText, variantUrl) {
    var m = /#EXT-X-MAP:URI="([^"]+)"/.exec(renditionPlaylistText || "");
    return m ? resolveUrl(m[1], variantUrl) : null;
}

// Downloaded covers are a few MB each; a file untouched for more than
// maxAgeDays is stale. Exactly maxAgeDays old is NOT yet stale (matches the
// inclusive boundary `find -mtime +N` itself uses), so a fresh 30-day
// re-check never drops a file the same run it crosses the line.
function isStale(mtimeMs, nowMs, maxAgeDays) {
    if (typeof mtimeMs !== "number" || !isFinite(mtimeMs))
        return false;
    var maxAgeMs = maxAgeDays * 24 * 60 * 60 * 1000;
    return (nowMs - mtimeMs) > maxAgeMs;
}

// `find -printf '%T@ %p\n'` output (epoch-seconds mtime, space, path) → the
// paths stale enough to prune. Malformed lines are skipped, never thrown on
//, a partially-corrupt listing should still prune the lines it can read.
function parsePruneListing(listingText, nowMs, maxAgeDays) {
    var stale = [];
    var lines = (listingText || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line === "")
            continue;
        var sep = line.indexOf(" ");
        if (sep === -1)
            continue;
        var epochSeconds = parseFloat(line.slice(0, sep));
        var path = line.slice(sep + 1);
        if (!isFinite(epochSeconds) || path === "")
            continue;
        if (isStale(epochSeconds * 1000, nowMs, maxAgeDays))
            stale.push(path);
    }
    return stale;
}
