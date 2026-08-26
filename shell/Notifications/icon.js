.pragma library

// Which picture a notification card shows (M48 D4). Pure: every lookup that
// needs Quickshell (a themed icon name, a desktop entry) is injected, the
// same split Menu/providers.js already uses for its own icon resolution, so
// the order can be asserted without a compositor (tst_notification_icon).
//
// The order, first hit wins:
//
//   1. `image`, the `image-data`/`image-path` hint. The server resolved it
//      already (notification.cpp's updateProperties leaves an `image://`,
//      a `file:` url or ""), so it needs no branching here.
//   2. `appIcon`, which the server does NOT resolve: an absolute path, a
//      url, or a themed name.
//   3. the sender's desktop entry: the `desktop-entry` hint first, then a
//      heuristic match on `appName` for the senders that supply neither
//      hint. Its `icon` is a path or a themed name, same branching as 2.
//   4. nothing, and the card draws its own `bell`.
//
// Tier 3 overlaps quickshell only partly: the server folds a desktop
// entry's icon into `appIcon` when the sender sent a `desktop-entry` hint
// AND no app_icon at all (notification.cpp), which leaves the much more
// common sender that sent neither, whose name is still the entry's.

// A themed name whose lookup fails resolves to "" rather than to the
// provider's magenta missing-texture pixmap, which renders as a perfectly
// healthy Image and would sit in the card looking like a broken icon.
var _ICON_URL_PREFIX = "image://icon/";

function _isUrl(value) {
    return value.indexOf("file:") === 0 || value.indexOf("image:") === 0;
}

// Resolves a name that may be an absolute path, an already-built url or a
// themed icon name. `themed` answers "" for a name the icon theme does not
// carry (Quickshell.iconPath(name, true)).
function _resolveName(value, themed) {
    var name = String(value || "");
    if (name.length === 0)
        return "";
    if (_isUrl(name))
        return name;
    if (name.charAt(0) === "/")
        return "file://" + name;
    return themed(name);
}

// The server hands every `image-path` hint that is not already a file url
// to the icon provider verbatim (notification.cpp), so both an absolute path
// and a themed name arrive here as `image://icon/<whatever was sent>`, and
// the provider answers a themed name it cannot find with its magenta
// missing-texture pixmap rather than with a failure. Unwrap those and
// resolve them properly; every other url shape is taken as given, including
// one carrying the provider's own `?path=`/`?fallback=` query.
function _checkedImage(value, themed) {
    var image = String(value || "");
    if (image.indexOf(_ICON_URL_PREFIX) !== 0 || image.indexOf("?") >= 0)
        return image;
    return _resolveName(image.slice(_ICON_URL_PREFIX.length), themed);
}

// `ctx.themed(name)` -> a usable source or ""; `ctx.entry(desktopId, appName)`
// -> the sender's desktop entry (anything with an `icon`) or null.
function resolve(entry, ctx) {
    var notification = entry || {};

    var image = _checkedImage(notification.image, ctx.themed);
    if (image.length > 0)
        return image;

    var appIcon = _resolveName(notification.appIcon, ctx.themed);
    if (appIcon.length > 0)
        return appIcon;

    var desktop = ctx.entry(String(notification.desktopEntry || ""),
        String(notification.appName || ""));
    if (desktop)
        return _resolveName(desktop.icon, ctx.themed);

    return "";
}
