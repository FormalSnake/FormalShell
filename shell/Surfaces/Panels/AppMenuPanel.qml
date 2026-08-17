import QtQuick
import Quickshell
import qs.Core
import qs.Components
import qs.Compositor

// The focused app's menu (DESIGN.md §Panels), opened from the bar's
// active-window cell — macOS's app-name menu, in the place the app name
// already sits.
//
// Everything here is data the desktop already publishes, so no per-app list
// is ever maintained: the window's appId resolves a desktop entry
// (DesktopEntries.heuristicLookup, the same lookup ActiveWindow's icon and
// name come from), that entry's own `Actions=` groups become the ACTIONS
// rows, and the compositor's window list filtered by the same appId becomes
// the WINDOWS rows.
//
// This is deliberately NOT a global menu bar. Reading an app's real File/
// Edit menus needs either org.gtk.Menus (GTK4 apps that set a menubar,
// which libadwaita apps do not), the DBusMenu registrar (keyed by X11
// window id, so XWayland only), or the kde-appmenu Wayland protocol
// (KWin-only; neither niri nor Hyprland implements it) — and Quickshell
// exposes no generic D-Bus to QML for any of them. Launcher actions plus
// the window list are what can be sourced honestly today.
//
// Honest states throughout, per the standing no-faked-data rule: nothing
// focused renders NO WINDOW, an appId with no desktop entry renders NO
// DESKTOP ENTRY, and an entry that declares no actions renders NO ACTIONS
// rather than an invented one.
Panel {
    id: root

    // The panel's own noun, not the instance: the hero below carries the
    // focused app's name (M28 Task 5). Titling the card band with that same
    // name too was the duplication trap DESIGN.md's plan bans — every other
    // panel's card band names the panel, not its subject.
    panelTitle: "APP MENU"
    panelWidth: Theme.space.popupWidthWide

    // Held, not raw: opening this panel takes keyboard focus off the very
    // window it describes (Compositor/focus.js).
    readonly property var _window: CompositorService.windowById(CompositorService.heldFocusedWindowId)
    readonly property string _appId: root._window ? root._window.appId : ""
    readonly property var _entry: root._appId !== "" ? DesktopEntries.heuristicLookup(root._appId) : null
    readonly property var _actions: (root._entry && root._entry.actions) ? root._entry.actions : []

    // The themed icon behind the hero's leading slot (M28 Task 5) — the
    // same lookup/check-then-fall-back-to-nothing idiom ActiveWindow.qml's
    // own bar cell already uses, so an unresolved icon just leaves the row
    // shorter rather than a missing-texture box.
    readonly property string _iconSource: (root._entry && root._entry.icon)
        ? Quickshell.iconPath(root._entry.icon, true)
        : ""

    readonly property var _appWindows: {
        var out = [];
        if (root._appId === "")
            return out;
        var all = CompositorService.windows;
        for (var i = 0; i < all.length; i++) {
            if (all[i].appId === root._appId)
                out.push(all[i]);
        }
        return out;
    }

    Component {
        id: actionRow

        Cell {
            id: actionCell
            required property var modelData
            width: parent.width

            Text {
                width: parent.width
                text: actionCell.modelData.name
                color: actionCell.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
                elide: Text.ElideRight
            }

            interactive: true
            onClicked: {
                actionCell.modelData.execute();
                root.close();
            }
        }
    }

    Component {
        id: windowRow

        Cell {
            id: windowCell
            required property var modelData
            readonly property bool isCurrent: root._window !== null && windowCell.modelData.id === root._window.id
            width: parent.width
            // The window you are already in inverts, DESIGN's selection
            // idiom standing in for macOS's Window-menu checkmark.
            selected: windowCell.isCurrent

            Text {
                width: parent.width
                // A toplevel is allowed to carry no title at all; its appId
                // is the only honest thing left to name it by.
                text: windowCell.modelData.title !== "" ? windowCell.modelData.title : windowCell.modelData.appId
                color: windowCell.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
                elide: Text.ElideRight
            }

            interactive: true
            onClicked: {
                CompositorService.focusWindow(windowCell.modelData.id);
                root.close();
            }
        }
    }

    Cell {
        visible: root._window === null
        width: parent.width

        MetaLabel { text: "NO WINDOW" }
    }

    Component {
        id: appIcon

        Item {
            width: Theme.space.xxl * 2
            height: Theme.space.xxl * 2

            Image {
                anchors.fill: parent
                visible: root._iconSource !== ""
                source: root._iconSource
                fillMode: Image.PreserveAspectFit
            }
        }
    }

    // The panel's own subject (M28 Task 5): the focused window's app name.
    // The card band above says the panel's noun (APP MENU) now, not the
    // instance, so this is the only place the name prints. The icon here is
    // genuinely new too: nothing else in this panel shows it. No readout:
    // this panel is a list of actions/windows, not a metric.
    PanelHero {
        visible: root._window !== null
        width: parent.width
        leading: appIcon
        title: root._entry ? root._entry.name : root._appId
    }

    Cell {
        visible: root._window !== null
        width: parent.width

        MetaLabel { text: "ACTIONS / " + root._actions.length }
    }

    Repeater {
        model: root._window !== null ? root._actions : []
        delegate: actionRow
    }

    Cell {
        visible: root._window !== null && root._entry === null
        width: parent.width

        MetaLabel { text: "NO DESKTOP ENTRY" }
    }

    Cell {
        visible: root._window !== null && root._entry !== null && root._actions.length === 0
        width: parent.width

        MetaLabel { text: "NO ACTIONS" }
    }

    Cell {
        visible: root._window !== null
        width: parent.width

        MetaLabel { text: "WINDOWS / " + root._appWindows.length }
    }

    Repeater {
        model: root._window !== null ? root._appWindows : []
        delegate: windowRow
    }

    Cell {
        id: closeCell
        visible: root._window !== null
        width: parent.width

        Text {
            width: parent.width
            text: "Close window"
            color: closeCell.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
            elide: Text.ElideRight
        }

        interactive: true
        onClicked: {
            if (root._window)
                CompositorService.closeWindow(root._window.id);
            root.close();
        }
    }
}
