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

function visibleChildren(nodes, id, condResults) {
    condResults = condResults || {};
    return directChildren(nodes, id).filter(function (child) {
        if (!isWhenVisible(child, condResults)) return false;
        if (child.kind === "submenu" || child.kind === "link") {
            return visibleChildren(nodes, child.id, condResults).length > 0;
        }
        return true;
    });
}
