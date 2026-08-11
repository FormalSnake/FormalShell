.pragma library

// Pure resolver for the drop-in plugin directory
// (~/.config/formalshell/plugins/<id>/manifest.json). Takes one scan payload
// in, returns resolved plugin records out: no Quickshell/Config access, so
// it's testable head-on the same way Bar/layout.js is.
//
// Manifest schema, exactly eight legal keys:
//   apiVersion  number, REQUIRED, must be API_VERSION
//   id          string, REQUIRED, must equal the plugin's directory name and
//               match ID_PATTERN (it is what `bar.layout` writes as
//               "plugin:<id>" and what `panel open plugin:<id>` addresses)
//   kind        string, REQUIRED, one of KINDS
//   entry       string, REQUIRED, a path inside the plugin directory
//   name        string, optional, defaults to id
//   region      string, kind "bar" only, one of REGIONS, default "right"
//   keepLoaded  bool,   kind "panel"/"overlay" only, default false
//   width       string, kind "panel" only, one of WIDTHS, default "default"
//
// `width` is an enum rather than a pixel number because DESIGN.md §1.3 snaps
// every floating card to one of the four popupWidth tokens; a raw literal
// here would be the first non-token width in the shell's card language.
//
// Failure contract, identical to Bar/layout.js's: absent or malformed input
// is never fatal. Each problem pushes ONE warning string and drops the
// smallest unit that fixes it. A manifest that cannot be addressed at all
// (unparsable, missing a required key, wrong apiVersion, id/dirname mismatch,
// unknown kind, escaping entry path) drops the whole plugin; anything else
// drops one key back to its default and keeps the plugin. An absent or empty
// plugins directory is zero plugins and zero warnings, not an error, and an
// id the user listed in settings.json's `plugins.disabled` is skipped
// silently because the user asked for it.
//
// Duplicate ids are structurally unreachable rather than checked: `id` must
// equal the plugin's own directory name, and directory names are unique.
//
// A missing entry FILE is not detectable here (this module never touches the
// filesystem). It surfaces at the host as Loader.status === Loader.Error and
// renders as a PLUGIN ERROR cell.
//
// Nothing watches the plugins directory. A newly dropped plugin appears after
// `qs ipc call plugins reload` or a shell restart, the same rescan-on-demand
// contract ImagePicker and CalendarEventsService already have.

var API_VERSION = 1;
var KINDS = ["bar", "panel", "overlay", "service"];
var REGIONS = ["left", "center", "right"];
var WIDTHS = ["narrow", "default", "wide", "menu"];
var ID_PATTERN = /^[a-z0-9][a-z0-9-]*$/;

// Must stay byte-identical to Bar/layout.js's own PLUGIN_PREFIX: the two
// modules address the same plugin from opposite ends (bar.layout placement
// there, PanelIpc registry keys here) and never import each other.
var PLUGIN_PREFIX = "plugin:";

var REQUIRED_KEYS = ["apiVersion", "id", "kind", "entry"];

// Optional key -> the kinds it means anything for. A key on the wrong kind is
// one warning and the key dropped, never a dropped plugin.
var OPTIONAL_KEYS = {
    name: KINDS,
    region: ["bar"],
    keepLoaded: ["panel", "overlay"],
    width: ["panel"]
};

var RECORD_BOUNDARY = "#--formalshell-plugin-boundary--";

// One `sh` process enumerates the directory AND reads every manifest, the
// same drop-in-directory read ThemeEngine.qml:165-167 performs against
// ~/.config/formalshell/matugen.d (Quickshell has no directory-listing QML
// type; CalendarEventsService.qml:13-15 states that doctrine). Per-plugin
// structure is recovered from RECORD_BOUNDARY rather than from a second
// process per file. A plugins directory that does not exist leaves the glob
// unmatched, `[ -f ]` fails, nothing prints.
var SCAN_SCRIPT = 'for m in "$1"/*/manifest.json; do [ -f "$m" ] && echo "$2" && echo "${m%/manifest.json}" && cat "$m" && echo; done';

// argv for Process.command. The directory only ever arrives as $1, never
// interpolated into the script text.
function scanCommand(pluginsDir) {
    return ["sh", "-c", SCAN_SCRIPT, "sh", pluginsDir, RECORD_BOUNDARY];
}

// Splits one StdioCollector payload into per-plugin records. Each record on
// the wire is RECORD_BOUNDARY \n <dir> \n <manifest bytes>. `id` is derived
// here so nothing downstream re-derives it from a path.
function splitScan(text) {
    var records = [];
    if (typeof text !== "string" || text === "")
        return records;

    var chunks = text.split(RECORD_BOUNDARY);
    for (var i = 1; i < chunks.length; i++) {
        var chunk = chunks[i].replace(/^\n+/, "");
        var nl = chunk.indexOf("\n");
        if (nl < 0)
            continue;
        var dir = chunk.slice(0, nl);
        if (dir === "")
            continue;
        records.push({
            dir: dir,
            id: dir.slice(dir.lastIndexOf("/") + 1),
            text: chunk.slice(nl + 1)
        });
    }
    return records;
}

// "file://" + dir + "/" + entry. The one place a plugin URL is built, so no
// host string-concatenates one.
function entryUrl(plugin) {
    return "file://" + plugin.dir + "/" + plugin.entry;
}

// The name both bar.layout and PanelIpc address a plugin by.
function surfaceKey(plugin) {
    return PLUGIN_PREFIX + plugin.id;
}

