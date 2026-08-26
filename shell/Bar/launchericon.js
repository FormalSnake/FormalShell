.pragma library

// What the launcher cell draws (owner, 2026-08-26: "i want a different icon
// for the launcher. Not the command key"). One settings key,
// `bar.launcherIcon`, and a grammar rather than an enum, so a name the shell
// has never heard of still resolves to something the owner asked for:
//
//   "command"       the shadcn Command palette sign, the shell's mark today
//   "formalshell"   the shell's own mark, which is that same sign until a
//                   real one exists. Named separately so the day a mark
//                   lands there is one place to change.
//   "distro"        whatever /etc/os-release names, resolved below
//   "<name>"        any icon name the active set knows ("snowflake",
//                   "terminal"), through Components/Icon.qml like every
//                   other icon in the shell
//   "<path>"        an absolute path, a ~ path, or a file:// URL to an image
//                   the owner supplies. The one sanctioned image icon
//                   besides a desktop entry's own (DESIGN.md §5 bans SVG
//                   icon ASSETS in the repo, which is about what the shell
//                   ships, not about what a user points it at)
//
// A spec is `{ kind: "icon"|"image", value }`. The caller draws one or the
// other and never has to parse anything itself.

var DEFAULT_NAME = "command";

// `~` and `file://` are resolved by the caller, which is the only thing that
// knows $HOME; everything here stays pure.
function isPath(value) {
    var v = String(value || "");
    return v.indexOf("/") === 0 || v.indexOf("~/") === 0 || v.indexOf("file://") === 0;
}

// os-release is `KEY=value`, values optionally quoted, `#` comments, and the
// freedesktop spec says an unknown key is skipped rather than fatal. Only
// two keys matter here: LOGO names an icon-theme icon outright (NixOS ships
// `LOGO=nix-snowflake`), and ID is the fallback for a distro that sets no
// LOGO, since most icon themes carry an icon named after the distro anyway.
function parseOsRelease(text) {
    var out = {};
    String(text || "").split("\n").forEach(function (line) {
        var trimmed = line.trim();
        if (trimmed === "" || trimmed.indexOf("#") === 0)
            return;
        var eq = trimmed.indexOf("=");
        if (eq <= 0)
            return;
        var key = trimmed.slice(0, eq).trim();
        var value = trimmed.slice(eq + 1).trim();
        if (value.length >= 2) {
            var first = value.charAt(0);
            var last = value.charAt(value.length - 1);
            if ((first === '"' && last === '"') || (first === "'" && last === "'"))
                value = value.slice(1, -1);
        }
        out[key] = value;
    });
    return out;
}

function distroIconName(osRelease) {
    var os = osRelease || {};
    return String(os.LOGO || os.ID || "").trim();
}

// The distro's own glyph in the icon SET, for a machine whose icon theme has
// no distro icon installed (a NixOS box without nixos-icons is the common
// case). Only the ones both shipped sets actually carry; anything else falls
// through to the shell's own mark rather than to a missing-glyph box.
var DISTRO_FALLBACK = {
    "nixos": "snowflake",
    "nix": "snowflake"
};

function distroFallbackName(osRelease) {
    var id = String((osRelease || {}).ID || "").trim().toLowerCase();
    return DISTRO_FALLBACK[id] || DEFAULT_NAME;
}

// `themeIcon` is the caller's icon-theme lookup for the distro case, "" when
// the theme has no such icon. Passed in rather than called here so this
// stays pure and the test can drive both branches.
function resolve(configValue, osRelease, themeIcon) {
    var value = String(configValue || "").trim();
    if (value === "" || value === DEFAULT_NAME || value === "formalshell")
        return { kind: "icon", value: DEFAULT_NAME };
    if (isPath(value))
        return { kind: "image", value: value };
    if (value !== "distro")
        return { kind: "icon", value: value };

    var name = distroIconName(osRelease);
    var resolved = (name !== "" && themeIcon) ? themeIcon(name) : "";
    if (resolved !== "" && resolved !== undefined && resolved !== null)
        return { kind: "image", value: String(resolved) };
    return { kind: "icon", value: distroFallbackName(osRelease) };
}
