.pragma library

// Pure JSONC parse + tree model for the unified menu. `buildTree` turns two
// flat dotted-id objects (shipped default, user override) into a hierarchy:
// dots imply parent/child ("system.power.reboot" nests under an
// auto-created "system.power" under "system"), a user entry's fields
// override the matching default entry's fields per-key, and
// `hidden: true` drops that id and its whole subtree.

function parseJsonc(text) {
    var out = "";
    var inString = false;
    var i = 0;
    var len = text.length;
    while (i < len) {
        var c = text[i];
        if (inString) {
            out += c;
            if (c === "\\" && i + 1 < len) {
                out += text[i + 1];
                i += 2;
                continue;
            }
            if (c === "\"") inString = false;
            i++;
            continue;
        }
        if (c === "\"") {
            inString = true;
            out += c;
            i++;
            continue;
        }
        if (c === "/" && text[i + 1] === "/") {
            while (i < len && text[i] !== "\n") i++;
            continue;
        }
        if (c === ",") {
            var j = i + 1;
            while (j < len) {
                var wc = text[j];
                if (wc === " " || wc === "\t" || wc === "\n" || wc === "\r") { j++; continue; }
                if (wc === "/" && text[j + 1] === "/") {
                    while (j < len && text[j] !== "\n") j++;
                    continue;
                }
                break;
            }
            if (j < len && (text[j] === "}" || text[j] === "]")) {
                i++;
                continue;
            }
        }
        out += c;
        i++;
    }
    return JSON.parse(out);
}

function splitId(id) {
    var dot = id.lastIndexOf(".");
    return dot < 0
        ? { parentId: null, segment: id }
        : { parentId: id.substring(0, dot), segment: id.substring(dot + 1) };
}

function titleCase(segment) {
    return segment.length ? segment.charAt(0).toUpperCase() + segment.slice(1) : segment;
}

function inferKind(entry) {
    // An explicit `kind` wins outright, the one escape hatch for a kind
    // the other four fields can't express, e.g. "note" (nix's own
    // non-activatable NO NIX/SEARCHING rows): those are hand-built Node
    // fragments from a provider fn today, bypassing buildTree entirely, but
    // a dynamically-injected root entry (providers.js's captureEntries()
    // pattern) still goes through here and has no other way to ask for it.
    if (entry.kind !== undefined) return entry.kind;
    if (entry.action !== undefined) return "action";
    if (entry.target !== undefined) return "link";
    if (entry.provider !== undefined) return "provider";
    return "submenu";
}

function mergeEntry(defEntry, userEntry) {
    var merged = {};
    Object.keys(defEntry || {}).forEach(function (k) { merged[k] = defEntry[k]; });
    Object.keys(userEntry || {}).forEach(function (k) { merged[k] = userEntry[k]; });
    return merged;
}

