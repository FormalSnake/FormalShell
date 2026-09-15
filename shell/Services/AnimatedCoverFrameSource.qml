pragma Singleton
import QtQuick
import Quickshell
import qs.Core
import qs.Services

// Shared gate + frame republisher for the Apple Music animated cover (M35,
// owner: "the bar mini cover doesnt appear to be animated ... like the
// image in the bar, the panel is fine", DESIGN.md §2 item 12 reversal).
// MediaPanel.qml's own AnimatedAlbumArt Loader stays the ONLY QtMultimedia
// Video decode in the shell; this singleton decides when that Loader may
// exist and republishes the frames it grabs so NowPlaying.qml's bar-side
// mini cover paints from the exact same frames instead of a second decode
// for a slot this small.
//
// `media.animatedBarCover` (on by default) is what lets `_barWanters`
// reach the gate. Off, the decode, the grab timer and MediaPanel's
// `keepMapped` exist only while the panel itself is open, like any other
// popout: the escape hatch for a machine where a video decode behind a
// 16px bar cover is not worth it.
Singleton {
    id: root

    readonly property bool barEnabled: Config.get("media.animatedBarCover", true)
    property bool panelWants: false
    property int _barWanters: 0

    function setBarWantsFrames(wasWanted, isWanted) {
        if (wasWanted === isWanted)
            return;
        root._barWanters += isWanted ? 1 : -1;
    }

    // The load gate (DESIGN.md §4 item 8's visualizer precedent, restated
    // for a decode instead of a child process): any leg going false kills
    // the decode outright, MediaPanel's Loader unloads its Video entirely.
    // `MediaService.isPlaying` is deliberately NOT in here (A6, owner,
    // 2026-09-15): folding pause into the load gate is what dropped the
    // Loader on every pause and swapped the animated cover for the static
    // one, which read as broken rather than paused. Whether the Video
    // actually runs is `playing`, below.
    readonly property bool active: (root.panelWants || (root.barEnabled && root._barWanters > 0))
        && AppleMusicArtService.animatedArtUrl !== "" && Theme.motionEnabled

    // Drives the decoder and the grab Timer (AnimatedAlbumArt.qml). Loaded
    // but not playing is a paused track: the Video stays mapped on its last
    // frame instead of unloading.
    readonly property bool playing: root.active && MediaService.isPlaying

    // Latest grabbed frame, published by AnimatedAlbumArt.qml's own Timer.
    // Every consumer (the panel's own dither pass, NowPlaying's mini cover)
    // reads this instead of touching the Video directly. Cleared when the
    // load gate drops or the track's art changes, never on a pause, so a
    // held frame survives exactly as long as it's still honest.
    property url frameUrl: ""

    onActiveChanged: if (!root.active) root.frameUrl = "";

    Connections {
        target: AppleMusicArtService
        function onAnimatedArtUrlChanged() {
            root.frameUrl = "";
        }
    }
}
