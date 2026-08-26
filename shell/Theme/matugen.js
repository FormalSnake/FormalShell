.pragma library

.import "flexoki.js" as Flexoki

// Builds a matugen `-c` TOML config from the spec-mandated merge order:
// user [config] verbatim, then the shell's own template blocks, then the
// user's [templates.*] section verbatim, then any drop-in fragments.

// Rank 0 of matugen's own candidate ranking, read off a `-d` run's stderr:
//
//   ... matugen::color::color] Ranked colors:
//   ... matugen::color::color] 0: #648db8
//   ... matugen::color::color] 1: #908a61
//
// The ranking is material's Score order, so rank 0 is the image's own color;
// ThemeEngine's header covers why none of the --prefer scalars substitutes
// for it. Returns null when the ranking isn't there to read (a matugen whose
// debug output moved, a run that died before extraction), which the caller
// answers with a plain --prefer run rather than by skipping the retheme.
function rankedSourceColor(text) {
    if (!text)
        return null;
    var lines = text.split("\n");
    var inRanking = false;
    for (var i = 0; i < lines.length; i++) {
        if (!inRanking) {
            inRanking = lines[i].indexOf("Ranked colors:") !== -1;
            continue;
        }
        // Anchored on the log prefix's own closing bracket so a timestamp can
        // never be read as a rank.
        var entry = lines[i].match(/\]\s*(\d+):\s*(#[0-9a-fA-F]{6})/);
        if (!entry)
            continue;
        return entry[1] === "0" ? entry[2].toLowerCase() : null;
    }
    return null;
}

function extractSection(text, name) {
    if (!text) return "";
    var headerRe = new RegExp("^\\[" + name + "(\\.|\\])");
    var lines = text.split("\n");
    var start = -1;
    for (var i = 0; i < lines.length; i++) {
        if (headerRe.test(lines[i].trim())) { start = i; break; }
    }
    if (start === -1) return "";
    var end = lines.length;
    for (var j = start + 1; j < lines.length; j++) {
        var line = lines[j].trim();
        if (line.charAt(0) === "[" && !headerRe.test(line)) { end = j; break; }
    }
    return lines.slice(start, end).join("\n");
}

function templateBlock(name, inputPath, outputPath) {
    return "[templates." + name + "]\n" +
        "input_path = '" + inputPath + "'\n" +
        "output_path = '" + outputPath + "'\n";
}

// The no-wallpaper twins of hyprland-colors.conf.tmpl and
// hyprland-colors.lua.tmpl. matugen only runs against an image, so the
// fallback palette has to render the same seven variables itself: without
// this a hyprland.conf sourcing that path (or a hyprland.lua dofile-ing it)
// would read a file that never appears until the first wallpaper is set. Keep
// the name list and the headers in step with both templates.
var HYPRLAND_VARS = ["primary", "primaryForeground", "background", "foreground",
    "border", "destructive", "warning"];

function _hyprRgb(value) {
    return "rgb(" + String(value).replace("#", "") + ")";
}

function hyprlandColors(palette) {
    var out = "# Rendered by matugen (ThemeEngine) into ~/.config/hypr/formalshell-colors.conf\n"
        + "# on every wallpaper/mode change; `source` it from hyprland.conf.\n";
    HYPRLAND_VARS.forEach(function (name) {
        out += "$" + name + " = " + _hyprRgb(palette[name]) + "\n";
    });
    return out;
}

// Hyprland 0.55 replaced hyprlang with Lua, and a Lua config cannot source
// hyprlang, so the same palette also ships as a table a `dofile` returns.
function hyprlandColorsLua(palette) {
    var out = "-- Rendered by matugen (ThemeEngine) into ~/.config/hypr/formalshell-colors.lua\n"
        + "-- on every wallpaper/mode change; `dofile` it from hyprland.lua.\n"
        + "return {\n";
    HYPRLAND_VARS.forEach(function (name) {
        out += "  " + name + " = \"" + _hyprRgb(palette[name]) + "\",\n";
    });
    return out + "}\n";
}

function buildConfig(opts) {
    var parts = [];

    // matugen hard-rejects a config file with no top-level [config] table
    // ("missing field `config`"), so this must always emit one, the user's
    // verbatim section if they have one, otherwise a bare header. A fresh
    // install with no ~/.config/matugen/config.toml must still produce a
    // config matugen will run.
    var userConfig = opts.userConfigText ? extractSection(opts.userConfigText, "config") : "";
    parts.push(userConfig || "[config]");

    parts.push(templateBlock("formalshell",
        opts.shellTemplateDir + "/theme.json.tmpl", opts.stateDir + "/theme.json.tmp"));
    parts.push(templateBlock("formalshell-hyprland",
        opts.shellTemplateDir + "/hyprland-colors.conf.tmpl", opts.stateDir + "/formalshell-colors.conf.tmp"));
    parts.push(templateBlock("formalshell-hyprland-lua",
        opts.shellTemplateDir + "/hyprland-colors.lua.tmpl", opts.stateDir + "/formalshell-colors.lua.tmp"));

    // App-facing palettes, written straight to their final config paths: only
    // theme.json and the Hyprland colours need the .tmp + rename dance (the
    // shell watches one, Hyprland re-reads the others the moment they change,
    // so none can afford a torn read); GTK and Qt apps read these at launch,
    // so a direct matugen write is fine. gtk.css imports
    // formalshell-colors.css; the qt{5,6}ct.conf color_scheme_path points at
    // colors/matugen.conf.
    parts.push(templateBlock("formalshell-gtk3",
        opts.shellTemplateDir + "/gtk-colors.css.tmpl", opts.homeDir + "/.config/gtk-3.0/formalshell-colors.css"));
    parts.push(templateBlock("formalshell-gtk4",
        opts.shellTemplateDir + "/gtk-colors.css.tmpl", opts.homeDir + "/.config/gtk-4.0/formalshell-colors.css"));
    parts.push(templateBlock("formalshell-qt5ct",
        opts.shellTemplateDir + "/qtct-colors.conf.tmpl", opts.homeDir + "/.config/qt5ct/colors/matugen.conf"));
    parts.push(templateBlock("formalshell-qt6ct",
        opts.shellTemplateDir + "/qtct-colors.conf.tmpl", opts.homeDir + "/.config/qt6ct/colors/matugen.conf"));

    if (opts.userConfigText) {
        var userTemplates = extractSection(opts.userConfigText, "templates");
        if (userTemplates) parts.push(userTemplates);
    }

    (opts.dropInTexts || []).forEach(function (text) {
        if (text) parts.push(text);
    });

    return parts.join("\n");
}


// --- Flexoki pin: rewriting a template before matugen renders it ----------
//
// matugen has no way to be handed an exact palette. Its scheme always grows
// out of one source colour, so a Flexoki-pinned run seeded with Flexoki blue
// still renders every template as a single-hue Material scheme: a terminal
// whose ANSI slots read primary/secondary/tertiary comes out blue where it
// asked for green, yellow and magenta.
//
// So the pin rewrites the templates instead. Each {{colors.*}} and
// {{base16.*}} value expression is replaced with the literal Flexoki tone in
// the format it asked for, and matugen renders the rewritten copy.
// Everything else in the file is matugen's: {{image}}, {{mode}}, post_hook,
// output_path, and the templates the user's own config declares.
//
// A filter pipeline survives the rewrite only on a `.hex` value, as
// `{{ "#4385be" | to_color | <filters> }}`: matugen 4.1.0 rejects a colour
// filter applied straight to a string (ParseError::ColorFilterOnString) and
// `to_color` renders hex whatever went in, so an rgb/hsl/hex_stripped value
// under a filter would come out in the wrong syntax and, wrapped in an
// `rgb(...)` the way a hyprland config wraps hex_stripped, would break the
// file it lands in. Those keep matugen's own value and are named in
// `skipped` instead. No template in the tree uses one.

function _rgbParts(hex) {
    var h = hex.replace("#", "");
    return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)];
}

