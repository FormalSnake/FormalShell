import Quickshell.Io

import qs.Services

// `qs ipc call record start|stop|toggle|status|gif` is a spec addendum
// (M22, the `panel`/`polkit`/`nightlight` tradition, CLAUDE.md hard rules).
// It drives RecordingService for compositor keybinds, the menu's own
// self-targeting rows, and the smoke rig.
//
// Thin by construction (NightLightIpc.qml's shape): every Process, watchdog
// and piece of state lives in the singleton, so a keybind, a menu row and a
// smoke assertion all exercise one implementation. Unknown scope or audio
// mode comes back as an error string naming the accepted values, never a
// silent fallback to something the caller did not ask for.
IpcHandler {
    target: "record"

    // scope: screen|region (default screen). audio: none|desktop|desktopmic
    // (default none). Answers with the destination path, since a region
    // scope blocks on a human and IpcHandler replies are synchronous.
    function start(scope: string, audio: string): string {
        return RecordingService.start(scope, audio);
    }

    // Same scope/audio contract as start(), plus a resolution cap
    // (recording.maxHeight) that overrides config for this one run. Its own
    // verb rather than a third argument on start(): IpcHandler dispatches
    // on exact arity, so widening start() would break the bare `record
    // start` a keybind already calls, the same reasoning startAt() already
    // states. Pass "" to take recording.maxHeight's own value; anything
    // else must be a plain integer height in pixels (M27 Task 4).
    function startCapped(scope: string, audio: string, maxHeight: string): string {
        return RecordingService.start(scope, audio, maxHeight);
    }

    // Start against a geometry the caller already has ("X,Y WxH"), skipping
    // the selection. Its own verb rather than an optional argument on start():
    // IpcHandler dispatches on exact arity, so a defaulted parameter would
    // break the bare `record start` a keybind actually calls, the same split
    // `capture textAt` already makes.
    function startAt(geometry: string, audio: string): string {
        return RecordingService.startAt({ geometry: geometry, audio: audio, scope: "region" });
    }

    // Also cancels a region selection that is still waiting for an answer.
    function stop(): string {
        return RecordingService.stop();
    }

    function toggle(scope: string, audio: string): string {
        return RecordingService.toggle(scope, audio);
    }

    // Transcodes `path` (default: the last recording) to a sibling .gif.
    function gif(path: string): string {
        return RecordingService.gif(path);
    }

    function status(): string {
        return JSON.stringify({
            active: RecordingService.active,
            scope: RecordingService.scope,
            audio: RecordingService.audioMode,
            path: RecordingService.path,
            elapsedMs: RecordingService.elapsedMs,
            transcoding: RecordingService.transcoding,
            finalizing: RecordingService.finalizing,
            lastGifPath: RecordingService.lastGifPath,
            lastError: RecordingService.lastError
        });
    }
}
