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
// "can be displayed with QsMenuAnchor or QsMenuOpener"). Items whose
// onlyMenu flag is set (SNI ItemIsMenu: "activation will do nothing") get
// the menu on left click too. QsMenuAnchor requires QApplication mode —
// shell.qml carries `//@ pragma UseQApplication` for exactly this — and
// renders a native-styled QMenu, not a shell-themed surface: quickshell's
// platform-menu path (core/platformmenu.cpp) owns that widget outright, so
// its styling is accepted as-is rather than half-rebuilding a menu
// renderer. Past a small
// visible count the rest collapse into one more Cell ("+N") that expands
// this row to reveal them too, instead of an unbounded strip of icons — the
// spec's "grouped drawer". Expand state lives in TrayService (shared, not
// local) so `qs ipc call tray expand` can drive it — this rig has no way to
// synthesize the pointer click that would otherwise be the only trigger.
// Hidden entirely (Row.implicitWidth is naturally 0 with an empty Repeater
// and no overflow cell) when nothing has registered — never an empty box.
Row {
    id: root

    // `.values` (used only for its length here, never as a model — see the
    // Repeater below) is a fresh JS array snapshot on every read, per
    // Quickshell's own ObjectModel docs.
    readonly property int _count: SystemTray.items.values.length
    readonly property int _visibleLimit: 4
    readonly property bool _overflowing: root._count > root._visibleLimit
    readonly property int _pinnedCount: root._overflowing ? root._visibleLimit - 1 : root._count
    readonly property int _overflowCount: root._count - root._pinnedCount
    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity.
    readonly property bool shown: root._count > 0

    spacing: Theme.space.sm
    visible: root.shown

    // Shared by every item cell below — right-clicking one just repoints
    // this at that cell and its menu handle rather than each delegate
    // owning its own anchor, since only one context menu is ever open.
    // Anchored to the cell's bottom-left expanding down-right, so the menu
    // drops under the bar cell instead of covering it (PopupAnchor's
    // default edges are Top|Left).
    QsMenuAnchor {
        id: contextMenu
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
    }

    function openMenu(cell) {
        if (contextMenu.visible)
            contextMenu.close();
        contextMenu.anchor.item = cell;
        contextMenu.menu = cell.modelData.menu;
        contextMenu.open();
    }

    // M20 Task 5d (owner: "auto close after an interval if no cursor is on
    // it anymore or no system tray menu is open"). `_rowHovered` is true
    // while the pointer sits over any pinned cell, expanded cell, or the
    // +N/-N toggle — read off the same `hovered`/containsMouse chrome each
    // cell already drives, not a new row-spanning MouseArea: `root` here IS
    // the Row, which manages every child's own x, so a background item
    // covering the full row can't take `anchors.fill: parent` without
    // fighting that layout, and hover already reaches nested MouseAreas
    // regardless of a parent's own hover state anyway. All items are read
    // unconditionally every evaluation (no early return) so the binding
    // stays subscribed to every delegate's `hovered`, not just the first.
    readonly property bool _rowHovered: {
        var any = false;
        for (var i = 0; i < trayRepeater.count; i++) {
            var item = trayRepeater.itemAt(i);
            if (item && item.hovered)
                any = true;
        }
        return any || overflowCell.hovered;
    }

    TrayCollapseGate {
        id: collapseGate
    }

    on_RowHoveredChanged: {
        if (root._rowHovered)
            collapseGate.rowEntered();
        else
            collapseGate.rowExited();
    }

    Connections {
        target: contextMenu
        function onVisibleChanged() {
            if (contextMenu.visible)
                collapseGate.menuOpened();
            else
                collapseGate.menuClosed();
        }
    }

    Connections {
        target: TrayService
        function onDrawerExpandedChanged() {
            if (TrayService.drawerExpanded)
                collapseGate.freshExpansion();
            else
                collapseGate.collapsed();
        }
    }

    // `interval` is `Theme.motion.rotatePeriod`, the existing ~3s pacing
    // token PowerPanel.qml's own phrase rotation uses — but unlike that
    // caller, `running` does NOT also gate on `Theme.motionEnabled`:
    // auto-collapse is behavior, not animation, and tokens.js's own
    // `motionTokens()` never zeroes `rotatePeriod` in the first place (only
    // fast/standard/reveal shrink to 0 when motion is disabled), so the
    // token already carries a real cadence either way. Also requires
    // `TrayService.drawerExpanded` directly rather than trusting the gate's
    // own reset alone, so there's no one-tick window where a just-collapsed
    // drawer's timer could still be seen running.
    Timer {
        id: collapseTimer
        interval: Theme.motion.rotatePeriod
        running: TrayService.drawerExpanded && collapseGate.armed
        repeat: false
        onTriggered: TrayService.collapseDrawer()
    }

    // Bound to the live ObjectModel itself, not a `.values` snapshot slice:
    // `.values` returns a fresh array on every read (Quickshell's own
    // docs), and Quickshell re-notifies it far more often than the item set
    // actually changes (observed in-VM: a static 6-item tray still saw each
    // delegate destroyed and recreated 4-7 times over one run). A
    // plain-array `Repeater.model` treats every new array as a full reset,
    // so each icon's async load kept restarting mid-decode before a single
    // frame ever painted, every pinned cell rendered blank. The live model
    // gives Repeater real add/remove diffing instead, so a delegate
    // survives an upstream re-notify that didn't actually add or remove
    // anything. Collapsing to the pinned count now happens per-delegate via
    // `index` (Row skips invisible children) rather than by slicing the
    // model.
    Repeater {
        id: trayRepeater
        model: SystemTray.items

        delegate: Cell {
            id: itemCell
            required property var modelData
            required property int index

            // Bar.qml's region delegate stretches this Row to the bar's
            // shared cell height; the Row top-aligns children, so without
            // this the shorter icon cells sit visibly high (Row permits
            // vertical anchors on children — it only manages x).
            anchors.verticalCenter: parent.verticalCenter
            // Same Row (`root` here IS the Row Bar.qml stretches) only
            // manages x, never size, so the cell's own icon-only content
            // would otherwise measure shorter than the bar's shared height
            // — see Workspaces.qml's identical fix for why this binds to
            // `root.height` (the externally forced value) and not
            // `Theme.barHeight` (which routes back through the same
            // implicitHeight chain Bar.qml measures this Row by).
            height: root.height
            visible: itemCell.index < root._pinnedCount || TrayService.drawerExpanded
            standalone: true
            hovered: itemHover.containsMouse
            // The item's own words, in the SNI's own order of preference:
            // ToolTip.title is what the spec means for hover text, Title is
            // the display name, and Id is the last thing that is always set.
            // Nothing here is ours to rewrite — hence `tooltipVerbatim`, which
            // keeps the card from uppercasing another process's string.
            tooltipText: itemCell.modelData.tooltipTitle || itemCell.modelData.title || itemCell.modelData.id
            tooltipVerbatim: true

            // M20 Task 5 shipped an alpha-mask 1-bit silhouette here (owner:
            // tray icons "often look invisible in light mode", third-party
            // SNI marks are frequently white/light symbolic glyphs drawn for
            // a dark bar). The owner ran real vendor icons in a live session
            // and rejected the treatment ("deep fried") 2026-08-09, reverted
            // to true color; light-mode invisibility is an open problem
            // again (DESIGN.md §2 item 12).
            //
            // The fixed square slot stays: bound to explicit width/height
            // rather than `implicitSize` alone, since quickshell's own
            // IconImage docs note implicitSize only seeds
            // implicitWidth/implicitHeight, it does not itself constrain the
            // rendered size, which is why SNI's native 16/22/24px pixmaps
            // were varying the cell's padding rhythm before M20 Task 5's
            // slot normalization.
            IconImage {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                asynchronous: true
                smooth: false
                width: Theme.fontSize.body
                height: Theme.fontSize.body
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
                        if (itemCell.modelData.onlyMenu && itemCell.modelData.hasMenu)
                            root.openMenu(itemCell);
                        else
                            itemCell.modelData.activate();
                    } else if (mouse.button === Qt.MiddleButton) {
                        itemCell.modelData.secondaryActivate();
                    } else if (mouse.button === Qt.RightButton && itemCell.modelData.hasMenu) {
                        root.openMenu(itemCell);
                    }
                }
            }
        }
    }

    Cell {
        id: overflowCell
        anchors.verticalCenter: parent.verticalCenter
        height: root.height
        visible: root._overflowing
        standalone: true
        hovered: overflowHover.containsMouse
        tooltipText: TrayService.drawerExpanded
            ? "TRAY / HIDE " + root._overflowCount
            : "TRAY / SHOW " + root._overflowCount + " MORE"

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (TrayService.drawerExpanded ? "−" : "+") + root._overflowCount
            color: overflowCell.foreground
            font.family: Theme.fontFamily
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
