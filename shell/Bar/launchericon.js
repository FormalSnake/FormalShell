.pragma library

// What the launcher cell draws (owner, 2026-08-26: "i want a different icon
// for the launcher. Not the command key"). One settings key,
// `bar.launcherIcon`, and a grammar rather than an enum, so a name the shell
// has never heard of still resolves to something the owner asked for:
//
//   unset           the machine's own distro logo, same as "distro" below
//   "command"       the shadcn Command palette sign, the shell's mark today
//   "formalshell"   the shell's own mark, which is that same sign until a
//                   real one exists. Named separately so the day a mark
//                   lands there is one place to change.
//   "distro"        the machine's own distro logo, resolved below: the real
//                   logo from the font-logos table the wrapper ships, or the
//                   icon theme for a distro that table has never heard of
//   "<name>"        any icon name the active set knows ("snowflake",
//                   "terminal"), through Components/Icon.qml like every
//                   other icon in the shell
//   "<path>"        an absolute path, a ~ path, or a file:// URL to an image
//                   the owner supplies. The one sanctioned image icon
//                   besides a desktop entry's own (DESIGN.md §5 bans SVG
//                   icon ASSETS in the repo, which is about what the shell
//                   ships, not about what a user points it at)
//
// A spec is `{ kind: "icon"|"image"|"glyph", value }`: a name for
// Components/Icon.qml, a URL for an Image, or a literal codepoint to draw in
// the distro logo font. The caller draws one of the three and never has to
// parse anything itself.

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

// `themeIcon` is the caller's icon-theme lookup for the distro case, "" when
// the theme has no such icon. Passed in rather than called here so this
// stays pure and the test can drive both branches.
//
// The distro order is: the bundled font-logos glyph first, then the machine's
// own icon theme, then Tux. The shell's own mark is not in that chain at all,
// since a caller asking for "distro" asked for a distro.
//
// Glyph before theme, which is the opposite of what this did first (owner,
// 2026-08-26: "the logo is tiny and has a white background"). A themed distro
// icon is a full-colour raster with its own padding baked in: dropped into a
// 13px bar slot it renders smaller than the glyphs beside it AND keeps its
// own light fill, so the mark read as a tiny white blob in a row of
// monochrome chrome. The font glyph is drawn on the text baseline and tints
// with `foreground` like every other bar icon. Anyone who actually wants the
// colour logo points `bar.launcherIcon` at the file, which is what the path
// form is for.
function resolve(configValue, osRelease, themeIcon, distroGlyph, tuxGlyph) {
    var value = String(configValue || "").trim();
    // Unset means the machine's own logo (owner, 2026-08-26). The command
    // sign is still reachable by naming it, and is still where the distro
    // chain ends up on a machine with no /etc/os-release at all.
    if (value === "")
        value = "distro";
    if (value === DEFAULT_NAME || value === "formalshell")
        return { kind: "icon", value: DEFAULT_NAME };
    if (isPath(value))
        return { kind: "image", value: value };
    if (value !== "distro")
        return { kind: "icon", value: value };

    var id = String((osRelease || {}).ID || "").trim();
    var glyph = (id !== "" && distroGlyph) ? distroGlyph(id) : "";
    if (glyph !== "" && glyph !== undefined && glyph !== null)
        return { kind: "glyph", value: String(glyph) };

    // Only reached by a distro the font table has never heard of, which is
    // the one case where a themed raster beats drawing Tux at it.
    var name = distroIconName(osRelease);
    var resolved = (name !== "" && themeIcon) ? themeIcon(name) : "";
    if (resolved !== "" && resolved !== undefined && resolved !== null)
        return { kind: "image", value: String(resolved) };

    // We know it is a Linux, we just cannot name it.
    if (id !== "" && tuxGlyph)
        return { kind: "glyph", value: String(tuxGlyph) };
    return { kind: "icon", value: DEFAULT_NAME };
}
