import Quickshell.Io
import Quickshell.Services.SystemTray

// `qs ipc call tray status|activate <id>|menu <id>`: spec addendum, same
// rationale as `panel` (CLAUDE.md's own note on that target): an item's
// Activate is normally that cell's own click, which the smoke rig can't
// synthesize (no synthetic pointer here, only wtype's keyboard events).
// This exposes the exact action Tray.qml's own click handlers take, the
// same "verify the action, not the input method" idiom `panel`/`picker`
// already established.
//
// `menu` (M32) opens TrayMenu.qml for the named item the same way a real
// right-click would — the compositor-keybind path and the smoke drive path
// the old native QMenu never had (a platform QMenu with no pointer to
// dismiss it would have wedged a headless run; the shell-owned menu is a
// layer-shell surface like any other popout, so it doesn't).
//
// The tray owns no drawer, no per-item buckets and no expand state of its
// own since M24, so none of those verbs exist here any more. Collapsing the
// tray is the bar chevron's job (`bar chevron`, BarIpc.qml): one region-level
// toggle over whatever bar.layout put on its governed side, rather than a set
// of per-item moves only this widget understood.
IpcHandler {
    target: "tray"

    property var trayMenu: null

    function status(): string {
        var items = SystemTray.items.values.map(function (item) {
            return {
                id: item.id,
                title: item.title,
                hasMenu: item.hasMenu
            };
        });
        return JSON.stringify({ items: items });
    }

    function activate(id: string): string {
        var items = SystemTray.items.values;
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === id) {
                items[i].activate();
                return "ok";
            }
        }
        return "error: no tray item with id '" + id + "'";
    }

    function menu(id: string): string {
        if (!trayMenu)
            return "error: no tray menu surface";
        var items = SystemTray.items.values;
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === id) {
                if (!items[i].hasMenu)
                    return "error: tray item '" + id + "' has no menu";
                trayMenu.openItem(null, items[i]);
                return "ok";
            }
        }
        return "error: no tray item with id '" + id + "'";
    }
}
