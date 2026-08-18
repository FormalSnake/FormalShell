import QtQuick
import Quickshell
import qs.Core
import qs.Components

// The shell-owned tray context menu (M32, replacing Tray.qml's old
// QsMenuAnchor/native-QMenu path — see that file's own header for the
// Hyprland grab bug that made this necessary). Composes Panel.qml rather
// than duplicating its frame: one instance, opened per tray item via
// openItem(cell, item), so it gets the card gutters (§1.3), dog-ear
// (§2.7) and title band (§2.9, naming the tray item) for free, exactly
// like every other popout.
//
// Driven by Quickshell.QsMenuOpener over the item's own DBusMenuHandle
// (item.menu) — ground-truthed against the pinned quickshell source
// (src/core/qsmenu.hpp, src/dbus/dbusmenu/dbusmenu.cpp): assigning a
// QsMenuHandle to QsMenuOpener.menu refs it, which for a DBusMenuHandle
// triggers AboutToShow(0) + GetLayout(0, -1, []) once and loads the
// *entire* subtree eagerly (GetLayout's recursive depth argument is
// effectively ignored by our own root ref — every descendant inherits
// mShowChildren=true from its parent at creation), not per-submenu-open.
// A `QsMenuEntry` is itself a `QsMenuHandle` (its own `menu()` override
// returns itself), so a second QsMenuOpener bound to a hasChildren entry
// reads its already-populated children synchronously — no second D-Bus
// round trip. Submenus expand in place (indented rows) rather than
// spawning cascade popups: `_expanded` tracks which entries are open,
// `_openerFor()` lazily creates one QsMenuOpener per expanded entry
// (destroyed on collapse/close), and `_flatten()` walks the tree into one
// ledger list every render. One surface, no nested popup grabs — the
// entire point of this milestone.
Panel {
    id: root

    panelTitle: root._title
    panelWidth: Theme.space.popupWidthDefault

    // The tray item's own DBusMenuHandle (SNI item.menu) — null while
    // closed, so QsMenuOpener drops every ref'd DBusMenuItem the instant
    // the surface closes rather than polling a menu nobody can see.
    property var menuHandle: null
    property string _title: ""
    // JS array of QsMenuEntry refs currently expanded (submenu rows shown
    // indented beneath their parent) and the {entry, opener} pairs backing
    // them — a plain array, not a model: nothing here renders directly off
    // it, `_rows` (rebuilt into a fresh array on every change) is what the
    // Repeater below binds to.
    property var _expanded: []
    property var _subOpeners: []
    property var _rows: []
    property int _cursor: -1

    function openItem(cell, item) {
        root._title = item.tooltipTitle || item.title || item.id;
        root._collapseAll();
        root._cursor = -1;
        root.menuHandle = item.menu;
        if (cell)
            root.openFrom(cell);
        else
            root.open();
    }

    onIsOpenChanged: {
        if (!root.isOpen) {
            root.menuHandle = null;
            root._collapseAll();
            root._cursor = -1;
            root._rows = [];
        }
    }

    function _collapseAll() {
        for (var i = 0; i < root._subOpeners.length; i++)
            root._subOpeners[i].opener.destroy();
        root._subOpeners = [];
        root._expanded = [];
    }

    function _openerFor(entry) {
        for (var i = 0; i < root._subOpeners.length; i++)
            if (root._subOpeners[i].entry === entry)
                return root._subOpeners[i].opener;
        var op = subOpenerComponent.createObject(root, { menu: entry });
        op.childrenChanged.connect(root._rebuildRows);
        root._subOpeners = root._subOpeners.concat([{ entry: entry, opener: op }]);
        return op;
    }

    function _collapseEntry(entry) {
        for (var i = root._subOpeners.length - 1; i >= 0; i--) {
            if (root._subOpeners[i].entry === entry) {
                root._subOpeners[i].opener.destroy();
                root._subOpeners.splice(i, 1);
            }
        }
    }

    function _toggle(entry) {
        var idx = root._expanded.indexOf(entry);
        if (idx >= 0) {
            root._expanded = root._expanded.slice(0, idx).concat(root._expanded.slice(idx + 1));
            root._collapseEntry(entry);
        } else {
            root._expanded = root._expanded.concat([entry]);
            root._openerFor(entry);
        }
        root._rebuildRows();
    }

    function _flatten(opener, depth, out) {
        var kids = opener && opener.children ? opener.children.values : [];
        for (var i = 0; i < kids.length; i++) {
            var e = kids[i];
            out.push({ entry: e, depth: depth });
            if (e.hasChildren && root._expanded.indexOf(e) !== -1)
                root._flatten(root._openerFor(e), depth + 1, out);
        }
    }

    function _rebuildRows() {
        var out = [];
        root._flatten(rootOpener, 0, out);
        root._rows = out;
        if (root._cursor < 0 || root._cursor >= root._rows.length)
            root._cursor = root._rows.length > 0 ? 0 : -1;
    }

    function _activate(entry) {
        if (!entry || entry.isSeparator || !entry.enabled)
            return;
        if (entry.hasChildren) {
            root._toggle(entry);
            return;
        }
        entry.triggered();
        root.close();
    }

    // IPC-safe standins for the real Down/Up/Enter keys above (TrayIpc.qml's
    // `menucursor <delta>`/`menuactivate`) — the same division the
    // picker's `choose`/`variant` verbs already draw (their own header:
    // "independent of real keyboard/pointer delivery... the same division
    // every other surface's actions already use in the smoke rig"), needed
    // here because this popout is IPC-opened with no bar cell (openItem's
    // `cell` is null over IPC), so it never receives real focus in a rig
    // with no synthetic pointer or working key delivery into an
    // IPC-triggered OnDemand layer surface.
    function moveCursor(delta) {
        root.cursorActive = true;
        root._moveCursor(delta);
    }

    function activateCursor() {
        if (root._cursor >= 0 && root._cursor < root._rows.length)
            root._activate(root._rows[root._cursor].entry);
    }

    // Skips separator rows (an inverted/hovered hairline reads as broken
    // chrome); disabled rows stay reachable, same as most native menus —
    // `_activate` is what refuses them.
    function _moveCursor(delta) {
        if (root._rows.length === 0) {
            root._cursor = -1;
            return;
        }
        var idx = root._cursor < 0 ? (delta > 0 ? -1 : 0) : root._cursor;
        for (var i = 0; i < root._rows.length; i++) {
            idx = (idx + delta + root._rows.length) % root._rows.length;
            if (!root._rows[idx].entry.isSeparator)
                break;
        }
        root._cursor = idx;
    }

    QsMenuOpener {
        id: rootOpener
        menu: root.menuHandle
    }

    Connections {
        target: rootOpener
        function onChildrenChanged() { root._rebuildRows(); }
    }

    Component {
        id: subOpenerComponent
        QsMenuOpener {}
    }

    // Panel.qml's shared keyboard-nav hook (M6 Task 7): first Up/Down only
    // reveals the cursor where `_rebuildRows()` already parked it (M26
    // Task 8's reveal-not-move idiom, AirpodsPanel.qml's own consumer
    // pattern), Enter activates it, Escape is Panel's own default (close).
    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen)
                return;
            if (!root.cursorActive && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                root.cursorActive = true;
                event.accepted = true;
                return;
            }
            switch (event.key) {
            case Qt.Key_Up:
                root._moveCursor(-1);
                event.accepted = true;
                break;
            case Qt.Key_Down:
                root._moveCursor(1);
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (root._cursor >= 0 && root._cursor < root._rows.length)
                    root._activate(root._rows[root._cursor].entry);
                event.accepted = true;
                break;
            }
        }
    }

    Cell {
        visible: root.isOpen && root._rows.length === 0
        width: parent.width

        MetaLabel { text: "EMPTY MENU" }
    }

    Repeater {
        model: root._rows

        delegate: Item {
            id: rowWrap
            required property var modelData
            required property int index
            readonly property var entry: rowWrap.modelData.entry
            readonly property int depth: rowWrap.modelData.depth
            readonly property real _availWidth: rowCell.width - Theme.space.controlPaddingX * 2 - Theme.borderWidth
                - rowWrap.depth * Theme.space.xxl
                - (trailingGlyph.visible ? trailingGlyph.implicitWidth + Theme.space.labelGap : 0)
                - (iconImg.visible ? iconImg.width + Theme.space.labelGap : 0)

            width: parent.width
            height: rowWrap.entry.isSeparator ? Theme.borderWidth : rowCell.height

            Rectangle {
                visible: rowWrap.entry.isSeparator
                anchors.fill: parent
                color: Theme.color.rule
            }

            Cell {
                id: rowCell
                visible: !rowWrap.entry.isSeparator
                width: parent.width
                // Checkable state as the selected fill (accent inversion,
                // DESIGN.md §2.2) — same fill the cursor row uses, per the
                // M32 plan's own constraint; a checked+cursor row is still
                // just the one inversion, never a double treatment.
                selected: (root.cursorActive && root._cursor === rowWrap.index) || rowWrap.entry.checkState === Qt.Checked
                interactive: rowWrap.entry.enabled
                hovered: root.cursorActive && root._cursor === rowWrap.index
                onContainsPointerChanged: if (rowCell.containsPointer) {
                    root.cursorActive = true;
                    root._cursor = rowWrap.index;
                }

                Image {
                    id: iconImg
                    anchors.left: parent.left
                    anchors.leftMargin: rowWrap.depth * Theme.space.xxl
                    anchors.verticalCenter: parent.verticalCenter
                    visible: rowWrap.entry.icon !== ""
                    source: rowWrap.entry.icon || ""
                    width: Theme.fontSize.body
                    height: Theme.fontSize.body
                    sourceSize.width: Theme.fontSize.body
                    sourceSize.height: Theme.fontSize.body
                }

                Text {
                    anchors.left: iconImg.visible ? iconImg.right : parent.left
                    anchors.leftMargin: iconImg.visible ? Theme.space.labelGap : rowWrap.depth * Theme.space.xxl
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, rowWrap._availWidth)
                    elide: Text.ElideRight
                    text: rowWrap.entry.text
                    color: rowWrap.entry.enabled ? rowCell.foreground : Theme.color.foregroundFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                Text {
                    id: trailingGlyph
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: rowWrap.entry.hasChildren
                    text: root._expanded.indexOf(rowWrap.entry) !== -1 ? "▾" : "▸"
                    color: rowCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                onClicked: root._activate(rowWrap.entry)
            }
        }
    }
}
