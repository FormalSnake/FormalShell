import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Services

// `qs ipc call tray status|expand|collapse|activate <id>` — spec addendum,
// same rationale as `panel` (CLAUDE.md's own note on that target): the
// grouped drawer's expand/collapse and an item's Activate are normally the
// cells' own clicks, which the smoke rig can't synthesize (no synthetic
// pointer here, only wtype's keyboard events) — this exposes the exact
// actions Tray.qml's own click handlers take, the same "verify the action,
// not the input method" idiom `panel`/`picker` already established.
// Opening an item's DBusMenu is deliberately NOT exposed: a platform QMenu
// with no pointer to dismiss it would wedge a headless run, so menu-open
// stays host-trial territory.
IpcHandler {
    target: "tray"

    function status(): string {
        var items = SystemTray.items.values.map(function (item) {
            return { id: item.id, title: item.title, hasMenu: item.hasMenu };
        });
        return JSON.stringify({ items: items, expanded: TrayService.drawerExpanded });
    }

    function expand(): string {
        TrayService.drawerExpanded = true;
        return "ok";
    }

    function collapse(): string {
        TrayService.collapseDrawer();
        return "ok";
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
}
