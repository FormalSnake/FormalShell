import QtQuick
import Quickshell.Widgets
import qs.Core
import qs.Components

// One StatusNotifierItem drawn as a bar cell, shared by the strip's own
// Tray rail and by the second bar the items that don't fit spill into
// (../TrayOverflow.qml), so an item looks and answers the same wherever it
// ends up. Left click Activate()s it, middle click SecondaryActivate()s it,
// right click opens its DBusMenu when item.hasMenu is true. Items whose
// onlyMenu flag is set (SNI ItemIsMenu: "activation will do nothing") get
// the menu on left click too.
Cell {
    id: root

    required property var item
    // The shared TrayMenu instance (shell.qml, wired through Bar.qml same
    // as every other panel property), null is a valid state (menu never
    // opened this session), the call below just no-ops rather than crash.
    property var menu: null

    // The surface this cell's menu opens on top of, or null to let the menu
    // replace whatever is open (the strip's own cells, which are not in a
    // popout to begin with).
    property var menuOwner: null

    // Emitted after a click that ACTED on the item, for a surface that is
    // only up to put one item in reach and has no reason to stay open past it
    // (the overflow bar). Opening the item's menu is not one of those: the
    // menu belongs to the cell that opened it, and taking that cell's surface
    // away underneath it is the gesture cancelling itself.
    signal acted

    // The item's own words, in the SNI's own order of preference:
    // ToolTip.title is what the spec means for hover text, Title is the
    // display name, and Id is the last thing that is always set. Nothing
    // here is ours to rewrite, hence `tooltipVerbatim`, which keeps the card
    // from uppercasing another process's string.
    tooltipText: root.item.tooltipTitle || root.item.title || root.item.id
    tooltipVerbatim: true

    // M20 Task 5 shipped an alpha-mask 1-bit silhouette here (owner: tray
    // icons "often look invisible in light mode", third-party SNI marks are
    // frequently white/light symbolic glyphs drawn for a dark bar). The
    // owner ran real vendor icons in a live session and rejected the
    // treatment ("deep fried") 2026-08-09, reverted to true color;
    // light-mode invisibility is an open problem again (DESIGN.md §2 item
    // 12).
    //
    // The fixed square slot stays: bound to explicit width/height rather
    // than `implicitSize` alone, since quickshell's own IconImage docs note
    // implicitSize only seeds implicitWidth/implicitHeight, it does not
    // itself constrain the rendered size, which is why SNI's native
    // 16/22/24px pixmaps were varying the cell's padding rhythm before M20
    // Task 5's slot normalization. It is also what makes every tray cell one
    // width, which Bar/tray.js's fit is arithmetic on.
    IconImage {
        anchors.verticalCenter: parent.verticalCenter
        asynchronous: true
        smooth: false
        width: Theme.fontSize.body
        height: Theme.fontSize.body
        source: root.item.icon
    }

    interactive: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton) {
            if (root.item.onlyMenu && root.item.hasMenu) {
                root._openMenu();
                return;
            }
            root.item.activate();
        } else if (mouse.button === Qt.MiddleButton) {
            root.item.secondaryActivate();
        } else if (mouse.button === Qt.RightButton) {
            if (root.item.hasMenu)
                root._openMenu();
            return;
        }
        root.acted();
    }

    function _openMenu() {
        if (root.menu)
            root.menu.openItem(root, root.item, root.menuOwner);
    }
}
