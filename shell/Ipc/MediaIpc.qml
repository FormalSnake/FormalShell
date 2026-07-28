import Quickshell.Io
import qs.Services

// `qs ipc call media play-pause|next|previous|status` — spec's IPC list
// (§IPC/CLI). MediaPanel's own transport cells call MediaService directly;
// this exists for compositor keybinds and headless smoke verification, same
// division of labour as WallpaperIpc/ThemeIpc over their own singletons.
IpcHandler {
    target: "media"

    function playPause(): string {
        MediaService.playPause();
        return "ok";
    }

    function next(): string {
        MediaService.next();
        return "ok";
    }

    function previous(): string {
        MediaService.previous();
        return "ok";
    }

    function status(): string {
        return JSON.stringify({
            available: MediaService.available,
            identity: MediaService.identity,
            title: MediaService.title,
            artist: MediaService.artist,
            album: MediaService.album,
            isPlaying: MediaService.isPlaying,
            position: MediaService.position,
            length: MediaService.length
        });
    }
}
