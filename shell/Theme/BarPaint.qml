import QtQuick
import "barpaint.js" as Paint

// The wingpanel band's paint, read off the wallpaper under the band (M60
// T3). The decision and its constants are barpaint.js; this is the sampler
// behind them: one hidden Image of the wallpaper decoded small, drawn
// cover-cropped into a Canvas the same way Background.qml crops it to the
// output, and the band's own rows read back out of that canvas.
//
// Not a singleton, and not in ThemeEngine: a Canvas paints only inside a
// window, so the sampler lives in the bar's own window (one per output,
// which is also the granularity the answer has) and the `strip` habit's
// Loader never brings it up at all.
//
// It samples on a wallpaper change, on a change of band, and never on a
// frame: `onPaint` runs when something calls `requestPaint`, and nothing
// here calls it on a clock. The mode and the fullscreen state reach the
// decision without resampling, since neither moves a pixel of wallpaper.
Item {
    id: root

    // The wallpaper's own path, empty for a session that has never set one.
    property string source: ""
    // The output, and the band on it: which edge the bar occupies and how
    // thick it is. The band's rect inside the sample is worked out from
    // these (barpaint.js's bandRect).
    property string edge: "top"
    property real thickness: 0
    property size screenSize: Qt.size(0, 0)
    // `light` or `dark`, which picks between the two translucent paints.
    property string mode: "dark"
    // A window covering this output, which wins over everything the
    // wallpaper says.
    property bool fullscreen: false

    readonly property var stats: root._stats
    readonly property string paint: Paint.decide(root._stats, root.mode, root.fullscreen)

    property var _stats: ({ mean: 0, std: 0, acutance: 0, sampled: false })

    readonly property int _sampleWidth: Paint.SAMPLE_WIDTH
    readonly property int _sampleHeight: root.screenSize.width > 0
        ? Math.max(1, Math.round(root._sampleWidth * root.screenSize.height / root.screenSize.width))
        : 1

    readonly property var _band: Paint.bandRect(root.edge, root.thickness,
        root.screenSize.width, root.screenSize.height, root._sampleWidth, root._sampleHeight)

    // A Canvas paints only while it is part of a window's scene, and
    // nothing about this one belongs on screen: it sits in a clip of no
    // size at all, so it is drawn and scissored away rather than hidden,
    // which is what keeps `onPaint` running. Behind everything either way.
    clip: true
    enabled: false
    z: -1
    width: 0
    height: 0

    on_BandChanged: canvas.requestPaint()

    Image {
        id: wallpaper
        visible: false
        source: root.source
        asynchronous: true
        cache: false
        smooth: false
        sourceSize.width: root._sampleWidth
        onStatusChanged: {
            if (wallpaper.status === Image.Ready) {
                root._retries = 0;
                canvas.requestPaint();
            } else if (wallpaper.status === Image.Null || wallpaper.status === Image.Error) {
                // Honest rather than stale: a wallpaper that went away
                // leaves the band with nothing to read, which is the bare
                // light-ink paint.
                root._stats = { mean: 0, std: 0, acutance: 0, sampled: false };
            }
        }
    }

    // A first paint can land before the decode's pixels are reachable and
    // read back as a run of zeroes, the same race DitherImage.qml retries
    // against.
    property int _retries: 0

    Timer {
        id: retry
        interval: 16
        onTriggered: canvas.requestPaint()
    }

    Canvas {
        id: canvas
        width: root._sampleWidth
        height: root._sampleHeight

        onPaint: {
            if (wallpaper.status !== Image.Ready || canvas.width <= 0 || canvas.height <= 0)
                return;
            var ctx = canvas.getContext("2d");
            ctx.reset();
            // Nearest-neighbour: an interpolated downscale is a blur, and a
            // blur is exactly what the acutance term measures the absence
            // of.
            ctx.imageSmoothingEnabled = false;

            var iw = wallpaper.implicitWidth;
            var ih = wallpaper.implicitHeight;
            if (iw <= 0 || ih <= 0)
                return;
            // Background.qml draws the wallpaper `PreserveAspectCrop`, so
            // the sample has to be cropped the same way or the band would
            // be read off rows the screen never shows.
            var cover = Math.max(canvas.width / iw, canvas.height / ih);
            var dw = iw * cover;
            var dh = ih * cover;
            ctx.drawImage(wallpaper, (canvas.width - dw) / 2, (canvas.height - dh) / 2, dw, dh);

            var band = root._band;
            var read = ctx.getImageData(band.x, band.y, band.width, band.height);
            var next = Paint.stats(read.data, band.width, band.height);
            if (!next.sampled || (next.mean === 0 && next.std === 0)) {
                if (root._retries < 20) {
                    root._retries++;
                    retry.restart();
                    return;
                }
            }
            root._retries = 0;
            root._stats = next;
        }
    }
}
