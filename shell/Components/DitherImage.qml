import QtQuick
import qs.Core

// 1-bit dithered imagery (DESIGN.md §2, dither imagery item; DitherFill.qml's
// sibling): a Canvas draws a hidden `Image` once it reports Ready, samples
// its pixels, and repaints a 4x4 ordered-Bayer duotone over the whole
// component — light pixels `lightColor` (`Theme.color.background`), dark
// pixels `darkColor` (`Theme.color.foreground`), roles only so a retheme
// recolors it. Nearest-neighbor decode, radius 0, one repaint per
// source/status/size/color change, never a per-frame timer here — a caller
// driving live frames (the animated album art path) reassigns `source`
// itself and this component just reacts, same as any other change.
//
// The Canvas writes with per-pixel `fillRect`, not `putImageData`: verified
// in-VM (real Wayland/Quickshell rendering, not the offscreen qmltestrunner
// path) that `putImageData` right after a `drawImage(Image item, …)` in the
// same paint silently fails to composite — the canvas keeps showing the
// raw drawImage content. `fillRect` is DitherFill.qml/DogEar.qml's own
// established write path and reads back correctly in both environments.
//
// `mode` picks the Canvas pass: "duotone" thresholds luminance across the
// whole image, painting every pixel light or dark (full duotone
// coverage).
//
// "retro" (Task 5b, content imagery — album art, animated cover) keeps
// the source's own colors instead of reducing to `lightColor`/`darkColor`:
// each channel posterizes independently to `levels` steps (default 3, so
// 0/128/255), the same Bayer bias nudging a channel to whichever
// neighboring step it lands on before rounding — classic ordered color
// dither. A pixel's hue survives because each channel quantizes on its
// own; only a source that was already gray comes out gray. Content is the
// sanctioned exception to the roles-only rule above: it is deliberately
// exempt from matugen retheming, the same way a photo doesn't retheme.
//
// M21 Task 3 (owner, live shell: "the album cover is dithered like i
// asked, but the colors dont change ... it doesnt become 90s image
// style"): 4 levels/channel was 64 colors, imperceptible on most covers,
// and 1px dither cells at a 96px slot read as texture rather than era.
// `chunk` (default 2) downsamples retro mode to a `width/chunk ×
// height/chunk` grid before the posterize+Bayer pass runs, sampling the
// source at each grid cell's center pixel (cheaper than averaging the
// cell, and correct here — a chunk is small enough, and Image already
// decoded at 2x sourceSize, that a center sample and a block average land
// on the same visible color) and painting the whole cell as one
// `chunk`-sized fillRect square instead of a single source pixel. The
// Bayer bias is now indexed by grid-cell position, not raw pixel
// position, so the dither pattern is visible at the enlarged scale
// instead of drowning as 1px noise.
//
// The hidden Image can report `Ready` before its decoded pixmap is
// actually synced for `Canvas.drawImage()` to read — a first paint can
// land on a fully blank (all-zero) sample. Duotone reads that as "all
// dark" (still a plausible-looking foreground fill), which is why this
// went unnoticed until retro mode painted it literally, solid black
// (probe-verified in-VM, M20 Task 5b). A full-buffer all-zero read
// (never a legitimate image, even one with real transparent regions —
// those still carry nonzero bytes somewhere) restarts a short one-shot
// timer instead of publishing that blank paint, bounded so a genuinely
// broken source still settles rather than retrying forever.
//
// `sourceItem` is the alternative input to `source` (M23, the dithered
// wallpaper): an Image item the caller already owns and keeps loaded,
// sampled in place of this component's own hidden one so a full-screen
// source is decoded once rather than twice. `source` is ignored while it
// is set.
//
// The source is drawn cover-cropped, never stretched. `Canvas.drawImage`
// reads the decoded pixmap and ignores the source item's own fillMode, so
// the crop is computed here from `implicitWidth`/`implicitHeight` (the
// decoded size, any sourceSize cap already applied) and the overflow is
// left to the canvas to clip. Before this the draw stretched to the
// component's box, invisible for as long as every caller was a square
// slot holding a square cover.
//
// `painted` reports whether the current source has actually reached the
// canvas. A caller crossfading between two of these needs it: nothing is
// shown at all until the first paint lands, so a fade started on the
// source Image's own `Ready` would fade in a blank layer.
Item {
    id: root

    property url source: ""
    // An externally-owned Image item to sample instead of the hidden one
    // below. Takes precedence over `source`.
    property Item sourceItem: null
    property string mode: "duotone"
    property color lightColor: Theme.color.background
    property color darkColor: Theme.color.foreground
    // "retro" mode only: steps per RGB channel (0/128/255 at the default
    // 3).
    property int levels: 3
    // "retro" mode only: the source is downsampled to a width/chunk x
    // height/chunk grid before quantizing, and each grid cell paints as
    // one chunk-sized hard-edged square (never smooth-scaled). 1 is a
    // plain per-pixel dither, same as before this property existed.
    property int chunk: 2

    // Whether the current source has reached the canvas. False again the
    // moment the source starts changing, so a caller can gate a crossfade
    // on it rather than on the source Image's own status.
    readonly property bool painted: root._painted

    // Whichever Image is supplying pixels this frame.
    readonly property Item _src: root.sourceItem !== null ? root.sourceItem : img

    property bool _painted: false

    // 4x4 ordered Bayer matrix, values 0..15 mapped to a per-pixel threshold.
    readonly property var _bayer: [
        0, 8, 2, 10,
        12, 4, 14, 6,
        3, 11, 1, 9,
        15, 7, 13, 5
    ]

    // Posterizes one channel value onto the nearest of `levels`
    // evenly-spaced steps, returning that step's index for `_palette`
    // rather than its value, nudged by `bias` (the Bayer cell's own
    // -0.5..0.5 offset, scaled to the step size) before rounding — the
    // offset only tips a channel over to its neighboring step near a
    // quantization boundary, so a channel already at a step (0 or 255
    // included) is stable regardless of position.
    function _stepIndex(value, step, bias, top) {
        var q = Math.round((value + bias * step) / step);
        return q < 0 ? 0 : (q > top ? top : q);
    }

    // Retro mode can only ever paint `levels ^ 3` distinct colors, so the
    // strings are built once per `levels` change and indexed per cell.
    // Formatting a fresh hex string and assigning it as `fillStyle` per
    // cell instead was measured at 491ms against 198ms for this lookup
    // (mac VM rig, 1920x1080, chunk 4); a full-screen source is the first
    // caller where that difference is a visible stall rather than noise.
    readonly property var _palette: {
        var lv = Math.max(2, root.levels);
        var step = 255 / (lv - 1);
        var out = [];
        for (var i = 0; i < lv * lv * lv; i++)
            out.push("#" + root._hex2(Math.round(Math.floor(i / (lv * lv)) * step))
                + root._hex2(Math.round(Math.floor(i / lv) % lv * step))
                + root._hex2(Math.round((i % lv) * step)));
        return out;
    }

    function _hex2(n) {
        var h = n.toString(16);
        return h.length < 2 ? "0" + h : h;
    }

    function _isBlankRead(data) {
        for (var k = 0; k < data.length; k++) {
            if (data[k] !== 0)
                return false;
        }
        return true;
    }

    property int _retryAttempts: 0

    Image {
        id: img
        anchors.fill: parent
        visible: false
        // Loads nothing at all while an external sourceItem is supplying
        // the pixels, so that caller's decode is the only one.
        source: root.sourceItem !== null ? "" : root.source
        asynchronous: true
        cache: false
        smooth: false
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.width * 2
        sourceSize.height: root.height * 2
    }

    // Whichever Image `_src` currently resolves to drives the repaints.
    Connections {
        target: root._src
        function onStatusChanged() {
            root._painted = false;
            if (root._src.status === Image.Ready) {
                root._retryAttempts = 0;
                canvas.requestPaint();
            }
        }
        function onSourceChanged() {
            root._painted = false;
        }
    }

    Timer {
        id: retryTimer
        interval: 16
        onTriggered: canvas.requestPaint()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var src = root._src;
            if (src.status !== Image.Ready || width <= 0 || height <= 0)
                return;
            var ctx = getContext("2d");
            ctx.reset();

            var w = Math.round(width);
            var h = Math.round(height);

            // Cover-crop: scale by the larger of the two axis ratios and
            // let the canvas clip whichever axis overflows, centered. A
            // source that has not reported its natural size yet falls back
            // to the old stretch rather than dividing by zero.
            var iw = src.implicitWidth;
            var ih = src.implicitHeight;
            if (iw > 0 && ih > 0) {
                var cover = Math.max(w / iw, h / ih);
                var dw = iw * cover;
                var dh = ih * cover;
                ctx.drawImage(src, (w - dw) / 2, (h - dh) / 2, dw, dh);
            } else {
                ctx.drawImage(src, 0, 0, w, h);
            }

            if (root.mode !== "duotone" && root.mode !== "retro") {
                root._painted = true;
                return;
            }

            var sample = ctx.getImageData(0, 0, w, h).data;

            if (root._isBlankRead(sample)) {
                if (root._retryAttempts < 20) {
                    root._retryAttempts++;
                    retryTimer.restart();
                }
                return;
            }
            root._retryAttempts = 0;

            if (root.mode === "retro") {
                var lv = Math.max(2, root.levels);
                var step = 255 / (lv - 1);
                var top = lv - 1;
                var palette = root._palette;
                var chunk = Math.max(1, root.chunk);
                var gw = Math.ceil(w / chunk);
                var gh = Math.ceil(h / chunk);
                for (var gy = 0; gy < gh; gy++) {
                    var py = gy * chunk;
                    var cy = Math.min(h - 1, py + Math.floor(chunk / 2));
                    var retroRowBase = cy * w * 4;
                    var retroBayerRow = (gy % 4) * 4;
                    for (var gx = 0; gx < gw; gx++) {
                        var px = gx * chunk;
                        var cx = Math.min(w - 1, px + Math.floor(chunk / 2));
                        var ri = retroRowBase + cx * 4;
                        var retroBias = (root._bayer[retroBayerRow + (gx % 4)] + 0.5) / 16 - 0.5;
                        ctx.fillStyle = palette[root._stepIndex(sample[ri], step, retroBias, top) * lv * lv
                            + root._stepIndex(sample[ri + 1], step, retroBias, top) * lv
                            + root._stepIndex(sample[ri + 2], step, retroBias, top)];
                        ctx.fillRect(px, py, Math.min(chunk, w - px), Math.min(chunk, h - py));
                    }
                }
                root._painted = true;
                return;
            }

            var light = root.lightColor;
            var dark = root.darkColor;

            for (var y = 0; y < h; y++) {
                var rowBase = y * w * 4;
                var bayerRow = (y % 4) * 4;
                for (var x = 0; x < w; x++) {
                    var i = rowBase + x * 4;
                    var luma = (0.299 * sample[i] + 0.587 * sample[i + 1] + 0.114 * sample[i + 2]) / 255;
                    var threshold = (root._bayer[bayerRow + (x % 4)] + 0.5) / 16;
                    ctx.fillStyle = luma > threshold ? light : dark;
                    ctx.fillRect(x, y, 1, 1);
                }
            }
            root._painted = true;
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    onSourceChanged: {
        root._retryAttempts = 0;
        root._painted = false;
        if (root._src.status === Image.Ready)
            canvas.requestPaint();
    }
    onSourceItemChanged: {
        root._retryAttempts = 0;
        root._painted = false;
        if (root._src.status === Image.Ready)
            canvas.requestPaint();
    }
    onModeChanged: canvas.requestPaint()
    onLightColorChanged: canvas.requestPaint()
    onDarkColorChanged: canvas.requestPaint()
    onLevelsChanged: canvas.requestPaint()
    onChunkChanged: canvas.requestPaint()
    // A Canvas does not paint while it is not visible, so a component that
    // was hidden through a source change has stale (or no) content the
    // moment it comes back.
    onVisibleChanged: {
        if (root.visible)
            canvas.requestPaint();
    }
}
