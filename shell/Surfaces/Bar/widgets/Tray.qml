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

    // Bound to the live ObjectModel itself, not a `.values` snapshot slice:
    // `.values` returns a fresh array on every read (Quickshell's own
    // docs), and Quickshell re-notifies it far more often than the item set
    // actually changes (observed in-VM: a static 6-item tray still saw each
    // delegate destroyed and recreated 4-7 times over one run). A
    // plain-array `Repeater.model` treats every new array as a full reset,
    // so the DitherImage icons below kept losing their Canvas mid-decode
    // before a single frame ever painted — every pinned cell rendered
    // blank. The live model gives Repeater real add/remove diffing instead,
    // so a delegate (and its Canvas) survives an upstream re-notify that
    // didn't actually add or remove anything. Collapsing to the pinned
    // count now happens per-delegate via `index` (Row skips invisible
    // children) rather than by slicing the model.
    Repeater {
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

            // M20 Task 5 (owner: tray icons "often look invisible in light
            // mode" — third-party SNI marks are frequently white/light
            // symbolic glyphs drawn for a dark bar). DitherImage's alpha-mask
            // mode reads the icon's own alpha channel instead of its RGB, so
            // the vendor's colors are discarded and every icon becomes a 1-bit
            // silhouette in the cell's own ink — legible against any theme.
            // Slot pinned to `Theme.fontSize.body`, the same existing token
            // the old IconImage used, but bound to explicit width/height
            // rather than `implicitSize` alone: quickshell's own IconImage
            // docs note implicitSize only seeds implicitWidth/implicitHeight,
            // it does not itself constrain the rendered size, which is why
            // SNI's native 16/22/24px pixmaps were varying the cell's padding
            // rhythm.
            //
            // Feeding `modelData.icon` straight into DitherImage's own hidden
            // Image (as every other DitherImage caller does) doesn't work
            // for SNI items that only carry an `IconPixmap` (no icon-theme
            // name — exactly `dev/sni-stub.py`'s fixture shape, and real
            // apps like Discord/Steam do the same): Quickshell serves those
            // through its own `image://qspixmap/…` provider, and
            // `Canvas.drawImage()` reads back nothing but transparent black
            // from it even once `Image.status` is `Ready` — ground-truthed
            // in-VM (a temporary `getImageData` probe on the paint), not a
            // qmltestrunner guess. A plain icon-theme-name source
            // (ActiveWindow.qml's own `Quickshell.iconPath()` path) doesn't
            // hit this; only the SNI pixmap provider does. `rawIcon` renders
            // the pixmap the normal way (proven correct — this is exactly
            // the pre-Task-5 IconImage path), invisible, and `grabToImage()`
            // (the same escape hatch
            // AnimatedAlbumArt.qml already uses for its own unreadable-by-
            // Canvas source, a real Video) hands DitherImage a grab result
            // it CAN read instead.
            IconImage {
                id: rawIcon
                anchors.verticalCenter: parent.verticalCenter
                visible: false
                asynchronous: true
                implicitSize: Theme.fontSize.body
                source: itemCell.modelData.icon
                onStatusChanged: {
                    if (status === Image.Ready)
                        grabToImage(function (result) { icon.source = result.url; });
                }
            }

            DitherImage {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize.body
                height: Theme.fontSize.body
                mode: "mask"
                darkColor: itemCell.invertedNow ? Theme.inverted().fg : Theme.color.foreground
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
