import Quickshell.Io

// `qs ipc call gallery open|close|toggle|status` — the only way into the dev
// gallery (Surfaces/Gallery/Gallery.qml). It is a Panel, but deliberately
// not one of PanelIpc's registry names: `panel open <name>` is the
// user-facing popout route, and a component-QA sheet has no business in it.
// Same summon-route shape as MenuIpc/PickerIpc, including the status()
// hook the smoke rig asserts a round trip through.
//
// open/close rather than show/hide, and not by taste: `qs ipc` has its own
// `show` subcommand, and `qs ipc call gallery show` resolves to THAT — it
// prints this handler's interface listing and never calls the function, so
// the surface silently never opened. Caught by the --gallery smoke leg
// asserting status() afterwards rather than trusting the call's own reply.
IpcHandler {
    target: "gallery"

    // Set from shell.qml — the single Gallery instance (see MenuIpc's
    // `menu` property for why: one instance, no singleton of its own).
    property var gallery: null

    function open(): string {
        if (!gallery)
            return "error: gallery not ready";
        gallery.open();
        return "ok";
    }

    function close(): string {
        if (!gallery)
            return "error: gallery not ready";
        gallery.close();
        return "ok";
    }

    function toggle(): string {
        if (!gallery)
            return "error: gallery not ready";
        gallery.toggle();
        return "ok";
    }

    function status(): string {
        if (!gallery)
            return "error: gallery not ready";
        return JSON.stringify({ isOpen: gallery.isOpen });
    }
}
