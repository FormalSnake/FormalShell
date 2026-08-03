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

// "github", "usage", and "tailscale" are deliberately absent from
// DEFAULT_LAYOUT below: all three are opt-in builtins (M12 Task 8, M14 Task
// 7, M16 Task 8), so the no-config bar stays byte-identical.
var BUILTIN_WIDGETS = ["workspaces", "activeWindow", "clock", "nowPlaying", "battery", "audio", "network", "bluetooth", "weather", "tray", "github", "usage", "tailscale", "bell", "indicators"];

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

function _moduleById(modules) {
    var byId = {};
    for (var i = 0; i < modules.length; i++) {
        var mod = modules[i];
        if (mod && typeof mod.id === "string" && mod.id !== "")
            byId[mod.id] = mod;
    }
    return byId;
}

function _resolveRegion(names, region, moduleById, warnings) {
    var resolved = [];
    for (var i = 0; i < names.length; i++) {
        var name = names[i];
        if (typeof name === "string" && name.indexOf(CUSTOM_PREFIX) === 0) {
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
// missing either `layout` or `modules`.
function resolve(bar) {
    var layout = (bar && bar.layout && typeof bar.layout === "object") ? bar.layout : {};
    var modules = (bar && Array.isArray(bar.modules)) ? bar.modules : [];
    var moduleById = _moduleById(modules);

    var regions = {};
    var warnings = [];

    for (var i = 0; i < REGIONS.length; i++) {
        var region = REGIONS[i];
        var names = Array.isArray(layout[region]) ? layout[region] : DEFAULT_LAYOUT[region];
        regions[region] = _resolveRegion(names, region, moduleById, warnings);
    }

    return { regions: regions, warnings: warnings };
}
