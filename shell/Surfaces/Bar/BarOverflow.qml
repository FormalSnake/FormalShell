import QtQuick
import qs.Core
import qs.Components

// The chevron's second bar (M52): the group behind a region's chevron, in a
// card hanging off that chevron cell, for the bar that has no room to open it
// in place. Same answer the tray already gives when the strip runs out of
// edge (TrayOverflow.qml), one altitude up: there it is one widget's items,
// here it is whatever `bar.layout` put on the governed side of a chevron.
//
// Always, not only when the strip is crowded (owner, 2026-09-01: "I want the
// chevron to always open the second bar just like the three dots"), which is
// the same call they made for the tray: this is where the group lives, not a
// state a busy bar falls into. The group used to open in place instead, and a
// playing track widening the centre left it clipped against it with the bar
// having no answer.
//
// A strip, so it takes Panel.qml's frame and none of its sheet: no header, no
// title, and a width that is exactly the rail plus the card's own padding.
//
// The cells are Bar.qml's OWN region delegate, handed over by the chevron
// that opened this (`openFor()` below), not a second registry of widgets: a
// Component carries its creation context, so every entry instantiated here
// still resolves the panel, screen and menu wiring that only Bar.qml has, and
// a widget joins this surface by being on the bar. The entries themselves are
// copies with the chevron annotation cleared (Bar/layout.js's
// `overflowEntries`), since the delegate's own collapse gate would otherwise
// collapse the group here too.
//
// One instance for the whole shell (shell.qml), like TrayOverflow, so which
// output it lands on and which cell it anchors under come from the chevron
// that opened it, not from the bar that published last: every output's bar
// carries a chevron for the same region, and they all write the same key.
//
// No keyboard cursor, unlike every other popout: a row here is an arbitrary
// bar widget, and a bar cell has no activation contract beyond a click
// (TrayOverflow can only do rows because a TrayCell has one). Escape and
// click-outside still close it, from Panel.
Panel {
    id: root

    showHeader: false

    // Which region's group is up. Set by the open/toggle functions below,
    // never bound.
    property string region: ""

    // region -> { entries, delegate, cell }, written by every bar's chevron
    // cell so the group can be summoned without one (BarIpc's `bar chevron`
    // verbs, which is the only path the smoke rig has: no synthetic pointer
    // exists there). One key per region and one bar per output, so on a
    // multi-monitor session this holds whichever bar published last: it is
    // the fallback for an open with no cell, never the answer for a click.
    property var sources: ({})

    // What the card is currently drawn from, and the cell it hangs off:
    // the chevron that was actually clicked (openFor below), so the card
    // lands on that bar's own output. Panel resolves both the screen and the
    // position off this cell's window, so a stale one here is a card opening
    // on the wrong monitor.
    property var source: null
    readonly property var sourceCell: root.source ? root.source.cell : null

    readonly property var _entries: root.source ? root.source.entries : []
    readonly property Component _delegate: root.source ? root.source.delegate : null

    readonly property bool _vertical: Theme.barVertical

    panelWidth: overflowRail.implicitWidth + Theme.space.panelPadding * 2

    function attach(regionName, entries, delegate, cell) {
        var next = {};
        for (var key in root.sources)
            next[key] = root.sources[key];
        var entry = { entries: entries, delegate: delegate, cell: cell };
        next[regionName] = entry;
        root.sources = next;
        // A card already up on this cell takes the new contents, which is how
        // a settings.json edit reaches a bar that is already open.
        if (root.sourceCell === cell)
            root.source = entry;
    }

    // The click path: the chevron hands over its own entries, delegate and
    // cell rather than being looked up by region, since every output's bar
    // writes the same region key and the map only remembers the last one.
    function openFor(regionName, entries, delegate, cell) {
        root.region = regionName;
        root.source = { entries: entries, delegate: delegate, cell: cell };
        if (cell)
            root.openFrom(cell);
        else
            root.open();
        return true;
    }

    // A click on the chevron the card is already hanging off shuts it; one on
    // another output's chevron moves it there rather than closing it.
    function toggleFor(regionName, entries, delegate, cell) {
        if (root.isOpen && root.region === regionName && root.sourceCell === cell) {
            root.close();
            return true;
        }
        return root.openFor(regionName, entries, delegate, cell);
    }

    function openRegion(regionName) {
        var entry = root.sources[regionName];
        if (!entry)
            return false;
        return root.openFor(regionName, entry.entries, entry.delegate, entry.cell);
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
