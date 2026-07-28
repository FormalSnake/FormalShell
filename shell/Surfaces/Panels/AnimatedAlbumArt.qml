import QtQuick
import QtMultimedia
import qs.Services

// Apple Music animated cover overlay (M7 Task 2, spec §5). Loaded from
// MediaPanel.qml via `Loader { source: "AnimatedAlbumArt.qml" }` rather than
// a direct `import QtMultimedia` there — that keeps a missing QtMultimedia
// module a failure of this one Loader's component creation, not of the
// whole now-playing panel, so the static album-art Image beneath is always
// the honest fallback rather than a broken panel. Square, radius 0
// (DESIGN.md's flat-forever rule — DMS's circular clip isn't ported), same
// footprint as the static Image it sits over.
Item {
    id: root

    // Covered by the static Image beneath for every other state: loading,
    // stalled, or errored out never shows a blank or frozen frame.
    visible: video.hasVideo && video.playbackState === MediaPlayer.PlayingState && video.error === MediaPlayer.NoError

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
}
