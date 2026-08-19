import QtQuick
import qs.Core
import "dither.js" as Dither

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
// "retro" (Task 5b, content imagery — album art, animated cover, the
// wallpaper) keeps the source's own colors instead of reducing to
// `lightColor`/`darkColor`: dither.js derives a palette of at most
// `paletteSize` colors from the image itself by median cut and each cell
// takes its nearest entry, ordered-dithered against the second nearest —
// a period-correct Amiga/VGA conversion rather than a fixed grid of
// posterize steps. Read dither.js's header for what that fixed grid did
// wrong (2026-08-12: dots over monotone sources, maximum-contrast dots
// everywhere else) and why a per-image palette is the fix. Content is the
// sanctioned exception to the roles-only rule above: it is deliberately
// exempt from matugen retheming, the same way a photo doesn't retheme.
//
// `chunk` (default 2) downsamples retro mode to a `width/chunk ×
// height/chunk` grid before the palette pass runs, sampling the source at
// each grid cell's center pixel (cheaper than averaging the cell, and
// correct here — a chunk is small enough, and Image already decoded at 2x
// sourceSize, that a center sample and a block average land on the same
// visible color) and painting the whole cell as one `chunk`-sized
// fillRect square instead of a single source pixel (M21 Task 3, owner:
// "the album cover is dithered like i asked ... it doesnt become 90s
// image style" — at a 96px slot, 1px dither cells read as texture, not as
// an era). The Bayer threshold is indexed by grid-cell position, not raw
// pixel position, so the dither pattern is visible at the enlarged scale
// instead of drowning as 1px noise. Runs of same-index cells paint as one
// fillRect: a small palette makes those runs long, which is what keeps a
// full-screen pass affordable now that flat regions genuinely stay flat.
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
    // "retro" mode only: the upper bound on colors derived from the image.
    // 6 is the era being referenced and it is also the intensity knob —
    // more colors means less quantization error, so less dithering.
    property int paletteSize: 6
    // "retro" mode only: the source is downsampled to a width/chunk x
    // height/chunk grid before quantizing, and each grid cell paints as
    // one chunk-sized hard-edged square (never smooth-scaled). 1 is a
    // plain per-pixel dither, same as before this property existed.
    property int chunk: 2
    // "retro" mode only: how much of the grid has been taken over by the
    // dither, 0..1, gated per cell by the same 4x4 Bayer threshold the
    // quantizer uses. The pass already draws the raw source into the canvas
    // before painting cells over it, so a cell left out by this gate shows
    // that raw source through — which makes 0 -> 1 a hard-edged ordered
    // dissolve from the untouched image into its quantized version, and
    // 1 -> 0 the same dissolve run backwards. 1 paints every cell, which is
    // the exact loop (run merge included) this had before the property
    // existed, so every caller that never sets it is unaffected.
    property real reveal: 1

    // `reveal` quantized onto the Bayer matrix's own 16 thresholds. The
    // matrix has no finer resolution than that, so two reveal values inside
    // the same sixteenth paint pixel-identical frames — tracking the level
    // instead of the raw scalar caps a dissolve at 17 repaints no matter how
    // long the animation runs or how fast the compositor ticks, and makes
    // the dissolve visibly stepped, which is the texture being referenced.
    property int _revealLevel: 16

    // Palette + per-cell indices from the last full pass. A `reveal` step
    // only changes WHICH of those cells paint, never what color any of them
    // is, so a dissolve frame reuses this instead of re-reading the whole
    // canvas back (`getImageData` over a full-screen buffer) and re-running
    // the median cut. Cleared by anything that changes what the grid means:
    // a new source, a resize, a different chunk/palette/mode.
    property var _quant: null

    // Whether the current source has reached the canvas. False again the
    // moment the source starts changing, so a caller can gate a crossfade
    // on it rather than on the source Image's own status.
    readonly property bool painted: root._painted

    // Whichever Image is supplying pixels this frame.
    readonly property Item _src: root.sourceItem !== null ? root.sourceItem : img

    property bool _painted: false

    function _isBlankRead(data) {
        for (var k = 0; k < data.length; k++) {
            if (data[k] !== 0)
                return false;
        }
        return true;
    }

    property int _retryAttempts: 0

    // Paints the quantized grid over the raw source already sitting on the
    // canvas. Horizontal run merge: a same-index run paints as one fillRect,
    // so a flat region costs one call per row instead of `gw` of them, and
    // the era's own look is mostly flat regions. A run also breaks on a cell
    // the `reveal` gate leaves out, which is what lets the raw source show
    // through mid-dissolve.
    function _paintCells(ctx, q, w, h) {
        var chunk = q.chunk;
        var gw = q.gw;
        var gh = q.gh;
        var indices = q.indices;
        var hexes = q.hexes;
        // +1 against a 0..15 matrix, so level 0 paints nothing and level 16
        // paints everything, both exactly.
        var limit = root._revealLevel;
        for (var ry = 0; ry < gh; ry++) {
            var py = ry * chunk;
            var ch = Math.min(chunk, h - py);
            var rowStart = ry * gw;
            var bayerRow = (ry % 4) * 4;
            var run = 0;
            while (run < gw) {
                if (Dither.BAYER[bayerRow + (run % 4)] + 1 > limit) {
                    run++;
                    continue;
                }
                var runIndex = indices[rowStart + run];
                var runEnd = run + 1;
                while (runEnd < gw && indices[rowStart + runEnd] === runIndex
                       && Dither.BAYER[bayerRow + (runEnd % 4)] + 1 <= limit)
                    runEnd++;
                var px = run * chunk;
                ctx.fillStyle = hexes[runIndex];
                ctx.fillRect(px, py, Math.min(runEnd * chunk, w) - px, ch);
                run = runEnd;
            }
        }
    }

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
            root._quant = null;
            if (root._src.status === Image.Ready) {
                root._retryAttempts = 0;
                canvas.requestPaint();
            }
        }
        function onSourceChanged() {
            root._painted = false;
            root._quant = null;
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
            // Nearest-neighbor for the cover-crop scale below: an
            // interpolated upscale would hand the quantizer colors the source
            // never contained (and blur a small source into a smooth wash
            // before it ever reached the palette pass), which is the opposite
            // of what a pixel-art conversion is for.
            ctx.imageSmoothingEnabled = false;

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

            // Dissolve frame: the raw source is back on the canvas above and
            // the quantization still stands, so this is one cell-paint pass
            // and nothing else — no readback, no median cut.
            if (root.mode === "retro" && root._quant) {
                root._paintCells(ctx, root._quant, w, h);
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
                var chunk = Math.max(1, root.chunk);
                var gw = Math.ceil(w / chunk);
                var gh = Math.ceil(h / chunk);
                var cellCount = gw * gh;

                // One center sample per grid cell, collected before any
                // color decision is made: the palette is derived from the
                // grid the pass will actually paint, so what the histogram
                // saw and what lands on screen cannot disagree.
                var cells = new Uint8Array(cellCount * 3);
                var ci = 0;
                for (var gy = 0; gy < gh; gy++) {
                    var cy = Math.min(h - 1, gy * chunk + Math.floor(chunk / 2));
                    var srcRow = cy * w * 4;
                    for (var gx = 0; gx < gw; gx++) {
                        var si = srcRow + Math.min(w - 1, gx * chunk + Math.floor(chunk / 2)) * 4;
                        cells[ci++] = sample[si];
                        cells[ci++] = sample[si + 1];
                        cells[ci++] = sample[si + 2];
                    }
                }

                var pal = Dither.palette(cells, cellCount, root.paletteSize);
                root._quant = {
                    chunk: chunk,
                    gw: gw,
                    gh: gh,
                    hexes: Dither.hexPalette(pal),
                    indices: Dither.quantize(cells, cellCount, gw, pal)
                };
                root._paintCells(ctx, root._quant, w, h);
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
                    var threshold = (Dither.BAYER[bayerRow + (x % 4)] + 0.5) / 16;
                    ctx.fillStyle = luma > threshold ? light : dark;
                    ctx.fillRect(x, y, 1, 1);
                }
            }
            root._painted = true;
        }
        onWidthChanged: {
            root._quant = null;
            requestPaint();
        }
        onHeightChanged: {
            root._quant = null;
            requestPaint();
        }
    }

    onSourceChanged: {
        root._retryAttempts = 0;
        root._painted = false;
        root._quant = null;
        if (root._src.status === Image.Ready)
            canvas.requestPaint();
    }
    onSourceItemChanged: {
        root._retryAttempts = 0;
        root._painted = false;
        root._quant = null;
        if (root._src.status === Image.Ready)
            canvas.requestPaint();
    }
    onModeChanged: {
        root._quant = null;
        canvas.requestPaint();
    }
    onLightColorChanged: canvas.requestPaint()
    onDarkColorChanged: canvas.requestPaint()
    onPaletteSizeChanged: {
        root._quant = null;
        canvas.requestPaint();
    }
    onChunkChanged: {
        root._quant = null;
        canvas.requestPaint();
    }
    // Cheap by design: the cache above survives, so a dissolve step repaints
    // cells without re-quantizing — and a step that lands inside the level
    // it is already on repaints nothing at all.
    onRevealChanged: {
        var level = Math.max(0, Math.min(16, Math.ceil(root.reveal * 16)));
        if (level === root._revealLevel)
            return;
        root._revealLevel = level;
        canvas.requestPaint();
    }
    // A Canvas does not paint while it is not visible, so a component that
    // was hidden through a source change has stale (or no) content the
    // moment it comes back.
    onVisibleChanged: {
        if (root.visible)
            canvas.requestPaint();
    }
}
