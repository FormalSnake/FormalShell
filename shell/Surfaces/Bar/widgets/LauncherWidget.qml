import QtQuick
import qs.Core
import qs.Components

// The launcher cell (DESIGN.md §3 Bar, M39 Task 1): the shell's mark at the
// head of the bar's left region, and the menu's only pointer-reachable
// summon path — every other route into it is a compositor keybind or the
// `menu` IPC target. It leads DEFAULT_LAYOUT.left rather than joining the
// opt-in builtins for exactly that reason: a bar with no launcher cell
// leaves a mouse user with no way to open the menu at all.
//
// The mark is `[F]` in the shell's own mono font, not a glyph from a Nerd
// Font private-use range: it has to survive a fontconfig `monospace` alias
// that resolves to a font with no icon coverage (the bar's hard rule is the
// alias, never a family name), and box-drawing/ASCII ornament is the accent
// this shell already speaks. Both brackets and the letter take
// `root.foreground` — one color, so Cell's hover inversion carries the whole
// mark to the accent pair with nothing left painting a resting-state token
// over an inverted fill.
Cell {
    id: root

    // shell.qml's single Menu instance, handed down through Bar.qml.
    property var menu: null

    readonly property bool _menuOpen: root.menu ? root.menu.isOpen : false

    standalone: true

    tooltipText: "LAUNCHER"

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "[F]"
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.body
    }

    PanelOpenDot {
        visible: root._menuOpen
        inverted: root.invertedNow
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
    }

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
