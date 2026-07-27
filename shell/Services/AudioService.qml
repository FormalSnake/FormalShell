pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default-sink volume/mute, backed by Quickshell's native Pipewire client
// (no wpctl/pactl spawning). Verified against quickshell source
// (src/services/pipewire/qml.hpp): PwNode.audio's volume/muted are marked
// "invalid unless the node is bound using PwObjectTracker" — the tracker
// below is load-bearing, not decoration. Binding the node is also what
// makes external changes (wpctl, pavucontrol, another client) observable:
// PwNodeAudio's volume/muted are live Q_PROPERTYs once bound, so they pick
// up both our own writes and anyone else's.
Singleton {
    id: root

    readonly property var _sink: Pipewire.defaultAudioSink
    readonly property var _sinkAudio: _sink?.audio ?? null

    readonly property bool available: _sinkAudio !== null
    property real volume: _sinkAudio ? _sinkAudio.volume : 0
    property bool muted: _sinkAudio ? _sinkAudio.muted : false

    // Fired whenever the bound sink's volume or mute state changes, ours or
    // someone else's — the OSD (M5 Task 6) shows on this, not on setVolume()
    // being called directly.
    signal changed

    PwObjectTracker {
        objects: root._sink ? [root._sink] : []
    }

    function setVolume(v) {
        if (!root._sinkAudio)
            return;
        root._sinkAudio.volume = Math.max(0, Math.min(1, v));
    }

    function toggleMute() {
        if (!root._sinkAudio)
            return;
        root._sinkAudio.muted = !root._sinkAudio.muted;
    }

    Connections {
        target: root._sinkAudio
        function onVolumeChanged() { root.changed(); }
        function onMutedChanged() { root.changed(); }
    }
}
