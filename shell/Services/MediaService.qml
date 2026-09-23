pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../Audio/model.js" as AudioModel
import "../Media/model.js" as MediaModel

// MPRIS now-playing state (DESIGN.md §Bar/§Panels, spec §5, M7 Task 1):
// exposes one "active player" (the explicitly selected one while it is
// still registered, otherwise an actually-playing one, otherwise the first
// registered player, otherwise null) so the bar cell and panel never have
// to pick between several simultaneous players themselves. Honest
// `available: false` (no player at all) rather than a zero/placeholder
// state, same rule Battery.qml/BluetoothWidget.qml follow.
//
// Everything MPRIS defines and a now-playing surface can act on is exposed
// here: transport, seek, shuffle, LoopStatus, per-player Volume, and Raise.
// Each is gated on the player's own capability flag
// (`shuffleSupported`/`loopSupported`/`volumeSupported`/`canRaise`), so a
// player that doesn't implement one costs a cell rather than showing a
// control that silently does nothing. Rating is deliberately absent:
// `xesam:userRating` is read-only metadata and MPRIS has no set-rating call
// at all, so a like button would be a per-app D-Bus dialect, not a feature.
//
// Three kinds of source share one row list (`players`), and every property
// below reads the active one whatever its kind: an MPRIS player; the radio
// (RadioService, `id: "radio"`), listed while a station is tuned; and an app
// playing audio with no MPRIS at all (`stream:<node id>`), listed only while
// the media panel is open or one is picked, and only ever picked by hand,
// since the most it offers is its own stream volume. `selectedId` "" is auto.
//
// The output a source plays on is read off Pipewire's link groups and moved
// with `pactl move-sink-input` (quickshell has no move of its own); the radio
// moves by telling its own mpv, which also keeps it there across restarts.
//
// MprisPlayer.position doesn't emit positionChanged on ordinary playback
// ticks (only on nonlinear jumps) per quickshell's own player.hpp docs, the
// Timer below is the documented workaround: manually re-emit the signal
// while playing so bindings that read `position` (the panel's progress fill)
// actually advance.
Singleton {
    id: root

    readonly property var _players: Mpris.players.values

    // Set by the media panel while it is open: the stream and sink lists
    // bind every Pipewire node they read, which is a standing cost no closed
    // surface should pay (AudioPanel.qml carries the same gate).
    property bool routingWanted: false

    // A bus name, "radio" or "stream:<node id>", opaque and only ever
    // compared for equality. Set by the panel's source menu or `media
    // select`; survives until that source goes, at which point pickPlayerId
    // falls back on its own.
    property string selectedId: ""

    readonly property var _mprisRows: root._players.map(function (p) {
        return { id: p.dbusName, kind: "mpris", identity: p.identity, isPlaying: p.isPlaying };
    })

    readonly property var _radioRows: RadioService.running
        ? [{ id: "radio", kind: "radio", identity: "Radio", isPlaying: !RadioService.paused }]
        : []

    readonly property bool _streamsLive: root.routingWanted || root.selectedId.indexOf("stream:") === 0
    readonly property var _streamNodes: root._streamsLive ? Pipewire.nodes.values.filter(function (n) {
        return n.audio !== null && AudioModel.isPlaybackStream(n);
    }) : []
    readonly property var _sinkNodes: root.routingWanted ? Pipewire.nodes.values.filter(function (n) {
        return n.audio !== null && !n.isStream && n.isSink;
    }) : []

    PwObjectTracker {
        objects: root._streamNodes.concat(root._sinkNodes)
    }

    // Every playback stream and whose it is: "radio" by the client name the
    // radio's mpv stamps on its stream, a player's bus name by
    // MediaModel.streamOwner, "" for an app with no MPRIS. `properties` is
    // only read once the node is bound.
    readonly property var _streams: root._streamNodes.filter(function (n) {
        return n.ready;
    }).map(function (n) {
        var props = n.properties || {};
        var owner = props["application.name"] === RadioService.clientName ? "radio"
            : MediaModel.streamOwner([props["application.name"], props["application.process.binary"],
                props["application.id"], n.name], root._mprisRows);
        return {
            node: n,
            id: "stream:" + n.id,
            owner: owner,
            label: AudioModel.streamLabel(props, n.description, n.name),
            title: String(props["media.name"] || "")
        };
    })

    readonly property var _streamRows: root._streams.filter(function (s) {
        return s.owner === "";
    }).map(function (s) {
        return { id: s.id, kind: "stream", auto: false, identity: s.label, isPlaying: false };
    })

    // Plain rows, built here so every live property read happens inside this
    // binding rather than inside Media/model.js. The pick itself is pure.
    readonly property var players: MediaModel.withLabels(root._mprisRows.concat(root._radioRows, root._streamRows))

    readonly property string activeId: MediaModel.pickPlayerId(root.players, root.selectedId)
    readonly property string activeKind: root.activeId === "" ? ""
        : root.activeId === "radio" ? "radio"
        : root.activeId.indexOf("stream:") === 0 ? "stream" : "mpris"
    readonly property string activeLabel: {
        for (var i = 0; i < root.players.length; i++)
            if (root.players[i].id === root.activeId)
                return root.players[i].label;
        return "";
    }

    readonly property var activePlayer: {
        if (root.activeKind !== "mpris")
            return null;
        for (var i = 0; i < root._players.length; i++)
            if (root._players[i].dbusName === root.activeId)
                return root._players[i];
        return null;
    }

    readonly property var _activeStream: {
        if (root.activeKind !== "stream")
            return null;
        for (var i = 0; i < root._streams.length; i++)
            if (root._streams[i].id === root.activeId)
                return root._streams[i];
        return null;
    }

    readonly property bool _radio: root.activeKind === "radio"
    readonly property var _station: root._radio ? RadioService.station : null

    readonly property bool available: root.activePlayer !== null || root._radio || root._activeStream !== null
    // Only an MPRIS player has a track with a position and a length; the
    // radio is live and an app stream says nothing about either.
    readonly property bool hasTimeline: root.activePlayer !== null
    readonly property string title: root.activePlayer ? root.activePlayer.trackTitle
        : root._station ? (RadioService.trackTitle || String(root._station.name || ""))
        : root._activeStream ? (root._activeStream.title || root._activeStream.label) : ""
    readonly property string artist: root.activePlayer ? root.activePlayer.trackArtist
        : root._station && RadioService.trackTitle !== "" ? String(root._station.name || "") : ""
    readonly property string album: root.activePlayer ? root.activePlayer.trackAlbum : ""
    readonly property string artUrl: root.activePlayer ? root.activePlayer.trackArtUrl : ""
    // `xesam:url` has no dedicated MprisPlayer property (only trackArtUrl
    // does); it comes straight out of the raw metadata map (LyricsService's
    // sibling-.lrc lookup, spec P2.1).
    readonly property string url: root.activePlayer && root.activePlayer.metadata ? (root.activePlayer.metadata["xesam:url"] || "") : ""
    readonly property string identity: root.activePlayer ? root.activePlayer.identity : root.activeLabel
    readonly property bool isPlaying: root.activePlayer ? root.activePlayer.isPlaying
        : root._radio ? !RadioService.paused : false
    readonly property bool canPlayPause: root.activePlayer ? root.activePlayer.canTogglePlaying : root._radio
    readonly property bool canGoNext: root.activePlayer ? root.activePlayer.canGoNext
        : root._radio && RadioService.queue.length > 1
    readonly property bool canGoPrevious: root.activePlayer ? root.activePlayer.canGoPrevious
        : root._radio && RadioService.queue.length > 1
    readonly property bool canSeek: root.activePlayer ? (root.activePlayer.canSeek && root.activePlayer.positionSupported) : false
    readonly property real position: root.activePlayer ? root.activePlayer.position : 0
    readonly property real length: root.activePlayer ? root.activePlayer.length : 0

    readonly property bool shuffleSupported: root.activePlayer ? root.activePlayer.shuffleSupported : false
    readonly property bool shuffle: root.activePlayer ? root.activePlayer.shuffle : false

    readonly property bool loopSupported: root.activePlayer ? root.activePlayer.loopSupported : false
    readonly property string loopState: {
        if (!root.activePlayer)
            return "none";
        switch (root.activePlayer.loopState) {
        case MprisLoopState.Track:
            return "track";
        case MprisLoopState.Playlist:
            return "playlist";
        default:
            return "none";
        }
    }

    // MPRIS Volume is the player's own 0..1 double, unrelated to the sink
    // volume AudioService owns: a browser at 0.5 here is still whatever the
    // sink says system-wide. The radio's is mpv's own 0..100, and an app
    // stream's is its Pipewire node volume, the same number the audio panel's
    // per-app slider moves.
    readonly property bool volumeSupported: root.activePlayer ? root.activePlayer.volumeSupported
        : root._radio || (root._activeStream !== null && root._activeStream.node.audio !== null)
    readonly property real volume: root.activePlayer ? MediaModel.clampVolume(root.activePlayer.volume)
        : root._radio ? RadioService.volume / 100
        : root._activeStream && root._activeStream.node.audio ? MediaModel.clampVolume(root._activeStream.node.audio.volume) : 0

    readonly property bool canRaise: root.activePlayer ? root.activePlayer.canRaise : false

    // ---- Output ---------------------------------------------------------

    readonly property var outputs: root._sinkNodes.map(function (n) {
        return { id: n.name, label: n.description || n.nickname || n.name };
    })

    // The streams the active source is playing through right now.
    readonly property var _routedStreams: root._activeStream ? [root._activeStream.node]
        : root._streams.filter(function (s) {
            return s.owner !== "" && s.owner === root.activeId;
        }).map(function (s) {
            return s.node;
        })

    readonly property bool canRoute: root.outputs.length > 1 && (root._radio || root._routedStreams.length > 0)

    // The sink name the active source is on: the radio's saved choice (""
    // being the default sink), otherwise whatever the first of its streams is
    // linked to.
    readonly property string outputId: {
        var fallback = Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.name : "";
        if (root._radio)
            return RadioService.output || fallback;
        if (root._routedStreams.length === 0)
            return "";
        var groups = Pipewire.linkGroups.values;
        for (var i = 0; i < groups.length; i++)
            if (groups[i].source && groups[i].target && groups[i].source.id === root._routedStreams[0].id)
                return groups[i].target.name;
        return fallback;
    }

    function setOutput(name) {
        var sink = String(name || "");
        if (!root.outputs.some(function (o) { return o.id === sink; }))
            return;
        if (root._radio) {
            var fallback = Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.name : "";
            RadioService.setOutput(sink === fallback ? "" : sink);
            return;
        }
        var ids = root._routedStreams.map(function (n) { return n.id; });
        if (ids.length === 0)
            return;
        moveList.targetSink = sink;
        moveList.nodeIds = ids;
        moveList.running = true;
    }

    // Two steps, since pactl addresses a stream by its sink-input index and
    // Pipewire by its node id: list the sink inputs, then move each one found.
    Process {
        id: moveList
        property string targetSink: ""
        property var nodeIds: []
        command: ["pactl", "-f", "json", "list", "sink-inputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                var indices = moveList.nodeIds.map(function (id) {
                    return MediaModel.sinkInputIndex(text, id);
                }).filter(function (i) {
                    return i >= 0;
                });
                if (indices.length === 0)
                    return;
                var script = indices.map(function (i) {
                    return "pactl move-sink-input " + i + " \"$1\"";
                }).join("; ");
                moveRun.command = ["sh", "-c", script, "sh", moveList.targetSink];
                moveRun.running = true;
            }
        }
    }

    Process {
        id: moveRun
    }

    function select(id) {
        root.selectedId = String(id || "");
    }

    function playPause() {
        if (root._radio)
            RadioService.toggle();
        else if (root.activePlayer && root.activePlayer.canTogglePlaying)
            root.activePlayer.togglePlaying();
    }

    function next() {
        if (root._radio)
            RadioService.next();
        else if (root.activePlayer && root.activePlayer.canGoNext)
            root.activePlayer.next();
    }

    function previous() {
        if (root._radio)
            RadioService.previous();
        else if (root.activePlayer && root.activePlayer.canGoPrevious)
            root.activePlayer.previous();
    }

    function seek(fraction) {
        if (!root.canSeek || root.activePlayer.length <= 0)
            return;
        root.activePlayer.position = MediaModel.clampFraction(fraction) * root.activePlayer.length;
    }

    function setShuffle(on) {
        if (root.shuffleSupported)
            root.activePlayer.shuffle = on === true;
    }

    function toggleShuffle() {
        root.setShuffle(!root.shuffle);
    }

    function setLoop(name) {
        if (!root.loopSupported || !MediaModel.isLoopName(name))
            return;
        if (name === "track")
            root.activePlayer.loopState = MprisLoopState.Track;
        else if (name === "playlist")
            root.activePlayer.loopState = MprisLoopState.Playlist;
        else
            root.activePlayer.loopState = MprisLoopState.None;
    }

    function cycleLoop() {
        root.setLoop(MediaModel.nextLoop(root.loopState));
    }

    function setVolume(v) {
        if (!root.volumeSupported)
            return;
        if (root._radio)
            RadioService.setVolume(MediaModel.clampVolume(v) * 100);
        else if (root._activeStream)
            root._activeStream.node.audio.volume = MediaModel.clampVolume(v);
        else
            root.activePlayer.volume = MediaModel.clampVolume(v);
    }

    function raise() {
        if (root.canRaise)
            root.activePlayer.raise();
    }

    Timer {
        interval: 1000
        running: root.isPlaying
        repeat: true
        onTriggered: if (root.activePlayer) root.activePlayer.positionChanged();
    }
}
