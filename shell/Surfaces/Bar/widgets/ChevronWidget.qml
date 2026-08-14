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
// configuration, and everything after it in its own region collapses behind
// it. This is macOS Hidden Bar / Bartender at the bar's altitude rather than
// the tray's. M23 built the same idea inside Tray.qml over SNI item ids,
// which was the wrong altitude and is gone; Tray.qml's own header records
// the spec deviation that removal amounts to.
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
// The direction deliberately does NOT mirror per region. A Row lays out left
// to right in all three regions and layout.js marks `collapsible` as
// strictly-later-in-the-array, so the group this cell governs sits to its
// RIGHT whichever region it is in. The glyph points where that group goes on
// the next click: right to let it out, left to fold it back in. A
// left-region mirror would point at the widgets BEFORE the chevron, which it
// never touches.
Cell {
    id: root

    // Which region's collapse state this cell owns, and that region's whole
    // resolved entry array (the source of the names below). Set by Bar.qml.
    property string region: ""
    property var regionEntries: []

    readonly property var hiddenNames: Layout.collapsedNames(root.regionEntries)

    // Collapsed is the default, matching Hidden Bar and Bartender: adding
    // `chevron` to bar.layout has to visibly do something on first run.
    // Anything but an explicit `false` reads as collapsed, so a state.json
    // written before this key existed needs no migration.
    readonly property bool collapsed: {
        var stored = Core.State.barCollapsed;
        return !stored || stored[root.region] !== false;
    }

    standalone: true
    tooltipText: (root.collapsed ? "BAR / SHOW " : "BAR / HIDE ") + root.hiddenNames.length

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.collapsed ? "󰅂" : "󰅁"
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.body
    }

    interactive: true
    onClicked: Core.State.setBarCollapsed(root.region, !root.collapsed)
}
