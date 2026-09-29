import Quickshell.Io

import qs.Services

// `qs ipc call mirror toggle|open|close|next|previous|status`: the launcher's
// camera mirror (Surfaces/Menu/views/MirrorView.qml) for a compositor
// keybind. The view is the menu's "mirror" route, so `menu summon mirror`
// lands on the same card; toggle() closes the launcher only when it is
// showing that route, and otherwise opens it there.
//
// next()/previous() step through the cameras and answer an error while the
// view is not showing, since the camera list only exists while it is.
// status() reports what the view holds: `streaming` is the Camera object's
// own `active`, so it is true exactly while the device is open, `irFilter`
// is true while an IR camera draws through its lit-frame filter, and `feed`
// is the window-space rect of the feed box, `picture` the part of it the
// video fills.
IpcHandler {
    target: "mirror"

    // Set from shell.qml, the single Menu instance.
    property var menu: null

    function _showing() {
        return menu !== null && menu.isOpen && menu.currentNodeId === "mirror";
    }

    function _feed() {
        var item = MirrorService.feedItem;
        if (!item)
            return null;
        var at = item.mapToItem(null, 0, 0);
        return { x: Math.round(at.x), y: Math.round(at.y), width: Math.round(item.width), height: Math.round(item.height) };
    }

    function _picture() {
        var item = MirrorService.videoItem;
        if (!item || !MirrorService.hasFrame)
            return null;
        var r = item.contentRect;
        // Two corners, since the feed is flipped left to right.
        var a = item.mapToItem(null, r.x, r.y);
        var b = item.mapToItem(null, r.x + r.width, r.y + r.height);
        return { x: Math.round(Math.min(a.x, b.x)), y: Math.round(Math.min(a.y, b.y)), width: Math.round(Math.abs(b.x - a.x)), height: Math.round(Math.abs(b.y - a.y)) };
    }

    function toggle(): string {
        if (!menu)
            return "error: menu not ready";
        if (_showing())
            menu.close();
        else
            menu.open("mirror");
        return "ok";
    }

    function open(): string {
        if (!menu)
            return "error: menu not ready";
        menu.open("mirror");
        return "ok";
    }

    function close(): string {
        if (!menu)
            return "error: menu not ready";
        if (_showing())
            menu.close();
        return "ok";
    }

    function next(): string {
        if (!_showing())
            return "error: mirror is not showing";
        MirrorService.cycle(1);
        return "ok";
    }

    function previous(): string {
        if (!_showing())
            return "error: mirror is not showing";
        MirrorService.cycle(-1);
        return "ok";
    }

    function status(): string {
        return JSON.stringify({
            showing: _showing(),
            open: MirrorService.open,
            streaming: MirrorService.streaming,
            hasFrame: MirrorService.hasFrame,
            irFilter: MirrorService.irFilter,
            error: MirrorService.error,
            current: MirrorService.currentId,
            feed: _feed(),
            picture: _picture(),
            cameras: MirrorService.cameras
        });
    }
}
