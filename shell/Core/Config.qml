pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Read-only watched ~/.config/formalshell/settings.json, the shell's user
// config surface. Per CLAUDE.md's hard rule the shell never writes this file;
// State.qml (runtime-mutable, $XDG_STATE_HOME) is the writable counterpart.
// v1 keys: menu.customPowerButtons: [{ label, icon, command, confirm? }],
// bar.position (string, default "top", one of "top" / "bottom" / "left" /
// "right": which output edge the bar runs along; on a left or right bar the
// three bar.layout regions run top to bottom and every cell turns its
// content along the strip, icons excepted), tray.maxVisible (number,
// default 0: the most SNI icons the bar strip will carry before the WHOLE
// tray moves to its second bar, Surfaces/Bar/TrayOverflow.qml. 0, the
// default, is none, so the tray lives in that bar behind the strip's dots
// toggle whatever the room; -1 is as many as fit; N is up to N, with room
// still having the last word over both), frame.thickness (number,
// default 0: the screen frame's band on the three edges the bar is not
// on, Surfaces/Frame/Frame.qml; 0 draws no frame) and frame.radius (number,
// default 20, or 0 when theme.radius is 0: the corner of the rounded
// cut-out the frame leaves for the desktop), theme.fontDisplay (reserved), media.appleMusicArt
// (bool, default false, AppleMusicArtService's opt-in, M7 Task 2).
// media.animatedBarCover (bool, default true, whether the bar's mini cover
// animates too; off, the animated cover decode exists only while the media
// panel is open).
// lock.blankAfterSeconds (number, default 30, Lock.qml's idle-blank
// timeout, seconds, fed straight to IdleMonitor.timeout), lock.
// fingerprintPamService (string, default "", the PAM service name for
// Lock.qml's parallel fingerprint flow; empty means no reader enrolled, so
// it never starts, M7 Task 4), lock.command (array of strings, default [],
// an external locker LockService spawns instead of raising the built-in
// surface: ["hyprlock"], ["loginctl", "lock-session"]; empty keeps the
// built-in one, M45) and lock.dither (bool, default theme.dither, the retro
// dither pass over the lock backdrop; off means the plain wallpaper
// draws, M45). screensaver.timeoutSeconds (number, default
// 300, IdleService's IdleMonitor.timeout), screensaver.guardMediaPlayback
// (bool, default true, Screensaver.qml's live guard against auto-activating
// while MediaService.isPlaying), screensaver.lockAfterSeconds (number,
// default 0, Screensaver.qml's optional chain into Lock once already
// showing; 0 disables the chain, M7 Task 5). screensaver.asciiPath (string,
// default "", a path to a user-supplied ASCII banner text file; "" means
// the bundled branding/screensaver.txt), screensaver.effect (string,
// default "random", one of effect.js's EFFECT_NAMES, or "random" to pick a
// fresh one every activation; an unknown name also falls back to random,
// M8b Task 7), screensaver.holdSeconds (number, default 6, how long the
// converged banner holds before the screensaver rerolls its effect and
// animates again, indefinitely; "random" never repeats the immediately
// previous effect, a pinned name replays itself, M13b Task 5).
// hotCorners.topLeft / topRight / bottomLeft / bottomRight (strings, one of
// "none" | "screensaver" | "lock"; defaults "none" / "none" / "screensaver"
// / "lock", both top corners stay inert because the bar owns the top edge
// and a corner there would take pixels out of its input region),
// hotCorners.enabled (bool, default true, false creates no corner surface
// at all), hotCorners.size (number, default 4, clamped 1..64, the trigger
// square's side in pixels; those pixels stop reaching the window under
// them, Wayland having no hover-only input region) and hotCorners.delayMs
// (number, default 400, clamped 0..10000, how long the pointer must dwell
// in the corner before the action fires; a click fires immediately
// regardless). Resolved by shell/HotCorners/corners.js.
// wallpaper.dither (bool, default theme.dither: true renders the
// wallpaper through the same image-derived-palette retro pass the album
// covers use (DESIGN.md §2 item 12), on a grid sized in screen pixels
// rather than source pixels, and off draws the plain undithered
// Images) and wallpaper.ditherColors (number, default 6, the upper bound
// on colors that pass derives from the wallpaper, and the intensity knob: a
// bigger palette leaves fewer cells sitting between two entries, so less of
// the screen patterns at all).
// picker.directory (string,
// default "", the wallpaper directory the menu's "wallpaper" route scans
// in wallpaper mode (`picker summon`); a `Dark`/`Light` subdirectory pair
// there (either name, any case) splits the listing into the two variants the
// route's DARK | LIGHT switcher picks between, and a directory with neither
// is listed flat exactly as before. `picker select`'s generic image-selector
// mode takes an arbitrary directory as an IPC argument instead, M7 Task 6,
// folded into the menu in M23).
// greeter.sessionCommand (array of strings, default ["Hyprland"], greeter.qml's
// Greetd.launch() argv once a login succeeds; the `greeter` system user has
// no real settings.json of its own, so this is really just this key's
// documented fallback today, a real deployment's session choice belongs in
// nixosModules.formalshell-greeter, M8 Task 4).
// calendar.icsDir (string, default "", CalendarEventsService's local .ics
// directory; "" means no local files) and calendar.eds (bool, default true
//, the same service's EDS/GOA backend via the formalshell-eds companion
// CLI; unreachable EDS degrades silently to ics-only after one probe,
// M12 Task 3).
// bar.layout ({left, center, right}: arrays of widget names, each region
// optional, an absent region falls back to today's default arrangement,
// resolved by shell/Bar/layout.js, M10 Task 3) and bar.modules (array of
// {id, type: "command"|"qml", ...}, referenced from bar.layout via a
// "custom:<id>" entry, "command" runs `command` on an `interval` (ms,
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
// github.intervalMs (number, default 300000, GithubWidget's `gh api`
// poll cadence in ms; the widget itself is opt-in via bar.layout,
// M12 Task 8).
// screenshot.directory (string, default "" meaning $HOME/Pictures/
// Screenshots: where ScreenshotIpc's grim captures land, created on first
// capture, M12 Task 9).
// motion.enabled (bool, default true, Theme's motion switch: false zeroes
// every animation duration (Tokens.motionTokens) so all transitions become
// instant state swaps, M13 Task 8).
// usage.claude / usage.codex (bool, each default true, UsagePanel's
// independent per-provider opt-out; a disabled provider polls nothing and
// renders no section at all) and usage.intervalMs (number, default 900000
//, the same panel's background poll cadence in ms; the widget itself is
// opt-in via bar.layout, M14 Task 7).
// weather.intervalMs (number, default 900000, WeatherPanel's open-meteo
// background poll cadence in ms; the widget stays in bar.layout by
// default, so this generally runs whenever the bar does, M15 Task 3).
// polkit.enabled (bool, default true, gates whether PolkitService.qml
// even constructs a PolkitAgent element at all, since registration is
// attempted the instant one exists; false means the shell never tries to
// register, M16 Task 4).
// battery.warnPercent / battery.criticalPercent (numbers, default 10 / 5,
// Power/model.js's warnEvent() thresholds, read by PowerPanel's own
// hysteresis watcher and Battery.qml's urgent/warning-cell checks, M16 Task
// 5 and M18 Task 7).
// nightlight.startOn (bool, default false, opt-in: whether
// NightLightService starts wlsunset automatically at shell boot) and
// nightlight.temp (number, default 4000, the fixed low colour
// temperature it pins via wlsunset's own SIGUSR1 runtime control, M16
// Task 6).
// tailscale.intervalMs (number, default 60000, TailscalePanel's
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
// recording.finalize (bool, default true): after wf-recorder exits,
// RecordingService trims the first 0.1s (a PipeWire capture-open click) via
// ffmpeg, re-encoding only when the first GOP holds discardable warmup
// packets, and loudnorm-normalizes the audio track when there is one;
// false saves the raw file exactly as wf-recorder wrote it, M27 Task 2.
// recording.player (string, default "xdg-open"): the command the SAVED
// notification's PLAY action hands the finished file to, the same
// env+sh convention screenshot.editor already establishes, M27 Task 3.
// recording.maxHeight (number, default 0 meaning no cap): downscales the
// capture to this height in pixels via wf-recorder's own -F scale filter
// when the source exceeds it, preserving aspect ratio. `record startCapped`
// overrides it for one run without touching config, M27 Task 4.
// recording.webcam (bool, default false): spawns an mpv overlay of a video
// capture device, placed bottom-right of the captured region, before the
// recording starts. recording.webcamDevice (string, default "" meaning
// auto-detect the first /dev/video* node) and recording.webcamSize (one of
// "small"/"medium"/"large", default "medium": the 8:9 portrait preset it
// scales to). Off entirely wherever CompositorService.floatingPlacementAvailable
// is false (no compositor detected) -- an unplaceable camera window is worse
// than none, M27 Task 5.
// reminders.defaultMessage (string, default "Time's up"): the body a
// reminder set with no message of its own fires with. ReminderService
// fills it in at set time, so a stored entry always carries a real message
// and the fire path needs no fallback branch of its own.
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
// notifications.position (string, default "bottom-right"): which screen
// corner the popup toast stack anchors to, one of "top-right" /
// "bottom-right" / "bottom-left" / "top-left". An unrecognised value falls
// back to the default (shell/Notifications/model.js's positionSpec()).
// Every corner clears the bar on whichever edge it takes (Theme.edgeInset +
// screenPadding) and sits screenPadding off the screen edge otherwise. The newest toast always sits nearest the
// anchored corner and the enter/exit slide comes from the anchored side
// edge, M34 Task 1.
// console.command (array of strings, default ["ghostty",
// "--class=dev.formalshell.console"]): argv for the quake console's
// terminal, spawned once and then kept, with no shell interpolation. It has
// to make the terminal announce console.appId, and every emulator spells
// that flag differently (`foot --app-id`, `alacritty --class`, `kitty
// --class`, `ghostty --class`), which is why this is argv and not a command
// name. console.appId (string, default "dev.formalshell.console"): the app
// id ConsoleService matches the mapped window against, change it in both
// places or the console never finds its own window and says so. The
// launcher's nix runner reuses this argv for a one-off drop-down, with the
// app id suffixed and `-e <command>` appended, so an emulator spelling its
// command flag some other way runs nothing there while the console itself
// still works.
// console.share (number, default 0.5, clamped 0.2..1): how much of the
// height under the bar the console covers, M37 Task 2.
// clipboard.paste (bool, default true: Enter on a clipboard-history row or
// an emoji row copies the entry and then synthesizes a paste into whatever
// window focus returns to, Raycast's behaviour; false copies only) and
// clipboard.pasteChord (string, default "ctrl+v", the chord that paste
// synthesizes, in wtype's own modifier vocabulary, e.g. "ctrl+shift+v" for
// a terminal-first session). A chord naming a modifier wtype does not know
// pastes nothing and warns, rather than sending some other keystroke.
// menu.emoji.sortByUsage (bool, default true): the emoji route orders by
// how often each emoji has been copied, weighted by how recently
// (shell/Menu/frecency.js, the same scoring the app rows use), so browsing
// ":e" opens on what the user actually reaches for. It reorders WITHIN a
// match tier only, never across one: a better name match still leads.
// False browses in Unicode's own file order. The ledger
// (state.json's `emojiUses`) records either way.
// clipssh.alias (string, default ""): the alias ~/.clipssh/aliases holds
// that the two callers with no row to read one off use, Shift+Enter on a
// clipboard image row and the auto-send below. Unset takes the only alias
// saved when there is exactly one; unset with none or several (and the
// literal "ask", which is how a one-alias store still gets a prompt) means
// undecided, and the launcher then drills into the alias route to ask
// while the auto-send says why it cannot.
// clipssh.autoSendImages (bool, default false): every image landing in
// clipboard history, a screenshot included, goes straight over ssh to
// clipssh.alias, which puts the remote path back on the clipboard. Off by
// default because it turns every copied image into network traffic.
// theme.preset (string, default "shadcn", one of "shadcn" | "retro"): a
// table of chrome defaults, not a mode (M49 D1). It sets theme.radius,
// theme.icons, theme.fonts, theme.surfaceOpacity, theme.blur and
// theme.dither, and any of those written explicitly wins over it; an
// unknown name resolves to "shadcn". theme.fonts (string, "pair" on
// shadcn: sans for words and mono for values; "mono" on retro points both
// aliases at the mono face, and an unrecognised value takes the preset's).
// theme.blur (bool, true on shadcn): whether the compositor blurs behind
// the bar, panels and launcher, the shell blurring nothing itself.
// theme.dither (bool, false on shadcn): the one texture knob, on it renders
// content imagery through the retro dither pass, and it is the default for
// wallpaper.dither and lock.dither above. Resolved by
// shell/Theme/presets.js, read by Core/Theme.qml alone.
Singleton {
    id: root

    property var settings: ({})

    // Flips true exactly once, the first time settings.json has actually
    // been resolved one way or another (parsed, or confirmed absent),
    // never back to false, even across a later reload. IdleService reads
    // this to apply screensaver.timeoutSeconds as a one-shot value rather
    // than a live binding (see its own header comment for the very real
    // reason: re-triggering IdleMonitor's underlying notification a second
    // time shortly after startup, exactly what a live binding here would
    // do, given settings.json loads asynchronously, has been observed to
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
    // missing, retry until the dir shows up (e.g. ThemeEngine creates it)
    // and the real QFileSystemWatcher takes over from here.
    Timer {
        id: rewatchTimer
        interval: 300
        onTriggered: settingsFile.reload()
    }

    // Home-manager retargets this file's symlink on every activation, which
    // no watch can see (ConfigReopen.qml carries the why). _applySettings()
    // below holds up the half of that contract this file owes: it publishes
    // only when the bytes actually changed, so a tick that finds the file
    // the same touches no binding in the shell.
    ConfigReopen { file: settingsFile }

    FileView {
        id: settingsFile
        path: root._configDir + "/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applySettings()
        onLoadFailed: error => {
            root._publish("");
            root.loaded = true;
            if (error === FileViewError.FileNotFound)
                rewatchTimer.restart();
        }
    }

    // The bytes last published, so a reload that finds the file unchanged
    // does nothing at all. `settings` is the object every binding in the
    // shell hangs off, so reassigning it re-evaluates all of them, and both
    // the tick above and rewatchTimer's own retry loop run whether or not
    // anything changed.
    property string _publishedText: ""

    function _publish(text) {
        if (root.loaded && text === root._publishedText)
            return;
        root._publishedText = text;
        if (text === "") {
            root.settings = ({});
            return;
        }
        try {
            root.settings = JSON.parse(text);
        } catch (e) {
            console.warn("Config: failed to parse settings.json:", e.message);
            // Keep the last good value rather than falling back to {}.
        }
    }

    function _applySettings() {
        root._publish(settingsFile.text());
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