// matugen prints hsl rounded to whole degrees and whole percent
// (`hsl(210, 92%, 80%)`), so this rounds the same way rather than carrying
// decimals a template would render differently from a non-pinned run.
function _hslParts(hex) {
    var rgb = _rgbParts(hex);
    var r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255;
    var max = Math.max(r, g, b), min = Math.min(r, g, b);
    var l = (max + min) / 2;
    var d = max - min;
    var h = 0, s = 0;
    if (d !== 0) {
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
        if (max === r) h = ((g - b) / d) % 6;
        else if (max === g) h = (b - r) / d + 2;
        else h = (r - g) / d + 4;
        h *= 60;
        if (h < 0) h += 360;
    }
    return [Math.round(h), Math.round(s * 100), Math.round(l * 100)];
}

function formatColor(hex, format) {
    var rgb, hsl;
    switch (format) {
    case "hex":
        return hex;
    case "hex_stripped":
        return hex.replace("#", "");
    case "rgb":
        rgb = _rgbParts(hex);
        return "rgb(" + rgb[0] + ", " + rgb[1] + ", " + rgb[2] + ")";
    case "rgba":
        rgb = _rgbParts(hex);
        return "rgba(" + rgb[0] + ", " + rgb[1] + ", " + rgb[2] + ", 1)";
    case "hsl":
        hsl = _hslParts(hex);
        return "hsl(" + hsl[0] + ", " + hsl[1] + "%, " + hsl[2] + "%)";
    case "hsla":
        hsl = _hslParts(hex);
        return "hsla(" + hsl[0] + ", " + hsl[1] + "%, " + hsl[2] + "%, 1)";
    }
    return null;
}

