import QtQuick
import Quickshell
import qs.Core
import qs.Components
import qs.Compositor

// The focused app's menu (DESIGN.md §3 "Panel"), opened from the bar's
// active-window cell: macOS's app-name menu, in the place the app name
// already sits.
//
// Everything here is data the desktop already publishes, so no per-app list
// is ever maintained: the window's appId resolves a desktop entry
// (DesktopEntries.heuristicLookup, the same lookup ActiveWindow's icon and
// name come from), that entry's own `Actions=` groups become the ACTIONS
// rows, and the compositor's window list filtered by the same appId becomes
// the WINDOWS rows. The window you are already in carries a `check`, the
// same mark macOS's Window menu puts there.
//
// This is deliberately NOT a global menu bar. Reading an app's real File/
// Edit menus needs either org.gtk.Menus (GTK4 apps that set a menubar,
// which libadwaita apps do not), the DBusMenu registrar (keyed by X11
// window id, so XWayland only), or the kde-appmenu Wayland protocol
// (KWin-only; Hyprland does not implement it), and Quickshell exposes no
// generic D-Bus to QML for any of them. Launcher actions plus the window
// list are what can be sourced honestly today, which is also why no row
// here opens a submenu.
//
// Honest states throughout, per the standing no-faked-data rule: nothing
// focused renders NO WINDOW, an appId with no desktop entry renders NO
// DESKTOP ENTRY, and an entry that declares no actions renders NO ACTIONS
// rather than an invented one.
//
// Keyboard (spec "Keyboard model"): one flat cursor over the action rows,
// then the window rows, then the close row, with Enter doing what a click
// on that row does. The panel had no key handling of its own to keep (D2's
// exception is for a menu tree this one cannot read), so it takes Panel's
// cursor like every other panel.
Panel {
    id: root

    // The panel's own noun, not the instance: the hero below carries the
    // focused app's name. Titling the card band with that same name too was
    // the duplication trap DESIGN.md's plan bans.
    panelIcon: "menu"
    panelTitle: "App menu"
    panelWidth: Theme.space.popupWidthDefault

    // Held, not raw: opening this panel takes keyboard focus off the very
    // window it describes (Compositor/focus.js).
    readonly property var _window: CompositorService.windowById(CompositorService.heldFocusedWindowId)
    readonly property string _appId: root._window ? root._window.appId : ""
    readonly property var _entry: root._appId !== "" ? DesktopEntries.heuristicLookup(root._appId) : null
    readonly property var _actions: (root._entry && root._entry.actions) ? root._entry.actions : []

    // The themed icon behind the hero's leading slot: the same lookup and
    // check-then-fall-back-to-nothing idiom ActiveWindow.qml's own bar cell
    // uses, so an unresolved icon just leaves the row shorter rather than a
    // missing-texture box.
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

    // Action rows, then window rows, then the close row.
    readonly property int _closeIndex: root._actions.length + root._appWindows.length

    cursorCount: root._window !== null ? root._closeIndex + 1 : 0

    onCursorActivated: index => {
        if (root._window === null)
            return;
        if (index < root._actions.length) {
            root._actions[index].execute();
            root.close();
        } else if (index < root._closeIndex) {
            CompositorService.focusWindow(root._appWindows[index - root._actions.length].id);
            root.close();
        } else {
            CompositorService.closeWindow(root._window.id);
            root.close();
        }
    }

    onIsOpenChanged: if (root.isOpen) {
        root.cursorIndex = 0;
        root.cursorSection = 0;
    }

    function _pointAt(index) {
        root.cursorActive = true;
        root.cursorSection = 0;
        root.cursorIndex = index;
    }

    Component {
        id: actionRow

        Cell {
            id: actionCell
            required property int index
            required property var modelData
            width: parent.width
            interactive: true
            cursor: root.cursorActive && root.cursorIndex === actionCell.index
            onContainsPointerChanged: if (actionCell.containsPointer) root._pointAt(actionCell.index)

            onClicked: {
                actionCell.modelData.execute();
                root.close();
            }

            Text {
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                text: actionCell.modelData.name
                color: actionCell.foreground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.body
                font.weight: Theme.weight.medium
                elide: Text.ElideRight
            }
        }
    }

    Component {
        id: windowRow

        Cell {
            id: windowCell
            required property int index
            required property var modelData
            readonly property bool _isCurrent: root._window !== null && windowCell.modelData.id === root._window.id
            readonly property int _cursorIndex: root._actions.length + windowCell.index

            width: parent.width
            interactive: true
            selected: windowCell._isCurrent
            cursor: root.cursorActive && root.cursorIndex === windowCell._cursorIndex
            onContainsPointerChanged: if (windowCell.containsPointer) root._pointAt(windowCell._cursorIndex)

            onClicked: {
                CompositorService.focusWindow(windowCell.modelData.id);
                root.close();
            }

            Item {
                width: parent.width
                height: windowTitle.implicitHeight

                Text {
                    id: windowTitle
                    anchors.left: parent.left
                    anchors.right: currentMark.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    // A toplevel is allowed to carry no title at all; its
                    // appId is the only honest thing left to name it by.
                    text: windowCell.modelData.title !== "" ? windowCell.modelData.title : windowCell.modelData.appId
                    color: windowCell.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                    elide: Text.ElideRight
                }

                Icon {
                    id: currentMark
                    name: "check"
                    size: Theme.fontSize.body
                    visible: windowCell._isCurrent
                    color: Theme.color.primary
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    SectionLabel {
        visible: root._window === null
        leftPadding: Theme.space.controlPaddingX
        text: "NO WINDOW"
    }

    Component {
        id: appIcon

        Item {
            width: Theme.space.xxl * 2
            height: Theme.space.xxl * 2

            Picture {
                anchors.fill: parent
                visible: root._iconSource !== ""
                source: root._iconSource
                fillMode: Image.PreserveAspectFit
            }
        }
    }

    // The panel's own subject: the focused window's app name. The header
    // says the panel's noun (App menu), so this is the only place the name
    // prints. No readout: this panel is a list of actions and windows, not a
    // metric.
    PanelHero {
        visible: root._window !== null
        width: parent.width
        leading: appIcon
        title: root._entry ? root._entry.name : root._appId
        // The appId is an identifier, so mono; skipped where it is already
        // the title, which is what a window with no desktop entry falls back
        // to.
        meta: root._entry ? root._appId : ""
        metaMono: true
    }

    Column {
        width: parent.width
        visible: root._window !== null
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "ACTIONS"
            count: root._actions.length
        }

        SectionLabel {
            visible: root._entry === null
            leftPadding: Theme.space.controlPaddingX
            text: "NO DESKTOP ENTRY"
        }

        SectionLabel {
            visible: root._entry !== null && root._actions.length === 0
            leftPadding: Theme.space.controlPaddingX
            text: "NO ACTIONS"
        }

        Repeater {
            model: root._window !== null ? root._actions : []
            delegate: actionRow
        }
    }

    Column {
        width: parent.width
        visible: root._window !== null
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "WINDOWS"
            count: root._appWindows.length
        }

        Repeater {
            model: root._window !== null ? root._appWindows : []
            delegate: windowRow
        }

        // The menu separator (spec "Panels"): the close row acts on the
        // window itself, not on the list above it.
        Rectangle {
            width: parent.width - Theme.space.sm * 2
            x: Theme.space.sm
            height: Theme.borderWidth
            color: Theme.color.border
        }

        Cell {
            id: closeCell
            visible: root._window !== null
            width: parent.width
            interactive: true
            cursor: root.cursorActive && root.cursorIndex === root._closeIndex
            onContainsPointerChanged: if (closeCell.containsPointer) root._pointAt(root._closeIndex)

            onClicked: {
                if (root._window)
                    CompositorService.closeWindow(root._window.id);
                root.close();
            }

            Item {
                width: parent.width
                height: closeLabel.implicitHeight

                Icon {
                    id: closeIcon
                    name: "x"
                    size: Theme.fontSize.body
                    color: closeCell.foreground
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: closeLabel
                    anchors.left: closeIcon.right
                    anchors.leftMargin: Theme.space.iconGap
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Close window"
                    color: closeCell.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                    elide: Text.ElideRight
                }
            }
        }
    }
}
