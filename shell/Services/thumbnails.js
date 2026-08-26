.pragma library

// Cache-key math for the wallpaper picker's prerendered thumbnails.
// Pure string work on purpose: the same derivation has to be reachable from
// the service that spawns the generator, from the grid delegate that reads
// the result, and from a test with no Qt object around it, so nothing here
// touches the filesystem or the QML engine.
//
// A cached name is `<basename>-<key>-<mode><size>.jpg`. The basename is
// carried only so the cache directory is readable by hand while debugging;
// the key is what makes the name unique, and the size and mode are in it so
// bumping either invalidates the affected files by construction rather than
// needing a version file nobody would remember to bump.
//
// Two modes, because two callers want different pixels from the same file.
// `cover` centre-crops to a square, which is what a grid of equal cells
// wants (the wallpaper picker: every cell is the same size and the picture
// fills it). `fit` scales the whole image inside the box and keeps its
// aspect, which is what a letterboxed slot wants (a clipboard row's
// capture: cropping a screenshot to its centre square throws away the part
// that identifies it). Neither ever upscales past the box.

// Two 32-bit FNV-1a passes, the second over the reversed string with a
// different offset basis, concatenated into 64 bits. One pass is not enough:
// a wallpaper directory is exactly the shape (hundreds of paths sharing a
// long common prefix) where a 32-bit hash's birthday bound stops being
// comfortable, and two paths colliding would silently show the wrong picture
// in the grid.
function _fnv1a(s, basis) {
    var h = basis >>> 0;
    for (var i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = Math.imul(h, 0x01000193) >>> 0;
    }
    return h >>> 0;
}

function _hex8(n) {
    var s = (n >>> 0).toString(16);
    while (s.length < 8)
        s = "0" + s;
    return s;
}

function _reverse(s) {
    return s.split("").reverse().join("");
}

function pathKey(path) {
    var p = String(path || "");
    return _hex8(_fnv1a(p, 0x811c9dc5)) + _hex8(_fnv1a(_reverse(p), 0x1000193));
}

function basename(path) {
    var p = String(path || "");
    var cut = p.lastIndexOf("/");
    return cut >= 0 ? p.slice(cut + 1) : p;
}

// Everything outside [A-Za-z0-9._-] collapses to `_`, and the result is
// capped well under any filesystem's per-component limit: the key and the
// size still follow it, and a wallpaper called something 200 characters long
// must not be the reason a cache write fails.
function _slug(name) {
    var out = String(name || "").replace(/[^A-Za-z0-9._-]+/g, "_");
    if (out.length > 48)
        out = out.slice(0, 48);
    return out === "" ? "image" : out;
}

// Anything that is not "fit" is "cover", so a caller that forgets the
// argument gets the mode the picker has always used rather than an
// undefined-shaped filename.
function normalizeMode(mode) {
    return mode === "fit" ? "fit" : "cover";
}

function cacheFileName(path, size, mode) {
    var base = basename(path);
    var dot = base.lastIndexOf(".");
    var stem = dot > 0 ? base.slice(0, dot) : base;
    return _slug(stem) + "-" + pathKey(path) + "-" + normalizeMode(mode) + Math.round(size) + ".jpg";
}

function cachePath(dir, path, size, mode) {
    return String(dir || "").replace(/\/+$/, "") + "/" + cacheFileName(path, size, mode);
}

// src/dst pairs flattened into one argv for the generator below, which walks
// them two at a time. The destination is computed here rather than in the
// script so QML knows every cached path without parsing anything back out.
function warmArgs(dir, paths, size, mode) {
    var out = [];
    (paths || []).forEach(function (p) {
        out.push(p);
        out.push(cachePath(dir, p, size, mode));
    });
    return out;
}

// The generator. `$1` is the cache directory, `$2` the square edge in px,
// `$3` the mode, then the src/dst pairs. Prints one source path per line as
// its thumbnail lands, so a grid can fill in progressively instead of
// waiting for the whole directory.
//
// - `-nostdin` because ffmpeg otherwise reads the shell's own stdin.
// - `cover` is `increase` + `crop`, a covering centre crop, which is what a
//   square grid cell's PreserveAspectCrop already shows, so the cache stores
//   exactly the pixels that get drawn and nothing more. `fit` scales the
//   whole picture inside the box instead, and its `min(iw,$size)` bound is
//   what stops a source already smaller than the box being upscaled into a
//   cache file bigger and blurrier than the original it came from.
// - `$src -nt $dst` is the whole invalidation rule: a wallpaper replaced in
//   place is newer than its thumbnail and gets redrawn. A hit `touch`es the
//   thumbnail instead, which makes the `-mtime` sweep above an LRU rather
//   than a fixed expiry, so a thumbnail in daily use is never rebuilt and an
//   orphan left by a deleted wallpaper goes away on its own.
// - A failed ffmpeg (no ffmpeg on PATH at all, an unreadable file, a format
//   it cannot decode) prints nothing and exits 0: the grid then falls back
//   to decoding the source itself, which is the behaviour that existed
//   before any of this.
function warmScript(concurrency) {
    return [
        'dir=$1; size=$2; mode=$3; shift 3',
        'mkdir -p "$dir" || exit 0',
        'find "$dir" -maxdepth 1 -type f \\( -name "*.part.jpg" -o -mtime +30 \\) -delete 2>/dev/null',
        'if [ "$mode" = fit ]; then',
        '  vf="scale=w=\'min(iw,$size)\':h=\'min(ih,$size)\':force_original_aspect_ratio=decrease:flags=lanczos"',
        'else',
        '  vf="scale=$size:$size:force_original_aspect_ratio=increase:flags=lanczos,crop=$size:$size"',
        'fi',
        'printf \'%s\\0\' "$@" | xargs -0 -r -n 2 -P ' + Math.max(1, Math.round(concurrency)) + ' sh -c \'',
        '  src=$1; dst=$2',
        '  if [ -f "$dst" ] && [ ! "$src" -nt "$dst" ]; then touch "$dst"; printf "%s\\n" "$src"; exit 0; fi',
        '  tmp="$dst.part.jpg"',
        '  ffmpeg -v error -nostdin -y -i "$src" -frames:v 1 -q:v 3 -vf "$0" \\',
        '    "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; exit 0; }',
        '  mv -f "$tmp" "$dst" && printf "%s\\n" "$src"',
        '\' "$vf"'
    ].join("\n");
}
