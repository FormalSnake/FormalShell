import QtQuick

// Cover-color extraction (DESIGN.md §2 item 12 / §4 item 8, M20 Task 5b,
// owner: "the audio visualizer ... uses the dithered album cover colors").
// An invisible Canvas samples `source`, posterizes every pixel to the same
// step count DitherImage's "retro" mode paints with (`levels`, no Bayer
// bias here — a plain nearest-step quantize, since this wants the stable
// color a pixel belongs to, not a dithered one), frequency-counts the
// posterized samples, and keeps the six most frequent DISTINCT steps,
// ordered by luminance so the palette (and the visualizer's bar order)
// stays stable rather than shuffling on a frequency tie. Runs once per
// `source` change, same trigger discipline as DitherImage.
//
// `opacity: 0` on the Canvas, not `visible: false`: the canvas still has
// to actually render to execute its paint pass and populate `colors`, and
// an invisible item is never rendered at all — opacity 0 keeps it in the
// scene graph, fully composited to nothing. The wrapping `Item` is left at
// its default 0x0 size (no `anchors.fill`) so embedding this anywhere
// never affects a parent's own layout or measurement.
//
// The hidden Image can report `Ready` before its decoded pixmap is
// actually synced for `Canvas.drawImage()` to read (the same async
// Image/Canvas timing gap DitherImage.qml's own header documents) — a
// first paint can land on a fully transparent read. DitherImage gets a
// few free extra repaints from its `anchors.fill: parent`-driven
// width/height churn during layout, enough in practice to paint over the
// gap; this component's Canvas is a fixed size with nothing to churn, so
// it retries itself: a transparent top-left sample (every real content
// source is opaque) restarts a short one-shot timer instead of publishing
// a wrong single-step palette, bounded so a genuinely empty/broken source
// still settles on `colors: []` rather than retrying forever.
Item {
    id: root

    property url source: ""
    property int levels: 4
    property var colors: []

    readonly property int _sampleSize: 32
    property int _retryAttempts: 0

    Image {
        id: img
        width: root._sampleSize
        height: root._sampleSize
        visible: false
        source: root.source
        asynchronous: true
        cache: false
        smooth: false
        fillMode: Image.PreserveAspectCrop
        onStatusChanged: {
            if (status === Image.Ready) {
                root._retryAttempts = 0;
                canvas.requestPaint();
            } else if (status === Image.Error) {
                root.colors = [];
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
        width: root._sampleSize
        height: root._sampleSize
        opacity: 0
        onPaint: {
            if (img.status !== Image.Ready || width <= 0 || height <= 0)
                return;
            var ctx = getContext("2d");
            ctx.reset();
            ctx.drawImage(img, 0, 0, width, height);

            var w = Math.round(width);
            var h = Math.round(height);
            var sample = ctx.getImageData(0, 0, w, h).data;

            if (sample[3] === 0) {
                if (root._retryAttempts < 20) {
                    root._retryAttempts++;
                    retryTimer.restart();
                } else {
                    root.colors = [];
                }
                return;
            }

            var lv = Math.max(2, root.levels);
            var step = 255 / (lv - 1);

            var counts = {};
            for (var i = 0; i < sample.length; i += 4) {
                var r = Math.round(Math.round(sample[i] / step) * step);
                var g = Math.round(Math.round(sample[i + 1] / step) * step);
                var b = Math.round(Math.round(sample[i + 2] / step) * step);
                var key = r + "," + g + "," + b;
                counts[key] = (counts[key] || 0) + 1;
            }

            var steps = Object.keys(counts).map(function (key) {
                var parts = key.split(",").map(Number);
                return {
                    r: parts[0],
                    g: parts[1],
                    b: parts[2],
                    count: counts[key],
                    luma: 0.299 * parts[0] + 0.587 * parts[1] + 0.114 * parts[2]
                };
            });

            steps.sort(function (a, b) { return b.count - a.count; });
            steps = steps.slice(0, 6);
            steps.sort(function (a, b) { return a.luma - b.luma; });

            root.colors = steps.map(function (s) {
                return Qt.rgba(s.r / 255, s.g / 255, s.b / 255, 1);
            });
        }
    }

    onSourceChanged: {
        root._retryAttempts = 0;
        if (root.source === "") {
            root.colors = [];
            return;
        }
        if (img.status === Image.Ready)
            canvas.requestPaint();
    }
    onLevelsChanged: if (img.status === Image.Ready) canvas.requestPaint();
}
