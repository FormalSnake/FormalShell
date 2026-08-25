import QtQuick
import QtMultimedia
import qs.Core
import qs.Services

// Apple Music animated cover overlay (M7 Task 2, spec §5; frames shared with
// the bar's mini cover, M35). Loaded from MediaPanel.qml via `Loader {
// source: "AnimatedAlbumArt.qml" }` rather than a direct `import
// QtMultimedia` there, which keeps a missing QtMultimedia module a failure of
// this one Loader's component creation instead of the whole now-playing
// panel, so the static album art beneath is always the honest fallback rather
// than a broken panel.
//
// The Timer at ~8fps grabs the Video's current frame (`Item.grabToImage`,
// ground-truthed against real Wayland/Quickshell rendering in the VM rig:
// the offscreen qmltestrunner path alone never exercises this) and publishes
// it to `AnimatedCoverFrameSource.frameUrl`, which is where the bar's mini
// cover (NowPlaying.qml) reads its frames from. One decode feeds both
// surfaces.
//
// `visible` folds in the full motion carve-out (DESIGN §4): a decoded,
// error-free, actually-playing frame AND `Theme.motionEnabled`. Motion
// disabled, paused, stalled, or errored all fall through to the same state,
// invisible, letting the static art beneath show instead. This Loader itself
// only exists while AnimatedCoverFrameSource.active is true
// (MediaPanel.qml), so `visible` here is a finer-grained gate on top of
// that: the Video can exist for a moment before it has actually started
// playing real frames.
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

    Timer {
        interval: 120
        repeat: true
        running: root.visible
        onTriggered: video.grabToImage(function (result) { AnimatedCoverFrameSource.frameUrl = result.url; })
    }
}
