.pragma library

// Omarchy-style tiered fuzzy scorer for the menu search field. Tiers sit
// 200 points apart (1000/800/600/400/200) so the root bonus (+100) and the
// app demotion (-50) can only reorder rows within a tier, neither can ever
// promote a weaker tier over a stronger one.

var TIER_EXACT = 1000;
var TIER_STARTS_WITH = 800;
var TIER_CONTAINS = 600;
var TIER_ALIAS = 400;
var TIER_TITLE = 200;
var ROOT_BONUS = 100;
var APP_DEMOTION = 50;
var MAX_RESULTS = 40;

function normalize(text) {
    return String(text || "").toLowerCase();
}

function slug(text) {
    return normalize(text).replace(/[^a-z0-9]+/g, "");
}

// True if any whitespace/punctuation-delimited word in `text` starts with
// `needle`, e.g. "here" matches "Open your files here" but "iles" does not.
function wordBoundaryMatch(text, needle) {
    var words = normalize(text).split(/[^a-z0-9]+/).filter(Boolean);
    for (var i = 0; i < words.length; i++) {
        if (words[i].indexOf(needle) === 0) return true;
    }
    return false;
}

function score(node, query, depth, declIndex) {
    var q = normalize(query);
    if (!q) return 0;

    var label = normalize(node.label);
    var tier;
    if (label === q) {
        tier = TIER_EXACT;
    } else if (label.indexOf(q) === 0) {
        tier = TIER_STARTS_WITH;
    } else if (label.indexOf(q) >= 0) {
        tier = TIER_CONTAINS;
    } else if ((node.aliases || []).some(function (a) { return normalize(a).indexOf(q) >= 0; }) || slug(node.id).indexOf(slug(q)) >= 0) {
        tier = TIER_ALIAS;
    } else if (wordBoundaryMatch(node.title, q)) {
        tier = TIER_TITLE;
    } else {
        return 0;
    }

    if (depth === 0) tier += ROOT_BONUS;
    if (node.kind === "app") tier -= APP_DEMOTION;
    return tier;
}

// The id itself plus every dotted prefix of it, as a lookup set. Ids are
// dotted paths (model.js's splitId derives parentage from exactly this), so
// no node lookup is needed to answer "is this level at or above `id`".
function _ancestry(id) {
    var out = {};
    var parts = String(id || "").split(".");
    var prefix = "";
    for (var i = 0; i < parts.length; i++) {
        if (parts[i] === "") continue;
        prefix = prefix ? prefix + "." + parts[i] : parts[i];
        out[prefix] = true;
    }
    return out;
}

// Depth-first walk of `nodes` from its roots, scoring every when-visible
// node against `query` (a node whose `when` isn't satisfied is skipped
// along with its whole subtree). Returns matches sorted by score, ties
// broken by shallower depth then declaration order, capped at 40.
//
// `withinId` is the level the search is being run from (Menu.qml's
// currentNodeId, null at root). It only matters for a `routeOnly` node: its
// children are reachable from a query typed while standing inside it, and
// invisible from anywhere else. That flag exists because a provider can
// legitimately mirror rows another provider already lists (the tray names
// its items after the applications they belong to), and a root search that
// walks both returns the same app twice. The route row itself still scores,
// so "tray" reaches the route from anywhere; what it no longer does is
// double every app in a search for one.
function rank(nodes, query, condResults, withinId) {
    condResults = condResults || {};
    var declIndex = 0;
    var results = [];
    var open = _ancestry(withinId);

    function visit(id, depth) {
        var node = nodes[id];
        if (!node) return;
        if (node.when !== undefined && condResults[node.id] !== true) return;

        var idx = declIndex++;
        var s = score(node, query, depth, idx);
        if (s > 0) results.push({ node: node, score: s, depth: depth, declIndex: idx });

        if (node.routeOnly === true && open[id] !== true) return;
        node.childIds.forEach(function (cid) { visit(cid, depth + 1); });
    }

    Object.keys(nodes)
        .filter(function (id) { return nodes[id].parentId === null; })
        .forEach(function (id) { visit(id, 0); });

    results.sort(function (a, b) {
        if (b.score !== a.score) return b.score - a.score;
        if (a.depth !== b.depth) return a.depth - b.depth;
        return a.declIndex - b.declIndex;
    });

    return results.slice(0, MAX_RESULTS).map(function (r) { return r.node; });
}
