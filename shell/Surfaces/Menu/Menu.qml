import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import "../../Menu/model.js" as Model
import "../../Menu/search.js" as Search

// The unified menu (DESIGN.md §Concrete translations/Menu): a single
// keyboard-exclusive top-layer window, centered on the focused output. Top
// cell is the search field (breadcrumb as its meta row); below it, rows are
// either search.rank() matches (query non-empty) or model.visibleChildren()
// of the current level (query empty). Whole-tree search, cursor wraps,
// Escape/backspace-on-empty pop one level, confirm-gated actions need a
// second Enter.
//
// _placeholderDefault below is a stand-in tree so this surface is testable
// on its own; Task 6 replaces it with the real default-menu.jsonc + user
// menu.jsonc + providers.js (apps, custom power buttons from Config).
PanelWindow {
    id: root

    property bool isOpen: false
    property var currentNodeId: null
    property int _cursorIndex: 0
    property string _confirmPendingId: ""
    property var _condResults: ({})
    property var _checkedResults: ({})

    readonly property var _placeholderDefault: ({
        "system": { label: "System" },
        "system.lock": { label: "Lock", action: "true", when: "true" },
        "system.power": { label: "Power" },
        "system.power.suspend": { label: "Suspend", action: "true" },
        "system.power.reboot": { label: "Reboot", action: "true", confirm: true },
        "system.power.shutdown": { label: "Shutdown", action: "true", confirm: true },
        "theme": { label: "Theme" },
        "theme.toggle-mode": { label: "Toggle Mode", action: "true", checked: "true" }
    })
    readonly property var _tree: Model.buildTree(root._placeholderDefault, {})
    readonly property var _nodes: root._tree.nodes

    readonly property var _displayRows: {
        var q = searchInput.text;
        return q.length > 0
            ? Search.rank(root._nodes, q, root._condResults)
            : Model.visibleChildren(root._nodes, root.currentNodeId, root._condResults);
    }

    readonly property string breadcrumb: {
        var parts = [];
        var id = root.currentNodeId;
        while (id !== null && root._nodes[id]) {
            parts.unshift(root._nodes[id].label);
            id = root._nodes[id].parentId;
        }
        return ["MENU"].concat(parts).join(" / ");
    }

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }
    readonly property real _maxTotalHeight: root._screen ? root._screen.height * 0.6 : 400
    readonly property real _rowsAreaHeight: Math.min(rowsView.contentHeight, Math.max(0, root._maxTotalHeight - Theme.borderWidth - searchCell.height))

    function open(route) {
        var target = null;
        var resolved = route ? root._resolveRoute(route) : null;
        var node = resolved ? root._nodes[resolved] : null;
        if (node) {
            if (node.kind === "submenu" || node.kind === "provider")
                target = node.id;
            else if (node.kind === "link")
                target = (node.target && root._nodes[node.target]) ? node.target : node.id;
        }
        root._enterLevel(target);
        root.isOpen = true;
        Qt.callLater(function () { searchInput.forceActiveFocus(); });
    }

    function close() {
        root.isOpen = false;
        root._confirmPendingId = "";
    }

    function _resolveRoute(route) {
        if (root._nodes[route]) return route;
        var ids = Object.keys(root._nodes);
        for (var i = 0; i < ids.length; i++) {
            var n = root._nodes[ids[i]];
            if ((n.aliases || []).indexOf(route) >= 0) return n.id;
        }
        return null;
    }

    function _enterLevel(id) {
        root.currentNodeId = id;
        root._cursorIndex = 0;
        root._confirmPendingId = "";
        searchInput.text = "";
        root._evalLevelConditions();
    }

    function _pop() {
        if (root.currentNodeId === null) {
            root.close();
            return;
        }
        root._enterLevel(root._nodes[root.currentNodeId].parentId);
    }

    function _moveCursor(delta) {
        var n = root._displayRows.length;
        if (n === 0) return;
        root._cursorIndex = (root._cursorIndex + delta + n) % n;
        root._confirmPendingId = "";
    }

    function _setCursor(index) {
        if (index === root._cursorIndex) return;
        root._cursorIndex = index;
        root._confirmPendingId = "";
    }

    function _activateRow(index) {
        var rows = root._displayRows;
        if (index < 0 || index >= rows.length) return;
        var node = rows[index];
        if (node.kind === "action") {
            if (node.confirm === true && root._confirmPendingId !== node.id) {
                root._confirmPendingId = node.id;
                return;
            }
            CompositorService.spawn(["sh", "-c", node.action]);
            root.close();
            return;
        }
        if (node.kind === "submenu" || node.kind === "provider") {
            root._enterLevel(node.id);
            return;
        }
        if (node.kind === "link") {
            root._enterLevel((node.target && root._nodes[node.target]) ? node.target : node.id);
        }
    }

    // Shell-condition batch: `when`/`checked` for the current level's direct
    // children only, run once per open()/_enterLevel() (never per-keystroke —
    // search filters purely against whatever's already cached). Results are
    // merged into fresh objects so QML's var-property change detection fires.
    function _evalLevelConditions() {
        Model.directChildren(root._nodes, root.currentNodeId).forEach(function (n) {
            if (n.when !== undefined && root._condResults[n.id] === undefined)
                root._runCondition(n.id, n.when, "when");
            if (n.checked !== undefined && root._checkedResults[n.id] === undefined)
                root._runCondition(n.id, n.checked, "checked");
        });
    }

    function _runCondition(nodeId, cond, kind) {
        var proc = _condProcComponent.createObject(root, { _nodeId: nodeId, _kind: kind });
        proc.command = ["sh", "-c", cond];
        proc.running = true;
    }

    Component {
        id: _condProcComponent

        Process {
            property string _nodeId
            property string _kind
            onExited: exitCode => {
                var id = _nodeId;
                var ok = exitCode === 0;
                var isWhen = _kind === "when";
                destroy();
                var merged = {};
                var source = isWhen ? root._condResults : root._checkedResults;
                for (var k in source) merged[k] = source[k];
                merged[id] = ok;
                if (isWhen) root._condResults = merged;
                else root._checkedResults = merged;
            }
        }
    }

    Component.onCompleted: {
        if (Quickshell.env("FORMALSHELL_SMOKE_OPEN_MENU") === "1")
            root.open();
    }

    screen: root._screen
    visible: root.isOpen
    color: Theme.color.background
    implicitWidth: 560
    implicitHeight: Theme.borderWidth + searchCell.height + root._rowsAreaHeight

    WlrLayershell.namespace: "formalshell:menu"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; left: true }
    margins {
        left: root._screen ? Math.round((root._screen.width - root.implicitWidth) / 2) : 0
        top: root._screen ? Math.round((root._screen.height - root.implicitHeight) / 2) : 0
    }

    // Outer top/left rule — Cell.qml's shared-rule contract makes every cell
    // draw its own bottom+right rule, so the container only needs to close
    // off the top and left of the whole grid.
    Rectangle {
        id: topRule
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.borderWidth
        color: Theme.color.rule
    }

    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: Theme.borderWidth
        color: Theme.color.rule
    }

    Cell {
        id: searchCell
        anchors.top: topRule.bottom
        anchors.left: parent.left
        anchors.leftMargin: Theme.borderWidth
        width: root.implicitWidth - Theme.borderWidth
        height: searchColumn.implicitHeight + Theme.spacing.sm * 2 + Theme.borderWidth

        Column {
            id: searchColumn
            width: parent.width
            spacing: Theme.spacing.xs

            MetaLabel {
                text: root.breadcrumb
            }

            TextInput {
                id: searchInput
                width: searchColumn.width
                color: Theme.color.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                focus: true
                selectByMouse: true
                cursorVisible: true

                onTextChanged: {
                    root._cursorIndex = 0;
                    root._confirmPendingId = "";
                }

                Keys.onPressed: event => {
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
                        root._activateRow(root._cursorIndex);
                        event.accepted = true;
                        break;
                    case Qt.Key_Escape:
                        root._pop();
                        event.accepted = true;
                        break;
                    case Qt.Key_Backspace:
                        if (searchInput.text.length === 0) {
                            root._pop();
                            event.accepted = true;
                        }
                        break;
                    }
                }
            }
        }
    }

    ListView {
        id: rowsView
        anchors.top: searchCell.bottom
        anchors.left: parent.left
        anchors.leftMargin: Theme.borderWidth
        width: root.implicitWidth - Theme.borderWidth
        height: root._rowsAreaHeight
        clip: true
        model: root._displayRows
        currentIndex: root._cursorIndex

        delegate: MenuRow {
            current: root._cursorIndex === index
            checkedState: node.checked !== undefined && root._checkedResults[node.id] === true
            confirming: root._confirmPendingId === node.id

            onActivate: root._activateRow(index)
            onHoverIn: root._setCursor(index)
        }
    }
}
