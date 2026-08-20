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
    // An explicit `kind` wins outright — the one escape hatch for a kind
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

function isWhenVisible(node, condResults) {
    if (node.when === undefined) return true;
    return condResults[node.id] === true;
}

// Honest placeholder for a level whose own `when` gate isn't satisfied (M17
// review finding, M-polish batch item F): summoning a route directly
// (Menu.qml's `open(route)` -> `_resolveRoute`/`_enterLevel`) bypasses the
// parent-level `isWhenVisible()` filter that would otherwise have kept a
// gated node off screen entirely — `menu summon share` without
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
// memo — two branches may legitimately share a target) so a link cycle
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
