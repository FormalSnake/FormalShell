import Quickshell.Io
import qs.Core
import qs.Plugins
import "../Bar/layout.js" as Layout

// `qs ipc call bar chevron <toggle|expand|collapse|status>` and
// `qs ipc call bar chevronAt <toggle|expand|collapse> <region>`: a spec
// addendum in the same class as `panel` (CLAUDE.md's own note on that
// target). The bar chevron (M24, ChevronWidget.qml) collapses everything
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
// M52: a group with no room left on the strip lives in the second bar
// (Surfaces/Bar/BarOverflow.qml) instead, and the same three verbs then open
// and close that surface rather than writing a collapse state the bar cannot
// act on. `status` reports which of the two a region is in (`offStrip`), the
// only headless read of a fit that is otherwise measured per output.
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
    // the only place the fit each bar measured is observable from here
    // (Surfaces/Bar/BarOverflow.qml's `offStrip`). Null in a run with no bar
    // on screen, where every region is trivially on the strip.
    property var barOverflow: null

    readonly property var _regions: Layout.resolve(Config.get("bar", null), PluginService.barPlugins).regions

    // Whether that region's group has left the strip for the second bar,
    // which decides what the three verbs below do: with no room, expanding is
    // opening that bar, not writing a state nothing can act on.
    function _offStrip(region) {
        return !!(root.barOverflow && root.barOverflow.offStrip[region]);
    }

    function _overflowOpen(region) {
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
        if (["toggle", "expand", "collapse"].indexOf(action) < 0)
            return "error: unknown chevron action '" + action + "' (toggle|expand|collapse)";
        // Off the strip these verbs address the second bar instead, so one
        // control keeps one summon path however crowded the bar is. The
        // stored state is deliberately not written here: it is where the user
        // left the group for when the room comes back.
        if (root._offStrip(region)) {
            if (action === "toggle")
                root.barOverflow.toggleRegion(region);
            else if (action === "expand")
                root.barOverflow.openRegion(region);
            else if (root._overflowOpen(region))
                root.barOverflow.close();
            return "ok";
        }
        if (action === "toggle")
            State.setBarCollapsed(region, !root._collapsed(region));
        else if (action === "expand")
            State.setBarCollapsed(region, false);
        else
            State.setBarCollapsed(region, true);
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
            var offStrip = root._offStrip(region);
            out[region] = {
                chevron: Layout.hasChevron(entries),
                collapsed: collapsed,
                collapses: collapses,
                // Off the strip nothing of the group is on the bar, whatever
                // the stored state says, so `hidden` reports what is really
                // not there rather than what was last asked for.
                hidden: (collapsed || offStrip) ? collapses : [],
                offStrip: offStrip,
                overflowOpen: root._overflowOpen(region)
            };
        }
        return JSON.stringify({ regions: out, chevronRegions: root._chevronRegions() });
    }
}
