pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default-sink volume/mute, backed by Quickshell's native Pipewire client
// (no wpctl/pactl spawning). Verified against quickshell source
// (src/services/pipewire/qml.hpp): PwNode.audio's volume/muted are marked
// "invalid unless the node is bound using PwObjectTracker", the tracker
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

    // The capture side is the same PwNode type carrying the same audio
    // interface; there is no separate microphone API and no
    // PwNodeAudio.inputMuted. Confirmed against the pinned quickshell source
    // (rev 43d4fa9): src/services/pipewire/qml.hpp:107 declares
    // Pipewire.defaultAudioSource as a PwNodeIface*, :312 gives PwNode its
    // `audio` PwNodeAudioIface*, and :226 declares that interface's `muted`
    // (WRITE setMuted, NOTIFY mutedChanged).
    readonly property var _source: Pipewire.defaultAudioSource
    readonly property var _sourceAudio: _source?.audio ?? null

    // Mute only, no gain: MicWidget reads these two and calls
    // toggleSourceMute(), and there is no input slider anywhere, so a
    // sourceVolume/setSourceVolume pair would have no caller. There is also
    // no source counterpart to `changed` below, deliberately: Osd.qml
    // auto-shows on that signal, and a mic mute popping the volume OSD would
    // be wrong. Both properties are plain bindings on the bound node, so they
    // update without one.
    readonly property bool sourceAvailable: _sourceAudio !== null
    property bool sourceMuted: _sourceAudio ? _sourceAudio.muted : false

    readonly property string sinkName: root._sink?.name ?? ""
    readonly property string sourceName: root._source?.name ?? ""

    function _find(name) {
        var nodes = Pipewire.nodes.values;
        for (var i = 0; i < nodes.length; i++) {
            if (nodes[i].name === name && nodes[i].audio !== null && !nodes[i].isStream)
                return nodes[i];
        }
        return null;
    }

    function setDefaultSink(name) {
        var node = root._find(name);
        if (!node || !node.isSink)
            return false;
        Pipewire.preferredDefaultAudioSink = node;
        return true;
    }

    function setDefaultSource(name) {
        var node = root._find(name);
        if (!node || node.isSink)
            return false;
        Pipewire.preferredDefaultAudioSource = node;
        return true;
    }

    // Fired whenever the bound sink's volume or mute state changes, ours or
    // someone else's, the OSD (M5 Task 6) shows on this, not on setVolume()
    // being called directly.
    signal changed

    PwObjectTracker {
        // Both nodes, and binding the source is load-bearing rather than
        // decoration: qml.hpp marks PwNodeAudio's volume/muted invalid unless
        // the node is bound here, so an unbound source would report
        // muted=false forever.
        objects: [root._sink, root._source].filter(n => n)
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

    function toggleSourceMute() {
        if (!root._sourceAudio)
            return;
        root._sourceAudio.muted = !root._sourceAudio.muted;
    }

    // PwNodeAudioIface's Q_PROPERTY for the averaged `volume` is declared
    // `NOTIFY volumesChanged` (plural, the signal backing the `volumes`
    // vector, reused for the average), there is no `volumeChanged` signal
    // to connect to. A singular `onVolumeChanged` handler here silently
    // never fires, so a pure volume change (no mute toggle) never emitted
    // `changed()`, and neither the OSD nor anything else keyed off it ever
    // auto-showed for an external volume change (e.g. wpctl, hardware keys).
    Connections {
        target: root._sinkAudio
        function onVolumesChanged() { root._report(); }
        function onMutedChanged() { root._report(); }
    }

    // A default-sink swap is not a volume change: AirPods leaving or joining
    // hands `_sink` to another node at its own level, and a node that was
    // just bound reports 0 before its real volume; neither is the user
    // turning a knob. Only a move on the same ready sink, away from what it
    // last reported, counts; everything else re-baselines.
    property var _reportedSink: null
    property real _reportedVolume: -1
    property bool _reportedMuted: false

    function _report() {
        var sink = root._sink;
        if (!sink || !sink.ready || !root._sinkAudio)
            return;
        var audio = root._sinkAudio;
        var moved = sink === root._reportedSink
            && (audio.volume !== root._reportedVolume || audio.muted !== root._reportedMuted);
        root._reportedSink = sink;
        root._reportedVolume = audio.volume;
        root._reportedMuted = audio.muted;
        if (moved)
            root.changed();
    }

    Connections {
        target: root._sink
        function onReadyChanged() { root._report(); }
    }
    on_SinkChanged: root._report()
}
