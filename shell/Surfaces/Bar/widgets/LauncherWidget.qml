import QtQuick
import qs.Core
import qs.Components

// The launcher cell (DESIGN.md §3 Bar, M39 Task 1): the shell's mark at the
// head of the bar's left region, and the menu's only pointer-reachable
// summon path, every other route into it is a compositor keybind or the
// `menu` IPC target. It leads DEFAULT_LAYOUT.left rather than joining the
// opt-in builtins for exactly that reason: a bar with no launcher cell
// leaves a mouse user with no way to open the menu at all.
//
// The mark is the command glyph, shadcn's own Command palette sign, drawn
// through `Icon` so the set follows `theme.icons` like every other icon in
// the shell.
Cell {
    id: root

    // shell.qml's single Menu instance, handed down through Bar.qml.
    property var menu: null

    readonly property bool _menuOpen: root.menu ? root.menu.isOpen : false


    tooltipText: "LAUNCHER"

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: "command"
        color: root.foreground
    }

    panelOpen: root._menuOpen

    interactive: true
    // Toggle rather than open: a second click on the mark closes the menu,
    // the same contract `menu toggle` over IPC already has.
    onClicked: {
        if (!root.menu)
            return;
        if (root.menu.isOpen)
            root.menu.close();
        else
            root.menu.open();
    }
}
