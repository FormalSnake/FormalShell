import QtQuick
import Quickshell.Io
import qs.Core as Core
import qs.Services
import "../../Menu/providers.js" as Providers

// --- Wallpaper / image picker (M23) ------------------------------------
//
// The picker used to be a Panel popout of its own
// (Surfaces/Picker/ImagePicker.qml, now deleted). It is a menu ROUTE:
// "wallpaper" is an ordinary provider node in default-menu.jsonc, its level
// renders as a grid instead of rows, and its cells are ordinary
// _displayRows entries (Providers.imageRows), so the cursor, the pointer
// gate, `activate(index)` over IPC, and every close path are the menu's
// own rather than a second implementation of each.
//
// Two modes, both driving the same grid, unchanged from the panel:
// - "wallpaper" (PickerIpc's summon(), the WALLPAPER menu row, `menu summon
//   wallpaper`): scans picker.directory from settings.json; choosing calls
//   Core.State.setWallpaper(), the exact call WallpaperIpc's set() makes,
//   so ThemeEngine's retheme fires through one trigger path and is never
//   duplicated here. A pick out of a Dark/Light set also commits that set
//   as the mode (Providers.wallpaperPickMode), in the same write.
// - "select" (Menu.qml's openImageSelect(), PickerIpc's select(), spec
//   §11's "doubles as a generic image-selector"): scans an arbitrary
//   directory and writes {token, value: path} through `selectionChannel`
//   instead of touching the wallpaper. Leaving the route without choosing
//   resolves the caller's poll loop with {token, cancelled: true}.
//
// A `Dark`/`Light` subdirectory pair inside the scanned directory splits
// the listing in two (Providers.wallpaperVariants) and raises the Dark |
// Light switcher above the grid; a directory with neither is listed flat
// and shows no switcher, so nothing changes for a setup that doesn't use
// them. The variant a route entry lands on is the theme's own current
// mode, which is the one the owner is looking at.
Item {
    id: root

    readonly property string routeId: "wallpaper"

    // The generic selection-file writer, handed in rather than owned here:
    // it also carries the menu-selection.txt path Menu.qml's select()/
    // input() modes write, and the two must never disagree about how a
    // write happens.
    property var selectionChannel: null

    property string mode: "wallpaper"   // "wallpaper" | "select"
    property string dir: ""
    property string token: ""
    // Everything the scan found, both variant subdirectories and the root
    // directory in one listing; the split below is what the grid reads.
    property var scanned: []
    property string variant: "dark"     // "dark" | "light"
    readonly property var variants: Providers.wallpaperVariants(root.scanned, root.dir)
    readonly property bool hasVariants: root.variants.hasVariants
    readonly property var images: Providers.wallpaperListing(root.variants, root.variant)
    // Set by Menu.qml's openImageSelect() so the level entry it triggers
    // keeps that caller's directory and token, every other way of reaching
    // this level (the menu row, `menu summon wallpaper`, `picker summon`)
    // is a plain wallpaper-mode open and resets both.
    property bool requestPending: false

    // Re-scanned on every entry into the route, so a directory edited
    // between opens is picked up. The command itself is
    // Providers.pickerScanCommand: ThumbnailService runs the identical scan
    // at startup to prerender the grid's thumbnails, and the two must never
    // disagree about what the listing is.
    function _scan() {
        if (root.dir === "") {
            root.scanned = [];
            return;
        }
        scanProc.command = Providers.pickerScanCommand(root.dir);
        scanProc.running = true;
    }

    Process {
        id: scanProc

        stdout: StdioCollector {
            onStreamFinished: root.scanned = text.split("\n").filter(function (l) { return l.length > 0; })
        }
    }

    // Whatever the scan just found gets a thumbnail built for it if it has
    // none yet: the startup warm covers the configured picker directory, and
    // this covers a wallpaper added since as well as every directory
    // `picker select` is pointed at. Already-cached paths cost the warm a
    // `test` apiece, so re-warming on every entry is close to free.
    onScannedChanged: ThumbnailService.warm(root.scanned, "cover")

    function enterRoute() {
        if (!root.requestPending) {
            root.abandonPending();
            root.mode = "wallpaper";
            root.dir = Core.Config.get("picker.directory", "");
            root.token = "";
        }
        root.requestPending = false;
        // The variant the theme is currently in, every entry, a switch is a
        // deliberate act of browsing the other set, not a preference the
        // route carries over from last time.
        root.variant = Core.State.mode === "light" ? "light" : "dark";
        root._scan();
    }

    // Dropping the listing destroys every decoded thumbnail with the grid
    // delegates that held them, the whole point of the old panel's close()
    // override (M16 Task 12), kept. Re-entering re-scans and re-decodes off
    // ThumbnailService's 512px cache rather than off the wallpapers
    // themselves, which is what makes re-entry cheap at all.
    function leaveRoute() {
        root.abandonPending();
        root.scanned = [];
    }

    function abandonPending() {
        if (root.mode === "select" && root.token !== "") {
            root.selectionChannel.writeFile(root.selectionChannel.pickerSelectionPath,
                JSON.stringify({ token: root.token, cancelled: true }));
            root.token = "";
        }
    }
}
