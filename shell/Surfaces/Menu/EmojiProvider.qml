import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import "../../Menu/model.js" as Model

// Vendored emoji dataset (M12 Task 6), ships inside the package like
// default-menu.jsonc, parsed with Model.parseHeaderedJson (native
// JSON.parse past the provenance header dev/gen-emoji.sh writes, with
// parseJsonc as its own fallback). Load failure degrades to an empty
// list (the emoji route and ":e" trigger simply return no rows), one
// console.warn.
//
// path starts empty, the same pathless-until-needed FileView pattern
// LauncherWidget.qml's osReleaseFile uses: a session that never types
// ":e" or opens the emoji route never pays for reading or parsing the
// 458KB file. ensureLoaded() sets the real path on first genuine need.
// blockLoading forces that one transition (path only ever moves from ""
// to the real path once) to finish synchronously rather than leaving the
// first grid, or `debug query ':e …'`, racing an async read: the file is
// small and the fast path above is cheap, and every access after the
// first is already-loaded property reads.
Item {
    id: root

    property string _emojiText: ""

    FileView {
        id: emojiFile
        path: ""
        blockLoading: true
        onLoaded: root._emojiText = emojiFile.text()
        onLoadFailed: error => console.warn("Menu: failed to load emoji.json:", error)
    }

    function ensureLoaded() {
        if (emojiFile.path === "")
            emojiFile.path = Quickshell.shellPath("Menu/emoji.json");
        root._emojiText = emojiFile.text();
    }

    readonly property var list: {
        if (!root._emojiText) return [];
        try {
            return Model.parseHeaderedJson(root._emojiText);
        } catch (e) {
            console.warn("Menu: failed to parse emoji.json:", e.message);
            return [];
        }
    }

    // The copy ledger the emoji route ranks by (state.json's `emojiUses`),
    // or an empty list when menu.emoji.sortByUsage is off, which is what
    // makes providers.js leave Unicode's own order alone. The key gates the
    // ranking only: the ledger keeps recording either way, so switching it
    // on later ranks by real history instead of starting blank.
    readonly property var uses: Core.Config.get("menu.emoji.sortByUsage", true)
        ? Core.State.emojiUses
        : []
}
