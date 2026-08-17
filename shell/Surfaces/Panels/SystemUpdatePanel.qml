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
// panel's header and the bar cell render, so the two can never disagree.
// An input type with no cheap probe (path, tarball, indirect, sourcehut)
// is "?" forever rather than a fabricated CURRENT.
Panel {
    id: root

    panelTitle: "SYSTEM UPDATE"
    panelWidth: Theme.space.popupWidthDefault

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
    onIsOpenChanged: if (root.isOpen) root._poll()

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

    Cell {
        width: parent.width

        MetaLabel { text: root.summary }
    }

    Cell {
        visible: root.inputs.length > 0
        width: parent.width

        MetaLabel { text: "INPUTS"; colon: true }
    }

    Component {
        id: inputRow

        Cell {
            id: inputCell
            required property var modelData
            width: parent.width

            readonly property string _status: Update.rowStatus(inputCell.modelData, root.heads)

            Row {
                width: parent.width
                spacing: Theme.space.sm

                Text {
                    width: parent.width - revText.width - statusText.width - parent.spacing * 2
                    text: inputCell.modelData.name
                    color: inputCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                    elide: Text.ElideRight
                }

                Text {
                    id: revText
                    anchors.verticalCenter: parent.verticalCenter
                    text: Update.shortRev(inputCell.modelData.rev)
                    color: Theme.color.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.caption
                }

                MetaLabel {
                    id: statusText
                    anchors.verticalCenter: parent.verticalCenter
                    text: inputCell._status
                    color: inputCell._status === "BEHIND" ? Theme.color.warning : Theme.color.foregroundDim
                }
            }
        }
    }

    Repeater {
        model: root.inputs
        delegate: inputRow
    }
}
