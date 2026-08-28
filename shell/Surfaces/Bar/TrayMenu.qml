import QtQuick
import Quickshell
import qs.Core
import qs.Components

// The shell-owned tray context menu (M32, replacing Tray.qml's old
// QsMenuAnchor/native-QMenu path, see that file's own header for the
// Hyprland grab bug that made this necessary). Composes Panel.qml rather
// than duplicating its frame: one instance, opened per tray item via
// openItem(cell, item), so the anchoring, the click-outside dismiss, the
// keyboard priming and the header naming the tray item all come for free,
// exactly like every other popout. Only the frame's own fill and corner
// differ, since this one is a menu (M43 D6).
//
// Driven by Quickshell.QsMenuOpener over the item's own DBusMenuHandle
// (item.menu), ground-truthed against the pinned quickshell source
// (src/core/qsmenu.hpp, src/dbus/dbusmenu/dbusmenu.cpp): assigning a
// QsMenuHandle to QsMenuOpener.menu refs it, which for a DBusMenuHandle
// triggers AboutToShow(0) + GetLayout(0, -1, []) once and loads the
// *entire* subtree eagerly (GetLayout's recursive depth argument is
// effectively ignored by our own root ref, every descendant inherits
// mShowChildren=true from its parent at creation), not per-submenu-open.
// A `QsMenuEntry` is itself a `QsMenuHandle` (its own `menu()` override
// returns itself), so a second QsMenuOpener bound to a hasChildren entry
// reads its already-populated children synchronously, no second D-Bus
// round trip. Submenus expand in place (indented rows) rather than
// spawning cascade popups: `_expanded` tracks which entries are open,
// `_openerFor()` lazily creates one QsMenuOpener per expanded entry
// (destroyed on collapse/close), and `_flatten()` walks the tree into one
// ledger list every render. One surface, no nested popup grabs, the
// entire point of this milestone.
Panel {
    id: root

    panelTitle: root._title
    panelWidth: Theme.space.popupWidthDefault
    // A menu, not a panel (M43 D6): the `popover` fill at `radiusMd`, the
    // same frame the tooltip takes, rather than the `card` at `radiusXl`
    // every widget popout wears.
    frameColor: Theme.surface(Theme.color.popover)
    frameRadius: Theme.radiusMd

    // The tray item's own DBusMenuHandle (SNI item.menu), null while
    // closed, so QsMenuOpener drops every ref'd DBusMenuItem the instant
    // the surface closes rather than polling a menu nobody can see.
    property var menuHandle: null
    property string _title: ""
    // JS array of QsMenuEntry refs currently expanded (submenu rows shown
    // indented beneath their parent) and the {entry, opener} pairs backing
    // them, a plain array, not a model: nothing here renders directly off
    // it, `_rows` (rebuilt into a fresh array on every change) is what the
    // Repeater below binds to.
    property var _expanded: []
    property var _subOpeners: []
    property var _rows: []
    property int _cursor: -1

    // `owner` is the popout the cell lives in, if it lives in one: the tray's
    // second bar passes itself, so this menu opens over that bar instead of
    // replacing it (Panel.qml's `owner`). A cell on the bar strip passes
    // nothing and this menu takes the slot outright, as every popout does.
    function openItem(cell, item, owner) {
        root._title = item.tooltipTitle || item.title || item.id;
        root._collapseAll();
        root._cursor = -1;
        root.menuHandle = item.menu;
        root.owner = owner !== undefined ? owner : null;
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
    // `menucursor <delta>`/`menuactivate`), the same division the
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
    // chrome); disabled rows stay reachable, same as most native menus,
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

    // One column at the Column type's own zero spacing, not the panel
    // content slot's `sectionGap`: this is a menu list, so its rows abut
    // exactly like the launcher's do.
    Column {
        width: parent.width

        Item {
            visible: root.isOpen && root._rows.length === 0
            width: parent.width
            height: Theme.space.controlHeight

            SectionLabel {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Empty menu"
            }
        }

        Repeater {
            model: root._rows

            delegate: Item {
                id: rowWrap
                required property var modelData
                required property int index
                readonly property var entry: rowWrap.modelData.entry
                readonly property int depth: rowWrap.modelData.depth

                readonly property bool cursorHere: root.cursorActive && root._cursor === rowWrap.index
                readonly property bool hovered: pointer.containsMouse
                readonly property bool filled: rowWrap.cursorHere || rowWrap.hovered
                readonly property color foreground: !rowWrap.entry.enabled
                    ? Theme.color.mutedForeground
                    : (rowWrap.filled ? Theme.color.accentForeground : Theme.color.foreground)

                readonly property real _availWidth: rowWrap.width - Theme.space.controlPaddingX * 2
                    - rowWrap.depth * Theme.space.xxl
                    - (trailingIcon.visible ? trailingIcon.width + Theme.space.iconGap : 0)
                    - (iconImg.visible ? iconImg.width + Theme.space.iconGap : 0)

                width: parent.width
                height: rowWrap.entry.isSeparator
                    ? Theme.borderWidth + Theme.space.sm * 2
                    : Theme.space.controlHeight

                // A separator is one `border` rule with a `sm` gap either side
                // of it, which is the whole of its chrome.
                Rectangle {
                    visible: rowWrap.entry.isSeparator
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Theme.borderWidth
                    color: Theme.color.border
                }

                // The launcher's own row (M43 D6): square, borderless, the
                // cursor filled `accent` and a hovered row washed.
                Item {
                    id: row
                    anchors.fill: parent
                    visible: !rowWrap.entry.isSeparator

                    Rectangle {
                        anchors.fill: parent
                        visible: rowWrap.cursorHere
                        color: Theme.color.accent
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.hoverFill
                        opacity: (rowWrap.hovered && !rowWrap.cursorHere) ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                        }
                    }

                    MouseArea {
                        id: pointer
                        anchors.fill: parent
                        enabled: rowWrap.entry.enabled
                        hoverEnabled: rowWrap.entry.enabled
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            root.cursorActive = true;
                            root._cursor = rowWrap.index;
                        }
                        onClicked: root._activate(rowWrap.entry)
                    }

                    // The item's own icon, which the tray hands over as a
                    // pixmap rather than a name.
                    Image {
                        id: iconImg
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.space.controlPaddingX + rowWrap.depth * Theme.space.xxl
                        anchors.verticalCenter: parent.verticalCenter
                        asynchronous: true
                        visible: rowWrap.entry.icon !== ""
                        source: rowWrap.entry.icon || ""
                        width: Theme.fontSize.body
                        height: Theme.fontSize.body
                        sourceSize.width: Theme.fontSize.body
                        sourceSize.height: Theme.fontSize.body
                    }

                    Text {
                        anchors.left: iconImg.visible ? iconImg.right : parent.left
                        anchors.leftMargin: iconImg.visible
                            ? Theme.space.iconGap
                            : Theme.space.controlPaddingX + rowWrap.depth * Theme.space.xxl
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, rowWrap._availWidth)
                        elide: Text.ElideRight
                        text: rowWrap.entry.text
                        color: rowWrap.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                    }

                    // Checked and "has a submenu" never co-occur on one entry,
                    // so one slot carries both: a `check` for the first, the
                    // chevron the expansion state names for the second.
                    Icon {
                        id: trailingIcon
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.space.controlPaddingX
                        anchors.verticalCenter: parent.verticalCenter
                        visible: rowWrap.entry.hasChildren || rowWrap.entry.checkState === Qt.Checked
                        name: rowWrap.entry.hasChildren
                            ? (root._expanded.indexOf(rowWrap.entry) !== -1 ? "chevron-down" : "chevron-right")
                            : "check"
                        size: Theme.fontSize.body
                        color: rowWrap.foreground
                    }
                }
            }
        }
    }
}
