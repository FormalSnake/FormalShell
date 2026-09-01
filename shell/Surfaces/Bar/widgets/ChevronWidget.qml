import QtQuick
import qs.Core
// Aliased alongside the unqualified import above, the idiom CalendarPanel.qml
// documents: QtQuick exports its own type named State (the property-binding
// one), so a bare `State.barCollapsed` here reads back undefined at runtime
// instead of reaching the qs.Core singleton. Confirmed the hard way on this
// very widget (2026-08-14): the glyph never left its collapsed form and every
// governed cell stayed hidden, while `bar chevron status` reported the state
// correctly because BarIpc.qml never imports QtQuick and so never collided.
import qs.Core as Core
import qs.Components
import "../../../Bar/layout.js" as Layout

// The bar's collapse boundary (M24, owner ask: "I want the chevron to
// show/hide bar items that shouldn't always show, and the chevron in of
// itself is an item so it can be changed position"). An ordinary bar.layout
// entry carrying no config of its own: its POSITION is the entire
// configuration, and everything on its governed side of its own region
// collapses behind it. This is macOS Hidden Bar / Bartender at the bar's
// altitude rather than the tray's. M23 built the same idea inside Tray.qml
// over SNI item ids, which was the wrong altitude and is gone; Tray.qml's
// own header records the spec deviation that removal amounts to.
//
// `region` and `regionEntries` are handed over by Bar.qml's region delegate
// once loaded, the same after-creation assignment CommandModule/QmlModule/
// PluginBarModule already take for their own definitions: only Bar.qml knows
// which Repeater instantiated this cell. Both stay in step with a
// settings.json edit for free, since Config changing re-resolves
// `bar._layout` into fresh arrays and a plain-array Repeater.model treats
// that as a full delegate reset.
//
// Glyphs are md-chevron_left (U+F0141) and md-chevron_right (U+F0142), both
// read out of the pinned nerd-fonts-jetbrains-mono cmap's own format-12
// subtable (nix/testvm.nix pins 3.4.0+2.304; glyph ids 5183 and 5184, names
// confirmed against that font's post table) rather than from memory, per
// DESIGN.md's literal-character rule.
//
// The direction mirrors per region because the governed side does (M25).
// layout.js marks `collapsible` on the side away from the region's anchored
// edge, so a right-region group sits to this cell's LEFT and a left- or
// center-region group sits to its RIGHT. The glyph points where that group
// moves on the next click: in a right region collapsed points left and
// expanded points right, and the other two regions read the same pair the
// other way round.
// M52: a group with no room left on the strip opens in a second bar instead
// (../BarOverflow.qml), which is the tray's own answer to a bar that has run
// out of edge. Which of the two happens is measured and never configured:
// Bar.qml works the room out (Bar/chevron.js) and hands `fits` over. The
// owner met the missing half of this with a track playing, where the centre
// widens and an expanded right group is clipped against it.
//
Cell {
    id: root

    // Which region's collapse state this cell owns, and that region's whole
    // resolved entry array (the source of the names below). Set by Bar.qml.
    property string region: ""
    property var regionEntries: []

    // The one shared BarOverflow instance (shell.qml, through Bar.qml), and
    // the region delegate its cells are built from. Null means no second bar
    // was wired in, and the group then opens in place whether it fits or not,
    // which is exactly M24's own behaviour.
    property var overflow: null
    property Component entryDelegate: null

    // Whether the group has room on the strip, measured by Bar.qml
    // (Bar/chevron.js) and handed over. False moves the whole group into the
    // second bar: this cell then toggles that surface instead of the stored
    // state, and Bar.qml's own delegate keeps the cells off the strip
    // regardless of what the state says, so the two never draw the group
    // twice. The state itself is left alone, so a group that regains its room
    // (the track stops, the centre narrows) comes back open if that is where
    // the user left it.
    property bool fits: true

    readonly property var hiddenNames: Layout.collapsedNames(root.regionEntries)
    readonly property var hiddenEntries: Layout.overflowEntries(root.regionEntries)

    readonly property bool offStrip: !root.fits && root.overflow !== null
    readonly property bool _overflowOpen: root.overflow !== null && root.overflow.isOpen
        && root.overflow.region === root.region

    // Collapsed is the default, matching Hidden Bar and Bartender: adding
    // `chevron` to bar.layout has to visibly do something on first run.
    // Anything but an explicit `false` reads as collapsed, so a state.json
    // written before this key existed needs no migration.
    readonly property bool collapsed: {
        var stored = Core.State.barCollapsed;
        return !stored || stored[root.region] !== false;
    }

    // Which of the two chevrons below is the outward one, read off layout.js's
    // own rule rather than restated here: the same annotation the governed
    // cells are gated on decides which way this points. "After" is further
    // along the strip: right on a horizontal bar, down on a vertical one,
    // where the glyph stays upright (Icon.qml) and so has to be named for
    // the screen direction rather than the row's.
    // What "open" means on this cell: the group on the strip, or the second
    // bar up. Either way the glyph points where the group moves on the next
    // click.
    readonly property bool _expanded: root.offStrip ? root._overflowOpen : !root.collapsed
    readonly property bool _pointsAfter: Layout.governsBefore(root.region) ? root._expanded : !root._expanded

    // Off the strip the group is not hidden or shown, it is somewhere else,
    // and the tooltip says so in the tray's own words.
    tooltipText: root.offStrip
        ? "BAR / " + root.hiddenNames.length + " ITEMS"
        : (root.collapsed ? "BAR / SHOW " : "BAR / HIDE ") + root.hiddenNames.length
    panelOpen: root._overflowOpen

    // The two directions this axis ever points, so the flip below only ever
    // crossfades between them rather than between all four glyph names.
    readonly property string _beforeName: root.vertical ? "chevron-up" : "chevron-left"
    readonly property string _afterName: root.vertical ? "chevron-down" : "chevron-right"

    // The flip (M51 Task 5): a crossfade rather than a rotation, since a
    // rotated glyph would read mirrored for half the turn. Both icons sit
    // stacked on the same spot (neither sets a horizontal anchor, matching
    // the single icon this replaces), so it reads as one glyph turning
    // rather than two glyphs trading places.
    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root._beforeName
        color: root.foreground
        opacity: root._pointsAfter ? 0 : 1
        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easingInOut }
        }
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root._afterName
        color: root.foreground
        opacity: root._pointsAfter ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easingInOut }
        }
    }

    interactive: true
    onClicked: {
        if (root.offStrip) {
            root.overflow.toggleRegion(root.region);
            return;
        }
        Core.State.setBarCollapsed(root.region, !root.collapsed);
    }

    // Published to the shared surface rather than held here: the second bar
    // has to be summonable without a click on this cell (BarIpc's `bar
    // chevron` verbs are the smoke rig's only pointer), and it needs this
    // cell as its anchor either way. Re-run on every input the group's
    // contents or its room depend on, so a settings.json edit or a widening
    // centre reaches a bar that is already open.
    function _publish() {
        if (!root.overflow || root.region === "")
            return;
        root.overflow.attach(root.region, root.hiddenEntries, root.entryDelegate, root);
        root.overflow.noteOffStrip(root.region, root.offStrip);
    }

    Component.onCompleted: root._publish()
    onRegionChanged: root._publish()
    onHiddenEntriesChanged: root._publish()
    onEntryDelegateChanged: root._publish()
    onOverflowChanged: root._publish()
    onOffStripChanged: root._publish()
}
