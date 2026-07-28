pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// MPRIS now-playing state (DESIGN.md §Bar/§Panels, spec §5, M7 Task 1):
// exposes one "active player" — an actually-playing one if any exists,
// otherwise the first registered player, otherwise null — so the bar cell
// and panel never have to pick between several simultaneous players
// themselves. Honest `available: false` (no player at all) rather than a
// zero/placeholder state, same rule Battery.qml/BluetoothWidget.qml follow.
//
// MprisPlayer.position doesn't emit positionChanged on ordinary playback
// ticks (only on nonlinear jumps) per quickshell's own player.hpp docs — the
// Timer below is the documented workaround: manually re-emit the signal
// while playing so bindings that read `position` (the panel's progress fill)
// actually advance.
Singleton {
    id: root

    readonly property var _players: Mpris.players.values

    readonly property var activePlayer: {
        for (var i = 0; i < root._players.length; i++)
            if (root._players[i].isPlaying)
                return root._players[i];
        return root._players.length > 0 ? root._players[0] : null;
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
        root.activePlayer.position = Math.max(0, Math.min(1, fraction)) * root.activePlayer.length;
    }

    Timer {
        interval: 1000
        running: root.isPlaying
        repeat: true
        onTriggered: if (root.activePlayer) root.activePlayer.positionChanged();
    }
}
