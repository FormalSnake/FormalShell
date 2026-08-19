import Quickshell.Io
import qs.Services

// `qs ipc call media play-pause|next|previous|shuffle|loop|volume|raise|
// select|status`, the spec's IPC list (§IPC/CLI). MediaPanel's own transport
// cells call MediaService directly; this exists for compositor keybinds and
// headless smoke verification, same division of labour as
// WallpaperIpc/ThemeIpc over their own singletons.
//
// Every route that acts on a player it doesn't have (no player at all, or a
// player that doesn't implement that part of MPRIS) answers with an error
// string naming which, rather than returning "ok" over a call that went
// nowhere.
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

    function shuffle(mode: string): string {
        if (!MediaService.available)
            return "error: no player";
        if (!MediaService.shuffleSupported)
            return "error: player does not support shuffle";
        if (mode === "on")
            MediaService.setShuffle(true);
        else if (mode === "off")
            MediaService.setShuffle(false);
        else if (mode === "toggle")
            MediaService.toggleShuffle();
        else
            return "error: unknown mode " + mode + " (on|off|toggle)";
        return "ok";
    }

    function loop(mode: string): string {
        if (!MediaService.available)
            return "error: no player";
        if (!MediaService.loopSupported)
            return "error: player does not support loop";
        if (mode === "cycle")
            MediaService.cycleLoop();
        else if (mode === "none" || mode === "track" || mode === "playlist")
            MediaService.setLoop(mode);
        else
            return "error: unknown mode " + mode + " (none|track|playlist|cycle)";
        return "ok";
    }

    // Percent on the wire, the player's own 0..1 double underneath: a CLI
    // argument reads better as 30 than 0.3, and it keeps the one scale this
    // handler speaks unambiguous.
    function volume(percent: int): string {
        if (!MediaService.available)
            return "error: no player";
        if (!MediaService.volumeSupported)
            return "error: player does not support volume";
        if (percent < 0 || percent > 100)
            return "error: volume out of range " + percent + " (0-100)";
        MediaService.setVolume(percent / 100);
        return "ok";
    }

    function raise(): string {
        if (!MediaService.available)
            return "error: no player";
        if (!MediaService.canRaise)
            return "error: player does not support raise";
        MediaService.raise();
        return "ok";
    }

    // Bus name, exactly as `status`/`players` report it. An unknown one is an
    // error rather than a selection nothing can satisfy.
    function select(id: string): string {
        var rows = MediaService.players;
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].id === id) {
                MediaService.select(id);
                return "ok";
            }
        }
        return "error: no player " + id;
    }

    function players(): string {
        return JSON.stringify(MediaService.players);
    }

    function status(): string {
        return JSON.stringify({
            available: MediaService.available,
            id: MediaService.activeId,
            selectedId: MediaService.selectedId,
            playerCount: MediaService.players.length,
            identity: MediaService.identity,
            title: MediaService.title,
            artist: MediaService.artist,
            album: MediaService.album,
            isPlaying: MediaService.isPlaying,
            position: MediaService.position,
            length: MediaService.length,
            canSeek: MediaService.canSeek,
            canRaise: MediaService.canRaise,
            shuffleSupported: MediaService.shuffleSupported,
            shuffle: MediaService.shuffle,
            loopSupported: MediaService.loopSupported,
            loop: MediaService.loopState,
            volumeSupported: MediaService.volumeSupported,
            volume: MediaService.volume
        });
    }
}