function buildTree(defaultObj, userObj) {
    defaultObj = defaultObj || {};
    userObj = userObj || {};

    var declaredIds = Object.keys(defaultObj);
    Object.keys(userObj).forEach(function (id) {
        if (declaredIds.indexOf(id) < 0) declaredIds.push(id);
    });

    var hiddenIds = {};
    declaredIds.forEach(function (id) {
        var u = userObj[id];
        if (u && u.hidden === true) hiddenIds[id] = true;
    });

    function underHiddenAncestor(id) {
        var parts = id.split(".");
        var prefix = "";
        for (var p = 0; p < parts.length; p++) {
            prefix = prefix ? prefix + "." + parts[p] : parts[p];
            if (hiddenIds[prefix]) return true;
        }
        return false;
    }

    var allIds = [];
    var seen = {};
    function addWithAncestors(id) {
        var parts = id.split(".");
        var prefix = "";
        for (var p = 0; p < parts.length; p++) {
            prefix = prefix ? prefix + "." + parts[p] : parts[p];
            if (hiddenIds[prefix]) return;
            if (!seen[prefix]) { seen[prefix] = true; allIds.push(prefix); }
        }
    }
    declaredIds.forEach(function (id) {
        if (!underHiddenAncestor(id)) addWithAncestors(id);
    });

    var nodes = {};
    allIds.forEach(function (id) {
        var split = splitId(id);
        var entry = mergeEntry(defaultObj[id], userObj[id]);
        var node = {
            id: id,
            parentId: split.parentId,
            label: entry.label !== undefined ? entry.label : titleCase(split.segment),
            icon: entry.icon !== undefined ? entry.icon : "",
            title: entry.title !== undefined ? entry.title : "",
            aliases: entry.aliases !== undefined ? entry.aliases : [],
            kind: inferKind(entry),
            childIds: []
        };
        if (entry.action !== undefined) node.action = entry.action;
        if (entry.target !== undefined) node.target = entry.target;
        if (entry.provider !== undefined) node.provider = entry.provider;
        if (entry.when !== undefined) node.when = entry.when;
        if (entry.checked !== undefined) node.checked = entry.checked;
        if (entry.confirm !== undefined) node.confirm = entry.confirm;
        if (entry.dim !== undefined) node.dim = entry.dim;
        if (entry.keepOpen !== undefined) node.keepOpen = entry.keepOpen;
        if (entry.routeOnly !== undefined) node.routeOnly = entry.routeOnly;
        if (entry.section !== undefined) node.section = entry.section;
        if (entry.prompt !== undefined) node.prompt = entry.prompt;
        nodes[id] = node;
    });

    var rootIds = [];
    allIds.forEach(function (id) {
        var node = nodes[id];
        if (node.parentId === null || !nodes[node.parentId]) {
            rootIds.push(id);
        } else {
            nodes[node.parentId].childIds.push(id);
        }
    });

    return { rootIds: rootIds, nodes: nodes };
}

// The heading a level's rows fall back to when nothing declares one. The
// root's own rows are the shell's commands; a level's rows are named by the
// level itself.
var ROOT_SECTION = "Commands";

// One heading per row, index-aligned with `rows` (M48 D6). The launcher
// draws a `SectionLabel` wherever this array CHANGES value, so a heading
// costs nothing when the whole list belongs to one group, and no row is
// ever reordered to fit a group: a section that is not contiguous in the
// rows it was handed simply gets its heading twice, which is the honest
// picture of a list ordered by something other than its sections.
//
// `ctx` is { mode, grid, searching, level, levelLabel, nodes }: the two
// dmenu modes name themselves, a grid has nowhere to draw a full-width band
// between two cells of a row so it has no headings at all, a query that
// ranks the whole tree names each row after the root route it came from
// (searchSectionOf, the same key search.js's rank groups by, so the
// headings come out one block each), and everything else is either the
// row's declared `section` key, the frecency head of a provider that marks
// one (`recent`), or the level.
// Index-aligned with the rows it was given, EXCEPT for a grid, which gets an
// empty array: _sectionOf answers "" for every row of one (a grid has
// nowhere to put a full-width band between two cells), and the row delegate
// that reads this by index is not the one a grid renders, so there is
// nothing to stay aligned with. Worth the exception because the emoji grid
// browses 3944 rows and rebuilds this on every keystroke.
function sectionsFor(rows, ctx) {
    rows = rows || [];
    ctx = ctx || {};
    if (ctx.grid === true)
        return [];
    var out = [];
    for (var i = 0; i < rows.length; i++)
        out.push(_sectionOf(rows[i], ctx));
    return _collapseSingleLevelGroup(out, ctx);
}

// A level whose rows are all one group is already named, by the breadcrumb
// chip directly above them: "Clipboard" followed by a CLIPBOARD heading says
// the word twice and separates nothing. A level that does split (the apps
// route's Recent) keeps every heading, because there the names are what tell
// the two runs apart.
function _collapseSingleLevelGroup(sections, ctx) {
    if (ctx.level === null || ctx.level === undefined || ctx.searching === true)
        return sections;
    if (ctx.mode !== undefined && ctx.mode !== "menu")
        return sections;
    for (var i = 0; i < sections.length; i++) {
        if (sections[i] !== "" && sections[i] !== ctx.levelLabel)
            return sections;
    }
    return sections.map(function () { return ""; });
}

function _sectionOf(row, ctx) {
    if (ctx.mode === "select") return "Options";
    if (ctx.mode === "input") return "";
    if (ctx.grid === true) return "";
    if (ctx.searching === true) return searchSectionOf(ctx.nodes, row);
    if (row && row.recent === true) return "Recent";
    if (row && row.section) return row.section;
    if (ctx.level === null || ctx.level === undefined) return ROOT_SECTION;
    return ctx.levelLabel || "";
}

