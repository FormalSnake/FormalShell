pragma Singleton
import QtQuick
import Quickshell
import qs.Core as Core
import "../Tray/model.js" as Model

// Shared state for the bar's SNI tray: the drawer's expand flag (M10 Task
// 1), the manage popup's open flag and the pinned/hidden bucket assignment
// behind both (M23 Task 3). Bar.qml is instantiated once per screen
// (Variants over Quickshell.screens), but Quickshell.Services.SystemTray's
// item list is one global thing, so the buckets and the drawer follow suit
// rather than forking per monitor. TrayIpc has no per-screen Tray.qml
// instance of its own to reach into, so this singleton is the one place both
// the widget's own cell clicks and `qs ipc call tray expand/pin/manage`
// (the smoke rig's stand-in for a synthetic pointer click, which doesn't
// exist here) can act on.
//
// The buckets resolve the same way every other settings-over-state pair in
// the shell does: `bar.tray.pinned` / `bar.tray.hidden` in settings.json win
// declaratively whenever they are present, and the manage popup's own writes
// to state.json are the fallback (Model.resolveOverride, itself
// Calendar/progress.js:49's contract). A settings-declared tray is therefore
// read-only at runtime, since the shell never writes settings.json.
// `bucketsLocked` says so out loud, so the popup can render one dim cell
// instead of buttons that would silently do nothing.
Singleton {
    id: root

    property bool drawerExpanded: false

    // The manage popup's open state, shared for the same reason
    // drawerExpanded is: a right-click lands on one screen's Tray.qml, while
    // `qs ipc call tray manage open` lands on no instance at all. Each
    // Tray.qml syncs its own Components/Panel from this and only the one on
    // the focused output answers; see that file's own gate.
    property bool manageOpen: false

    // How many cells the tray region gets before the drawer takes over,
    // chevron included. Lives here rather than in Tray.qml because TrayIpc
    // has to answer `tray status` with the same split the bar is actually
    // rendering, and a second copy of the number is a second thing to keep
    // in step.
    readonly property int visibleLimit: 4

    readonly property var _settingsPinned: Core.Config.get("bar.tray.pinned", undefined)
    readonly property var _settingsHidden: Core.Config.get("bar.tray.hidden", undefined)

    readonly property var pinned: root._array(Model.resolveOverride(root._settingsPinned, Core.State.trayPinned))
    readonly property var hidden: root._array(Model.resolveOverride(root._settingsHidden, Core.State.trayHidden))

    // Present means "declared", by exactly the test resolveOverride itself
    // applies: a `null` in settings.json falls through to state.json, so it
    // must not read as a lock either.
    readonly property bool bucketsLocked: root._declared(root._settingsPinned) || root._declared(root._settingsHidden)

    function _declared(value) {
        return value !== undefined && value !== null;
    }

    function _array(value) {
        return Array.isArray(value) ? value : [];
    }

    function toggleDrawer() {
        drawerExpanded = !drawerExpanded;
    }

    function collapseDrawer() {
        drawerExpanded = false;
    }

    function openManage() {
        root.manageOpen = true;
    }

    function closeManage() {
        root.manageOpen = false;
    }

    function toggleManage() {
        root.manageOpen = !root.manageOpen;
    }

    // Which bucket an id is assigned to: "pinned", "hidden", or "drawer"
    // for an unlisted one. Not where it renders: Model.buckets() decides
    // that, and an unlisted id still lands on the bar whenever the fallback
    // ordering has room for it.
    function bucketOf(id) {
        return Model.classify(id, root.pinned, root.hidden);
    }

    function _without(list, id) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            if (list[i] !== id)
                out.push(list[i]);
        }
        return out;
    }

    // Every bucket write funnels through here, so "settings.json owns this"
    // is one check in one place. Returns false rather than throwing or
    // half-writing: the manage popup renders a locked cell instead of
    // calling this at all, and TrayIpc turns the same false into an error
    // string.
    function _write(pinned, hidden) {
        if (root.bucketsLocked)
            return false;
        Core.State.setTrayBuckets(pinned, hidden);
        return true;
    }

    // Pinning clears a hide and hiding clears a pin: the two buckets are
    // mutually exclusive, matching omarchy's own tray (Tray.qml:189-211
    // there). Clearing one never touches the other, since an id can only be
    // in one of them to begin with.
    function setPinned(id, on) {
        var pinned = root._without(root.pinned, id);
        var hidden = on ? root._without(root.hidden, id) : root.hidden.slice();
        if (on)
            pinned.push(id);
        return root._write(pinned, hidden);
    }

    function setHidden(id, on) {
        var hidden = root._without(root.hidden, id);
        var pinned = on ? root._without(root.pinned, id) : root.pinned.slice();
        if (on)
            hidden.push(id);
        return root._write(pinned, hidden);
    }

    function togglePin(id) {
        return root.setPinned(id, root.bucketOf(id) !== "pinned");
    }

    function toggleHide(id) {
        return root.setHidden(id, root.bucketOf(id) !== "hidden");
    }
}
