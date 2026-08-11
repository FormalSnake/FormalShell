.pragma library

// Live `checked` conditions for the menu's toggle rows. A toggle row's
// checkmark has to flip in the same event-loop turn the toggle itself does,
// so a "@state:" condition is answered from a property snapshot the caller
// hands in and never spawns a Process. Pure and dependency-free so
// qmltestrunner reaches it head-on (tests/tst_menu_toggles.qml), the same
// shape as model.js and frecency.js.
//
// PATHS is a closed allow-list, checked by membership rather than by looking
// the string up in anything: a condition naming a path outside it resolves
// false, so a hand-written ~/.config/formalshell/menu.jsonc has no route into
// the QML engine through this field. A new path has to be added BOTH here and
// to Menu.qml's _stateSnapshot literal; tst_menu_toggles.qml's drift guard
// fails when the two disagree.

var PREFIX = "@state:";

var PATHS = [
    "nightlight.active",     // NightLightService.active
    "screensaver.stayAwake", // IdleService.stayAwake
    "notifications.dnd",     // NotificationService.dnd
    "theme.dark"             // Core.State.mode === "dark"
];

// Mirrors Menu.qml's own "@ipc:" prefix test, minus the assumption that the
// value is a string: `checked` comes straight from user jsonc.
function isStateCondition(cond) {
    return typeof cond === "string" && cond.indexOf(PREFIX) === 0;
}

function statePath(cond) {
    return isStateCondition(cond) ? cond.slice(PREFIX.length) : null;
}

function isKnownPath(path) {
    return PATHS.indexOf(path) >= 0;
}

// A NEW object every call, carrying exactly PATHS as keys. QML's var-property
// change detection compares references, so a snapshot mutated in place would
// repaint nothing; and normalizing here is what keeps the allow-list and the
// caller's snapshot literal from drifting on value shape (a missing key reads
// false, an unlisted key is dropped, only a strict `true` counts).
function snapshot(live) {
    var source = live || {};
    var out = {};
    for (var i = 0; i < PATHS.length; i++)
        out[PATHS[i]] = source[PATHS[i]] === true;
    return out;
}

// The keys snapshot() would silently drop. Only the drift guard in
// tst_menu_toggles.qml calls this.
function unknownKeys(live) {
    var out = [];
    Object.keys(live || {}).forEach(function (k) {
        if (!isKnownPath(k)) out.push(k);
    });
    return out;
}

// Tri-state by contract. `undefined` means "not a @state: condition at all",
// which is what leaves a plain shell-command `checked` field resolving from
// the caller's Process cache exactly as it did before. A path outside the
// allow-list answers false rather than undefined, so a typo renders an off
// checkmark instead of falling through to a cache that can never hold it.
function resolveState(cond, snap) {
    if (!isStateCondition(cond)) return undefined;
    var path = statePath(cond);
    if (!isKnownPath(path)) return false;
    return (snap || {})[path] === true;
}

// The single decision the row delegate makes: live state wins outright, so a
// stale cached Process result can never paint over the current one.
function checkedFor(node, snap, condResults) {
    if (!node || node.checked === undefined) return false;
    var live = resolveState(node.checked, snap);
    if (live !== undefined) return live;
    return (condResults || {})[node.id] === true;
}

// Fresh object for the same reason snapshot() builds one.
function withResult(source, id, ok) {
    var out = {};
    for (var k in source) out[k] = source[k];
    out[id] = ok;
    return out;
}
