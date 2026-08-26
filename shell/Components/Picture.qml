import QtQuick
import qs.Core

// Content imagery (M49 D3): an `Image` that renders through DitherImage's
// retro pass whenever `theme.dither` is on. A surface never branches on the
// knob, it reaches for this instead of a bare `Image`, so the preset reaches
// every app icon, notification image and album cover from one place.
//
// Retro mode, so the picture keeps its own colours rather than reducing to
// two role colours: an icon that reads by its colour has to stay readable.
// Tray icons stay a plain `Image` (the "deep fried" rejection, 2026-08-09),
// and so do the wallpaper picker's grid and the clipboard row's thumbnail,
// which exist to choose a picture and must show the picture as it is.
//
// The plain `Image` is hidden while the dither layer has actually painted,
// never before: DitherImage shows nothing at all until its canvas has run,
// so hiding on `active` alone would blank the slot for the length of the
// decode. Sampling a hidden source is fine, `Canvas.drawImage` reads the
// decoded pixmap and does not care whether the item is on screen, which is
// the same arrangement Background.qml's crossfade layers already run.
//
// The dither pass cover-crops whatever `fillMode` the image is set to, so a
// non-square source in a square slot loses its letterboxing under the knob.
// Every site here is an icon or a cover slot sized to its own aspect.
Item {
    id: root

    property url source: ""
    property int fillMode: Image.PreserveAspectFit
    property bool cache: true
    property bool asynchronous: false
    property bool smooth: true
    property alias sourceSize: img.sourceSize
    readonly property alias status: img.status

    // The upper bound on colours the retro pass derives from the picture.
    readonly property int paletteSize: 6

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        fillMode: root.fillMode
        cache: root.cache
        asynchronous: root.asynchronous
        smooth: root.smooth
        visible: !ditherLoader.active || !(ditherLoader.item && ditherLoader.item.painted)
    }

    Loader {
        id: ditherLoader
        anchors.fill: parent
        active: Theme.dither
        sourceComponent: DitherImage {
            anchors.fill: parent
            sourceItem: img
            mode: "retro"
            paletteSize: root.paletteSize
            // An icon slot smaller than a control takes a per-pixel dither:
            // a chunked grid over that few pixels reads as a broken image
            // rather than as texture.
            chunk: Math.min(root.width, root.height) < Theme.space.controlHeight ? 1 : 2
        }
    }
}
