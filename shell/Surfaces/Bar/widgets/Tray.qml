import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.Core
import qs.Components
import qs.Compositor
import qs.Services
import "../../../Tray/model.js" as TrayModel

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
//
// Which item lands where is the M23 Task 3 bucket split (shell/Tray/model.js,
// TrayService's own resolved arrays): a pinned id is always on the bar, a
// hidden id is drawn nowhere at all, and everything else keeps the
// positional "first N are visible" ordering described above. The chevron
// cell is drawn for any registered item now, not only for an overflowing
// one, because right-clicking it is the manage popup's only affordance; it
// still carries the +N/-N count whenever the drawer holds anything.
Row {
    id: root

    // `.values` (read here for the ids and the count, never used as a
    // model, see the Repeater below) is a fresh JS array snapshot on every
    // read, per Quickshell's own ObjectModel docs.
    readonly property var _ids: SystemTray.items.values.map(function (item) { return item.id; })
    readonly property int _count: root._ids.length
    // The pinned/drawer/hidden split (M23 Task 3). Every ordering rule,
    // the chevron's own reserved slot included, lives in the pure module
    // rather than in arithmetic here, and with both override arrays empty
    // it reproduces the _pinnedCount/_overflowCount arithmetic this block
    // used to carry inline, so an unconfigured tray renders exactly as it
    // did before the buckets existed.
    readonly property var _buckets: TrayModel.buckets(root._ids, TrayService.pinned, TrayService.hidden, TrayService.visibleLimit)
    readonly property int _drawerCount: root._buckets.drawer.length
    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity.
    //
    // Counts every registered item, hidden ones included: a tray whose items
    // are all hidden still renders its chevron, because right-clicking that
    // chevron is the only way back to the popup that hid them.
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
        function onManageOpenChanged() {
            root._syncManagePanel();
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

    // The bucket manager (M23 Task 3), reached by right-clicking the chevron
    // below. One Components/Panel per bar rather than the single shell.qml
    // instance every other popout gets, since the tray owns no file outside
    // this one. It costs nothing until it opens: a Panel leaves its window
    // unmapped for as long as `isOpen` is false.
    TrayManagePanel {
        id: managePanel
    }

    // Only the bar on the focused output answers a summon. TrayService.
    // manageOpen is one shared flag for every screen's Tray (the same reason
    // drawerExpanded is shared: `qs ipc call tray manage open` has no
    // per-screen instance to reach), and Panel.qml puts its surface on the
    // focused output regardless of which bar asked, so without this gate a
    // second monitor's copy would map an identical layer surface on top of
    // the first, and each would close the other back down through
    // PanelRegistry's mutual exclusion.
    readonly property bool _onFocusedOutput: {
        var window = root.QsWindow.window;
        if (!window || !window.screen)
            return false;
        // Resolved exactly the way Panel.qml resolves its own `screen`,
        // fallback included: the output the compositor names as focused, or
        // the first screen when it names one we don't have. The fallback is
        // load-bearing, not defensive: a session that has focused nothing
        // yet reports no output name at all (a fresh nested compositor with
        // no windows in it, which is precisely what the smoke rig boots), and
        // a bare name comparison would then match no bar and open nothing.
        var screens = Quickshell.screens;
        var target = screens.length > 0 ? screens[0] : null;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === CompositorService.focusedOutputName)
                target = screens[i];
        }
        return target !== null && target.name === window.screen.name;
    }

    function _syncManagePanel() {
        if (TrayService.manageOpen && root._onFocusedOutput)
            managePanel.open(overflowCell.mapToItem(null, 0, 0).x);
        else if (managePanel.isOpen)
            managePanel.close();
    }

    // Escape, a click outside, and another popout taking the registry slot
    // all close the Panel directly, so the shared flag has to follow it back
    // down, or the next summon would write a value that never changed and
    // nothing would react to it.
    Connections {
        target: managePanel
        function onIsOpenChanged() {
            if (!managePanel.isOpen && TrayService.manageOpen)
                TrayService.closeManage();
        }
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

            // Where this item renders, keyed by its own id rather than by
            // `index`, now that the split is an override on top of the
            // ordering rather than the ordering itself: a hidden item stays
            // hidden even while the drawer is expanded, which no positional
            // test can express. Two items publishing the same SNI id share
            // one bucket and therefore one answer here; see Tray/model.js's
            // header for why that identity is the one available.
            readonly property bool _inVisible: root._buckets.visible.indexOf(itemCell.modelData.id) >= 0
            readonly property bool _inDrawer: root._buckets.drawer.indexOf(itemCell.modelData.id) >= 0

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
            visible: itemCell._inVisible || (itemCell._inDrawer && TrayService.drawerExpanded)
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
        // Shown for any registered item, not only for an overflowing one:
        // the chevron is the manage popup's only affordance, so a tray that
        // fits (or one whose items are all hidden) still needs it.
        visible: root.shown
        standalone: true
        hovered: overflowHover.containsMouse
        tooltipText: root._drawerCount === 0
            ? "TRAY / MANAGE"
            : TrayService.drawerExpanded
                ? "TRAY / HIDE " + root._drawerCount
                : "TRAY / SHOW " + root._drawerCount + " MORE"

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // A bare chevron (U+F0140, nf-md-chevron_down, checked against
            // the pinned Nerd Font's own cmap per DESIGN.md's literal-
            // character rule) when the drawer holds nothing: the cell is
            // still here for the manage popup a right-click opens, and "+0"
            // would be a count of nothing.
            text: root._drawerCount === 0
                ? "󰅀"
                : (TrayService.drawerExpanded ? "−" : "+") + root._drawerCount
            color: overflowCell.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }

        MouseArea {
            id: overflowHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            // Right-click opens the bucket manager, the same split omarchy's
            // own chevron uses. Left-click stays the drawer toggle it has
            // always been, so nothing a user already knows changed meaning.
            // With an empty drawer there is nothing to toggle, and a cell
            // that renders a cursor but answers no click reads as broken, so
            // that one case falls through to the manager instead.
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton || root._drawerCount === 0)
                    TrayService.toggleManage();
                else
                    TrayService.toggleDrawer();
            }
        }
    }
}
