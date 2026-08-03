import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Core as Core

// Per-screen wallpaper surface, pinned to the wlr-layer-shell Background
// layer (below Bottom, i.e. below every other surface including windows) —
// verified against quickshell's own WlrLayer::Enum source, not guessed.
// Shows State.wallpaper when set; otherwise just the live Theme.color.background
// fill, so the layer is always present even before a wallpaper is picked.
//
// Double-buffered crossfade (DESIGN.md §4's third motion carve-out):
// `bottomImage` always holds the last fully-shown wallpaper, opaque;
// `topImage` receives an incoming source at opacity 0 and fades to 1 over
// Theme.motion.reveal once it finishes loading (never mid-decode, so the
// fade never starts on blank pixels), then gets "promoted" onto
// bottomImage so the next change has a clean top layer to fade into. First
// paint and motion.enabled: false both skip the fade — a hard cut straight
// onto bottomImage, today's behavior.
PanelWindow {
    id: background
    required property var modelData
    screen: modelData
    anchors { top: true; bottom: true; left: true; right: true }
    color: Core.Theme.color.background
    WlrLayershell.layer: WlrLayer.Background

    property bool _firstPaint: true
    // Guards the promote-time opacity reset from re-triggering the fade
    // Behavior — that reset is bookkeeping, not a user-visible transition.
    property bool _suppressTopFade: false

    function _wallpaperUrl(path) {
        return path !== "" ? "file://" + path : "";
    }

    function _applyWallpaper(path) {
        var url = background._wallpaperUrl(path);
        if (background._firstPaint || Core.Theme.motion.reveal === 0) {
            background._firstPaint = false;
            background._suppressTopFade = true;
            topImage.source = "";
            topImage.opacity = 0;
            background._suppressTopFade = false;
            bottomImage.source = url;
            return;
        }
        topImage._pendingFade = true;
        topImage.source = url;
    }

    Component.onCompleted: background._applyWallpaper(Core.State.wallpaper)

    Connections {
        target: Core.State
        function onWallpaperChanged() {
            background._applyWallpaper(Core.State.wallpaper);
        }
    }

    Image {
        id: bottomImage
        anchors.fill: parent
        visible: source !== ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        // Catches up to a just-promoted topImage in the background. Only
        // once this decode actually lands do we drop topImage — never in
        // the same tick as the source swap, or the screen shows nothing
        // but Theme.color.background for the length of this decode (the
        // bug this split guards against).
        onStatusChanged: {
            if (status === Image.Ready && topImage.opacity === 1 && source === topImage.source) {
                background._suppressTopFade = true;
                topImage.opacity = 0;
                background._suppressTopFade = false;
            }
        }
    }

    Image {
        id: topImage
        property bool _pendingFade: false
        anchors.fill: parent
        visible: opacity > 0
        opacity: 0
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        onStatusChanged: {
            if (status === Image.Ready && _pendingFade) {
                _pendingFade = false;
                opacity = 1;
            }
        }
        // Reaching full opacity only starts bottomImage's own decode of
        // the same source — it must stay the frontmost, fully-decoded
        // layer until bottomImage's onStatusChanged above confirms the
        // catch-up landed and hides it.
        onOpacityChanged: {
            if (opacity === 1 && !background._suppressTopFade)
                bottomImage.source = topImage.source;
        }
        Behavior on opacity {
            enabled: !background._suppressTopFade
            NumberAnimation { duration: Core.Theme.motion.reveal; easing.type: Core.Theme.motion.revealEasing }
        }
    }
}
