.pragma library

// Pure bucket resolver for the bar's SNI tray (DESIGN.md §Bar, M23 Task 3).
// Takes the live item ids plus the two override arrays in, returns the
// { visible, drawer, hidden } split Tray.qml renders out. No Quickshell,
// Config or State access, so it's testable head-on like Bar/layout.js.
//
// The buckets are macOS Bartender's, by way of omarchy's own tray
// (shell/plugins/bar/widgets/Tray.qml:155-160), with one deliberate
// divergence: upstream defaults every unlisted item to the drawer, while
// here the fallback stays FormalShell's existing "first N are visible"
// ordering and `pinned`/`hidden` are overrides layered on top of it. With
// both arrays empty, buckets() reproduces the _pinnedCount/_overflowCount
// arithmetic Tray.qml carried before this module existed, entry for entry.
// That equivalence is this module's acceptance criterion, and
// tests/tst_tray_model.qml asserts it directly. An install that never opens
// the manage popup therefore cannot see its tray change.
//
// Ids are SNI application ids: opaque strings, compared only for equality,
// never parsed and never ordered. Two instances of the same application
// publish the same id and so share a bucket. Upstream has the same
// limitation, and the alternative (a synthetic per-object identity) would
// not survive the item list being rebuilt, which Quickshell does far more
// often than the item set actually changes.

// Everything a hand-edited settings.json can put in `bar.tray.pinned` that
// is not an id: a non-array becomes empty, non-string entries are dropped.
// A typo there costs the user their override, never the tray itself.
function _ids(list) {
    if (!Array.isArray(list))
        return [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        if (typeof list[i] === "string" && list[i] !== "")
            out.push(list[i]);
    }
    return out;
}

// Which bucket an id is ASSIGNED to, which is not the same question as where
// buckets() below decides to render it. "drawer" is the default for an
// unlisted id (omarchy's own name for the same bucket), so an item that is
// neither pinned nor hidden reads as "drawer" here while still rendering on
// the bar whenever the fallback ordering has room for it. The manage popup
// reads this to label its own actions.
//
// `hidden` wins for an id that somehow appears in both arrays: rule 1 of
// buckets() drops hidden ids before anything else gets a say, so answering
// "pinned" here would describe a cell that is never drawn. TrayService keeps
// the two mutually exclusive on every write it makes; a hand-written
// settings.json is the only way to reach the overlap at all.
function classify(id, pinned, hidden) {
    if (_ids(hidden).indexOf(id) >= 0)
        return "hidden";
    if (_ids(pinned).indexOf(id) >= 0)
        return "pinned";
    return "drawer";
}

// `ids` in the compositor-given order (Tray.qml passes SystemTray.items'
// own order), `visibleLimit` the cell budget for the whole tray region.
// Rules, in order:
//
//   1. Ids in `hidden` drop out entirely: they appear in neither `visible`
//      nor `drawer`, only in the returned `hidden` array, which is what the
//      manage popup lists them from.
//   2. Ids in `pinned` are always in `visible`, regardless of `visibleLimit`.
//      Pinning more items than the budget widens the tray rather than
//      silently ignoring the pin.
//   3. The remaining ids fill `visible` in their incoming order until it
//      reaches the budget; the rest go to `drawer`.
//   4. One slot of that budget belongs to the chevron whenever anything
//      would overflow (the `_visibleLimit - 1` Tray.qml applied before this
//      module existed), so an unconfigured tray's row width is unchanged.
//
// `visible` and `drawer` both come back in incoming order, not
// pins-then-rest: pinning an item must not shuffle the icons around it.
// Selection is tracked per position rather than per id so a duplicate id
// still occupies exactly the number of slots its instances occupy today.
function buckets(ids, pinned, hidden, visibleLimit) {
    var all = _ids(ids);
    var pins = _ids(pinned);
    var hides = _ids(hidden);
    var limit = (typeof visibleLimit === "number" && isFinite(visibleLimit) && visibleLimit >= 1)
        ? Math.floor(visibleLimit)
        : 1;
    var i;

    var kept = [];
    var hiddenOut = [];
    for (i = 0; i < all.length; i++) {
        if (hides.indexOf(all[i]) >= 0)
            hiddenOut.push(all[i]);
        else
            kept.push(all[i]);
    }

    // Rule 4. `slots` is the whole budget when everything fits and one less
    // when it does not, because the chevron takes a cell of its own exactly
    // then. Measured against `kept`, not `all`: hiding items is how a user
    // gets back under the budget, so a hidden id must not keep the chevron
    // reserved.
    var slots = kept.length > limit ? limit - 1 : kept.length;

    var take = [];
    var used = 0;
    for (i = 0; i < kept.length; i++) {
        take.push(pins.indexOf(kept[i]) >= 0);
        if (take[i])
            used++;
    }

    // Rule 3, over whatever rule 2 left unclaimed. `used` can already exceed
    // `slots` when more items are pinned than fit, which ends this loop
    // before it starts rather than evicting a pin.
    for (i = 0; i < kept.length && used < slots; i++) {
        if (take[i])
            continue;
        take[i] = true;
        used++;
    }

    var visible = [];
    var drawer = [];
    for (i = 0; i < kept.length; i++)
        (take[i] ? visible : drawer).push(kept[i]);

    return { visible: visible, drawer: drawer, hidden: hiddenOut };
}

// Settings (`bar.tray.pinned`/`bar.tray.hidden`) declaratively override the
// runtime state value when present; state.json's own value (written by the
// manage popup) is the fallback when settings is silent, never the other
// way around, matching Config's read-only-settings-wins convention
// elsewhere in the shell. The same contract, and the same two-line body, as
// Calendar/progress.js:49: restated here rather than imported so neither
// module has to know the other exists.
function resolveOverride(settingsValue, stateValue) {
    return (settingsValue === undefined || settingsValue === null) ? stateValue : settingsValue;
}
