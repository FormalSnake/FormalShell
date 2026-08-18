import Quickshell.Io
import Quickshell.Services.SystemTray

// `qs ipc call tray status|activate <id>|menu <id>|menucursor <delta>|
// menuactivate`: spec addendum, same rationale as `panel` (CLAUDE.md's own
// note on that target): an item's Activate is normally that cell's own
// click, which the smoke rig can't synthesize (no synthetic pointer here,
// only wtype's keyboard events). This exposes the exact action Tray.qml's
// own click handlers take, the same "verify the action, not the input
// method" idiom `panel`/`picker` already established.
//
// `menu` (M32) opens TrayMenu.qml for the named item the same way a real
// right-click would — the compositor-keybind path and the smoke drive path
// the old native QMenu never had (a platform QMenu with no pointer to
// dismiss it would have wedged a headless run; the shell-owned menu is a
// layer-shell surface like any other popout, so it doesn't). `menucursor`/
// `menuactivate` stand in for the menu's own real Down/Up/Enter keys, same
// division as `picker`'s `choose`/`variant` — an IPC-opened popout gets no
// bar cell and so never reliably picks up real Wayland keyboard focus in
// this rig, confirmed by a wtype Escape landing on a menu that stayed open
// (2026-08-18).
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

    // Cursor-nav standins for the real Down/Up/Enter keys `menu` sets up to
    // receive (TrayMenu.qml's moveCursor()/activateCursor()) — the same
    // "verify the action, not the input method" division `picker`'s own
    // choose()/variant() already draw for exactly this reason: an
    // IPC-opened popout gets no bar cell and so never picks up real focus
    // in a rig with no synthetic pointer. Named menucursor/menuactivate,
    // not cursor()/activate(), so they don't collide with this handler's
    // own top-level `activate(id)` (the tray item click, not the menu row).
    function menucursor(delta: string): string {
        if (!trayMenu || !trayMenu.isOpen)
            return "error: no tray menu open";
        const step = parseInt(delta, 10);
        if (isNaN(step))
            return "error: delta must be an integer";
        trayMenu.moveCursor(step);
        return "ok";
    }

    function menuactivate(): string {
        if (!trayMenu || !trayMenu.isOpen)
            return "error: no tray menu open";
        trayMenu.activateCursor();
        return "ok";
    }
}
