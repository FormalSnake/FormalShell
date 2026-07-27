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

    if (opts.userConfigText) {
        var userConfig = extractSection(opts.userConfigText, "config");
        if (userConfig) parts.push(userConfig);
    }

    parts.push(templateBlock("formalshell",
        opts.shellTemplateDir + "/theme.json.tmpl", opts.stateDir + "/theme.json.tmp"));
    parts.push(templateBlock("formalshell-niri-border",
        opts.shellTemplateDir + "/niri-border.kdl.tmpl", opts.stateDir + "/niri-border.kdl.tmp"));

    if (opts.userConfigText) {
        var userTemplates = extractSection(opts.userConfigText, "templates");
        if (userTemplates) parts.push(userTemplates);
    }

    (opts.dropInTexts || []).forEach(function (text) {
        if (text) parts.push(text);
    });

    return parts.join("\n");
}
