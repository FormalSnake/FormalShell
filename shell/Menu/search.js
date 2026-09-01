.pragma library
.import "model.js" as Model

// Omarchy-style tiered fuzzy scorer for the menu search field. Tiers sit
// 200 points apart (1000/800/600/400/200) so the root bonus (+100) and the
// app demotion (-50) can only reorder rows within a tier, neither can ever
// promote a weaker tier over a stronger one.
//
// The score picks WHICH rows make the cut and which group leads; the group
// picks where a row lands. A raw score order interleaves an app, a
// clipboard entry and a power action row by row, with nothing but the icon
// to say which is which, so the capped list is dealt out by root route
// (Model.searchSectionOf) in the order each route's best hit earned, and
// the launcher draws one heading per block. The top row is still the best
// hit overall, since its group is the first dealt.

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

// The node's own identifier for the alias tier, with any parent's id-prefix
// stripped: a jsonc node's parentId IS its dotted prefix (model.js's
// splitId), but a provider-built node's parentId is just the provider
// route's own id ("apps"), while the id itself can carry dots of its own
// (an app's "apps.org.mozilla.firefox"). Splitting the full id on its last
// dot would cut a provider id in the wrong place and still leave the
// route's own prefix in front of a jsonc id; stripping node.parentId
// instead works for both. A node with no parentId at all falls back to the
// whole id rather than guessing.
function _ownId(node) {
    var id = String(node.id || "");
    var parentId = node.parentId;
    return (parentId && id.indexOf(parentId + ".") === 0) ? id.slice(parentId.length + 1) : id;
}

// Memoised the way providers.js's _emojiName memoises the emoji dataset's
// lowercase name: node.id and node.parentId never change once the tree is
// built, so the slug only needs computing once per node no matter how many
// keystrokes query it.
function _slugId(node) {
    if (node._slugId === undefined) node._slugId = slug(_ownId(node));
    return node._slugId;
}

// `qNorm`/`qSlug` are the query, normalized/slugged once by rank() rather
// than per node: a query is invariant across the whole tree walk, and the
// old per-node recompute was pure waste on a tree with hundreds of nodes.
function score(node, qNorm, qSlug, depth) {
    if (!qNorm) return 0;

    if (node._lcLabel === undefined) node._lcLabel = normalize(node.label);
    var label = node._lcLabel;
    var tier;
    if (label === qNorm) {
        tier = TIER_EXACT;
    } else if (label.indexOf(qNorm) === 0) {
        tier = TIER_STARTS_WITH;
    } else if (label.indexOf(qNorm) >= 0) {
        tier = TIER_CONTAINS;
    } else if ((node.aliases || []).some(function (a) { return normalize(a).indexOf(qNorm) >= 0; }) || _slugId(node).indexOf(qSlug) >= 0) {
        tier = TIER_ALIAS;
    } else if (wordBoundaryMatch(node.title, qNorm)) {
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
// along with its whole subtree). Returns the 40 best matches (score, ties
// broken by shallower depth then declaration order) grouped by root route,
// groups in the order of their best hit, score order inside each.
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
    // Hoisted out of score(): normalize()/slug() cost nothing repeated once
    // per query, but score() used to pay for both on every node it visited.
    var qNorm = normalize(query);
    var qSlug = slug(qNorm);

    function visit(id, depth) {
        var node = nodes[id];
        if (!node) return;
        if (node.when !== undefined && condResults[node.id] !== true) return;

        var idx = declIndex++;
        var s = score(node, qNorm, qSlug, depth);
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

    var groups = {};
    var order = [];
    results.slice(0, MAX_RESULTS).forEach(function (r) {
        var key = Model.searchSectionOf(nodes, r.node);
        if (groups[key] === undefined) {
            groups[key] = [];
            order.push(key);
        }
        groups[key].push(r.node);
    });
    return order.reduce(function (out, key) { return out.concat(groups[key]); }, []);
}
