import QtQuick
import qs.Core
import qs.Components

// The chevron's second bar (M52): the group behind a region's chevron, in a
// card hanging off that chevron cell, for the bar that has no room to open it
// in place. Same answer the tray already gives when the strip runs out of
// edge (TrayOverflow.qml), one altitude up: there it is one widget's items,
// here it is whatever `bar.layout` put on the governed side of a chevron.
//
// The room question is Bar.qml's (`_regionFits`, Bar/chevron.js): with room
// the group still opens in place, exactly as M24/M25 shipped it, and this
// surface is never summoned. Without room the strip would clip it against the
// centre instead, which is how the owner met it (2026-09-01: a playing track
// widens the centre, and the expanded group disappears behind it).
//
// A strip, so it takes Panel.qml's frame and none of its sheet: no header, no
// title, and a width that is exactly the rail plus the card's own padding.
//
// The cells are Bar.qml's OWN region delegate, handed over by whichever
// chevron attached (`attach()` below), not a second registry of widgets: a
// Component carries its creation context, so every entry instantiated here
// still resolves the panel, screen and menu wiring that only Bar.qml has, and
// a widget joins this surface by being on the bar. The entries themselves are
// copies with the chevron annotation cleared (Bar/layout.js's
// `overflowEntries`), since the delegate's own collapse gate would otherwise
// collapse the group here too.
//
// One instance for the whole shell (shell.qml), like TrayOverflow: which bar
// attached last decides which output it lands on and which cell it anchors
// under.
//
// No keyboard cursor, unlike every other popout: a row here is an arbitrary
// bar widget, and a bar cell has no activation contract beyond a click
// (TrayOverflow can only do rows because a TrayCell has one). Escape and
// click-outside still close it, from Panel.
Panel {
    id: root

    showHeader: false

    // Which region's group is up. Set by attach()'s callers through the
    // open/toggle functions below, never bound.
    property string region: ""

    // region -> { entries, delegate, cell }, written by every bar's chevron
    // cell so the group can be summoned without one (BarIpc's `bar chevron`
    // verbs, which is the only path the smoke rig has: no synthetic pointer
    // exists there).
    property var sources: ({})

    // region -> bool: is that region's group off the strip right now? Written
    // by the same chevrons and read back by BarIpc's `chevron status`, which
    // is where the fit becomes observable without measuring a screenshot.
    // Every output's bar writes the one shared map, so on a multi-output rig
    // this is whichever bar answered last.
    property var offStrip: ({})

    readonly property var _source: root.sources[root.region] || null
    readonly property var _entries: root._source ? root._source.entries : []
    readonly property Component _delegate: root._source ? root._source.delegate : null

    readonly property bool _vertical: Theme.barVertical

    panelWidth: overflowRail.implicitWidth + Theme.space.panelPadding * 2

    function attach(regionName, entries, delegate, cell) {
        var next = {};
        for (var key in root.sources)
            next[key] = root.sources[key];
        next[regionName] = { entries: entries, delegate: delegate, cell: cell };
        root.sources = next;
    }

    function noteOffStrip(regionName, off) {
        if (!!root.offStrip[regionName] === !!off)
            return;
        var next = {};
        for (var key in root.offStrip)
            next[key] = root.offStrip[key];
        next[regionName] = !!off;
        root.offStrip = next;
        // A group that has just regained its room belongs back on the strip,
        // not in a card left hanging under it.
        if (!off && root.isOpen && root.region === regionName)
            root.close();
    }

    function openRegion(regionName) {
        var source = root.sources[regionName];
        if (!source)
            return false;
        root.region = regionName;
        if (source.cell)
            root.openFrom(source.cell);
        else
            root.open();
        return true;
    }

    function toggleRegion(regionName) {
        if (root.isOpen && root.region === regionName) {
            root.close();
            return true;
        }
        return root.openRegion(regionName);
    }

    Rail {
        id: overflowRail
        vertical: root._vertical
        spacing: Theme.space.sm

        Repeater {
            // Nothing to draw until a chevron has attached (a Repeater with a
            // null delegate is a warning per model row, not an empty rail),
            // and nothing while the surface is off screen: these cells are
            // second copies of live bar widgets, each with its own poll timer,
            // service subscription or child process, so they exist exactly as
            // long as the window is mapped. `visible` rather than `isOpen`,
            // which is Panel's own mapped lifetime and so holds through the
            // exit fade: a card emptying out as it fades is worse than the
            // rebuild on the next open, and that rebuild is a fresh poll
            // rather than a stale one.
            model: (root._delegate && root.visible) ? root._entries : []
            delegate: root._delegate
        }
    }
}
