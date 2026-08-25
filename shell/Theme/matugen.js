.pragma library

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

// The no-wallpaper twin of hyprland-colors.conf.tmpl. matugen only runs
// against an image, so the fallback palette has to render the same seven
// variables itself: without this a hyprland.conf sourcing that path would
// source a file that never appears until the first wallpaper is set. Keep the
// name list and the header in step with the template.
var HYPRLAND_VARS = ["primary", "primaryForeground", "background", "foreground",
    "border", "destructive", "warning"];

function hyprlandColors(palette) {
    var out = "# Rendered by matugen (ThemeEngine) into ~/.config/hypr/formalshell-colors.conf\n"
        + "# on every wallpaper/mode change; `source` it from hyprland.conf.\n";
    HYPRLAND_VARS.forEach(function (name) {
        out += "$" + name + " = rgb(" + String(palette[name]).replace("#", "") + ")\n";
    });
    return out;
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

    // App-facing palettes, written straight to their final config paths: only
    // theme.json and the Hyprland colours need the .tmp + rename dance (the
    // shell watches one, Hyprland reloads the other on write, so neither can
    // afford a torn read); GTK and Qt apps read these at launch, so a direct
    // matugen write is fine. gtk.css imports formalshell-colors.css; the
    // qt{5,6}ct.conf color_scheme_path points at colors/matugen.conf.
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
