import Quickshell.Io

// `qs ipc call picker summon|select|choose|close|status` — spec §11's image/
// wallpaper picker. summon() opens it in wallpaper mode over the configured
// picker.directory; choosing an image there sets the wallpaper exactly like
// `wallpaper set` (Core.State.setWallpaper — see Menu.qml's picker block,
// not duplicated here). select() opens the same grid over an arbitrary
// directory in the generic "doubles as an image-selector" mode: the chosen
// path (or a cancel) lands in
// $XDG_STATE_HOME/formalshell/picker-selection.txt as `{token, value}` /
// `{token, cancelled: true}` JSON, correlated by the caller-supplied token —
// same request/answer handshake as MenuIpc's select()/input(), see its
// header comment for the full rationale. choose() performs the actual
// selection over IPC, independent of real keyboard/pointer delivery — the
// same division every other surface's actions already use in the smoke rig.
//
// The surface behind all five verbs is the MENU (M23): the picker is the
// menu's "wallpaper" route, not a panel of its own, so `menu summon
// wallpaper` and `picker summon` land on exactly the same grid. The target
// keeps its own name and its own selection file because it is a separate,
// documented request channel with its own callers — merging it into `menu`
// would break every existing bind and let one channel answer the other's
// poll.
IpcHandler {
    target: "picker"

    // Set from shell.qml — the single Menu instance.
    property var picker: null

    function summon(): string {
        if (!picker)
            return "error: picker not ready";
        picker.openWallpaperPicker();
        return "ok";
    }

    function select(directory: string, token: string): string {
        if (!picker)
            return "error: picker not ready";
        picker.openImageSelect(directory, token);
        return "ok";
    }

    function choose(path: string): string {
        if (!picker)
            return "error: picker not ready";
        return picker.chooseImage(path) ? "ok" : "error: not on the picker route, or path not in the current listing";
    }

    function close(): string {
        if (!picker)
            return "error: picker not ready";
        picker.close();
        return "ok";
    }

    function status(): string {
        if (!picker)
            return "error: picker not ready";
        return JSON.stringify(picker.pickerStatus());
    }
}
