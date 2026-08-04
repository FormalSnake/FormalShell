import Quickshell.Io
import qs.Services

// `qs ipc call screensaver start|stop|status|stayAwakeOn|stayAwakeOff|
// stayAwakeToggle` — spec's IPC list. Same division of labour as
// MediaIpc/LockIpc: the surface owns the real start()/stop()/guard logic;
// this just exposes it for compositor keybinds and headless smoke
// verification. The stayAwake verbs (M-polish batch item B) drive
// IdleService.stayAwake directly — there is no separate "stayAwake" IPC
// target, it rides the existing "screensaver" one since that's the surface
// the toggle actually gates.
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

    function stayAwakeOn(): string {
        IdleService.stayAwake = true;
        return "ok";
    }

    function stayAwakeOff(): string {
        IdleService.stayAwake = false;
        return "ok";
    }

    function stayAwakeToggle(): string {
        IdleService.toggleStayAwake();
        return "ok";
    }

    function status(): string {
        if (!screensaver)
            return "error: screensaver not ready";
        return JSON.stringify({
            active: screensaver.active,
            isIdle: IdleService.isIdle,
            guardMediaPlayback: screensaver.guardMediaPlayback,
            mediaPlaying: MediaService.isPlaying,
            stayAwake: IdleService.stayAwake
        });
    }

    // Deterministic frame-step verification affordance (M11 Task 1): pins
    // the already-showing surface to an exact frame instead of letting its
    // Timer free-run, so a headless recorder can capture one screenshot per
    // frame with even spacing regardless of the render backend's own
    // wall-clock jitter. Never a way to start the screensaver itself, and
    // never touches which effect is selected — Screensaver.qml releases the
    // pin the moment `active` goes false, so normal animation always
    // resumes on the next real activation.
    function frame(n: int): string {
        if (!screensaver)
            return "error: screensaver not ready";
        if (!screensaver.active)
            return "error: screensaver not active";
        if (n < 0)
            return "error: frame must be >= 0";
        screensaver.pinFrame(n);
        return "ok";
    }

    // The effect the current (or next) activation resolved to, the frame at
    // which it's guaranteed fully converged (Effect.convergenceFrame) — so a
    // recorder knows how many frames to capture rather than guessing
    // per-effect constants of its own — and the activation's completed
    // cycle count (M13b Task 5): 0 until the first effect has converged,
    // held, and rerolled, so the rig can observe continuous cycling from
    // two read-only calls instead of screenshots. cycles is deliberately
    // the last key: the smoke rig greps '"cycles":0}' as an exact
    // zero-baseline match.
    function frameInfo(): string {
        if (!screensaver)
            return "error: screensaver not ready";
        return JSON.stringify({
            effect: screensaver.effectName,
            convergenceFrame: screensaver.convergenceFrame(),
            cycles: screensaver.cycles
        });
    }
}
