import QtQuick
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.Core
import qs.Components

// Bar region for the SNI tray (DESIGN.md §Bar, spec §Surfaces-1, M10 Task 1).
// Quickshell.Services.SystemTray both hosts and watches
// org.kde.StatusNotifierWatcher once referenced (its own module doc: merely
// referencing the singleton "will make quickshell start tracking system
// tray contents"), so every real StatusNotifierItem registered on the
// session bus shows up in .items with no extra wiring on our end. Each item
// renders as its own standalone Cell, left click Activate()s it, middle
// click SecondaryActivate()s it, right click opens its DBusMenu when
// item.hasMenu is true. Items whose onlyMenu flag is set (SNI ItemIsMenu:
// "activation will do nothing") get the menu on left click too.
//
// M32: the menu itself is TrayMenu.qml (`menu` below, one shared instance
// wired in from shell.qml/Bar.qml), a shell-owned QsMenuOpener surface,
// not the old QsMenuAnchor/native-QMenu path this file used to open
// directly. That native QMenu was also an xdg_popup with its own
// keyboard+pointer grab (platformmenu.cpp); Hyprland's grab code never adds
// the layer-shell parent to the grab's accept set on the path Qt takes to
// map it (`m_parent` stays null, XDGShell.cpp), and its popup grab is
// pointer+keyboard rather than keyboard-only, so a click anywhere outside
// the accept set, including the tray icon's own pixmap, inside the same
// Cell's hit area the surrounding padding shares, tore the grab down and
// closed the menu instantly (the same shell worked before the owner's hosts
// moved to Hyprland, 2026-08-17). A
// layer-shell popout takes no such grab, so this class of bug is gone by
// construction rather than patched.
// Hidden entirely (Row.implicitWidth is naturally 0 with an empty Repeater)
// when nothing has registered, never an empty box.
//
// Spec deviation, owner's call (M24, the same class as the `panel` IPC
// addendum): spec §Surfaces-1 says "SNI tray (grouped drawer)", and this
// file used to cap the strip at four cells with a "+N" chevron the rest
// collapsed behind. There is no drawer here now, and no per-item
// pinned/drawer/hidden split either (M23's buckets, removed the day after
// they shipped). Bounding the strip moved up one altitude, to the bar's own
// chevron widget (ChevronWidget.qml): a user with a large tray puts
// `chevron` on the far side of `tray` from that region's anchored edge
// (after it in the right region, before it in the other two) and the whole
// tray collapses behind it along with everything else on that side, which
// generalizes the protection the 4-item limit gave rather than dropping it.
// Two chevrons on one bar (this file's own and the bar's) is what made
// the affordance ambiguous in the first place.
Rail {
    id: root

    // The shared TrayMenu instance (shell.qml, wired through Bar.qml same
    // as every other panel property), null is a valid state (menu never
    // opened this session), openMenu() below just no-ops rather than crash.
    property var menu: null

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity. `.values` is read here for the count alone, never
    // as a model (a fresh JS array snapshot on every read, per Quickshell's
    // own ObjectModel docs; see the Repeater below for why that matters).
    readonly property bool shown: SystemTray.items.values.length > 0

    // Bar.qml sets these on the widget it loads; this rail is not a Cell
    // itself, so it hands them to each cell it holds (DESIGN.md §3 Bar).
    property bool ghost: false
    property string barEdge: ""

    // The rail follows the bar: a column on a left or right bar, where
    // Bar.qml's region delegate sizes it across the strip by width rather
    // than height.
    vertical: root.barEdge === "left" || root.barEdge === "right"
    spacing: Theme.space.sm
    visible: root.shown

    function openMenu(cell) {
        if (root.menu)
            root.menu.openItem(cell, cell.modelData);
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
    // anything.
    Repeater {
        model: SystemTray.items

        delegate: Cell {
            id: itemCell
            required property var modelData

            ghost: root.ghost
            barEdge: root.barEdge

            // Bar.qml's region delegate stretches this rail to the bar's
            // shared cell thickness, and a positioner manages position,
            // never size, so the cell's own icon-only content would
            // otherwise measure shorter than that. It binds to the rail's
            // own forced extent (`root` here IS the rail Bar.qml
            // stretches), not `Theme.barThickness`, which routes back
            // through the same implicit-size chain Bar.qml measures this
            // rail by; Workspaces.qml's fix is the same.
            width: root.vertical ? root.width : implicitWidth
            height: root.vertical ? implicitHeight : root.height
            // The item's own words, in the SNI's own order of preference:
            // ToolTip.title is what the spec means for hover text, Title is
            // the display name, and Id is the last thing that is always set.
            // Nothing here is ours to rewrite, hence `tooltipVerbatim`, which
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

            interactive: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
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
