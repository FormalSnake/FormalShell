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
// coverage). "mask" (Task 5, tray icon silhouettes) thresholds alpha
// instead, using the same Bayer bias to dither the soft anti-aliased
// edges of an icon into a stipple: pixels whose alpha clears the
// threshold paint `darkColor` at full opacity, everything else is left
// (or reset back to) fully transparent — no `lightColor` backing, so the
// cell's own background shows through. The second `ctx.reset()` in the
// mask branch is the clear step, not `clearRect`: it stays on the same
// proven fillRect/reset write path rather than a second untested primitive.
Item {
    id: root

    property url source: ""
    property string mode: "duotone"
    property color lightColor: Theme.color.background
    property color darkColor: Theme.color.foreground

    // 4x4 ordered Bayer matrix, values 0..15 mapped to a per-pixel threshold.
    readonly property var _bayer: [
        0, 8, 2, 10,
        12, 4, 14, 6,
        3, 11, 1, 9,
        15, 7, 13, 5
    ]

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
        onStatusChanged: if (status === Image.Ready) canvas.requestPaint();
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

            if (root.mode !== "duotone" && root.mode !== "mask")
                return;

            var w = Math.round(width);
            var h = Math.round(height);
            var sample = ctx.getImageData(0, 0, w, h).data;

            if (root.mode === "mask") {
                var maskDark = root.darkColor;
                ctx.reset();
                for (var my = 0; my < h; my++) {
                    var maskRowBase = my * w * 4;
                    var maskBayerRow = (my % 4) * 4;
                    for (var mx = 0; mx < w; mx++) {
                        var mi = maskRowBase + mx * 4;
                        var alpha = sample[mi + 3] / 255;
                        var maskThreshold = (root._bayer[maskBayerRow + (mx % 4)] + 0.5) / 16;
                        if (alpha > maskThreshold) {
                            ctx.fillStyle = maskDark;
                            ctx.fillRect(mx, my, 1, 1);
                        }
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

    onSourceChanged: if (img.status === Image.Ready) canvas.requestPaint();
    onModeChanged: canvas.requestPaint()
    onLightColorChanged: canvas.requestPaint()
    onDarkColorChanged: canvas.requestPaint()
}