var _EXPR_RE = /\{\{\s*(colors|base16)\.([A-Za-z0-9_]+)\.(default|light|dark)\.([A-Za-z_]+)\s*(\|[^{}]*?)?\}\}/g;

// Replaces every color expression this table can answer. An expression it
// cannot (a custom_colors entry the user declared, a format matugen grew
// since) is left verbatim for matugen to render from its own scheme, and
// named in `skipped` so the caller can say so once rather than silently
// shipping one blue value in an otherwise Flexoki file.
function substituteFlexoki(text, mode) {
    if (!text)
        return { text: text, substituted: 0, skipped: [] };
    var tables = {
        colors: { light: Flexoki.materialRoles("light"), dark: Flexoki.materialRoles("dark") },
        base16: { light: Flexoki.base16("light"), dark: Flexoki.base16("dark") }
    };
    var fallbackScheme = mode === "light" ? "light" : "dark";
    var count = 0;
    var skipped = [];
    var out = text.replace(_EXPR_RE, function (match, group, name, scheme, format, filters) {
        var table = tables[group][scheme === "default" ? fallbackScheme : scheme];
        var key = name;
        if (!(key in table) && group === "base16") {
            // matugen dumps base0a, the matugen-themes templates write
            // base0A; Flexoki's own base16 tables use the upper form.
            for (var candidate in table) {
                if (candidate.toLowerCase() === name.toLowerCase()) {
                    key = candidate;
                    break;
                }
            }
        }
        var value = table[key];
        var rendered = value ? formatColor(value, format) : null;
        if (rendered === null || (filters && format !== "hex")) {
            if (skipped.indexOf(group + "." + name + "." + format) === -1)
                skipped.push(group + "." + name + "." + format);
            return match;
        }
        count++;
        return filters ? '{{ "' + rendered + '" | to_color ' + filters.trim() + " }}" : rendered;
    });
    return { text: out, substituted: count, skipped: skipped };
}

// matugen expands a leading ~ in input_path/output_path itself; a rewritten
// copy is read by this shell first, so the same expansion has to happen here.
function expandHome(path, home) {
    if (path === "~")
        return home;
    return path.indexOf("~/") === 0 ? home + path.substring(1) : path;
}

var _INPUT_RE = /^([ \t]*input_path[ \t]*=[ \t]*)(['"])([^'"\n]*)\2/gm;

function templateInputs(configText) {
    var found = [];
    if (!configText)
        return found;
    configText.replace(_INPUT_RE, function (match, lead, quote, path) {
        found.push(path);
        return match;
    });
    return found;
}

// Repoints each [templates.*] at its rewritten copy, in the order
// templateInputs() returned them. A mapper answering null leaves that entry
// on its original file, which is what an unreadable template gets: matugen
// then fails on it exactly as it would have without the pin.
function rewriteTemplateInputs(configText, mapper) {
    var i = 0;
    return configText.replace(_INPUT_RE, function (match, lead, quote, path) {
        var next = mapper(path, i++);
        return next === null ? match : lead + "'" + next + "'";
    });
}
