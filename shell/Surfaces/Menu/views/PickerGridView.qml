import QtQuick
import qs.Core as Core
import qs.Components
import qs.Services

// The wallpaper route's grid (DESIGN.md §Concrete translations' "grid of
// image cells sharing hairline rules", spec §11), the picker's own surface,
// one of the menu's views over Menu.qml's shared _displayRows/cursorIndex
// state rather than a panel of its own.
GridView {
    id: root

    property var rowsById: ({})
    property var rowsPrev: ({})
    property var blankRow: ({})
    property int cursorIndex: -1
    property var hoverGate: null
    property real pixelRatio: 1

    // 4 columns at every scale (spec §11's grid): a wallpaper preview reads
    // fine at that size, and Menu.qml's `cursorColumns` reads it back for
    // wrap/page-step arithmetic, the same seam appGrid's own `columns`
    // property already is.
    readonly property int columns: 4

    signal activated(int index)
    signal cursorRequested(int index)

    // Delegates recycle rather than being destroyed and rebuilt on every
    // flick. Safe here because every delegate in this file is required
    // properties plus bindings off them, with no Component.onCompleted work
    // that a reused item would skip.
    reuseItems: true
    clip: true
    cellWidth: root.width / root.columns
    cellHeight: root.cellWidth
    // Same hard-jump follow as the row list, for the same reason: held
    // arrow keys outrun the default animated highlight move and the cursor
    // cell ends up off-viewport.
    highlightMoveDuration: 0

    function placeCursor(index) {
        root.currentIndex = index;
    }

    function scrollHome() {
        if (root.model)
            root.positionViewAtBeginning();
    }

    function cancelGlide() {
        wheel.cancel();
    }

    function cursorReport() {
        if (root.currentIndex >= 0 && root.model && root.currentIndex < root.model.count)
            return { index: root.currentIndex, id: root.model.get(root.currentIndex).rowId };
        return { index: -1, id: "" };
    }

    // A row here is a row of thumbnails, not a text line.
    WheelScroll {
        id: wheel
        flickable: root
        step: root.cellHeight
    }

    // The wrapper carries the GridView's own cell, so the `Cell` inside it
    // can hold the gutter between thumbnails in its margins and every gap
    // comes out the same width, the edges of the grid included.
    delegate: Item {
        id: imageSlot
        required property int index
        required property string rowId
        readonly property var entry: root.rowsById[imageSlot.rowId] || root.rowsPrev[imageSlot.rowId] || null
        readonly property string path: imageSlot.entry ? (imageSlot.entry.row.path || "") : ""

        width: root.cellWidth
        height: root.cellHeight

        Cell {
            id: imageCell
            anchors.fill: parent
            anchors.margins: Core.Theme.space.xs
            radius: Core.Theme.radiusMd
            // A grid cursor is the ring (spec "Launcher"): the thumbnail
            // covers the cell, so a fill would sit under the picture and
            // never be seen.
            cursor: imageSlot.index === root.cursorIndex
            hovered: imageCell.containsPointer && (!root.hoverGate || root.hoverGate.live)

            // The thumbnail is inset far enough that its square corners sit
            // inside the cell's rounded ones, which is what lets an image
            // live in a `radiusMd` frame with no mask: at `sm` the corner of
            // the inset square is 5.7px from the arc's centre against a
            // radius of 8.
            //
            // Decode capped at the cell's own on-screen size (M16 Task 12):
            // without this, a 6000×4000 source decodes at full resolution
            // into a ~130px cell, ~96MB of resident RGBA per thumbnail,
            // times every file in the directory.
            //
            // The 2x factor matters on the fallback path: sourceSize with
            // both dimensions set decodes to FIT INSIDE that box (Qt's
            // KeepAspectRatio), not to cover it, so a non-square source into
            // this square cell would decode short on one axis and
            // PreserveAspectCrop would upscale it back out, visibly
            // blurrier than an uncapped decode. A box 2x the cell's side
            // keeps the fit-inside decode covering the cell for any source
            // up to 2:1 either way, comfortably past 16:9, while still
            // capping memory to a small multiple of the cell. A cached
            // thumbnail is already a square crop, so the same box is simply
            // generous for it.
            // Sized off the GridView's own cell rather than off
            // `imageCell`: a `Cell` measures its content to publish an
            // implicit size, so a child measured back off the cell closes a
            // loop Qt then reports and breaks (its own anchors already
            // decide its size, but the detector sees the cycle first).
            Image {
                id: thumb
                anchors.centerIn: parent
                width: imageSlot.width - (Core.Theme.space.xs + Core.Theme.space.sm) * 2
                height: imageSlot.height - (Core.Theme.space.xs + Core.Theme.space.sm) * 2
                // ThumbnailService's prerendered square crop when there is
                // one, the wallpaper itself otherwise. The fallback is not a
                // degraded mode, it is exactly what this cell did before the
                // cache existed: a cold cache, an install with no ffmpeg,
                // and a format ffmpeg cannot decode all land on it.
                readonly property string cachedUrl: imageSlot.path !== "" ? ThumbnailService.urlFor(imageSlot.path, "cover") : ""
                source: thumb.cachedUrl !== "" ? thumb.cachedUrl : (imageSlot.path !== "" ? "file://" + imageSlot.path : "")
                fillMode: Image.PreserveAspectCrop
                // PreserveAspectCrop paints past its own bounds without
                // this, over the cells beside it.
                clip: true
                asynchronous: true
                cache: false
                sourceSize.width: thumb.width * 2 * root.pixelRatio
                sourceSize.height: thumb.height * 2 * root.pixelRatio
            }

            interactive: true
            // Same gate as the row list: filtering re-renders cells under a
            // parked pointer, and Qt delivers that as a hover move
            // indistinguishable from a real one.
            onPointerMoved: (x, y) => {
                if (root.hoverGate && root.hoverGate.moved(imageCell, x, y))
                    root.cursorRequested(imageSlot.index);
            }
            onClicked: root.activated(imageSlot.index)
        }
    }
}
