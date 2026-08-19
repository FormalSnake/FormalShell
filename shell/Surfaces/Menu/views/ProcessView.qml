import QtQuick
import qs.Core as Core
import qs.Components
import qs.Services
import "../../../Menu/actions.js" as Actions
import "../../../Monitor/procs.js" as Procs

// The process table, rendered inside the launcher card (M39). Registered in
// Menu/appviews.js against the "processes" route, loaded by Menu.qml's
// app-view Loader, and the second view to use that registry: MonitorView is
// the read-only ledger of the machine, this is the one surface in the shell
// that acts on it.
//
// It uses all four app-view seams (Menu/appviews.js's own header lists
// them): `query` binds the launcher's search field to the filter, so
// narrowing 400 processes to one is the same typing that narrows any other
// route; `scrollTarget` hands the launcher this list; `viewKey` claims the
// keys a row cursor needs before the menu's own handler sees them; and
// `viewActions` fills the action bar with the verbs of THIS route instead
// of the row-list ones, which is what keeps the footer honest about Enter
// killing something.
//
// One line per process, in mek.gallery's ruled-row grammar: fixed gutters
// for the numbers (tabular by construction, since the whole shell is
// monospace), the argv absorbing whatever is left, and the cursor row as a
// full fg/bg inversion. The columns are the four facts a decision needs
// (which process, whose command line, what it costs), and nothing else fits
// on a line that has to stay scannable.
//
// Destructive by design, so every action is two presses: the first arms it
// and the row goes full-bleed urgent under a CONFIRM verb, the second sends
// the signal. Moving the cursor, retyping the filter or leaving the route
// disarms it. The confirm is not a modal and never steals a key: it is the
// same arm-then-Enter idiom the launcher's own confirm rows already use
// (Menu.qml's _confirmPendingId).
//
// Casing rule, same as MonitorView's: every string this view WRITES is
// uppercase meta, every string it is HANDED (a process name, an argv, a
// kill's own error text) renders verbatim.
Item {
    id: root

    // What the card wants to be before Menu.qml caps it: the whole table on
    // a quiet machine, the cap plus a scrollbar-less overflow on a busy one.
    // The empty state is measured off its own cell rather than the list,
    // whose contentHeight is 0 exactly when that cell is the only thing to
    // show.
    implicitHeight: header.height + columnHeader.height
        + (root._rows.length === 0 ? emptyCell.height : list.contentHeight)


    Component.onCompleted: ProcessService.subscribe()
    Component.onDestruction: ProcessService.unsubscribe()

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

    // Retyping the filter is a new decision about what to act on, so it
    // disarms too. A cursor move disarms in _moveCursor; a process that
    // exits from under an armed confirm needs nothing, since _press re-arms
    // whenever the pid under the cursor is not the pid that was armed.
    onQueryChanged: root._disarm()

    function _disarm() {
        root.confirmAction = "";
        root.confirmPid = 0;
    }

    function _moveCursor(delta) {
        if (root._rows.length === 0)
            return;
        var next = Math.max(0, Math.min(root._rows.length - 1, root._cursorIndex + delta));
        root.cursorPid = root._rows[next].pid;
        root._disarm();
        list.positionViewAtIndex(next, ListView.Contain);
    }

    // --- Formatting ------------------------------------------------------

    function _pct(fraction) {
        // Null in, dash out (MonitorView's own rule): the first poll after
        // the route opens has no previous sample to difference, and a 0.0%
        // there would read as a measurement.
        if (fraction === null || fraction === undefined)
            return "—";
        return (fraction * 100).toFixed(1) + "%";
    }

    function _bytes(value) {
        if (typeof value !== "number" || !isFinite(value))
            return "—";
        var units = ["B", "K", "M", "G", "T"];
        var i = 0;
        var v = value;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? v.toFixed(0) : v.toFixed(1)) + units[i];
    }

    // Column gutters measured off the font rather than pinned as literals,
    // so a retheme that changes fontBaseSize keeps the columns aligned.
    TextMetrics {
        id: metrics
        font.family: Core.Theme.fontFamily
        font.pixelSize: Core.Theme.fontSize.body
        text: "0"
    }
    readonly property real _digit: metrics.advanceWidth
    // 7 digits covers /proc/sys/kernel/pid_max at its 4194304 ceiling.
    readonly property real _pidWidth: root._digit * 7
    readonly property real _nameWidth: root._digit * 20
    readonly property real _cpuWidth: root._digit * 6
    readonly property real _memWidth: root._digit * 7
    readonly property real _rowHeight: metrics.height + Core.Theme.space.controlPaddingY * 2 + Core.Theme.borderWidth

    // --- Actions ----------------------------------------------------------

    // The verb a press would take right now, in the action bar's own shape.
    // Everything the footer says about this route is derived here, so the
    // bar can never promise a key the handler below does not answer.
    readonly property var viewActions: {
        var hints = [
            { key: "↑↓", label: "Move" },
            { key: "^⏎", label: "Kill" },
            { key: "^R", label: "Restart" },
            { key: Actions.KEY_ESC, label: root.confirmAction !== "" ? "Cancel" : "Back" }
        ];
        if (!root._cursorRow)
            return { primary: null, hints: hints };
        var name = root._cursorRow.name;
        if (root.confirmAction !== "")
            return { primary: { key: Actions.KEY_ENTER, label: "Confirm " + root.confirmAction + " " + name }, hints: hints };
        return { primary: { key: Actions.KEY_ENTER, label: "Terminate " + name }, hints: hints };
    }

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

    // --- Header -----------------------------------------------------------

    Cell {
        id: header
        width: root.width

        Item {
            width: parent.width
            implicitHeight: headerLabel.implicitHeight

            MetaLabel {
                id: headerLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root._rows.length === ProcessService.rows.length
                    ? "PROCESSES / " + root._rows.length
                    : "PROCESSES / " + root._rows.length + " OF " + ProcessService.rows.length
                colon: true
            }

            // The last action's own answer, verbatim: a kill that failed on
            // permissions says so in the kernel's words rather than this
            // file's guess at what went wrong.
            Text {
                anchors.left: headerLabel.right
                anchors.leftMargin: Core.Theme.space.lg
                anchors.right: sortLabel.left
                anchors.rightMargin: Core.Theme.space.lg
                anchors.verticalCenter: parent.verticalCenter
                visible: ProcessService.lastResult !== null
                text: ProcessService.lastResult
                    ? ProcessService.lastResult.pid + " " + ProcessService.lastResult.action + ": " + ProcessService.lastResult.message
                    : ""
                color: (ProcessService.lastResult && ProcessService.lastResult.ok)
                    ? Core.Theme.color.foregroundDim
                    : Core.Theme.color.urgent
                elide: Text.ElideRight
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.caption
            }

            MetaLabel {
                id: sortLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "SORT ↓" + root.sortMode + " ^S"
            }
        }
    }

    // Column labels, and the other way to sort: a click on one takes that
    // column, which is the only thing on this route the pointer can do that
    // the keyboard cannot say faster.
    Cell {
        id: columnHeader
        width: root.width
        anchors.top: header.bottom
        interactive: true
        onClicked: mouse => {
            var x = mouse.x;
            if (x < root._pidWidth)
                root.sortMode = "pid";
            else if (x < root._pidWidth + Core.Theme.space.lg + root._nameWidth)
                root.sortMode = "name";
            else if (x > columnHeader.width - root._memWidth - Core.Theme.space.lg * 2)
                root.sortMode = "mem";
            else if (x > columnHeader.width - root._memWidth - root._cpuWidth - Core.Theme.space.lg * 3)
                root.sortMode = "cpu";
        }

        Item {
            width: parent.width
            implicitHeight: pidHeader.implicitHeight

            MetaLabel {
                id: pidHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root._pidWidth
                horizontalAlignment: Text.AlignRight
                text: "PID"
                color: root.sortMode === "pid" ? Core.Theme.color.foreground : Core.Theme.color.foregroundDim
            }

            MetaLabel {
                id: nameHeader
                anchors.left: pidHeader.right
                anchors.leftMargin: Core.Theme.space.lg
                anchors.verticalCenter: parent.verticalCenter
                width: root._nameWidth
                text: "PROCESS"
                color: root.sortMode === "name" ? Core.Theme.color.foreground : Core.Theme.color.foregroundDim
            }

            MetaLabel {
                anchors.left: nameHeader.right
                anchors.leftMargin: Core.Theme.space.lg
                anchors.right: cpuHeader.left
                anchors.rightMargin: Core.Theme.space.lg
                anchors.verticalCenter: parent.verticalCenter
                text: "COMMAND"
                elide: Text.ElideRight
            }

            MetaLabel {
                id: cpuHeader
                anchors.right: memHeader.left
                anchors.rightMargin: Core.Theme.space.lg
                anchors.verticalCenter: parent.verticalCenter
                width: root._cpuWidth
                horizontalAlignment: Text.AlignRight
                text: "CPU"
                color: root.sortMode === "cpu" ? Core.Theme.color.foreground : Core.Theme.color.foregroundDim
            }

            MetaLabel {
                id: memHeader
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root._memWidth
                horizontalAlignment: Text.AlignRight
                text: "MEM"
                color: root.sortMode === "mem" ? Core.Theme.color.foreground : Core.Theme.color.foregroundDim
            }
        }
    }

    // --- Table ------------------------------------------------------------

    // A ListView rather than a Column in a Flickable (MonitorView's shape):
    // this route renders every process on the machine, and a delegate per
    // row for 400 of them costs more to build than the whole launcher.
    // ListView is itself a Flickable, so the scroll seam above is unchanged.
    ListView {
        id: list
        anchors.top: columnHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        // A whole number of rows, never the leftover space: the card's own
        // height cap (Menu.qml's _maxTotalHeight) lands wherever it lands,
        // and a list anchored to the bottom of it draws its last row cut in
        // half, which reads as a broken frame rather than as more content
        // below.
        height: Math.max(0, Math.floor((root.height - header.height - columnHeader.height) / root._rowHeight) * root._rowHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root._rows

        delegate: Cell {
            id: procRow
            required property int index
            required property var modelData

            width: list.width
            height: root._rowHeight
            interactive: true
            selected: procRow.index === root._cursorIndex
            urgent: root.confirmAction !== "" && root.confirmPid === procRow.modelData.pid

            onClicked: {
                root.cursorPid = procRow.modelData.pid;
                root._disarm();
            }

            Text {
                id: pidText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root._pidWidth
                horizontalAlignment: Text.AlignRight
                text: procRow.modelData.pid
                color: procRow.dimForeground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }

            Text {
                id: nameText
                anchors.left: pidText.right
                anchors.leftMargin: Core.Theme.space.lg
                anchors.verticalCenter: parent.verticalCenter
                width: root._nameWidth
                elide: Text.ElideRight
                text: procRow.modelData.name
                color: procRow.foreground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }

            // A kernel thread has no argv at all, which is a fact about the
            // process rather than a gap in the reading, so the column says
            // which of the two it is.
            Text {
                anchors.left: nameText.right
                anchors.leftMargin: Core.Theme.space.lg
                anchors.right: cpuText.left
                anchors.rightMargin: Core.Theme.space.lg
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: procRow.modelData.kernel ? "KERNEL" : procRow.modelData.cmd
                color: procRow.dimForeground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
                font.capitalization: procRow.modelData.kernel ? Font.AllUppercase : Font.MixedCase
            }

            Text {
                id: cpuText
                anchors.right: memText.left
                anchors.rightMargin: Core.Theme.space.lg
                anchors.verticalCenter: parent.verticalCenter
                width: root._cpuWidth
                horizontalAlignment: Text.AlignRight
                text: root._pct(procRow.modelData.cpuFraction)
                color: procRow.foreground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }

            Text {
                id: memText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root._memWidth
                horizontalAlignment: Text.AlignRight
                text: root._bytes(procRow.modelData.memBytes)
                color: procRow.foreground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }
        }
    }

    // Nothing to show is two different facts, and they need two different
    // answers: the collector has not landed a sample yet, or it has and the
    // filter matched none of it. A sibling of the list rather than a child,
    // which would scroll with its content.
    Cell {
        id: emptyCell
        anchors.top: list.top
        width: list.width
        visible: root._rows.length === 0

        MetaLabel {
            text: ProcessService.available ? "NO MATCH" : "NO SAMPLE YET"
        }
    }
}
