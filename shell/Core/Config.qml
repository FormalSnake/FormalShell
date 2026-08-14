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
// M8b Task 7), screensaver.holdSeconds (number, default 6 — how long the
// converged banner holds before the screensaver rerolls its effect and
// animates again, indefinitely; "random" never repeats the immediately
// previous effect, a pinned name replays itself, M13b Task 5).
// hotCorners.topLeft / topRight / bottomLeft / bottomRight (strings, one of
// "none" | "screensaver" | "lock"; defaults "none" / "none" / "screensaver"
// / "lock" — both top corners stay inert because the bar owns the top edge
// and a corner there would take pixels out of its input region),
// hotCorners.enabled (bool, default true — false creates no corner surface
// at all), hotCorners.size (number, default 4, clamped 1..64 — the trigger
// square's side in pixels; those pixels stop reaching the window under
// them, Wayland having no hover-only input region) and hotCorners.delayMs
// (number, default 400, clamped 0..10000 — how long the pointer must dwell
// in the corner before the action fires; a click fires immediately
// regardless). Resolved by shell/HotCorners/corners.js.
// wallpaper.dither (bool, default true — Background.qml renders the
// wallpaper through the same image-derived-palette retro pass the album
// covers use (DESIGN.md §2 item 12), on a grid sized in screen pixels rather
// than source pixels; false puts the plain undithered Images back on screen,
// M23) and wallpaper.ditherColors (number, default 6 — the upper bound on
// colors that pass derives from the wallpaper, and the intensity knob: a
// bigger palette leaves fewer cells sitting between two entries, so less of
// the screen patterns at all).
// picker.directory (string,
// default "" — the wallpaper directory the menu's "wallpaper" route scans
// in wallpaper mode (`picker summon`); a `Dark`/`Light` subdirectory pair
// there (either name, any case) splits the listing into the two variants the
// route's DARK | LIGHT switcher picks between, and a directory with neither
// is listed flat exactly as before. `picker select`'s generic image-selector
// mode takes an arbitrary directory as an IPC argument instead, M7 Task 6,
// folded into the menu in M23).
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
// bar.widgets.<name>.showLabel (bool, per widget, M23): weather and audio
// default false since their glyph already carries the value the label
// would repeat (condition and mute/level state), with the suppressed
// value moved into the cell's own tooltipText instead of lost; battery,
// bell, github, usage, keyboardLayout and systemUpdate default true,
// unchanged from today until a user opts one out. <name> is the widget's
// own name from shell/Bar/layout.js's BUILTIN_WIDGETS, resolved
// independently of bar.layout, so placing a widget and labeling it are
// two separate keys.
// "chevron" (M24) is a bar.layout entry name like any other builtin, absent
// from the default arrangement. Its POSITION is the whole configuration:
// everything on its governed side of its own region collapses behind it, and
// moving it is the only control there is: no per-widget key says whether a
// widget hides. The governed side runs inward from the region's anchored
// edge (M25), so a right-region chevron collapses what precedes it and a
// left or center one collapses what follows. One chevron per region; a
// second, or one with nothing at all on its governed side, is dropped with a
// warning (shell/Bar/layout.js). Whether a
// region is currently collapsed is runtime state, not settings: it lives in
// state.json's `barCollapsed`, defaults collapsed, and is written by the
// cell's own click or by `bar chevron toggle|expand|collapse [region]`.
// github.intervalMs (number, default 300000 — GithubWidget's `gh api`
// poll cadence in ms; the widget itself is opt-in via bar.layout,
// M12 Task 8).
// screenshot.directory (string, default "" meaning $HOME/Pictures/
// Screenshots: where ScreenshotIpc's grim captures land, created on first
// capture, M12 Task 9).
// motion.enabled (bool, default true — Theme's motion switch: false zeroes
// every animation duration (Tokens.motionTokens) so all transitions become
// instant state swaps, M13 Task 8).
// usage.claude / usage.codex (bool, each default true — UsagePanel's
// independent per-provider opt-out; a disabled provider polls nothing and
// renders no section at all) and usage.intervalMs (number, default 900000
// — the same panel's background poll cadence in ms; the widget itself is
// opt-in via bar.layout, M14 Task 7).
// weather.intervalMs (number, default 900000 — WeatherPanel's open-meteo
// background poll cadence in ms; the widget stays in bar.layout by
// default, so this generally runs whenever the bar does, M15 Task 3).
// polkit.enabled (bool, default true — gates whether PolkitService.qml
// even constructs a PolkitAgent element at all, since registration is
// attempted the instant one exists; false means the shell never tries to
// register, M16 Task 4).
// battery.warnPercent / battery.criticalPercent (numbers, default 10 / 5 —
// Power/model.js's warnEvent() thresholds, read by PowerPanel's own
// hysteresis watcher and Battery.qml's urgent/warning-cell checks, M16 Task
// 5 and M18 Task 7).
// nightlight.startOn (bool, default false — opt-in: whether
// NightLightService starts wlsunset automatically at shell boot) and
// nightlight.temp (number, default 4000 — the fixed low colour
// temperature it pins via wlsunset's own SIGUSR1 runtime control, M16
// Task 6).
// tailscale.intervalMs (number, default 60000 — TailscalePanel's
// `tailscale status --json` poll cadence in ms; the widget itself is
// opt-in via bar.layout, M16 Task 8).
// capture.ocrLanguage (string, default "eng": the language CaptureIpc's
// `text` verb passes to tesseract's -l) and capture.timeoutSeconds
// (number, default 90: how long that target waits for a slurp answer
// before auto-cancelling, M22).
// recording.directory (string, default "" meaning $HOME/Videos: where
// RecordingService's wf-recorder captures land, created on first run),
// recording.framerate (number, default 30, wf-recorder -r; 0 omits the
// flag), recording.codec (string, default "", wf-recorder -c; "" leaves
// its own default), recording.audioBackend (string, default "",
// wf-recorder --audio-backend: pulse or pipewire), recording.noDmabuf
// (bool, default false, wf-recorder --no-dmabuf: required wherever there
// is no GPU to import a dmabuf through, e.g. the llvmpipe VM),
// recording.timeoutSeconds (number, default 90: the region-scope slurp
// watchdog), recording.gifFps (number, default 12) and recording.gifWidth
// (number, default 640: the two-pass ffmpeg transcode's output size, M22).
// reminders.defaultMessage (string, default "Time's up"): the body a
// reminder set with no message of its own fires with. ReminderService
// fills it in at set time, so a stored entry always carries a real message
// and the fire path needs no fallback branch of its own.
// keybinds.niriConfigPath (string, default ""): an explicit niri
// config.kdl for the menu's keybinds route to parse. "" walks the normal
// chain: $NIRI_CONFIG, $XDG_CONFIG_HOME/niri/config.kdl,
// /etc/niri/config.kdl. Hyprland ignores it, that leg reads
// `hyprctl binds -j`.
// plugins.disabled (array of strings, default []): ids of drop-in plugins
// under ~/.config/formalshell/plugins/<id>/ that PluginService skips at
// scan time, so one can be parked without deleting its directory. There is
// deliberately no per-plugin `enabled` flag: a plugin's own manifest.json
// belongs to whoever wrote it, and disabling belongs in the user's one
// config file. bar.layout additionally accepts a "plugin:<id>" entry,
// which places that plugin's bar cell explicitly; a kind:"bar" plugin
// named in no region is appended to the region its manifest asks for.
// systemUpdate.flakeDir (string, default "" meaning no flake is
// configured; SystemUpdatePanel renders NO FLAKE rather than guessing
// /etc/nixos) and systemUpdate.intervalMs (number, default 10800000 = 3h).
// The cadence is hours rather than minutes because each poll costs one
// network round trip per direct flake input and the unauthenticated GitHub
// API allows 60 requests per hour per IP; the widget itself is opt-in via
// bar.layout.
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
