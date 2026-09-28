import Quickshell.Io

import qs.Services

// `qs ipc call airplay status`, the `panel`/`localsend` spec addendum
// tradition: a headless drive path for the smoke rig and for checking the
// receiver from a compositor keybind or over ssh. No other verb: UxPlay
// takes no remote command and `airplay.enable`/`airplay.name` are
// settings.json keys this shell only ever reads, so there is nothing here
// to flip.
IpcHandler {
    target: "airplay"

    function status(): string {
        return JSON.stringify({
            enabled: AirplayService.enabled,
            installed: AirplayService.installed,
            running: AirplayService.running,
            active: AirplayService.active,
            name: AirplayService.name,
            client: AirplayService.client,
            title: AirplayService.title,
            artist: AirplayService.artist,
            album: AirplayService.album,
            hasCover: AirplayService.hasCover,
            lastError: AirplayService.lastError
        });
    }
}
