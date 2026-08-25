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
// Two independent "who wants frames" signals feed one gate, mirroring
// VisualizerService's own precedent: `panelWants` is a single flag
// (MediaPanel is a shell-wide singleton instance, shell.qml) bound straight
// off its own isOpen; `_barWanters` is a refcount that NowPlaying.qml
// instances drive through setBarWantsFrames() using the same
// wasWanted/isWanted no-op guard VisualizerService.setBarVisible uses, so a
// caller can call on every visibility change without tracking whether it
// actually flipped.
Singleton {
    id: root

    property bool panelWants: false
    property int _barWanters: 0

    function setBarWantsFrames(wasWanted, isWanted) {
        if (wasWanted === isWanted)
            return;
        root._barWanters += isWanted ? 1 : -1;
    }

    // The full gate (DESIGN.md §4 item 8's visualizer precedent, restated
    // for a decode instead of a child process): any leg going false kills
    // the decode outright, MediaPanel's Loader unloads its Video entirely
    //, never just a paused paint.
    readonly property bool active: (root.panelWants || root._barWanters > 0)
        && MediaService.isPlaying && AppleMusicArtService.animatedArtUrl !== "" && Theme.motionEnabled

    // Latest grabbed frame, published by AnimatedAlbumArt.qml's own Timer.
    // Every consumer (the panel's own dither pass, NowPlaying's mini cover)
    // reads this instead of touching the Video directly. Cleared the moment
    // the gate drops so a consumer that re-activates later never paints a
    // stale frame from a previous track or session.
    property url frameUrl: ""

    onActiveChanged: if (!root.active) root.frameUrl = "";
}
