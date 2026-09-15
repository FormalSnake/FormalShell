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
// error-free frame, playing or paused, AND `Theme.motionEnabled`. Motion
// disabled, stalled, or errored fall through to invisible, letting the
// static art beneath show instead; a pause (A6) stays visible on its held
// frame rather than falling back. This Loader itself only exists while
// AnimatedCoverFrameSource.active is true (MediaPanel.qml), so `visible`
// here is a finer-grained gate on top of that: the Video can exist for a
// moment before it has actually started playing real frames.
//
// The decode is software only (nix/package.nix sets
// QT_FFMPEG_DECODING_HW_DEVICE_TYPES empty): a VA-API frame on the NVIDIA
// driver hung the render thread inside vaSyncSurface and froze the whole
// shell with it (g815, 2026-09-11). Never hand this Video a hardware frame.
Item {
    id: root

    visible: Theme.motionEnabled && video.hasVideo && video.error === MediaPlayer.NoError
        && (video.playbackState === MediaPlayer.PlayingState || video.playbackState === MediaPlayer.PausedState)

    function _grab() {
        video.grabToImage(function (result) { AnimatedCoverFrameSource.frameUrl = result.url; });
    }

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

    // Mirrors the song's own playing state (A6) rather than unloading on
    // pause: `play()`/`pause()` hold the decoder's position so a resume
    // continues from where it stopped instead of restarting the loop.
    Connections {
        target: AnimatedCoverFrameSource
        function onPlayingChanged() {
            if (AnimatedCoverFrameSource.playing) {
                video.play();
            } else {
                video.pause();
                // One extra grab on the transition: the 120ms Timer can be
                // mid-interval when the pause lands, so the last published
                // frame may trail the video's actual paused position.
                root._grab();
            }
        }
    }

    Timer {
        interval: 120
        repeat: true
        running: AnimatedCoverFrameSource.playing
        onTriggered: root._grab()
    }
}
