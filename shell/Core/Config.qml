pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Read-only watched ~/.config/formalshell/settings.json — the shell's user
// config surface. Per CLAUDE.md's hard rule the shell never writes this file;
// State.qml (runtime-mutable, $XDG_STATE_HOME) is the writable counterpart.
// v1 keys: menu.customPowerButtons: [{ label, icon, command, confirm? }],
// bar.position (reserved), theme.fontDisplay (reserved), media.appleMusicArt
// (bool, default false — AppleMusicArtService's opt-in, M7 Task 2).
// lock.blankAfterSeconds (number, default 30 — Lock.qml's idle-blank
// timeout, seconds, fed straight to IdleMonitor.timeout), lock.
// fingerprintPamService (string, default "" — the PAM service name for
// Lock.qml's parallel fingerprint flow; empty means no reader enrolled, so
// it never starts, M7 Task 4). screensaver.timeoutSeconds (number, default
// 300 — IdleService's IdleMonitor.timeout), screensaver.guardMediaPlayback
// (bool, default true — Screensaver.qml's live guard against auto-activating
// while MediaService.isPlaying), screensaver.lockAfterSeconds (number,
// default 0 — Screensaver.qml's optional chain into Lock once already
// showing; 0 disables the chain, M7 Task 5). screensaver.asciiPath (string,
// default "" — a path to a user-supplied ASCII banner text file; "" means
// the bundled branding/screensaver.txt), screensaver.effect (string,
// default "random" — one of effect.js's EFFECT_NAMES, or "random" to pick a
// fresh one every activation; an unknown name also falls back to random,
// M8b Task 7). picker.directory (string,
// default "" — ImagePicker's configured wallpaper directory, scanned by its
// summon()/wallpaper mode; select()'s generic-image-selector mode takes an
// arbitrary directory as an IPC argument instead, M7 Task 6).
// greeter.sessionCommand (array of strings, default ["niri"] — greeter.qml's
// Greetd.launch() argv once a login succeeds; the `greeter` system user has
// no real settings.json of its own, so this is really just this key's
// documented fallback today — a real deployment's session choice belongs in
// nixosModules.formalshell-greeter, M8 Task 4).
// calendar.icsDir (string, default "" — CalendarEventsService's local .ics
// directory; "" means no local files) and calendar.eds (bool, default true
// — the same service's EDS/GOA backend via the formalshell-eds companion
// CLI; unreachable EDS degrades silently to ics-only after one probe,
// M12 Task 3).
// bar.layout ({left, center, right}: arrays of widget names, each region
// optional — an absent region falls back to today's default arrangement,
// resolved by shell/Bar/layout.js, M10 Task 3) and bar.modules (array of
// {id, type: "command"|"qml", ...}, referenced from bar.layout via a
// "custom:<id>" entry — "command" runs `command` on an `interval` (ms,
// default 5000) and parses Waybar-JSON-compatible stdout
// (CommandModule.qml); "qml" loads a `source` file into a Loader
// (QmlModule.qml)). An unknown widget name or a dangling module reference
// is dropped with a console warning, never a crash.
// github.intervalMs (number, default 300000 — GithubWidget's `gh api`
// poll cadence in ms; the widget itself is opt-in via bar.layout,
// M12 Task 8).
Singleton {
    id: root

    property var settings: ({})

    // Flips true exactly once, the first time settings.json has actually
    // been resolved one way or another (parsed, or confirmed absent) —
    // never back to false, even across a later reload. IdleService reads
    // this to apply screensaver.timeoutSeconds as a one-shot value rather
    // than a live binding (see its own header comment for the very real
    // reason: re-triggering IdleMonitor's underlying notification a second
    // time shortly after startup — exactly what a live binding here would
    // do, given settings.json loads asynchronously — has been observed to
    // silently and permanently break IdleMonitor.isIdle for the rest of the
    // process's life).
    property bool loaded: false

    readonly property string _configDir: {
        const xdgConfig = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config");
        return xdgConfig + "/formalshell";
    }

    // Same bounded-retry rationale as Theme.qml's theme.json watch: at first
    // launch settings.json (and its parent dir) may not exist yet, and a bare
    // watchChanges: true never attaches to a path whose parent dir is also
    // missing — retry until the dir shows up (e.g. ThemeEngine creates it)
    // and the real QFileSystemWatcher takes over from here.
    Timer {
        id: rewatchTimer
        interval: 300
        onTriggered: settingsFile.reload()
    }

    FileView {
        id: settingsFile
        path: root._configDir + "/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applySettings()
        onLoadFailed: error => {
            root.settings = {};
            root.loaded = true;
            if (error === FileViewError.FileNotFound)
                rewatchTimer.restart();
        }
    }

    function _applySettings() {
        try {
            root.settings = JSON.parse(settingsFile.text());
        } catch (e) {
            console.warn("Config: failed to parse settings.json:", e.message);
            // Keep the last good value rather than falling back to {}.
        }
        root.loaded = true;
    }

    // Dotted-path lookup: Config.get("menu.customPowerButtons", [])
    function get(path, fallback) {
        var node = root.settings;
        var parts = path.split(".");
        for (var i = 0; i < parts.length; i++) {
            if (node === undefined || node === null || typeof node !== "object")
                return fallback;
            node = node[parts[i]];
        }
        return node === undefined ? fallback : node;
    }
}
