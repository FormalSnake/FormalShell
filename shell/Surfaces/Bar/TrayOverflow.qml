import QtQuick
import Quickshell.Services.SystemTray
import qs.Core
import qs.Components
import qs.Surfaces.Bar.widgets

// The tray's second bar: the whole tray, in a card hanging off the toggle
// that replaced it on the strip (widgets/Tray.qml). This is Ice's and
// Bartender's answer to a menu bar that has run out of edge, at the altitude
// the tray actually overflows at, rather than the bar's own chevron
// (ChevronWidget.qml), which collapses a whole configured group whether it
// fits or not.
//
// Every registered item is here, never a remainder (owner, 2026-08-28): the
// strip hands the tray over whole or not at all, so this bar is the tray
// while it is up.
//
// A strip, so it takes Panel.qml's frame and none of its sheet: no header
// (`showHeader: false`), no title, and a width that is exactly the rail plus
// the card's own padding, so the surface is the row of icons and nothing
// else. Everything else a popout needs, the anchoring under the opening
// cell, the click-outside dismiss, the multi-output dismiss twins, the
// keyboard priming, comes from Panel unchanged.
//
// One instance for the whole shell (shell.qml), not one per output, the same
// "one controller, opened on the focused screen at trigger time" split
// TrayMenu takes: which bar opened it decides which output it lands on.
// Opening an item's context menu from here closes this bar, since both are
// popouts and the shell allows one at a time (Panel's PanelRegistry); the
// menu keeps the anchor of the cell that opened it either way.
Panel {
    id: root

    showHeader: false

    // The shared TrayMenu instance, handed over by whichever Tray opened
    // this so a right click here reaches the same surface it does on the
    // strip.
    property var menu: null

    // How many items the strip kept: 0 while the tray has moved here, the
    // whole count while it has not. Written by the owning Tray and read back
    // by TrayIpc's `status`, which is the only place the answer is
    // observable without measuring a screenshot. It never gates what this
    // bar draws, which is always every item.
    property int inlineCount: 0

    readonly property bool _vertical: Theme.barVertical
    readonly property int _count: SystemTray.items.values.length

    panelWidth: overflowRail.implicitWidth + Theme.space.panelPadding * 2

    // A row on a horizontal bar walks under Left/Right (one row of `_count`
    // columns); a column beside a vertical one is an ordinary list.
    cursorCount: root._count
    cursorColumns: root._vertical ? 1 : Math.max(1, root._count)

    function _pointAt(index) {
        root.cursorActive = true;
        root.cursorIndex = index;
    }

    onCursorActivated: index => {
        var items = SystemTray.items.values;
        var item = items[index];
        if (!item)
            return;
        if (item.onlyMenu && item.hasMenu) {
            if (root.menu)
                root.menu.openItem(null, item);
        } else {
            item.activate();
        }
        root.close();
    }

    Rail {
        id: overflowRail
        vertical: root._vertical
        spacing: Theme.space.sm

        // The same live ObjectModel the strip renders, not a `.values`
        // snapshot: a plain-array model is a full delegate reset on every one
        // of Quickshell's re-notifies, and every icon's async load restarts
        // mid-decode with it (widgets/Tray.qml's own Repeater carries the
        // whole story).
        Repeater {
            model: SystemTray.items

            delegate: TrayCell {
                id: itemCell
                required property var modelData
                required property int index

                item: itemCell.modelData
                menu: root.menu
                ghost: true
                barEdge: Theme.barPosition
                cursor: root.cursorActive && itemCell.index === root.cursorIndex
                // A pointer reaching a cell reveals the cursor on it, the
                // same gate the first navigation key flips.
                onContainsPointerChanged: if (itemCell.containsPointer) root._pointAt(itemCell.index)
                // Reaching an item is the whole errand, so the bar closes
                // behind it the way a menu row does.
                onActed: root.close()
            }
        }
    }
}
