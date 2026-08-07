.pragma library

// Builds a matugen `-c` TOML config from the spec-mandated merge order:
// user [config] verbatim, then the shell's own template blocks, then the
// user's [templates.*] section verbatim, then any drop-in fragments.

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

function buildConfig(opts) {
    var parts = [];

    // matugen hard-rejects a config file with no top-level [config] table
    // ("missing field `config`"), so this must always emit one — the user's
    // verbatim section if they have one, otherwise a bare header. A fresh
    // install with no ~/.config/matugen/config.toml must still produce a
    // config matugen will run.
    var userConfig = opts.userConfigText ? extractSection(opts.userConfigText, "config") : "";
    parts.push(userConfig || "[config]");

    parts.push(templateBlock("formalshell",
        opts.shellTemplateDir + "/theme.json.tmpl", opts.stateDir + "/theme.json.tmp"));
    parts.push(templateBlock("formalshell-niri-border",
        opts.shellTemplateDir + "/niri-border.kdl.tmpl", opts.stateDir + "/niri-border.kdl.tmp"));

    // App-facing palettes, written straight to their final config paths: only
    // theme.json/niri-border.kdl need the .tmp + rename dance (the shell
    // watches those); GTK and Qt apps read these at launch, so a direct
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
