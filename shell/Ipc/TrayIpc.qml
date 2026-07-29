import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Services

// `qs ipc call tray status|expand|collapse` — spec addendum, same rationale
// as `panel` (CLAUDE.md's own note on that target): the grouped drawer's
// expand/collapse is normally the overflow cell's own click, which the
// smoke rig can't synthesize (no synthetic pointer here, only wtype's
// keyboard events) — this exposes the exact action Tray.qml's own click
// handler takes, the same "verify the action, not the input method" idiom
// `panel`/`picker` already established.
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
}
