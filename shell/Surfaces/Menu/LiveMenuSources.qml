import QtQuick
import qs.Compositor
import qs.Services

// The clipboard and window lists behind the menu's clipboard/apps
// providers, mirrored ONLY while the menu is actually open (M17 review
// finding, M-polish batch item G, owner: low-end laptop): `active` gates
// both ternaries below, so a capture or a window event landing while the
// menu is closed touches nothing here at all. The moment `active` flips
// true both re-read the live state and resubscribe, so content is exactly
// as fresh as before for as long as the menu stays open.
Item {
    id: root

    // Bound to Menu.qml's isOpen.
    property bool active: false

    readonly property var clipboardItems: root.active ? ClipboardService.items : []

    // Prerender the ledger's image captures the moment the live list
    // resolves, `fit` rather than the picker's `cover` (MenuRow's own thumb
    // slot letterboxes). Gated behind `active` by construction, since
    // clipboardItems is empty while closed, so a capture landing on a
    // closed launcher warms nothing. A ledger of text entries warms nothing
    // either: the filter is what decides there is work at all.
    // `kind`/`path` are the service's own field names; `thumbSource` is what
    // clipboardProvider renames `path` to on the row it builds, and this
    // reads the service rather than the rows so it does not wait on a tree
    // rebuild to notice a new capture.
    onClipboardItemsChanged: {
        var images = (root.clipboardItems || []).filter(function (item) {
            return item && item.kind === "image" && (item.path || "") !== "";
        }).map(function (item) { return item.path; });
        ThumbnailService.warm(images, "fit");
    }

    // The same gate, for the same reason, on the compositor's window list.
    // The apps provider decorates each app row with its running windows,
    // and it reads this inside the tree's own binding, so an ungated read
    // subscribed the whole tree to every window open, close AND TITLE
    // CHANGE: a browser tab switch rebuilt the JSONC merge, every provider,
    // the frecency sort and a Quickshell.iconPath call per installed app,
    // with the launcher closed and nobody looking. Closed, the app rows
    // carry no window matches, which is exactly as observable as the
    // clipboard being empty up there.
    //
    // Even while active, `_windowsLive` below is kept apart from a raw
    // CompositorService.windows binding: appmatch.js only ever compares
    // `id` and `appId` (never title), so it is republished only when that
    // pair changes for some window, and a title-only tick (a browser tab
    // switch, again) leaves the array's identity alone instead of rebuilding
    // the tree under whoever is typing in the launcher.
    readonly property var windows: root.active ? root._windowsLive : []

    property var _windowsLive: []
    property string _windowsKey: ""

    function _update() {
        var windowList = CompositorService.windows || [];
        var pairs = [];
        for (var i = 0; i < windowList.length; i++) {
            var w = windowList[i] || {};
            pairs.push((w.id || "") + "\0" + (w.appId || ""));
        }
        var key = JSON.stringify(pairs);
        if (key === root._windowsKey)
            return;
        root._windowsKey = key;
        root._windowsLive = windowList;
    }

    onActiveChanged: if (root.active) root._update()

    // Enabled only while active, mirroring the ternary above: a windows
    // tick while closed must cost nothing, the same guarantee the raw-
    // binding form gave for free by simply not reading
    // CompositorService.windows in the branch that isn't taken.
    Connections {
        target: CompositorService
        enabled: root.active
        function onWindowsChanged() { root._update(); }
    }
}
