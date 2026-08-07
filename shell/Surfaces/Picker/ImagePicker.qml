import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import qs.Components

// Image/wallpaper picker (DESIGN.md §Concrete translations' "grid of image
// cells sharing hairline rules", spec §11, M7 Task 6): a ledger grid, one
// cell per file scanned from a directory, cursor-navigable with Cell's own
// inversion marking the current cell — grid first, Omarchy's skewed
// carousel is explicitly a later flourish. Reuses Panel.qml (opened via IPC,
// no bar cell of its own — same anchorX:-1 fallback every other IPC-only
// panel already relies on) rather than inventing a second popout mechanism.
//
// Two modes, both driving the same grid:
// - "wallpaper" (openWallpaper(), PickerIpc's summon()): scans
//   picker.directory from settings.json; choosing an image calls
//   Core.State.setWallpaper() directly — the exact call WallpaperIpc's
//   set() makes, so ThemeEngine's retheme pipeline fires through the one
//   trigger path, never duplicated here.
// - "select" (openSelect(directory, token), PickerIpc's select() — spec
//   §11's "doubles as a generic image-selector"): scans an arbitrary
//   directory; choosing an image writes {token, value: path} to
//   picker-selection.txt instead of touching the wallpaper — the same
//   request/answer handshake MenuIpc's select()/input() already established
//   (see Menu.qml's header comment for the full rationale: IPC calls are
//   synchronous request/response, so the UI's eventual answer can't ride
//   back on the call that opened it). Escape/click-outside/close() without
//   a choice resolves the pending request with {token, cancelled: true},
//   mirroring Menu's _abandonPendingSelect.
//
// choose(path) is the one piece with no Menu precedent: it performs the
// exact same action Enter/click below do, callable over IPC independent of
// real keyboard/pointer delivery — every other surface's actions are
// already verified this way in the smoke rig (media's transport controls,
// wallpaper's own `set`, lock's `lock`), so the picker's grid-cursor
// keyboard nav (real feature, Up/Down/Left/Right below) and its headless
// verification path (this) are deliberately kept separate.
Panel {
    id: root

    panelWidth: Core.Theme.space.popupWidthWide
    panelTitle: root._mode === "select" ? "SELECT IMAGE" : "WALLPAPER"

    readonly property int columns: 4

    property string _mode: "wallpaper"
    property string _directory: ""
    property string _selectToken: ""
    property var _images: []
    property int _cursor: 0

    function openWallpaper() {
        root._mode = "wallpaper";
        root._directory = Core.Config.get("picker.directory", "");
        root._selectToken = "";
        root._cursor = 0;
        root._scan();
        root.open();
    }

    function openSelect(directory, token) {
        root._mode = "select";
        root._directory = directory && directory.length > 0 ? directory : Core.Config.get("picker.directory", "");
        root._selectToken = token;
        root._cursor = 0;
        root._scan();
        root.open();
    }

    function status() {
        return {
            open: root.isOpen,
            mode: root._mode,
            directory: root._directory,
            count: root._images.length,
            cursor: root._cursor
        };
    }

    // Overrides Panel's own close(): every close path (backdrop click,
    // Escape, PanelRegistry preempting this panel for another) already
    // routes through here, so dropping _images here is the one place that
    // needs it. The Repeater's model swap destroys every decoded Image
    // delegate with it — reopening re-scans and re-decodes, which is cheap;
    // the decodes themselves were the cost (M16 Task 12).
    function close() {
        root._images = [];
        root.isOpen = false;
        if (Core.PanelRegistry.current === root)
            Core.PanelRegistry.current = null;
    }

    // Callable over IPC (PickerIpc's choose()) as well as from Enter/click
    // below — the one function that actually resolves a request, so both
    // paths stay in perfect sync by construction. Refuses a path outside the
    // current listing rather than trusting an arbitrary caller-supplied one.
    function choose(path) {
        if (!root.isOpen || root._images.indexOf(path) < 0)
            return false;
        root._cursor = root._images.indexOf(path);
        if (root._mode === "select") {
            root._writeSelectionFile(JSON.stringify({ token: root._selectToken, value: path }));
            root._selectToken = "";
        } else {
            Core.State.setWallpaper(path);
        }
        root.close();
        return true;
    }

    // Quickshell has no directory-listing QML type (same rationale as
    // CalendarEventsService's own `find`-backed read) — re-scanned on every
    // open() so a directory edited between opens is picked up.
    function _scan() {
        if (root._directory === "") {
            root._images = [];
            return;
        }
        scanProc.command = ["sh", "-c", 'find "$1" -maxdepth 1 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.bmp" \\) 2>/dev/null | sort', "sh", root._directory];
        scanProc.running = true;
    }

    Process {
        id: scanProc

        stdout: StdioCollector {
            onStreamFinished: root._images = text.split("\n").filter(function (l) { return l.length > 0; })
        }
    }

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }
    readonly property string _selectionPath: root._stateDir + "/picker-selection.txt"

    // Same Process-write rationale as Menu.qml's _writeSelectionFile: never
    // FileView.setText(), which silently skips both the write and its
    // saved() signal when the new text is byte-identical to its cached copy.
    function _writeSelectionFile(content) {
        var proc = _selectionFileProcComponent.createObject(root, {});
        proc.command = ["sh", "-c", 'printf \'%s\' "$2" > "$1"', "sh", root._selectionPath, content];
        proc.running = true;
    }

    Component {
        id: _selectionFileProcComponent

        Process {
            onExited: exitCode => {
                if (exitCode !== 0)
                    console.warn("ImagePicker: selection-file write failed, code", exitCode);
                destroy();
            }
        }
    }

    // Leaving "select" mode without the caller ever getting an answer (the
    // panel closes via Escape, click-outside, or PanelRegistry preempting it
    // for another panel) must still resolve that caller's poll loop.
    function _abandonPendingSelect() {
        if (root._mode === "select" && root._selectToken !== "") {
            root._writeSelectionFile(JSON.stringify({ token: root._selectToken, cancelled: true }));
            root._selectToken = "";
        }
    }

    onIsOpenChanged: if (!root.isOpen) root._abandonPendingSelect()

    function _moveCursor(dx, dy) {
        var n = root._images.length;
        if (n === 0)
            return;
        var col = root._cursor % root.columns;
        var row = Math.floor(root._cursor / root.columns);
        var maxRow = Math.floor((n - 1) / root.columns);
        col = Math.max(0, Math.min(root.columns - 1, col + dx));
        row = Math.max(0, Math.min(maxRow, row + dy));
        root._cursor = Math.max(0, Math.min(n - 1, row * root.columns + col));
    }

    // Panel.qml's shared keyboard-nav hook: arrows move the cursor,
    // Enter/Return confirms it. Escape keeps closing the panel as normal —
    // Panel.qml dispatches that separately regardless of whether this
    // handler accepts the event.
    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen)
                return;
            switch (event.key) {
            case Qt.Key_Left:
                root._moveCursor(-1, 0);
                event.accepted = true;
                break;
            case Qt.Key_Right:
                root._moveCursor(1, 0);
                event.accepted = true;
                break;
            case Qt.Key_Up:
                root._moveCursor(0, -1);
                event.accepted = true;
                break;
            case Qt.Key_Down:
                root._moveCursor(0, 1);
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (root._images.length > 0)
                    root.choose(root._images[root._cursor]);
                event.accepted = true;
                break;
            }
        }
    }

    Cell {
        visible: root._images.length === 0
        width: parent.width

        MetaLabel { text: "NO IMAGES" }
    }

    Grid {
        id: pickerGrid
        width: parent.width
        columns: root.columns
        visible: root._images.length > 0

        Repeater {
            model: root._images

            delegate: Cell {
                id: imageCell
                required property int index
                required property string modelData
                width: pickerGrid.width / root.columns
                height: width
                selected: imageCell.index === root._cursor

                // Decode capped at the cell's own on-screen size (M16 Task
                // 12): without this, a 6000×4000 source decodes at full
                // resolution into a 105px cell — ~96MB of resident RGBA for
                // a thumbnail, times every file in the directory, forever
                // (until close() above freed it).
                //
                // The 2x factor matters: sourceSize with both dimensions set
                // decodes to FIT INSIDE that box (Qt's KeepAspectRatio), not
                // to cover it, so a non-square source into this square cell
                // would decode short on one axis and PreserveAspectCrop
                // would upscale it back out — visibly blurrier than an
                // uncapped decode. Requesting a box 2x the cell's side keeps
                // the fit-inside decode covering the cell for any source up
                // to a 2:1 aspect ratio (landscape or portrait) — comfortably
                // past 16:9 — while still capping memory to a small multiple
                // of the cell, not the source resolution.
                Image {
                    anchors.fill: parent
                    source: "file://" + imageCell.modelData
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: imageCell.width * 2 * (root.screen ? root.screen.devicePixelRatio : 1)
                    sourceSize.height: imageCell.height * 2 * (root.screen ? root.screen.devicePixelRatio : 1)
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root._cursor = imageCell.index
                    onClicked: root.choose(imageCell.modelData)
                }
            }
        }
    }
}
