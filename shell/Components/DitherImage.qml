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
Item {
    id: root

    property url source: ""
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

    // 4x4 ordered Bayer matrix, values 0..15 mapped to a per-pixel threshold.
    readonly property var _bayer: [
        0, 8, 2, 10,
        12, 4, 14, 6,
        3, 11, 1, 9,
        15, 7, 13, 5
    ]

    // Posterizes one channel value to the nearest of `levels` evenly-spaced
    // steps, nudged by `bias` (the Bayer cell's own -0.5..0.5 offset, scaled
    // to the step size) before rounding — the offset only tips a channel
    // over to its neighboring step near a quantization boundary, so a
    // channel already at a step (0 or 255 included) is stable regardless
    // of position.
    function _quantizeChannel(value, step, bias) {
        var q = Math.round((value + bias * step) / step) * step;
        return Math.max(0, Math.min(255, Math.round(q)));
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
        source: root.source
        asynchronous: true
        cache: false
        smooth: false
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.width * 2
        sourceSize.height: root.height * 2
        onStatusChanged: {
            if (status === Image.Ready) {
                root._retryAttempts = 0;
                canvas.requestPaint();
            }
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
            if (img.status !== Image.Ready || width <= 0 || height <= 0)
                return;
            var ctx = getContext("2d");
            ctx.reset();
            ctx.drawImage(img, 0, 0, width, height);

            if (root.mode !== "duotone" && root.mode !== "retro")
                return;

            var w = Math.round(width);
            var h = Math.round(height);
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
                        var rr = root._quantizeChannel(sample[ri], step, retroBias);
                        var rg = root._quantizeChannel(sample[ri + 1], step, retroBias);
                        var rb = root._quantizeChannel(sample[ri + 2], step, retroBias);
                        ctx.fillStyle = "#" + root._hex2(rr) + root._hex2(rg) + root._hex2(rb);
                        ctx.fillRect(px, py, Math.min(chunk, w - px), Math.min(chunk, h - py));
                    }
                }
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
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    onSourceChanged: {
        root._retryAttempts = 0;
        if (img.status === Image.Ready)
            canvas.requestPaint();
    }
    onModeChanged: canvas.requestPaint()
    onLightColorChanged: canvas.requestPaint()
    onDarkColorChanged: canvas.requestPaint()
    onLevelsChanged: canvas.requestPaint()
    onChunkChanged: canvas.requestPaint()
}
