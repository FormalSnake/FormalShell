import Quickshell.Io
import qs.Core
import qs.Plugins
import "../Bar/layout.js" as Layout

// `qs ipc call bar chevron <toggle|expand|collapse|status>` and
// `qs ipc call bar chevronAt <toggle|expand|collapse> <region>`: a spec
// addendum in the same class as `panel` (CLAUDE.md's own note on that
// target). The bar chevron (M24, ChevronWidget.qml) holds everything
// placed on its governed side of its own region (M25: inward from that
// region's anchored edge), and its only real input is a click on
// that cell, which this rig cannot synthesize: no synthetic pointer exists
// here, only wtype's keyboard events. Without these routes the feature could
// not be verified headlessly at all, and a compositor keybind would have no
// summon path either.
//
// Two verbs rather than one with an optional region because quickshell
// dispatches IPC on exact arity (ipccomm.cpp: `argumentTypes.length() !=
// arguments.length()` is rejected before the handler runs), the same split
// CaptureIpc's text/textAt pair already makes. `chevron` infers the region
// when exactly one exists and refuses to guess when more than one does;
// `chevronAt` names it outright.
//
// M52: the governed group lives in the second bar
// (Surfaces/Bar/BarOverflow.qml) and nowhere else, so these three verbs open
// and close that surface. There is no collapse state behind them any more:
// `expand` is `panel open` for one group, `collapse` closes it, and `status`
// reports whether it is up.
//
// The layout is resolved here rather than read off a Bar instance: Bar.qml
// is instantiated once per screen and this handler answers for the whole
// shell, while Layout.resolve is pure and re-runs on any Config change like
// every other Config.get() consumer. Its warnings are dropped on the floor
// on purpose, since Bar.qml already prints them once per resolve and this
// would double every one of them.
IpcHandler {
    id: root
    target: "bar"

    // shell.qml's single BarOverflow instance: the chevron's second bar, and
    // so the whole of what these verbs act on. Null in a run with no bar on
    // screen, where there is no group to summon.
    property var barOverflow: null

    readonly property var _regions: Layout.resolve(Config.get("bar", null), PluginService.barPlugins).regions

    function _open(region) {
        return !!(root.barOverflow && root.barOverflow.isOpen && root.barOverflow.region === region);
    }

    function _chevronRegions() {
        var out = [];
        for (var i = 0; i < Layout.REGIONS.length; i++) {
            var region = Layout.REGIONS[i];
            if (Layout.hasChevron(root._regions[region]))
                out.push(region);
        }
        return out;
    }

    // Every action lands here so the three verbs answer identically whether
    // the region was inferred or named.
    function _act(action, region) {
        if (Layout.REGIONS.indexOf(region) < 0)
            return "error: unknown region '" + region + "' (left|center|right)";
        if (!Layout.hasChevron(root._regions[region]))
            return "error: no chevron in bar.layout." + region;
        if (["toggle", "expand", "collapse"].indexOf(action) < 0)
            return "error: unknown chevron action '" + action + "' (toggle|expand|collapse)";
        if (!root.barOverflow)
            return "error: no bar overflow surface";
        // The three verbs address the group's one home, the second bar
        // (Surfaces/Bar/BarOverflow.qml). There is no collapse state left to
        // write: a governed entry is never on the strip.
        if (action === "toggle")
            root.barOverflow.toggleRegion(region);
        else if (action === "expand")
            root.barOverflow.openRegion(region);
        else if (root._open(region))
            root.barOverflow.close();
        return "ok";
    }

    function chevron(action: string): string {
        if (action === "status")
            return root._status();
        var regions = root._chevronRegions();
        if (regions.length === 0)
            return "error: bar.layout has no chevron in any region";
        if (regions.length > 1)
            return "error: chevrons in " + regions.length + " regions (" + regions.join(", ") + "); use chevronAt <action> <region>";
        return root._act(action, regions[0]);
    }

    function chevronAt(action: string, region: string): string {
        return root._act(action, region);
    }

    // `collapses` is what the chevron governs and never moves: those entries
    // are off the strip for the whole session, so it doubles as "what is
    // hidden right now" and there is no second list to report. `open` is
    // whether that group's second bar is up. Both are reported for every
    // region, chevron or not, because a caller asserting on one region should
    // not have to know which shape the others took.
    function _status() {
        var out = {};
        for (var i = 0; i < Layout.REGIONS.length; i++) {
            var region = Layout.REGIONS[i];
            var entries = root._regions[region];
            out[region] = {
                chevron: Layout.hasChevron(entries),
                collapses: Layout.collapsedNames(entries),
                open: root._open(region)
            };
        }
        return JSON.stringify({ regions: out, chevronRegions: root._chevronRegions() });
    }
}
