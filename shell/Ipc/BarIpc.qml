import Quickshell.Io
import qs.Core
import qs.Plugins
import "../Bar/layout.js" as Layout

// `qs ipc call bar chevron <toggle|expand|collapse|status>` and
// `qs ipc call bar chevronAt <toggle|expand|collapse> <region>`: a spec
// addendum in the same class as `panel` (CLAUDE.md's own note on that
// target). The bar chevron (M24, ChevronWidget.qml) collapses everything
// placed after it in its own region, and its only real input is a click on
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
// The layout is resolved here rather than read off a Bar instance: Bar.qml
// is instantiated once per screen and this handler answers for the whole
// shell, while Layout.resolve is pure and re-runs on any Config change like
// every other Config.get() consumer. Its warnings are dropped on the floor
// on purpose, since Bar.qml already prints them once per resolve and this
// would double every one of them.
IpcHandler {
    id: root
    target: "bar"

    readonly property var _regions: Layout.resolve(Config.get("bar", null), PluginService.barPlugins).regions

    function _chevronRegions() {
        var out = [];
        for (var i = 0; i < Layout.REGIONS.length; i++) {
            var region = Layout.REGIONS[i];
            if (Layout.hasChevron(root._regions[region]))
                out.push(region);
        }
        return out;
    }

    function _collapsed(region) {
        var stored = State.barCollapsed;
        return !stored || stored[region] !== false;
    }

    // Every action lands here so the three verbs answer identically whether
    // the region was inferred or named.
    function _act(action, region) {
        if (Layout.REGIONS.indexOf(region) < 0)
            return "error: unknown region '" + region + "' (left|center|right)";
        if (!Layout.hasChevron(root._regions[region]))
            return "error: no chevron in bar.layout." + region;
        if (action === "toggle")
            State.setBarCollapsed(region, !root._collapsed(region));
        else if (action === "expand")
            State.setBarCollapsed(region, false);
        else if (action === "collapse")
            State.setBarCollapsed(region, true);
        else
            return "error: unknown chevron action '" + action + "' (toggle|expand|collapse)";
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

    // `collapses` is what the chevron governs and does not move; `hidden` is
    // what is actually hidden right now, so it empties on expand. Both are
    // reported for every region, chevron or not, because a caller asserting
    // on one region should not have to know which shape the others took.
    // `collapsed` for a region with no chevron is honest stored state that
    // nothing currently reads.
    function _status() {
        var out = {};
        for (var i = 0; i < Layout.REGIONS.length; i++) {
            var region = Layout.REGIONS[i];
            var entries = root._regions[region];
            var collapses = Layout.collapsedNames(entries);
            var collapsed = root._collapsed(region);
            out[region] = {
                chevron: Layout.hasChevron(entries),
                collapsed: collapsed,
                collapses: collapses,
                hidden: collapsed ? collapses : []
            };
        }
        return JSON.stringify({ regions: out, chevronRegions: root._chevronRegions() });
    }
}
