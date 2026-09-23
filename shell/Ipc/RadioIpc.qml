import Quickshell.Io
import qs.Services

// `qs ipc call radio status|play|toggle|random|stop`: Radio Atlas's player
// for keybinds and for reading it from outside the shell. `play` takes a
// saved station's id (a favourite, a recent one, or a cliamp channel once
// the atlas has listed them), so a key can be bound to one station. Opening the atlas is
// `panel toggle radio`.
IpcHandler {
    target: "radio"

    function status(): string {
        return JSON.stringify({
            running: RadioService.running,
            paused: RadioService.paused,
            loaded: RadioService.loaded,
            station: RadioService.station ? RadioService.station.name : "",
            title: RadioService.title,
            label: RadioService.label,
            volume: RadioService.volume,
            muted: RadioService.muted,
            output: RadioService.output,
            error: RadioService.error,
            playerError: RadioService.playerError,
            queue: RadioService.queue.length,
            favorites: RadioService.favorites.length,
            recent: RadioService.recent.length
        });
    }

    function play(id: string): string {
        var lists = [RadioService.favorites, RadioService.recent, RadioService.cliampStations];
        for (var l = 0; l < lists.length; l++)
            for (var i = 0; i < lists[l].length; i++)
                if (lists[l][i].uuid === id) {
                    RadioService.playFromSaved(lists[l][i], lists[l]);
                    return "ok";
                }
        return "error: no saved station " + id;
    }

    function toggle(): string {
        if (!RadioService.running)
            return "error: nothing tuned";
        RadioService.toggle();
        return "ok";
    }

    function random(): string {
        RadioService.tuneRandom();
        return "ok";
    }

    function stop(): string {
        RadioService.stop();
        return "ok";
    }
}
