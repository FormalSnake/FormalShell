import QtQuick
import Quickshell.Io
import qs.Core
import qs.Components
import qs.Services
import "../../SystemUpdate/model.js" as Update

// Flake-inputs-behind panel: the popout behind SystemUpdateWidget's bar
// cell, on TailscalePanel's poll-in-panel pattern (the one poll lives HERE,
// not in the widget, so `panel open systemupdate` over IPC renders honestly
// even when bar.layout never names the widget; the widget flips pollEnabled
// true from its own Component.onCompleted).
//
// WHAT THIS ANSWERS: "are my flake inputs behind their upstream refs". Not
// "does my running system differ from what a rebuild would produce". The
// wording never drifts toward the latter.
//
// Two stages, and stage 1 is deliberately not a Process. A FileView reads
// systemUpdate.flakeDir's flake.lock: zero cost, no nix invocation, no
// network, and `watchChanges` re-reads for free the moment the user runs
// `nix flake update` themselves. Stage 2 fans out one probe per direct
// input, queued strictly one at a time (HyprlandBackend's _keywordQueue
// idiom: reassigning a running Process's command drops the in-flight
// invocation).
//
// pollState is the honest-state axis, and SystemUpdate/model.js's
// summaryLabel() turns it plus the counts into the one string both this
// panel's hero and the bar cell render, so the two can never disagree.
// An input type with no cheap probe (path, tarball, indirect, sourcehut)
// is "?" forever rather than a fabricated CURRENT.
//
// Layout (DESIGN.md §3 "Panel"): a hero naming the flake and carrying the
// summary, an `INPUTS (n)` section of rows (name in sans, locked rev in
// mono, status as a section label that goes `warning` on BEHIND), and a
// footer pairing an outline Check button with the behind count.
//
// Keyboard (spec "Keyboard model"): the cursor walks the input rows, which
// carry no action of their own the way MonitorPanel's readouts don't, and
// Tab reaches the footer where Enter re-runs the check. The panel never
// applies an update: it answers whether the inputs are behind, and running
// a rebuild is the user's own call at their own terminal.
Panel {
    id: root

    panelIcon: "package"
    panelTitle: "System update"
    panelWidth: Theme.space.popupWidthDefault

    titleActions: [
        IconButton {
            name: "refresh-cw"
            enabled: root.flakeDir !== ""
            onClicked: root._poll()
        }
    ]

    cursorCount: root.inputs.length
    // 0 is the input list, 1 is the footer's check button.
    sectionCount: 2

    onCursorActivated: {
        if (root.cursorSection === 1)
            root._poll();
    }

    property bool pollEnabled: false

    // "noflake" | "nolock" | "checking" | "offline" | "ok". Starts at
    // "checking" (CHECKING, i.e. nobody has asked yet) rather than at
    // "noflake": the flake directory has not been read at this point, so
    // NO FLAKE would be a claim rather than an answer.
    property string pollState: "checking"
    property var inputs: []
    // input name -> upstream rev, "" for anything that did not resolve.
    property var heads: ({})

    readonly property var counts: Update.countBehind(root.inputs, root.heads)
    readonly property string summary: Update.summaryLabel(root.pollState, root.counts)

    // The hero's own subject: which flake this is (the directory's own
    // basename, the instance rather than the panel's generic "flake inputs"
    // noun) and how many inputs are behind.
    readonly property string _flakeName: {
        var parts = root.flakeDir.split("/").filter(function (p) { return p !== ""; });
        return parts.length > 0 ? parts[parts.length - 1] : "";
    }

    readonly property string flakeDir: {
        var v = Config.get("systemUpdate.flakeDir", "");
        return (typeof v === "string") ? v : "";
    }

    readonly property int _interval: {
        var v = Config.get("systemUpdate.intervalMs", 10800000);
        return (typeof v === "number" && v > 0) ? v : 10800000;
    }

    // Stage 1. An absent flakeDir is NO FLAKE and never a guess at
    // /etc/nixos: a wrong directory would report someone else's inputs.
    FileView {
        id: lockFile
        printErrors: false
        path: root.flakeDir === "" ? "" : root.flakeDir + "/flake.lock"
        watchChanges: true
        onFileChanged: reload()
        // Parsing the lock is free, so it happens whenever the file lands.
        // The probes are not: they only fire once someone has opted in, so a
        // panel nobody named in bar.layout and nobody opened never costs a
        // network round trip.
        onLoaded: {
            var parsed = Update.parseLock(lockFile.text());
            if (!parsed.ok) {
                root.pollState = "nolock";
                root.inputs = [];
                root.heads = ({});
                return;
            }
            root.inputs = parsed.inputs;
            root.heads = ({});
            root.pollState = "checking";
            if (root.pollEnabled || root.isOpen)
                root._probe();
        }
        onLoadFailed: {
            root.pollState = root.flakeDir === "" ? "noflake" : "nolock";
            root.inputs = [];
            root.heads = ({});
        }
    }

    // Stage 2, strictly one probe at a time: reassigning a running Process's
    // command drops the in-flight invocation (HyprlandBackend's _keywordQueue
    // idiom). `_queue` holds the inputs still to ask about, `_attempted`
    // counts the ones that had a probe at all, and `_resolved` counts the
    // answers that came back with a real rev.
    property var _queue: []
    property int _attempted: 0
    property int _resolved: 0
    property string _probeKind: ""
    property string _probeName: ""

    function _probe() {
        if (root.flakeDir === "")
            return;
        root.pollState = "checking";
        root._queue = root.inputs.slice();
        root._attempted = 0;
        root._resolved = 0;
        root._next();
    }

    function _next() {
        if (probeProc.running)
            return;
        while (root._queue.length > 0) {
            var input = root._queue.shift();
            var cmd = Update.probeCommand(input);
            // An input type with no cheap probe stays unknown; it is not a
            // failed probe, so it must not count toward NO NETWORK.
            if (cmd.kind === "none")
                continue;
            root._probeKind = cmd.kind;
            root._probeName = input.name;
            root._attempted += 1;
            probeProc.command = cmd.argv;
            probeProc.running = true;
            return;
        }
        // Every probe that ran failed to reach its forge, so the answer is
        // about the network rather than about any one input.
        root.pollState = (root._attempted > 0 && root._resolved === 0) ? "offline" : "ok";
    }

    Process {
        id: probeProc
        stdout: StdioCollector {
            id: probeCollector
        }
        onExited: exitCode => {
            var rev = Update.parseProbe(root._probeKind, exitCode, probeCollector.text).rev;
            var next = {};
            for (var k in root.heads)
                next[k] = root.heads[k];
            next[root._probeName] = rev;
            root.heads = next;
            if (rev !== "")
                root._resolved += 1;
            root._next();
        }
    }

    function _poll() {
        if (root.flakeDir === "") {
            root.pollState = "noflake";
            return;
        }
        lockFile.reload();
    }

    onPollEnabledChanged: if (root.pollEnabled) root._poll()
    onIsOpenChanged: {
        if (!root.isOpen)
            return;
        root._poll();
        root.cursorIndex = 0;
        root.cursorSection = 0;
    }

    Timer {
        interval: root._interval
        running: root.pollEnabled
        repeat: true
        onTriggered: root._poll()
    }

    // A poll right after a reconnect rather than showing NO NETWORK for up
    // to three hours (TailscalePanel makes the same call).
    Connections {
        target: ConnectivityService
        function onReconnected() {
            if (root.pollEnabled || root.isOpen)
                root._poll();
        }
    }

    // No flake directory configured at all means there is no subject to
    // promote, so the hero gives way to the model's own one-line answer.
    Cell {
        visible: root.flakeDir === ""
        width: parent.width

        SectionLabel { text: root.summary }
    }

    // The panel's own subject once a directory is named: which flake, what
    // the last check said, and how many of its inputs are behind. The
    // readout only carries a number while a poll has actually resolved, so
    // CHECKING and NO NETWORK never sit under a stale count.
    PanelHero {
        id: hero
        visible: root.flakeDir !== ""
        width: parent.width
        title: root._flakeName
        meta: root.summary
        readout: root.pollState === "ok" ? String(root.counts.behind) : ""

        leading: Component {
            Icon {
                name: "package"
                size: Theme.fontSize.heading
                color: hero.foreground
            }
        }
    }

    Component {
        id: inputRow

        Cell {
            id: inputCell
            required property int index
            required property var modelData
            width: parent.width

            readonly property string _status: Update.rowStatus(inputCell.modelData, root.heads)

            cursor: root.cursorActive && root.cursorSection === 0 && root.cursorIndex === inputCell.index
            warning: inputCell._status === "BEHIND"

            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (inputCell.containsPointer) {
                root.cursorActive = true;
                root.cursorSection = 0;
                root.cursorIndex = inputCell.index;
            }

            Item {
                width: parent.width
                height: Math.max(nameText.implicitHeight, revText.implicitHeight, statusText.implicitHeight)

                Text {
                    id: nameText
                    anchors.left: parent.left
                    anchors.right: revText.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    text: inputCell.modelData.name
                    color: inputCell.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                    elide: Text.ElideRight
                }

                // A locked revision is an identifier, so it takes the mono
                // face (spec "Type").
                Text {
                    id: revText
                    anchors.right: statusText.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    text: Update.shortRev(inputCell.modelData.rev)
                    color: inputCell.dimForeground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.caption
                }

                SectionLabel {
                    id: statusText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: inputCell._status
                    color: inputCell._status === "BEHIND" ? Theme.color.warning : inputCell.dimForeground
                }
            }
        }
    }

    Column {
        width: parent.width
        visible: root.inputs.length > 0
        spacing: Theme.space.rowGap

        SectionLabel { text: "INPUTS"; count: root.inputs.length }

        Cell {
            visible: root.pollState === "ok" && root.counts.unknown > 0
            width: parent.width

            SectionLabel { text: root.counts.unknown + " UNKNOWN" }
        }

        Repeater {
            model: root.inputs
            delegate: inputRow
        }
    }

    // Footer (spec "Panels"): the outline action on the left, the figure it
    // produces on the right.
    Item {
        width: parent.width
        height: Math.max(checkButton.height, behindRow.implicitHeight)

        Button {
            id: checkButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            variant: "outline"
            icon: "refresh-cw"
            text: root.pollState === "checking" ? "Checking" : "Check"
            enabled: root.flakeDir !== "" && root.pollState !== "checking"
            cursor: root.cursorActive && root.cursorSection === 1
            onClicked: root._poll()
        }

        Row {
            id: behindRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.xs

            Text {
                id: behindValue
                text: root.pollState === "ok" ? String(root.counts.behind) : "--"
                color: Theme.color.foreground
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize.display
                font.weight: Theme.weight.semibold
            }

            SectionLabel {
                text: "BEHIND"
                anchors.bottom: behindValue.bottom
                anchors.bottomMargin: Theme.space.xs
            }
        }
    }
}
