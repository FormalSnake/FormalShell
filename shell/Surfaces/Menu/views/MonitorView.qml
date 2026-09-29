import QtQuick
import Quickshell
import qs.Core as Core
import qs.Components
import qs.Services
import "../../../Menu/actions.js" as Actions
import "../../../Monitor/format.js" as Format
import "../../../Monitor/history.js" as History
import "../../../Monitor/procs.js" as Procs
import "../../../Menu/rowsync.js" as RowSync

// The full system monitor, rendered inside the launcher card. Registered in
// Menu/appviews.js against the "monitor" route, loaded by Menu.qml's app-view
// Loader. Nothing here knows about the menu beyond being sized by it, so this
// file is also what a second app view copies.
//
// A task manager's two halves: a strip of five tiles (CPU, Memory, GPU, Disk,
// Network), each a label over one big figure and a history line, then the
// process table taking the rest of the card. The table shipped as a route of
// its own for one day and was folded back in here (owner, 2026-08-19: "I
// never wanted a separate processes list"): there is one place to look at the
// machine, and typing in it filters the table.
//
// This view uses all four of Menu/appviews.js's seams: `query` filters the
// table, `scrollTarget` is the table, `viewKey` claims the keys a row cursor
// needs before the menu's own handler sees them, and `viewActions` replaces
// the row list's verbs with the ones that are true here. Per-core bars,
// sensors and per-interface detail are not drawn here; `monitor status` and
// `monitor gpu` still report them.
//
// SystemMonitorService is subscribed on completion and released on
// destruction, which is the whole reason that service refcounts: the menu
// unloads this view the moment the route is left or the launcher closes, so
// a closed launcher leaves nothing polling /proc. The history lines are this
// view's own for the same reason: they start when the view opens.
//
// Anything the first tick cannot know renders as a dash, never a zero:
// every delta (CPU busy, network rates) needs two samples, and a card whose
// driver publishes no utilisation counter has nothing to plot.
//
// Face rule (spec "Type"): words take the sans face, values and identifiers
// take mono.
Item {
    id: root

    implicitHeight: strip.height + Core.Theme.space.sectionGap + procChrome.height
        + (root._rows.length === 0 ? emptyCell.height : root._rows.length * root._rowHeight)

    Component.onCompleted: {
        SystemMonitorService.subscribe();
        ProcessService.subscribe();
    }
    Component.onDestruction: {
        SystemMonitorService.unsubscribe();
        ProcessService.unsubscribe();
    }

    // The app-view scroll seam (Menu.qml's key handler): the table is the
    // part with more content than room, and it is what the cursor lives in.
    readonly property Flickable scrollTarget: list

    // Bound by Menu.qml to the live search text.
    property string query: ""

    property string sortMode: "cpu"

    // Which process the cursor is on, held as a pid rather than an index:
    // the table re-sorts on every poll and a row that gained a percent
    // point moves under an index-based cursor, so an index would arm a
    // confirm on one process and fire it at another.
    property int cursorPid: 0

    // The armed action, or "" when nothing is. Cleared by anything that
    // changes what the cursor is pointing at.
    property string confirmAction: ""
    property int confirmPid: 0

    readonly property var _rows: Procs.sortRows(Procs.filterRows(ProcessService.rows, root.query), root.sortMode)
    readonly property int _cursorIndex: {
        for (var i = 0; i < root._rows.length; i++) {
            if (root._rows[i].pid === root.cursorPid)
                return i;
        }
        return root._rows.length > 0 ? 0 : -1;
    }
    readonly property var _cursorRow: root._cursorIndex >= 0 ? root._rows[root._cursorIndex] : null

    // --- The keyed row model ---------------------------------------------
    //
    // The table re-sorts on every 2s poll, and a JS array handed to a
    // ListView is a model reset, so a row that overtook its neighbour used
    // to be two rows redrawn rather than one row moving. This model holds
    // the same pids in the same order, synced by Menu/rowsync.js's diff.
    // Above the limit the poll has rearranged the table rather than moved
    // anything through it, and the model is refilled with no transitions.
    ListModel {
        id: procModel
    }

    readonly property int _rowResetLimit: 64
    property bool _rowsAnimate: false

    // The hover wash's gate (Components/PointerMoveGate.qml): a re-sort
    // slides rows under a parked pointer every poll, and a key moves the
    // cursor out from under it, so neither may light the row it lands on.
    PointerMoveGate {
        id: hoverGate
    }

    readonly property var _blankRow: ({ pid: 0, name: "", cmd: "", kernel: false, state: "", cpuFraction: null, memBytes: null })

    function _syncRows() {
        var rows = root._rows;
        var pids = [];
        for (var i = 0; i < rows.length; i++)
            pids.push(rows[i].pid);

        var held = [];
        for (i = 0; i < procModel.count; i++)
            held.push(procModel.get(i).procPid);

        var plan = RowSync.plan(held, pids, root._rowResetLimit);
        if (plan.reset || plan.ops.length > 0)
            hoverGate.reset();
        if (plan.reset) {
            root._rowsAnimate = false;
            procModel.clear();
            for (i = 0; i < pids.length; i++)
                procModel.append({ procPid: pids[i] });
            return;
        }
        if (plan.ops.length === 0)
            return;
        root._rowsAnimate = true;
        for (i = 0; i < plan.ops.length; i++) {
            var op = plan.ops[i];
            if (op.op === "remove")
                procModel.remove(op.index);
            else if (op.op === "insert")
                procModel.insert(op.index, { procPid: op.id });
            else
                procModel.move(op.from, op.to, 1);
        }
    }

    on_RowsChanged: root._syncRows()

    // Retyping the filter is a new decision about what to act on, so it
    // disarms too. A cursor move disarms in _moveCursor; a process that
    // exits from under an armed confirm needs nothing, since _press re-arms
    // whenever the pid under the cursor is not the pid that was armed.
    onQueryChanged: root._disarm()

    // --- History ----------------------------------------------------------

    property var _hist: ({ cpu: [], mem: [], gpu: [], rx: [], tx: [] })

    // GpuService's own handler for this signal was connected first (it is a
    // singleton), so its cards already carry this tick's reading.
    Connections {
        target: SystemMonitorService

        function onTick() {
            var h = root._hist;
            var mem = SystemMonitorService.mem;
            var rows = SystemMonitorService.net.rows || [];
            var rx = null;
            var tx = null;
            if (rows.length > 0) {
                rx = 0;
                tx = 0;
                for (var i = 0; i < rows.length; i++) {
                    rx += Number(rows[i].rxBytesPerSec) || 0;
                    tx += Number(rows[i].txBytesPerSec) || 0;
                }
            }
            var gpu = root._gpu;
            root._hist = {
                cpu: History.push(h.cpu, SystemMonitorService.cpu.aggregate),
                mem: History.push(h.mem, mem.available ? mem.usedFraction : null),
                gpu: History.push(h.gpu, gpu && gpu.metrics ? gpu.metrics.busy : null),
                rx: History.push(h.rx, rx),
                tx: History.push(h.tx, tx)
            };
        }
    }

    // --- The tiles --------------------------------------------------------

    // The card the GPU tile reports: one that publishes a utilisation
    // counter, then the discrete one, then whatever is first.
    readonly property var _gpu: {
        var cards = GpuService.cards;
        var pick = null;
        for (var i = 0; i < cards.length; i++) {
            var busy = cards[i].metrics ? cards[i].metrics.busy : null;
            if (busy !== null && busy !== undefined)
                return cards[i];
            if (!pick || cards[i].discrete === true)
                pick = cards[i];
        }
        return pick;
    }

    // The mount the disk tile reports: the root filesystem, or the first
    // one listed on a machine that has no "/" of its own.
    readonly property var _disk: {
        var rows = SystemMonitorService.disk.rows || [];
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].mount === "/")
                return rows[i];
        }
        return rows.length > 0 ? rows[0] : null;
    }

    function _join(parts) {
        return parts.filter(function (p) { return p !== ""; }).join(", ");
    }

    readonly property var _tiles: {
        var cpu = SystemMonitorService.cpu;
        var load = SystemMonitorService.load;
        var mem = SystemMonitorService.mem;
        var h = root._hist;
        var out = [];

        out.push({
            label: "CPU",
            value: Format.pct(cpu.aggregate),
            sub: root._join([
                cpu.cores.length > 0 ? cpu.cores.length + " cores" : "",
                load.available ? "load " + load.load1.toFixed(2) : ""
            ]),
            series: h.cpu
        });

        out.push({
            label: "Memory",
            value: mem.available ? Format.pct(mem.usedFraction) : "--",
            sub: mem.available
                ? Format.bytes(mem.totalBytes - mem.availableBytes) + " of " + Format.bytes(mem.totalBytes)
                : "",
            series: h.mem
        });

        var gpu = root._gpu;
        var m = gpu ? gpu.metrics : null;
        var measured = !!m && m.busy !== null && m.busy !== undefined;
        var gpuSub = "No GPU";
        if (gpu) {
            if (!measured)
                gpuSub = "No metrics";
            else if (m.vramTotal !== null && m.vramTotal !== undefined && m.vramUsed !== null && m.vramUsed !== undefined)
                gpuSub = Format.bytes(m.vramUsed) + " of " + Format.bytes(m.vramTotal) + " VRAM";
            else
                gpuSub = gpu.name;
        }
        out.push({
            label: "GPU",
            value: measured ? Format.pct(m.busy) : "--",
            sub: gpuSub,
            series: h.gpu
        });

        var disk = root._disk;
        out.push({
            label: "Disk",
            value: disk ? Format.pct(disk.fraction) : "--",
            sub: disk ? disk.mount + ", " + Format.bytes(disk.used) + " of " + Format.bytes(disk.size) : "No disk",
            fraction: disk ? disk.fraction : 0
        });

        var netRows = SystemMonitorService.net.rows || [];
        var rx = h.rx.length > 0 ? h.rx[h.rx.length - 1] : null;
        var tx = h.tx.length > 0 ? h.tx[h.tx.length - 1] : null;
        out.push({
            label: "Network",
            value: netRows.length > 0 ? Format.rate(rx) : "--",
            valueIcon: "arrow-down",
            sub: netRows.length > 0 ? Format.rate(tx) : (SystemMonitorService.net.available ? "Sampling" : "No interface"),
            subIcon: netRows.length > 0 ? "arrow-up" : "",
            series: h.rx,
            secondary: h.tx,
            ceiling: History.ceiling(h.rx.concat(h.tx), 1024)
        });
        return out;
    }

    // One tile of the strip. A bordered `Cell`, so each theme draws its own
    // block. `fraction` at 0 or above swaps the history line for a groove,
    // for a figure (disk fill) that has no history worth drawing.
    component Tile: Cell {
        id: tile

        property var info: ({})

        readonly property real _plot: Core.Theme.space.controlHeight

        Column {
            width: parent.width
            spacing: Core.Theme.space.xxs

            SectionLabel {
                width: parent.width
                text: tile.info.label
                elide: Text.ElideRight
            }

            Row {
                width: parent.width
                spacing: Core.Theme.space.xxs

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!tile.info.valueIcon
                    name: tile.info.valueIcon || "arrow-down"
                    size: Core.Theme.fontSize.title
                    color: tile.dimForeground
                }

                Text {
                    width: parent.width - (tile.info.valueIcon ? Core.Theme.fontSize.title + Core.Theme.space.xxs : 0)
                    text: tile.info.value
                    color: tile.foreground
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: Core.Theme.fontSize.body
                    font.family: Core.Theme.fontFamilyMono
                    font.pixelSize: Core.Theme.fontSize.display
                    font.weight: Core.Theme.weight.semibold
                }
            }

            Row {
                width: parent.width
                height: subText.implicitHeight
                spacing: Core.Theme.space.xxs

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!tile.info.subIcon
                    name: tile.info.subIcon || "arrow-up"
                    size: Core.Theme.fontSize.caption
                    color: tile.dimForeground
                }

                Text {
                    id: subText
                    width: parent.width - (tile.info.subIcon ? Core.Theme.fontSize.caption + Core.Theme.space.xxs : 0)
                    text: tile.info.sub
                    elide: Text.ElideRight
                    color: tile.dimForeground
                    font.family: Core.Theme.fontFamilyMono
                    font.pixelSize: Core.Theme.fontSize.caption
                }
            }

            Item {
                width: parent.width
                height: tile._plot

                Sparkline {
                    anchors.fill: parent
                    visible: tile.info.fraction === undefined
                    values: tile.info.series || []
                    secondary: tile.info.secondary || []
                    ceiling: tile.info.ceiling || 1
                }

                Track {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: tile.info.fraction !== undefined
                    value: tile.info.fraction || 0
                }
            }
        }
    }

    Row {
        id: strip
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.space.lg

        Repeater {
            model: root._tiles

            delegate: Tile {
                required property var modelData

                info: modelData
                width: Math.floor((strip.width - strip.spacing * (root._tiles.length - 1)) / root._tiles.length)
            }
        }
    }

    // --- Process table ----------------------------------------------------
    //
    // One line per process, drawn like the palette's own rows: square,
    // borderless, the cursor row filled `accent`. Fixed gutters for the
    // numbers, which are mono and so tabular by construction, the name in
    // sans with the app's icon beside it, the command line absorbing whatever
    // is left.
    //
    // Destructive by design, so every action is two presses: the first arms
    // it and the row takes a `destructive` border and ink under a CONFIRM
    // verb, the second sends the signal. Moving the cursor, retyping the
    // filter or leaving the route disarms it. The confirm is not a modal and
    // never steals a key: it is the same arm-then-Enter idiom the launcher's
    // own confirm rows already use (Menu.qml's _confirmPendingId).

    function _disarm() {
        root.confirmAction = "";
        root.confirmPid = 0;
    }

    function _moveCursor(delta) {
        if (root._rows.length === 0)
            return;
        var next = Math.max(0, Math.min(root._rows.length - 1, root._cursorIndex + delta));
        hoverGate.reset();
        root.cursorPid = root._rows[next].pid;
        root._disarm();
        list.positionViewAtIndex(next, ListView.Contain);
    }

    // The desktop entry's icon for a process, "" when no entry claims it.
    // Only hits are kept: DesktopEntries fills in after startup, and a miss
    // remembered from before it finished would blank the icon for good.
    property var _iconCache: ({})

    function _iconFor(row) {
        if (row.kernel)
            return "";
        var names = Procs.launcherNames(row);
        var key = names.join("|");
        if (root._iconCache[key] !== undefined)
            return root._iconCache[key];
        for (var i = 0; i < names.length; i++) {
            var entry = DesktopEntries.heuristicLookup(names[i]);
            if (!entry || !entry.icon)
                continue;
            var path = Quickshell.iconPath(entry.icon, true);
            if (path !== "") {
                root._iconCache[key] = path;
                return path;
            }
        }
        return "";
    }

    // Column gutters measured off the font rather than pinned as literals,
    // so a retheme that changes fontBaseSize keeps the columns aligned.
    TextMetrics {
        id: metrics
        font.family: Core.Theme.fontFamilyMono
        font.pixelSize: Core.Theme.fontSize.body
        text: "0"
    }
    readonly property real _digit: metrics.advanceWidth
    // 7 digits covers /proc/sys/kernel/pid_max at its 4194304 ceiling.
    readonly property real _pidWidth: root._digit * 7
    readonly property real _stateWidth: root._digit * 9
    readonly property real _cpuWidth: root._digit * 6
    readonly property real _memWidth: root._digit * 7
    readonly property real _iconExtent: Core.Theme.space.huge
    readonly property real _nameWidth: root._iconExtent + Core.Theme.space.lg + root._digit * 22
    // Same floor every other row in the shell takes (DESIGN.md §1 Padding):
    // `controlHeight`, and taller only where the text itself needs it.
    readonly property real _rowHeight: Math.max(Core.Theme.space.controlHeight,
        metrics.height + Core.Theme.space.controlPaddingY * 2)

    // The verb a press would take right now, in the action bar's own shape.
    // Everything the footer says about this route is derived here, so the
    // bar can never promise a key the handler below does not answer.
    readonly property var viewActions: {
        var hints = [
            { keys: ["Ctrl", "Enter"], label: "Kill" },
            { keys: ["Ctrl", "R"], label: "Restart" },
            { keys: ["Ctrl", "S"], label: "Sort" },
            { keys: Actions.KEY_ESC, label: root.confirmAction !== "" ? "Cancel" : "Back" }
        ];
        if (!root._cursorRow)
            return { primary: null, hints: hints };
        var name = root._cursorRow.name;
        if (root.confirmAction !== "")
            return { primary: { keys: Actions.KEY_ENTER, label: "Confirm " + root._verbs[root.confirmAction].toLowerCase() + " " + name }, hints: hints };
        return { primary: { keys: Actions.KEY_ENTER, label: "Terminate " + name }, hints: hints };
    }

    // The signal names ProcessService takes, as the words the footer says.
    readonly property var _verbs: ({ TERM: "Terminate", KILL: "Kill", RESTART: "Restart" })

    // One press of the primary: arm the action, or run the armed one. The
    // pointer path (the action bar's own click) and the rig's `menu
    // activate` both land here too, so there is exactly one place that
    // decides what Enter means on this route.
    function _press(action) {
        var row = root._cursorRow;
        if (!row)
            return false;
        if (root.confirmAction === "" || root.confirmPid !== row.pid || root.confirmAction !== action) {
            root.confirmAction = action;
            root.confirmPid = row.pid;
            return true;
        }
        root._disarm();
        if (action === "RESTART")
            ProcessService.restartPid(row.pid);
        else
            ProcessService.signalPid(row.pid, action);
        return true;
    }

    // The rig's stand-in for Enter (Menu.qml's `activate`, MenuIpc's own
    // `menu activate <index>`): index < 0 means "wherever the cursor already
    // is", which is what the action bar's click passes.
    function viewActivate(index) {
        if (index >= 0 && index < root._rows.length)
            root.cursorPid = root._rows[index].pid;
        return root._press(root.confirmAction !== "" ? root.confirmAction : "TERM");
    }

    // Keys claimed ahead of Menu.qml's own handler. Everything not listed
    // falls through untouched, which is what keeps Escape popping the level,
    // backspace popping on an empty field, and every printable character
    // going to the search field where the filter lives.
    function viewKey(key, modifiers) {
        var ctrl = (modifiers & Qt.ControlModifier) !== 0;
        switch (key) {
        case Qt.Key_Up:
            root._moveCursor(-1);
            return true;
        case Qt.Key_Down:
            root._moveCursor(1);
            return true;
        case Qt.Key_PageUp:
            root._moveCursor(-Math.max(1, Math.floor(list.height / root._rowHeight) - 1));
            return true;
        case Qt.Key_PageDown:
            root._moveCursor(Math.max(1, Math.floor(list.height / root._rowHeight) - 1));
            return true;
        case Qt.Key_Home:
            root._moveCursor(-root._rows.length);
            return true;
        case Qt.Key_End:
            root._moveCursor(root._rows.length);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            return root._press(ctrl ? "KILL" : (root.confirmAction !== "" ? root.confirmAction : "TERM"));
        case Qt.Key_R:
            if (!ctrl)
                return false;
            return root._press("RESTART");
        case Qt.Key_S:
            if (!ctrl)
                return false;
            root.sortMode = Procs.nextSort(root.sortMode);
            return true;
        case Qt.Key_Escape:
            // Only when something is armed: cancelling the confirm is what
            // the footer promises there, and every other Escape still pops
            // the route.
            if (root.confirmAction === "") {
                return false;
            }
            root._disarm();
            return true;
        }
        return false;
    }

    // A sortable column's label, and the control that sorts by it: the
    // ghost button's own box and washes behind the column's own words,
    // sized to the column rather than to a button's padding so the label
    // stays on the column it names. The chosen column takes full ink and
    // an arrow for the direction it runs.
    component ColumnHeader: Box {
        id: columnHeader

        property string label: ""
        property bool chosen: false
        property bool descending: false
        property int alignment: Text.AlignLeft
        property real pad: 0

        signal picked()

        readonly property color ink: columnHeader.chosen
            ? Core.Theme.color.foreground
            : Core.Theme.color.mutedForeground

        role: "button.ghost"
        state: headerPointer.pressed ? "press" : headerPointer.containsMouse ? "hover" : "rest"
        height: Core.Theme.space.keycapHeight

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: columnHeader.alignment === Text.AlignLeft ? parent.left : undefined
            anchors.right: columnHeader.alignment === Text.AlignRight ? parent.right : undefined
            anchors.leftMargin: columnHeader.pad
            anchors.rightMargin: columnHeader.pad
            layoutDirection: columnHeader.alignment === Text.AlignRight ? Qt.RightToLeft : Qt.LeftToRight
            spacing: Core.Theme.space.xxs

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: columnHeader.label
                color: columnHeader.ink
                font.family: Core.Theme.fontFamilySans
                font.pixelSize: Core.Theme.fontSize.caption
                font.weight: Core.Theme.weight.medium
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: columnHeader.chosen
                name: columnHeader.descending ? "chevron-down" : "chevron-up"
                size: Core.Theme.fontSize.caption
                color: columnHeader.ink
            }
        }

        MouseArea {
            id: headerPointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: columnHeader.picked()
        }
    }

    // The room a column header's box keeps either side of its label, so the
    // label lands on the column and the box around it still reads as one.
    readonly property real _headerPad: Core.Theme.space.xs

    // The row gutter: every heading, empty state and column label starts
    // here so it lines up with the words in the rows under it. The inline
    // components cannot see `root`, so they read the same token.
    readonly property real rowGutter: Core.Theme.space.controlPaddingX

    // Where each column starts inside a row's content, which is the row
    // gutter in from the table's edge: the rows and the headers over them
    // are laid out off the same numbers, from the right edge in.
    readonly property real _contentWidth: Math.max(0, list.width - root.rowGutter * 2)
    readonly property real _memX: root._contentWidth - root._memWidth
    readonly property real _cpuX: root._memX - Core.Theme.space.lg - root._cpuWidth
    readonly property real _pidX: root._cpuX - Core.Theme.space.lg - root._pidWidth
    readonly property real _stateX: root._pidX - Core.Theme.space.lg - root._stateWidth
    readonly property real _cmdX: root._nameWidth + Core.Theme.space.lg
    readonly property real _cmdWidth: Math.max(0, root._stateX - Core.Theme.space.lg - root._cmdX)

    // The table's heading and its column labels, measured as one block so
    // the list below can be told how much room is left in whole rows.
    Column {
        id: procChrome
        anchors.top: strip.bottom
        anchors.topMargin: Core.Theme.space.sectionGap
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.space.rowGap

        Item {
            width: parent.width
            height: procHeading.implicitHeight

            SectionLabel {
                id: procHeading
                anchors.left: parent.left
                leftPadding: root.rowGutter
                text: "Processes"
                count: root._rows.length
            }

            // The last action's own answer, verbatim: a kill that failed on
            // permissions says so in the kernel's words rather than this
            // file's guess at what went wrong.
            Text {
                anchors.left: procHeading.right
                anchors.leftMargin: Core.Theme.space.lg
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: ProcessService.lastResult !== null
                text: ProcessService.lastResult
                    ? ProcessService.lastResult.pid + " " + ProcessService.lastResult.action + ": " + ProcessService.lastResult.message
                    : ""
                color: (ProcessService.lastResult && ProcessService.lastResult.ok)
                    ? Core.Theme.color.mutedForeground
                    : Core.Theme.color.destructive
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                font.family: Core.Theme.fontFamilyMono
                font.pixelSize: Core.Theme.fontSize.caption
            }
        }

        // The column labels, on the row's own gutter so each one sits over
        // its column. The four the table can sort by are controls; the
        // command line and the state are not sort keys, so theirs are words
        // alone.
        Item {
            width: parent.width
            height: Core.Theme.space.keycapHeight

            ColumnHeader {
                x: root.rowGutter - root._headerPad
                width: root._nameWidth + root._headerPad * 2
                label: "Name"
                pad: root._headerPad
                chosen: root.sortMode === "name"
                descending: Procs.sortDescending("name")
                onPicked: root.sortMode = "name"
            }

            Text {
                x: root.rowGutter + root._cmdX
                width: root._cmdWidth
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: "Command"
                color: Core.Theme.color.mutedForeground
                font.family: Core.Theme.fontFamilySans
                font.pixelSize: Core.Theme.fontSize.caption
                font.weight: Core.Theme.weight.medium
            }

            Text {
                x: root.rowGutter + root._stateX
                width: root._stateWidth
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: "State"
                color: Core.Theme.color.mutedForeground
                font.family: Core.Theme.fontFamilySans
                font.pixelSize: Core.Theme.fontSize.caption
                font.weight: Core.Theme.weight.medium
            }

            ColumnHeader {
                x: root.rowGutter + root._pidX - root._headerPad
                width: root._pidWidth + root._headerPad * 2
                label: "PID"
                pad: root._headerPad
                chosen: root.sortMode === "pid"
                descending: Procs.sortDescending("pid")
                onPicked: root.sortMode = "pid"
                alignment: Text.AlignRight
            }

            ColumnHeader {
                x: root.rowGutter + root._cpuX - root._headerPad
                width: root._cpuWidth + root._headerPad * 2
                label: "CPU"
                pad: root._headerPad
                chosen: root.sortMode === "cpu"
                descending: Procs.sortDescending("cpu")
                onPicked: root.sortMode = "cpu"
                alignment: Text.AlignRight
            }

            ColumnHeader {
                x: root.rowGutter + root._memX - root._headerPad
                width: root._memWidth + root._headerPad * 2
                label: "Memory"
                pad: root._headerPad
                chosen: root.sortMode === "mem"
                descending: Procs.sortDescending("mem")
                onPicked: root.sortMode = "mem"
                alignment: Text.AlignRight
            }
        }
    }

    // A ListView rather than a Column in a Flickable: this table renders
    // every process on the machine, and a delegate per row for 400 of them
    // costs more to build than the whole launcher. ListView is itself a
    // Flickable, so the scroll seam is unchanged.
    ListView {
        id: list
        // Delegates recycle rather than being destroyed and rebuilt, which
        // is safe because this delegate is required properties plus
        // bindings off them, with no Component.onCompleted work a reused
        // item would skip.
        reuseItems: true
        anchors.top: procChrome.bottom
        anchors.topMargin: Core.Theme.space.rowGap
        anchors.left: parent.left
        anchors.right: parent.right
        // A whole number of rows, never the leftover space: the card's own
        // body height (Menu.qml's `_bodyHeight`) lands wherever it lands,
        // and a list anchored to the bottom of it draws its last row cut in
        // half, which reads as a broken frame rather than as more content
        // below.
        height: Math.max(0, Math.floor((root.height - strip.height - Core.Theme.space.sectionGap - procChrome.height - Core.Theme.space.rowGap) / root._rowHeight) * root._rowHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: procModel
        // A row that gained a percent point and overtook its neighbour slides
        // past it instead of the two swapping between two frames. No `add` or
        // `remove` to go with it: a process starting or exiting is not a
        // movement of the table, and a poll that starts one row and ends
        // another would otherwise fade two rows every two seconds.
        displaced: MoveTransition { enabled: root._rowsAnimate }
        move: MoveTransition { enabled: root._rowsAnimate }

        WheelScroll {
            flickable: list
            step: root._rowHeight
        }

        // The launcher's row (MenuRow.qml): a ghost Cell whose `selected`
        // is the cursor, whose wash is the pointer once the gate has seen it
        // move, and whose `destructive` border is an armed signal.
        delegate: Cell {
            id: procRow
            required property int index
            required property int procPid
            // The model carries pids so the rows keep their identity across a
            // re-sort; the row itself still comes off `_rows`, which the sync
            // leaves in step with the model. Safe by index here, and not in
            // the launcher's list, because this view has no `remove`
            // transition: nothing outlives the model row it draws.
            readonly property var row: root._rows[procRow.index] || root._blankRow
            readonly property string iconSource: root._iconFor(procRow.row)

            width: list.width
            height: root._rowHeight
            ghost: true
            interactive: true
            selected: procRow.index === root._cursorIndex
            destructive: root.confirmAction !== "" && root.confirmPid === procRow.row.pid
            hovered: procRow.containsPointer && hoverGate.live
            onPointerMoved: (x, y) => hoverGate.moved(procRow, x, y)
            onClicked: {
                root.cursorPid = procRow.row.pid;
                root._disarm();
            }

            Item {
                width: root._contentWidth
                height: root._rowHeight - Core.Theme.space.controlPaddingY * 2

                Picture {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._iconExtent
                    height: root._iconExtent
                    visible: procRow.iconSource !== ""
                    source: procRow.iconSource
                    sourceSize: Qt.size(root._iconExtent * 2, root._iconExtent * 2)
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    x: (root._iconExtent - width) / 2
                    visible: procRow.iconSource === ""
                    name: procRow.row.kernel === true ? "cpu" : "terminal"
                    size: Core.Theme.fontSize.body
                    color: procRow.dimForeground
                }

                // The process's name is what it is called, not what it
                // measures, so it takes the sans face while every column
                // beside it stays mono (spec "Type").
                Text {
                    x: root._iconExtent + Core.Theme.space.lg
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._nameWidth - x
                    elide: Text.ElideRight
                    text: procRow.row.name
                    color: procRow.foreground
                    font.family: Core.Theme.fontFamilySans
                    font.pixelSize: Core.Theme.fontSize.body
                    font.weight: Core.Theme.weight.medium
                }

                // A kernel thread has no argv at all, which is a fact about
                // the process rather than a gap in the reading, so the column
                // says which of the two it is: a badge where a command line
                // would be.
                Cell {
                    id: kernelChip
                    x: root._cmdX
                    anchors.verticalCenter: parent.verticalCenter
                    height: Core.Theme.space.keycapHeight
                    visible: procRow.row.kernel === true
                    chip: true
                    selected: true

                    Text {
                        text: "Kernel"
                        color: kernelChip.foreground
                        font.family: Core.Theme.fontFamilySans
                        font.pixelSize: Core.Theme.fontSize.caption
                        font.weight: Core.Theme.weight.medium
                    }
                }

                Text {
                    x: root._cmdX
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._cmdWidth
                    visible: procRow.row.kernel !== true
                    elide: Text.ElideRight
                    text: procRow.row.cmd
                    color: procRow.dimForeground
                    font.family: Core.Theme.fontFamilyMono
                    font.pixelSize: Core.Theme.fontSize.body
                }

                Text {
                    x: root._stateX
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._stateWidth
                    elide: Text.ElideRight
                    text: Procs.stateLabel(procRow.row.state)
                    color: procRow.dimForeground
                    font.family: Core.Theme.fontFamilySans
                    font.pixelSize: Core.Theme.fontSize.bodySmall
                }

                Text {
                    x: root._pidX
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._pidWidth
                    horizontalAlignment: Text.AlignRight
                    text: procRow.row.pid
                    color: procRow.dimForeground
                    font.family: Core.Theme.fontFamilyMono
                    font.pixelSize: Core.Theme.fontSize.body
                }

                Text {
                    x: root._cpuX
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._cpuWidth
                    horizontalAlignment: Text.AlignRight
                    text: Format.procPct(procRow.row.cpuFraction)
                    color: procRow.foreground
                    font.family: Core.Theme.fontFamilyMono
                    font.pixelSize: Core.Theme.fontSize.body
                }

                Text {
                    x: root._memX
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._memWidth
                    horizontalAlignment: Text.AlignRight
                    text: Format.bytes(procRow.row.memBytes)
                    color: procRow.foreground
                    font.family: Core.Theme.fontFamilyMono
                    font.pixelSize: Core.Theme.fontSize.body
                }
            }
        }
    }

    // Nothing to show is two different facts, and they need two different
    // answers: the collector has not landed a sample yet, or it has and the
    // filter matched none of it. A sibling of the list rather than a child,
    // which would scroll with its content.
    Item {
        id: emptyCell
        anchors.top: list.top
        anchors.left: parent.left
        width: list.width
        height: root._rowHeight
        visible: root._rows.length === 0

        SectionLabel {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: root.rowGutter
            text: ProcessService.available ? "No matching processes" : "No sample yet"
        }
    }
}
