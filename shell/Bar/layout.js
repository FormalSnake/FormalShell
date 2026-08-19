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

// "chevron" (M24) is placed like any other builtin, and its POSITION is its
// entire configuration: every entry on its governed side of the same region
// is annotated `collapsible: true`, which is what Bar.qml's region delegate
// gates on. Which side that is depends on the region (governsBefore() below),
// so the group always opens away from the region's anchored edge.
// Two rules keep the chevron from being a control that does nothing, both
// enforced here rather than in the widget: only the first chevron in a region
// survives, and a chevron with nothing on its governed side is dropped
// outright. Each drop carries its own warning string, same as an unknown
// widget name.
//
// Drop-in plugins (shell/Plugins/manifest.js) are placed by the same
// mechanism under their own disjoint prefix: a `plugin:<id>` name resolves
// to { kind: "plugin", id, plugin } against the resolved-manifest array
// PluginService.barPlugins hands in, rendered by PluginBarModule.qml. A bar
// plugin whose id appears in NO region is appended to the region its own
// manifest asks for, id-sorted, so dropping a plugin directory in is enough
// to see its cell; an explicit bar.layout placement always wins, and a
// plugin named anywhere is never appended twice.

// "github", "usage", "tailscale", "visualizer", "microphone",
// "keyboardLayout", "systemUpdate", "chevron", "airpods", "dualsense",
// "display" and "monitor" are deliberately absent from DEFAULT_LAYOUT below:
// all twelve are opt-in builtins (M12 Task 8, M14 Task 7, M16 Task 8, the
// ASCII visualizer's own owner-ask task, the cheap-wins trio, M24's collapse
// boundary, M29 Tasks 3+4's AirPods/DualSense cells, M36's display cell
// (the display panel long predates having a cell at all), and M38 Task 6's
// system monitor: a monitor cell in the bar is optional per install, since
// the launcher's "monitor" route (Menu/appviews.js) is the always-available
// path to the same data), so the no-config bar stays byte-identical.
var BUILTIN_WIDGETS = ["workspaces", "activeWindow", "clock", "nowPlaying", "battery", "audio", "network", "bluetooth", "weather", "tray", "github", "usage", "tailscale", "visualizer", "bell", "indicators", "microphone", "keyboardLayout", "systemUpdate", "chevron", "airpods", "dualsense", "display", "monitor"];

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

function _isChevron(entry) {
    return entry.kind === "builtin" && entry.name === "chevron";
}

// Which side of a region's chevron collapses behind it (M25). A region pinned
// to a screen edge governs inward, away from that edge: the right region is
// anchored right, so its chevron governs the entries BEFORE it and the cells
// between it and the edge, the chevron itself included, keep their x when the
// group opens. `center` is anchored to nothing and reflows from both ends
// whichever side it governs, so it stays on the left region's "after"
// direction rather than paying for a mirror that buys it nothing.
function governsBefore(region) {
    return region === "right";
}

// Two passes, in this order, because the second depends on what the first
// leaves behind: a left region's ["clock", "chevron", "chevron"] loses its
// trailing chevron as a duplicate, which makes the surviving one trailing in
// turn, and a chevron that collapses nothing is exactly the dead control the
// rule exists to prevent. The right region's mirror of that case is
// ["chevron", "chevron", "clock"], where the survivor ends up first with
// nothing before it. Both passes warn per drop.
function _dropDeadChevrons(entries, region, warnings) {
    var deduped = [];
    var seen = false;
    var i;
    for (i = 0; i < entries.length; i++) {
        if (_isChevron(entries[i])) {
            if (seen) {
                warnings.push("bar.layout." + region + ": only one chevron per region");
                continue;
            }
            seen = true;
        }
        deduped.push(entries[i]);
    }
    var before = governsBefore(region);
    var edge = before ? 0 : deduped.length - 1;
    if (deduped.length > 0 && _isChevron(deduped[edge])) {
        warnings.push("bar.layout." + region + ": chevron has nothing " + (before ? "before" : "after") + " it");
        deduped.splice(edge, 1);
    }
    return deduped;
}

// `region` is carried on the entry so a consumer holding one entry (Bar.qml's
// region delegate gets exactly that, via `modelData`) can name the region
// whose collapse state it answers to, without the delegate having to know
// which Repeater it was instantiated from.
function _annotate(entries, region) {
    var before = governsBefore(region);
    var chevronAt = -1;
    var i;
    for (i = 0; i < entries.length && chevronAt < 0; i++) {
        if (_isChevron(entries[i]))
            chevronAt = i;
    }
    for (i = 0; i < entries.length; i++) {
        entries[i].region = region;
        entries[i].collapsible = chevronAt >= 0 && (before ? i < chevronAt : i > chevronAt);
    }
}

// How an entry is written in bar.layout, which is the only name a user ever
// typed for it and therefore the only one `bar chevron status` or a tooltip
// can honestly report back.
function entryName(entry) {
    switch (entry.kind) {
    case "builtin": return entry.name;
    case "module": return CUSTOM_PREFIX + entry.id;
    }
    return PLUGIN_PREFIX + entry.id;
}

// The names a region's chevron governs, in layout order. Empty for a region
// with no chevron; never empty for a region that has one, since a chevron
// with nothing on its governed side was already dropped above.
function collapsedNames(entries) {
    var out = [];
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].collapsible)
            out.push(entryName(entries[i]));
    }
    return out;
}

function hasChevron(entries) {
    for (var i = 0; i < entries.length; i++) {
        if (_isChevron(entries[i]))
            return true;
    }
    return false;
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

    // After the auto-append, never inside _resolveRegion: an unnamed plugin
    // lands past everything bar.layout listed, so a left or center chevron
    // the user wrote last is only genuinely last once that pass has run. A
    // right region's chevron governs the other way and no append can land
    // before it, so the ordering only ever decides the other two.
    for (i = 0; i < REGIONS.length; i++) {
        region = REGIONS[i];
        regions[region] = _dropDeadChevrons(regions[region], region, warnings);
        _annotate(regions[region], region);
    }

    return { regions: regions, warnings: warnings };
}