// One record in, one plugin (or null) plus its warnings out.
function validateRecord(record) {
    var warnings = [];
    var prefix = "plugins/" + record.id + ": ";

    var m;
    try {
        m = JSON.parse(record.text);
    } catch (e) {
        warnings.push(prefix + "manifest.json is not valid JSON: " + e.message);
        return { plugin: null, warnings: warnings };
    }

    if (!m || typeof m !== "object" || Array.isArray(m)) {
        warnings.push(prefix + "manifest.json must be a JSON object");
        return { plugin: null, warnings: warnings };
    }

    for (var r = 0; r < REQUIRED_KEYS.length; r++) {
        if (m[REQUIRED_KEYS[r]] === undefined) {
            warnings.push(prefix + "manifest is missing required key \"" + REQUIRED_KEYS[r] + "\"");
            return { plugin: null, warnings: warnings };
        }
    }

    if (m.apiVersion !== API_VERSION) {
        warnings.push(prefix + "apiVersion " + m.apiVersion + " is not supported (this shell speaks " + API_VERSION + ")");
        return { plugin: null, warnings: warnings };
    }

    if (m.id !== record.id) {
        warnings.push(prefix + "manifest id \"" + m.id + "\" does not match its directory name");
        return { plugin: null, warnings: warnings };
    }

    if (!ID_PATTERN.test(record.id)) {
        warnings.push(prefix + "id \"" + record.id + "\" must be lowercase letters, digits and dashes");
        return { plugin: null, warnings: warnings };
    }

    var kind = m.kind;
    if (KINDS.indexOf(kind) < 0) {
        warnings.push(prefix + "unknown kind \"" + kind + "\"");
        return { plugin: null, warnings: warnings };
    }

    var entry = m.entry;
    if (typeof entry !== "string" || entry === "" || entry.charAt(0) === "/"
        || ("/" + entry + "/").indexOf("/../") >= 0) {
        warnings.push(prefix + "entry \"" + entry + "\" must be a path inside the plugin directory");
        return { plugin: null, warnings: warnings };
    }

    for (var key in m) {
        if (REQUIRED_KEYS.indexOf(key) >= 0)
            continue;
        var allowed = OPTIONAL_KEYS[key];
        if (!allowed)
            warnings.push(prefix + "unknown manifest key \"" + key + "\"");
        else if (allowed.indexOf(kind) < 0)
            warnings.push(prefix + "\"" + key + "\" is not a valid key for kind \"" + kind + "\"");
    }

    var name = record.id;
    if (m.name !== undefined) {
        if (typeof m.name === "string" && m.name !== "")
            name = m.name;
        else
            warnings.push(prefix + "\"name\" must be a non-empty string, using \"" + record.id + "\"");
    }

    // Keys with no meaning for this kind stay present as null: a consumer
    // reading `plugin.keepLoaded === null` learns "this kind has no such
    // concept", which is not the same answer as false.
    var region = null;
    if (kind === "bar") {
        region = "right";
        if (m.region !== undefined) {
            if (REGIONS.indexOf(m.region) >= 0)
                region = m.region;
            else
                warnings.push(prefix + "unknown region \"" + m.region + "\", using \"right\"");
        }
    }

    var keepLoaded = null;
    if (kind === "panel" || kind === "overlay") {
        keepLoaded = false;
        if (m.keepLoaded !== undefined) {
            if (typeof m.keepLoaded === "boolean")
                keepLoaded = m.keepLoaded;
            else
                warnings.push(prefix + "\"keepLoaded\" must be true or false, using false");
        }
    }

    var width = null;
    if (kind === "panel") {
        width = "default";
        if (m.width !== undefined) {
            if (WIDTHS.indexOf(m.width) >= 0)
                width = m.width;
            else
                warnings.push(prefix + "unknown width \"" + m.width + "\", using \"default\"");
        }
    }

    var plugin = {
        id: record.id,
        kind: kind,
        entry: entry,
        dir: record.dir,
        name: name,
        region: region,
        keepLoaded: keepLoaded,
        width: width
    };
    plugin.entryUrl = entryUrl(plugin);

    return { plugin: plugin, warnings: warnings };
}

// The one function PluginService calls. `disabled` may be undefined or null.
// Plugins come back id-sorted so auto-append order into a bar region is
// deterministic rather than filesystem-order.
function resolve(text, disabled) {
    var skip = Array.isArray(disabled) ? disabled : [];
    var records = splitScan(text);
    var plugins = [];
    var byId = {};
    var warnings = [];

    for (var i = 0; i < records.length; i++) {
        if (skip.indexOf(records[i].id) >= 0)
            continue;
        var result = validateRecord(records[i]);
        for (var w = 0; w < result.warnings.length; w++)
            warnings.push(result.warnings[w]);
        if (result.plugin) {
            plugins.push(result.plugin);
            byId[result.plugin.id] = result.plugin;
        }
    }

    plugins.sort(function (a, b) { return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0); });
    return { plugins: plugins, byId: byId, warnings: warnings };
}

function barPlugins(plugins) {
    return (plugins || []).filter(function (p) { return p.kind === "bar"; });
}

function surfacePlugins(plugins) {
    return (plugins || []).filter(function (p) { return p.kind === "panel" || p.kind === "overlay"; });
}

function servicePlugins(plugins) {
    return (plugins || []).filter(function (p) { return p.kind === "service"; });
}
