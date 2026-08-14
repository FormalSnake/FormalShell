import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Services
import "../Tray/model.js" as Model

// `qs ipc call tray status|expand|collapse|activate <id>|pin <id>|unpin <id>|
// hide <id>|show <id>|manage open|close|toggle`: spec addendum, same
// rationale as `panel` (CLAUDE.md's own note on that target): the grouped
// drawer's expand/collapse, an item's Activate, the manage popup's summon
// and every bucket move it offers are normally the cells' own clicks, which
// the smoke rig can't synthesize (no synthetic pointer here, only wtype's
// keyboard events). This exposes the exact actions Tray.qml and
// TrayManagePanel.qml's own click handlers take, the same "verify the
// action, not the input method" idiom `panel`/`picker` already established.
// Without the four bucket verbs the Bartender buckets could not be verified
// headlessly at all.
// Opening an item's DBusMenu is deliberately NOT exposed: a platform QMenu
// with no pointer to dismiss it would wedge a headless run, so menu-open
// stays host-trial territory.
IpcHandler {
    target: "tray"

    function _ids() {
        return SystemTray.items.values.map(function (item) {
            return item.id;
        });
    }

    // The one place all four bucket verbs land, so their refusals read the
    // same. Ids are opaque strings, matched by equality only, and one nobody
    // published is an error rather than a silent no-op: a caller that
    // mistyped one would otherwise read "ok" and then assert against a tray
    // that never moved. TrayService returns false only when settings.json
    // declares the buckets, which the shell may never write.
    function _move(id, verb) {
        if (_ids().indexOf(id) < 0)
            return "error: no tray item with id '" + id + "'";
        var ok = (verb === "pin" || verb === "unpin")
            ? TrayService.setPinned(id, verb === "pin")
            : TrayService.setHidden(id, verb === "hide");
        return ok ? "ok" : "error: tray buckets are set in settings.json (bar.tray.pinned/bar.tray.hidden)";
    }

    function status(): string {
        var buckets = Model.buckets(_ids(), TrayService.pinned, TrayService.hidden, TrayService.visibleLimit);
        var items = SystemTray.items.values.map(function (item) {
            return {
                id: item.id,
                title: item.title,
                hasMenu: item.hasMenu,
                bucket: TrayService.bucketOf(item.id)
            };
        });
        return JSON.stringify({
            items: items,
            // Where the bar actually draws each item right now. `hidden` is
            // both an assignment and a render bucket, since a hidden id is
            // drawn nowhere; `pinned` is the assignment behind `visible`,
            // which also holds whatever the fallback ordering had room for.
            visible: buckets.visible,
            drawer: buckets.drawer,
            hidden: buckets.hidden,
            pinned: TrayService.pinned,
            visibleLimit: TrayService.visibleLimit,
            bucketsLocked: TrayService.bucketsLocked,
            expanded: TrayService.drawerExpanded,
            manageOpen: TrayService.manageOpen
        });
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

    function pin(id: string): string {
        return _move(id, "pin");
    }

    function unpin(id: string): string {
        return _move(id, "unpin");
    }

    function hide(id: string): string {
        return _move(id, "hide");
    }

    function show(id: string): string {
        return _move(id, "show");
    }

    // The chevron's right-click, which no rig here can produce. Explicit
    // open/close rather than a bare toggle so a screenshot leg never has to
    // know what state the previous leg left behind.
    function manage(action: string): string {
        if (action === "open") {
            TrayService.openManage();
            return "ok";
        }
        if (action === "close") {
            TrayService.closeManage();
            return "ok";
        }
        if (action === "toggle") {
            TrayService.toggleManage();
            return "ok";
        }
        return "error: unknown manage action '" + action + "' (open|close|toggle)";
    }
}
