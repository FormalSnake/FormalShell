import QtQuick
import qs.Core
import qs.Components
import "../../../Bar/layout.js" as Layout

// The bar's overflow boundary (M24, owner ask: "I want the chevron to
// show/hide bar items that shouldn't always show, and the chevron in of
// itself is an item so it can be changed position"; M52, owner ask:
// "I want the chevron to always open the second bar just like the three
// dots"). An ordinary bar.layout entry carrying no config of its own: its
// POSITION is the entire configuration, and everything on its governed side
// of its own region lives in the second bar this cell opens
// (../BarOverflow.qml) rather than on the strip.
//
// This is macOS Hidden Bar / Bartender at the bar's altitude, and it is the
// tray's own answer one altitude up (widgets/Tray.qml's dots): the group is
// somewhere else, always, rather than sometimes here and sometimes there.
// M23 built a per-item version inside Tray.qml, which was the wrong altitude
// and is gone; Tray.qml's own header records the spec deviation that removal
// amounts to. The group used to open in place and collapse behind this cell
// (M24/M25), which a playing track then clipped against the centre: the bar
// had no room for it and no answer for that (owner, 2026-09-01).
//
// The glyph points at the card, not along the strip: the group is never on
// the bar, so there is no direction for it to travel in. Shut, it points the
// way the second bar opens, which is away from the bar's own edge (down from
// a top bar, up from a bottom one, and sideways off a vertical one); open, it
// points back at the bar the card folds into. Which side of the cell the
// group is written on (layout.js's `governsBefore`) decides what is in the
// card, never which way this points.
Cell {
    id: root

    // Which region's group this cell holds, and that region's whole resolved
    // entry array (the source of the names below). Set by Bar.qml, which
    // republishes `_layout` only when the resolved regions actually differ,
    // so a Config or plugin-scan tick that changes nothing leaves this cell
    // alone rather than resetting it.
    property string region: ""
    property var regionEntries: []

    // The one shared BarOverflow instance (shell.qml, through Bar.qml), and
    // the region delegate its cells are built from. Null means no second bar
    // was wired in, and this cell then has nothing to open: it still draws,
    // since the group is off the strip either way, but a click does nothing.
    property var overflow: null
    property Component entryDelegate: null

    readonly property var hiddenNames: Layout.collapsedNames(root.regionEntries)
    readonly property var hiddenEntries: Layout.overflowEntries(root.regionEntries)

    // This cell's own card, not the region's: every output's bar carries a
    // chevron for the same region, and only the one the card hangs off is
    // open.
    readonly property bool _open: root.overflow !== null && root.overflow.isOpen
        && root.overflow.region === root.region && root.overflow.sourceCell === root

    // The tray's own words for the same thing: what is behind this cell, and
    // how much of it.
    tooltipText: "BAR / " + root.hiddenNames.length + " ITEMS"
    panelOpen: root._open

    // The two directions this cell ever points, named for the screen rather
    // than for the row: the glyph stays upright on a vertical bar (Icon.qml),
    // so it has to be.
    readonly property string _awayName: {
        switch (Theme.barPosition) {
        case "bottom": return "chevron-up";
        case "left": return "chevron-right";
        case "right": return "chevron-left";
        }
        return "chevron-down";
    }
    readonly property string _backName: {
        switch (Theme.barPosition) {
        case "bottom": return "chevron-down";
        case "left": return "chevron-left";
        case "right": return "chevron-right";
        }
        return "chevron-up";
    }

    // The flip (M51 Task 5): a crossfade rather than a rotation, since a
    // rotated glyph would read mirrored for half the turn. Both icons sit
    // stacked on the same spot (neither sets a horizontal anchor, matching
    // the single icon this replaces), so it reads as one glyph turning
    // rather than two glyphs trading places.
    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root._awayName
        color: root.foreground
        opacity: root._open ? 0 : 1
        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easingInOut }
        }
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root._backName
        color: root.foreground
        opacity: root._open ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easingInOut }
        }
    }

    interactive: true
    // The group goes with the click: this cell hands the second bar its own
    // entries, delegate and cell rather than letting it look the region up,
    // since the surface is one instance for the whole shell and every
    // output's bar writes the same region key. Look it up and a click on the
    // second monitor opens the card on the first.
    onClicked: {
        if (root.overflow)
            root.overflow.toggleFor(root.region, root.hiddenEntries, root.entryDelegate, root);
    }

    // Published to the shared surface as well as carried on the click: the
    // second bar has to be summonable without a click on this cell (BarIpc's
    // `bar chevron` verbs are the smoke rig's only pointer, and a compositor
    // keybind has no other route either), and it needs this cell as its
    // anchor. Re-run on every input its contents depend on, so a
    // settings.json edit reaches a bar that is already open.
    function _publish() {
        if (!root.overflow || root.region === "")
            return;
        root.overflow.attach(root.region, root.hiddenEntries, root.entryDelegate, root);
    }

    Component.onCompleted: root._publish()
    onRegionChanged: root._publish()
    onHiddenEntriesChanged: root._publish()
    onEntryDelegateChanged: root._publish()
    onOverflowChanged: root._publish()
}