// The heading a whole-tree search result sits under: the label of the root
// route it descends from (an app under Apps, a clipboard entry under
// Clipboard, a power action under System), or the root's own heading for a
// route row itself. A ranked list mixes every kind the tree holds, and the
// route is what says what a row IS when the icon alone does not; a row's own
// declared `section` is a browsing group (the root's Suggestions) and would
// cut the list into a heading per row, so it is not consulted here. Walked
// by `parentId` rather than the dotted id, since an app's own id can carry
// dots of its own.
function searchSectionOf(nodes, row) {
    nodes = nodes || {};
    var node = row;
    while (node && node.parentId !== null && node.parentId !== undefined) {
        var parent = nodes[node.parentId];
        if (!parent) break;
        node = parent;
    }
    return node === row ? ROOT_SECTION : node.label;
}

// The distinct headings of a `sectionsFor` result, in the order they first
// appear. `menu status` reports this, since a heading is otherwise only
// observable by reading pixels off a screenshot.
function sectionNames(sections) {
    var out = [];
    for (var i = 0; i < (sections || []).length; i++) {
        var s = sections[i];
        if (s !== "" && out.indexOf(s) < 0) out.push(s);
    }
    return out;
}

// What the empty search field says a level is for: the level's own `prompt`
// key, or its label. The root has no node and reads the command palette's
// own line instead (Menu.qml).
function promptFor(node) {
    if (!node) return "";
    if (node.prompt) return node.prompt;
    return "Search " + node.label;
}

function isWhenVisible(node, condResults) {
    if (node.when === undefined) return true;
    return condResults[node.id] === true;
}

// Honest placeholder for a level whose own `when` gate isn't satisfied (M17
// review finding, M-polish batch item F): summoning a route directly
// (Menu.qml's `open(route)` -> `_resolveRoute`/`_enterLevel`) bypasses the
// parent-level `isWhenVisible()` filter that would otherwise have kept a
// gated node off screen entirely, `menu summon share` without
// localsend_app used to render SHARE's actionable children anyway, each
// one silently exiting 127 on activation. Never activatable ("note" kind,
// `dim: true`), the same honest-unavailable shape every other absent state
// in this tree already uses (nix's NO NIX, share's own NOTHING TO SHARE).
function gatedNoteRow(node) {
    return {
        id: node.id + ".unavailable",
        parentId: node.id,
        label: "UNAVAILABLE",
        icon: "",
        title: "",
        aliases: [],
        kind: "note",
        dim: true,
        childIds: []
    };
}

// A link's own subtree is empty by construction (it points elsewhere), so
// pruning must follow the target's children rather than the link node's.
function directChildren(nodes, id) {
    if (id === null || id === undefined) {
        return Object.keys(nodes)
            .filter(function (k) { return nodes[k].parentId === null; })
            .map(function (k) { return nodes[k]; });
    }
    var node = nodes[id];
    if (!node) return [];
    var childIds = (node.kind === "link" && node.target && nodes[node.target])
        ? nodes[node.target].childIds
        : node.childIds;
    return childIds.map(function (cid) { return nodes[cid]; }).filter(Boolean);
}

// `_ancestry` tracks ids on the current recursion path (not a global
// memo, two branches may legitimately share a target) so a link cycle
// (a -> b -> a) bottoms out as "no visible children" instead of recursing
// forever. Each call gets its own copy: siblings must not see each
// other's marks, only actual ancestors matter.
function visibleChildren(nodes, id, condResults, _ancestry) {
    condResults = condResults || {};
    var ancestry = {};
    for (var k in _ancestry) ancestry[k] = true;
    if (id !== null && id !== undefined) {
        if (ancestry[id]) return [];
        ancestry[id] = true;
    }
    return directChildren(nodes, id).filter(function (child) {
        if (!isWhenVisible(child, condResults)) return false;
        if (child.kind === "submenu" || child.kind === "link") {
            return visibleChildren(nodes, child.id, condResults, ancestry).length > 0;
        }
        return true;
    });
}
