.pragma library

// Pure resolver for `bar.layout`/`bar.modules` (DESIGN.md §Bar, spec
// §Surfaces-1, M10 Task 3). Takes the raw settings.json `bar` object in,
// returns a resolved { regions: {left, center, right}, warnings } out — no
// Quickshell/Config access, so it's testable head-on. Each resolved entry
// is either { kind: "builtin", name } (one of BUILTIN_WIDGETS, rendered by
// Bar.qml's own component registry) or { kind: "module", id, module }
// (module is the matching entry from `bar.modules`, looked up by id via
// the layout name's "custom:" prefix — distinct from BUILTIN_WIDGETS so a
// user's module id can never collide with a built-in widget name). Absent
// or malformed input is never fatal: an unknown widget name, a "custom:"
// reference with no matching module, or a module with an unrecognized
// `type` is dropped with one warning string rather than thrown — a typo in
// settings.json must never crash the bar. A region missing from
// `bar.layout` falls back to DEFAULT_LAYOUT for that region alone (today's
// exact arrangement); a region present but empty (`[]`) stays empty.

// Drop-in plugins (shell/Plugins/manifest.js) are placed by the same
// mechanism under their own disjoint prefix: a `plugin:<id>` name resolves
// to { kind: "plugin", id, plugin } against the resolved-manifest array
// PluginService.barPlugins hands in, rendered by PluginBarModule.qml. A bar
// plugin whose id appears in NO region is appended to the region its own
// manifest asks for, id-sorted, so dropping a plugin directory in is enough
// to see its cell; an explicit bar.layout placement always wins, and a
// plugin named anywhere is never appended twice.

// "github", "usage", "tailscale", "visualizer", "microphone",
// "keyboardLayout" and "systemUpdate" are deliberately absent from
// DEFAULT_LAYOUT below: all seven are opt-in builtins (M12 Task 8, M14
// Task 7, M16 Task 8, the ASCII visualizer's own owner-ask task, and the
// cheap-wins trio), so the no-config bar stays byte-identical.
var BUILTIN_WIDGETS = ["workspaces", "activeWindow", "clock", "nowPlaying", "battery", "audio", "network", "bluetooth", "weather", "tray", "github", "usage", "tailscale", "visualizer", "bell", "indicators", "microphone", "keyboardLayout", "systemUpdate"];

var MODULE_TYPES = ["command", "qml"];

var DEFAULT_LAYOUT = {
    left: ["workspaces", "activeWindow"],
    center: ["clock", "nowPlaying"],
    // "bell" joined the defaults in M13b Task 2 (owner-requested): the
    // notification bell is always-visible, so unlike "github" it earns a
    // default slot rather than opt-in status.
    right: ["battery", "audio", "network", "bluetooth", "weather", "tray", "bell", "indicators"]
};

var REGIONS = ["left", "center", "right"];

var CUSTOM_PREFIX = "custom:";

// Must stay byte-identical to shell/Plugins/manifest.js's own PLUGIN_PREFIX:
// the two pure modules address the same plugin from opposite ends (bar
// placement here, PanelIpc registry keys there) and never import each other.
var PLUGIN_PREFIX = "plugin:";

function _moduleById(modules) {
    var byId = {};
    for (var i = 0; i < modules.length; i++) {
        var mod = modules[i];
        if (mod && typeof mod.id === "string" && mod.id !== "")
            byId[mod.id] = mod;
    }
    return byId;
}

// manifest.js already guarantees a resolved plugin has a non-empty unique id
// (it must equal its own directory name), so this needs none of _moduleById's
// shape guards.
function _pluginById(plugins) {
    var byId = {};
    for (var i = 0; i < plugins.length; i++)
        byId[plugins[i].id] = plugins[i];
    return byId;
}

function _isPlaced(entries, id) {
    for (var i = 0; i < entries.length; i++)
        if (entries[i].kind === "plugin" && entries[i].id === id)
            return true;
    return false;
}

function _resolveRegion(names, region, moduleById, pluginById, warnings) {
    var resolved = [];
    for (var i = 0; i < names.length; i++) {
        var name = names[i];
        if (typeof name === "string" && name.indexOf(PLUGIN_PREFIX) === 0) {
            var pluginId = name.slice(PLUGIN_PREFIX.length);
            var plugin = pluginById[pluginId];
            if (!plugin) {
                warnings.push("bar.layout." + region + ": unknown bar plugin \"" + pluginId + "\"");
            } else {
                resolved.push({ kind: "plugin", id: pluginId, plugin: plugin });
            }
        } else if (typeof name === "string" && name.indexOf(CUSTOM_PREFIX) === 0) {
            var id = name.slice(CUSTOM_PREFIX.length);
            var mod = moduleById[id];
            if (!mod) {
                warnings.push("bar.layout." + region + ": unknown module \"" + id + "\"");
            } else if (MODULE_TYPES.indexOf(mod.type) < 0) {
                warnings.push("bar.layout." + region + ": module \"" + id + "\" has unknown type \"" + mod.type + "\"");
            } else {
                resolved.push({ kind: "module", id: id, module: mod });
            }
        } else if (BUILTIN_WIDGETS.indexOf(name) >= 0) {
            resolved.push({ kind: "builtin", name: name });
        } else {
            warnings.push("bar.layout." + region + ": unknown widget \"" + name + "\"");
        }
    }
    return resolved;
}

// `bar` is the raw settings.json `bar` object — may be undefined, null, or
// missing either `layout` or `modules`. `barPlugins` is manifest.js's
// kind === "bar" array, already id-sorted; undefined or null means none, so
// every pre-plugin caller keeps its exact previous result.
function resolve(bar, barPlugins) {
    var layout = (bar && bar.layout && typeof bar.layout === "object") ? bar.layout : {};
    var modules = (bar && Array.isArray(bar.modules)) ? bar.modules : [];
    var moduleById = _moduleById(modules);
    var plugins = Array.isArray(barPlugins) ? barPlugins : [];
    var pluginById = _pluginById(plugins);

    var regions = {};
    var warnings = [];
    var i;
    var region;

    for (i = 0; i < REGIONS.length; i++) {
        region = REGIONS[i];
        var names = Array.isArray(layout[region]) ? layout[region] : DEFAULT_LAYOUT[region];
        regions[region] = _resolveRegion(names, region, moduleById, pluginById, warnings);
    }

    // Auto-append: a bar plugin the user never named anywhere lands in the
    // region its own manifest asks for, so installing a plugin is a directory
    // drop rather than a directory drop plus a settings.json edit. Explicit
    // placement above always wins.
    for (i = 0; i < plugins.length; i++) {
        var plugin = plugins[i];
        var placed = false;
        for (var r = 0; r < REGIONS.length && !placed; r++)
            placed = _isPlaced(regions[REGIONS[r]], plugin.id);
        if (!placed)
            regions[plugin.region].push({ kind: "plugin", id: plugin.id, plugin: plugin });
    }

    return { regions: regions, warnings: warnings };
}
