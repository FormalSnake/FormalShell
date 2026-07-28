import Quickshell.Io
import qs.Services

// `qs ipc call screensaver start|stop|status` — spec's IPC list. Same
// division of labour as MediaIpc/LockIpc: the surface owns the real
// start()/stop()/guard logic; this just exposes it for compositor keybinds
// and headless smoke verification.
IpcHandler {
    target: "screensaver"

    // Set from shell.qml — the single Screensaver instance.
    property var screensaver: null

    function start(): string {
        if (!screensaver)
            return "error: screensaver not ready";
        screensaver.start();
        return "ok";
    }

    function stop(): string {
        if (!screensaver)
            return "error: screensaver not ready";
        screensaver.stop();
        return "ok";
    }

    function status(): string {
        if (!screensaver)
            return "error: screensaver not ready";
        return JSON.stringify({
            active: screensaver.active,
            isIdle: IdleService.isIdle,
            guardMediaPlayback: screensaver.guardMediaPlayback,
            mediaPlaying: MediaService.isPlaying
        });
    }
}
