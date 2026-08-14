import Quickshell.Io
import Quickshell.Services.SystemTray

// `qs ipc call tray status|activate <id>`: spec addendum, same rationale as
// `panel` (CLAUDE.md's own note on that target): an item's Activate is
// normally that cell's own click, which the smoke rig can't synthesize (no
// synthetic pointer here, only wtype's keyboard events). This exposes the
// exact action Tray.qml's own click handler takes, the same "verify the
// action, not the input method" idiom `panel`/`picker` already established.
// Opening an item's DBusMenu is deliberately NOT exposed: a platform QMenu
// with no pointer to dismiss it would wedge a headless run, so menu-open
// stays host-trial territory.
//
// The tray owns no drawer, no per-item buckets and no expand state of its
// own since M24, so none of those verbs exist here any more. Collapsing the
// tray is the bar chevron's job (`bar chevron`, BarIpc.qml): one region-level
// toggle over whatever bar.layout put after it, rather than a set of
// per-item moves only this widget understood.
IpcHandler {
    target: "tray"

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
}
