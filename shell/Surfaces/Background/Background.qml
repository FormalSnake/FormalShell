import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Components
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
//
// A request that arrives while topImage is already fully faded in
// (opacity 1) but bottomImage is still catching up to it queues instead of
// clobbering topImage.source: overwriting it there wouldn't re-fire
// onOpacityChanged (opacity isn't changing), so bottomImage's catch-up
// check would compare against a source it'll never match and the promote
// would never run — topImage stuck at opacity 1 for the rest of the
// session. The queued request replaces any earlier one and is applied the
// moment the in-flight promote actually lands.
//
// Dithered by default (M23, owner: "it would be cool for the rendered
// wallpaper to also be dithered ... similar to album covers"): both
// crossfade layers render through the same `DitherImage` retro pass the
// album covers use (DESIGN.md §2 item 12), sampling the two Images above
// rather than decoding the file a second time each. `wallpaper.dither:
// false` in settings.json puts the plain Images back on screen; the
// crossfade and its promote bookkeeping are identical either way, the
// dither layers just take over what is visible and add themselves to the
// two gates below.
//
// Both gates exist because a DitherImage shows nothing at all until its
// canvas has painted. Starting the fade on the source Image's own `Ready`
// would fade in a blank layer for the length of the dither pass, and
// dropping topImage before the bottom layer had repainted would flash the
// bare background color, so each waits on `painted` as well.
PanelWindow {
    id: background
    required property var modelData
    screen: modelData
    anchors { top: true; bottom: true; left: true; right: true }
    color: Core.Theme.color.background
    WlrLayershell.layer: WlrLayer.Background
    // Reaches under the bar's exclusive zone: the strip is transparent, so
    // whatever this surface paints is what shows between its cells. At the
    // default zone of 0 the compositor shrinks this surface out of the bar's
    // band and its own backdrop shows there instead.
    WlrLayershell.exclusiveZone: -1

    property bool _firstPaint: true
    // Guards the promote-time opacity reset from re-triggering the fade
    // Behavior — that reset is bookkeeping, not a user-visible transition.
    property bool _suppressTopFade: false
    property bool _hasQueued: false
    property string _queuedUrl: ""

    readonly property bool _dither: Core.Config.get("wallpaper.dither", true)
    // Upper bound on colors DitherImage derives from the wallpaper, and the
    // one knob for how much dithering there is: a bigger palette quantizes
    // the photograph more finely, so fewer cells sit between two entries and
    // fewer of them pattern at all. 6 is the era being referenced.
    readonly property int _ditherColors: Core.Config.get("wallpaper.ditherColors", 6)
    // Dither cell size in SCREEN pixels, so the grid is a property of the
    // display and never of the wallpaper file: a 4000px photo and a 1200px
    // one land on the same grid on the same screen, and a 4K screen gets
    // proportionally larger cells rather than four times as many of them
    // (which would also be four times the paint cost, for a texture that
    // reads finer the further the pixels are apart). ~480 cells across the
    // long edge at any resolution, the coarse end of the era being
    // referenced; the floor of 2 keeps a very small screen from landing on
    // a 1px grid, which reads as noise rather than as dither.
    readonly property int _ditherChunk: Math.max(2, Math.round(Math.max(background.width, background.height) / 480))

    function _wallpaperUrl(path) {
        return path !== "" ? "file://" + path : "";
    }

    function _applyWallpaper(path) {
        var url = background._wallpaperUrl(path);
        if (background._firstPaint || Core.Theme.motion.reveal === 0) {
            background._firstPaint = false;
            background._hasQueued = false;
            background._suppressTopFade = true;
            topImage.source = "";
            topImage.opacity = 0;
            background._suppressTopFade = false;
            bottomImage.source = url;
            return;
        }
        if (topImage.opacity === 1) {
            background._queuedUrl = url;
            background._hasQueued = true;
            return;
        }
        topImage._pendingFade = true;
        topImage.source = url;
    }

    function _startQueued() {
        if (!background._hasQueued)
            return;
        var url = background._queuedUrl;
        background._hasQueued = false;
        topImage._pendingFade = true;
        topImage.source = url;
    }

    // Called from both the source Image's status and its dither layer's
    // paint, whichever settles last.
    function _tryStartFade() {
        if (!topImage._pendingFade || topImage.status !== Image.Ready)
            return;
        if (background._dither && !topDither.painted)
            return;
        topImage._pendingFade = false;
        topImage.opacity = 1;
    }

    function _tryPromote() {
        if (bottomImage.status !== Image.Ready || topImage.opacity !== 1 || bottomImage.source !== topImage.source)
            return;
        if (background._dither && !bottomDither.painted)
            return;
        background._suppressTopFade = true;
        topImage.opacity = 0;
        topImage.source = "";
        background._suppressTopFade = false;
        background._startQueued();
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
        visible: !background._dither && source !== ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        // Catches up to a just-promoted topImage in the background. Only
        // once this decode actually lands do we drop topImage — never in
        // the same tick as the source swap, or the screen shows nothing
        // but Theme.color.background for the length of this decode (the
        // bug this split guards against). Clearing topImage.source here
        // (not just its opacity) is what keeps the crossfade from holding
        // two full-size decodes of the same wallpaper resident forever.
        onStatusChanged: background._tryPromote()
        // Decode capped near the screen's own size (M16 Task 12), at a
        // fraction of the resident memory a native-resolution decode would
        // take. sourceSize with both dimensions set fits the decode INSIDE
        // that box (Qt's KeepAspectRatio), not covering it, so requesting
        // the box straight (width, height) would starve whichever axis a
        // non-screen-aspect wallpaper doesn't bind on and PreserveAspectCrop
        // would upscale it back out. Requesting a square box sized to the
        // screen's larger side instead covers any wallpaper at least as
        // wide (relatively) as the screen itself — true for virtually all
        // real wallpapers, landscape photos included — with zero decode
        // overhead over the straight box whenever it holds; only a source
        // more extreme than the screen's own aspect (ultra-panoramic on a
        // standard screen, or portrait) falls back to a mild upscale.
        sourceSize.width: Math.max(background.width, background.height)
        sourceSize.height: Math.max(background.width, background.height)
    }

    // Stays visible (not just opaque) whenever dithering is on, even with
    // no wallpaper set: a Canvas only paints while its item is visible, and
    // this one has to be free to paint before anything puts it on screen.
    // Its opacity is another matter, and 0 is no obstacle to painting
    // (probed in the mac VM rig, not assumed).
    DitherImage {
        id: bottomDither
        anchors.fill: parent
        visible: background._dither
        sourceItem: bottomImage
        mode: "retro"
        chunk: background._ditherChunk
        paletteSize: background._ditherColors
        onPaintedChanged: background._tryPromote()
    }

    Image {
        id: topImage
        property bool _pendingFade: false
        anchors.fill: parent
        visible: !background._dither && opacity > 0
        opacity: 0
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        onStatusChanged: background._tryStartFade()
        // Same cover-vs-fit rationale as bottomImage's sourceSize above.
        sourceSize.width: Math.max(background.width, background.height)
        sourceSize.height: Math.max(background.width, background.height)
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

    // The visible top layer while dithering, riding topImage's animated
    // opacity so the crossfade above is untouched by any of this.
    DitherImage {
        id: topDither
        anchors.fill: parent
        visible: background._dither
        opacity: topImage.opacity
        sourceItem: topImage
        mode: "retro"
        chunk: background._ditherChunk
        paletteSize: background._ditherColors
        onPaintedChanged: background._tryStartFade()
    }
}
