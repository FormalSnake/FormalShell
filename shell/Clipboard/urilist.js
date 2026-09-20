.pragma library

// GTK4 apps copy an image as a GdkFileList, not as pixels: Loupe and
// Nautilus both offer `text/uri-list` (RFC 2483: CRLF lines, `#` comments)
// with the path again as text/plain, and no image/* type at all. This reads
// such an offer down to the one local image it names, or null for anything
// else (several files, a remote uri, a file that is not a picture).

// What ffmpeg's image2 demuxer decodes to a single frame. No svg: that
// would need a rasteriser the wrapper's PATH does not carry.
var EXTENSIONS = ["png", "jpg", "jpeg", "webp", "gif", "bmp", "tif", "tiff", "avif"];

function imageFile(uriList) {
    if (typeof uriList !== "string") return null;
    var uris = uriList.replace(/\0/g, "").split(/\r?\n/).filter(function (l) {
        return l.length > 0 && l.charAt(0) !== "#";
    });
    if (uris.length !== 1) return null;

    var m = /^file:\/\/[^\/]*(\/.*)$/.exec(uris[0]);
    if (!m) return null;

    var path;
    try {
        path = decodeURIComponent(m[1]);
    } catch (e) {
        return null;
    }

    var dot = path.lastIndexOf(".");
    var ext = dot < 0 ? "" : path.slice(dot + 1).toLowerCase();
    if (EXTENSIONS.indexOf(ext) < 0) return null;
    return { uri: uris[0], path: path, png: ext === "png" };
}
