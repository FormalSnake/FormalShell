import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.Core
import qs.Components
import qs.Services

// Bar region for the SNI tray (DESIGN.md §Bar, spec §Surfaces-1, M10 Task 1).
// Quickshell.Services.SystemTray both hosts and watches
// org.kde.StatusNotifierWatcher once referenced (its own module doc: merely
// referencing the singleton "will make quickshell start tracking system
// tray contents"), so every real StatusNotifierItem registered on the
// session bus shows up in .items with no extra wiring on our end. Each item
// renders as its own standalone Cell — left click Activate()s it, middle
// click SecondaryActivate()s it, right click opens its DBusMenu via
// QsMenuAnchor when item.hasMenu is true (Quickshell.DBusMenu's own doc:
// "can be displayed with QsMenuAnchor or QsMenuOpener"). Past a small
// visible count the rest collapse into one more Cell ("+N") that expands
// this row to reveal them too, instead of an unbounded strip of icons — the
// spec's "grouped drawer". Expand state lives in TrayService (shared, not
// local) so `qs ipc call tray expand` can drive it — this rig has no way to
// synthesize the pointer click that would otherwise be the only trigger.
// Hidden entirely (Row.implicitWidth is naturally 0 with an empty Repeater
// and no overflow cell) when nothing has registered — never an empty box.
Row {
    id: root

    readonly property var _items: SystemTray.items.values
    readonly property int _visibleLimit: 4
    readonly property bool _overflowing: root._items.length > root._visibleLimit
    readonly property int _pinnedCount: root._overflowing ? root._visibleLimit - 1 : root._items.length
    readonly property int _overflowCount: root._items.length - root._pinnedCount
    readonly property var _shown: (root._overflowing && !TrayService.drawerExpanded)
        ? root._items.slice(0, root._pinnedCount)
        : root._items

    spacing: Theme.space.sm
    visible: root._items.length > 0

    // Shared by every item cell below — right-clicking one just repoints
    // this at that cell and its menu handle rather than each delegate
    // owning its own anchor, since only one context menu is ever open.
    QsMenuAnchor {
        id: contextMenu
    }

    Repeater {
        model: root._shown

        delegate: Cell {
            id: itemCell
            required property var modelData

            height: root.height
            standalone: true
            hovered: itemHover.containsMouse

            IconImage {
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: Theme.fontSize.body
                source: itemCell.modelData.icon
            }

            MouseArea {
                id: itemHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        itemCell.modelData.activate();
                    } else if (mouse.button === Qt.MiddleButton) {
                        itemCell.modelData.secondaryActivate();
                    } else if (mouse.button === Qt.RightButton && itemCell.modelData.hasMenu) {
                        contextMenu.anchor.item = itemCell;
                        contextMenu.menu = itemCell.modelData.menu;
                        contextMenu.open();
                    }
                }
            }
        }
    }

    Cell {
        id: overflowCell
        visible: root._overflowing
        height: root.height
        standalone: true
        hovered: overflowHover.containsMouse

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (TrayService.drawerExpanded ? "−" : "+") + root._overflowCount
            color: overflowCell.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }

        MouseArea {
            id: overflowHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: TrayService.toggleDrawer()
        }
    }
}
