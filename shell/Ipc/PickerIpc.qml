import Quickshell.Io

// `qs ipc call picker summon|select|choose|close|status` — spec §11's image/
// wallpaper picker. summon() opens it in wallpaper mode over the configured
// picker.directory; choosing an image there sets the wallpaper exactly like
// `wallpaper set` (Core.State.setWallpaper — see ImagePicker.qml, not
// duplicated here). select() opens the same grid over an arbitrary
// directory in the generic "doubles as an image-selector" mode: the chosen
// path (or a cancel) lands in
// $XDG_STATE_HOME/formalshell/picker-selection.txt as `{token, value}` /
// `{token, cancelled: true}` JSON, correlated by the caller-supplied token —
// same request/answer handshake as MenuIpc's select()/input(), see its
// header comment for the full rationale. choose() performs the actual
// selection over IPC, independent of real keyboard/pointer delivery — the
// same division every other surface's actions already use in the smoke rig.
IpcHandler {
    target: "picker"

    // Set from shell.qml — the single ImagePicker instance.
    property var picker: null

    function summon(): string {
        if (!picker)
            return "error: picker not ready";
        picker.openWallpaper();
        return "ok";
    }

    function select(directory: string, token: string): string {
        if (!picker)
            return "error: picker not ready";
        picker.openSelect(directory, token);
        return "ok";
    }

    function choose(path: string): string {
        if (!picker)
            return "error: picker not ready";
        return picker.choose(path) ? "ok" : "error: not open, or path not in the current listing";
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
        return JSON.stringify(picker.status());
    }
}
