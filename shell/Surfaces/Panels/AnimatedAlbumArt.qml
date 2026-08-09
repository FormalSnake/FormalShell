import QtQuick
import QtMultimedia
import qs.Core
import qs.Components
import qs.Services

// Apple Music animated cover overlay (M7 Task 2, spec §5; dithered by M20
// Task 3). Loaded from MediaPanel.qml via `Loader { source:
// "AnimatedAlbumArt.qml" }` rather than a direct `import QtMultimedia`
// there — that keeps a missing QtMultimedia module a failure of this one
// Loader's component creation, not of the whole now-playing panel, so the
// static album-art DitherImage beneath is always the honest fallback
// rather than a broken panel.
//
// The Video decodes normally underneath but is never the visible content:
// a Timer at ~8fps grabs its current frame (`Item.grabToImage`, ground-
// truthed against real Wayland/Quickshell rendering in the mac VM rig —
// the offscreen qmltestrunner path alone never exercises this) and hands
// the grab result straight to DitherImage's `source`, which repaints its
// own 1-bit duotone pass on every new frame. The choppy ~8fps cadence is
// the intended aesthetic (DESIGN.md §2), not a defect.
//
// `visible` folds in the full motion carve-out (DESIGN §4): a decoded,
// error-free, actually-playing frame AND `Theme.motionEnabled`. Motion
// disabled, paused, stalled, or errored all fall through to the same
// state — invisible, letting the static art beneath show instead — so
// there is never a frame where the raw Video is the only thing painted.
Item {
    id: root

    visible: Theme.motionEnabled && video.hasVideo && video.playbackState === MediaPlayer.PlayingState && video.error === MediaPlayer.NoError

    Video {
        id: video
        anchors.fill: parent
        source: AppleMusicArtService.animatedArtUrl
        fillMode: VideoOutput.PreserveAspectCrop
        loops: MediaPlayer.Infinite
        muted: true
        onSourceChanged: if (source != "") play();
        Component.onCompleted: if (source != "") play();
    }

    DitherImage {
        id: dither
        anchors.fill: parent
    }

    Timer {
        interval: 120
        repeat: true
        running: root.visible
        onTriggered: video.grabToImage(function (result) { dither.source = result.url; })
    }
}
