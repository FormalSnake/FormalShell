pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
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
// MprisPlayer.position doesn't emit positionChanged on ordinary playback
// ticks (only on nonlinear jumps) per quickshell's own player.hpp docs — the
// Timer below is the documented workaround: manually re-emit the signal
// while playing so bindings that read `position` (the panel's progress fill)
// actually advance.
Singleton {
    id: root

    readonly property var _players: Mpris.players.values

    // Plain rows, built here so every live property read happens inside this
    // binding rather than inside Media/model.js. The pick itself is pure.
    readonly property var players: MediaModel.withLabels(root._players.map(function (p) {
        return { id: p.dbusName, identity: p.identity, isPlaying: p.isPlaying };
    }))

    // A bus name, opaque and only ever compared for equality. Set by the
    // panel's switcher or `media select`; survives until that player quits,
    // at which point pickPlayerId falls back on its own.
    property string selectedId: ""

    readonly property string activeId: MediaModel.pickPlayerId(root.players, root.selectedId)

    readonly property var activePlayer: {
        for (var i = 0; i < root._players.length; i++)
            if (root._players[i].dbusName === root.activeId)
                return root._players[i];
        return null;
    }

    readonly property bool available: root.activePlayer !== null
    readonly property string title: root.activePlayer ? root.activePlayer.trackTitle : ""
    readonly property string artist: root.activePlayer ? root.activePlayer.trackArtist : ""
    readonly property string album: root.activePlayer ? root.activePlayer.trackAlbum : ""
    readonly property string artUrl: root.activePlayer ? root.activePlayer.trackArtUrl : ""
    readonly property string identity: root.activePlayer ? root.activePlayer.identity : ""
    readonly property bool isPlaying: root.activePlayer ? root.activePlayer.isPlaying : false
    readonly property bool canGoNext: root.activePlayer ? root.activePlayer.canGoNext : false
    readonly property bool canGoPrevious: root.activePlayer ? root.activePlayer.canGoPrevious : false
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
    // sink says system-wide.
    readonly property bool volumeSupported: root.activePlayer ? root.activePlayer.volumeSupported : false
    readonly property real volume: root.activePlayer ? MediaModel.clampVolume(root.activePlayer.volume) : 0

    readonly property bool canRaise: root.activePlayer ? root.activePlayer.canRaise : false

    function select(id) {
        root.selectedId = String(id || "");
    }

    function playPause() {
        if (root.activePlayer && root.activePlayer.canTogglePlaying)
            root.activePlayer.togglePlaying();
    }

    function next() {
        if (root.activePlayer && root.activePlayer.canGoNext)
            root.activePlayer.next();
    }

    function previous() {
        if (root.activePlayer && root.activePlayer.canGoPrevious)
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
        if (root.volumeSupported)
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
