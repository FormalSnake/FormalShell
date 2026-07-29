# FormalShell usage reference

Per-surface reference for FormalShell's IPC targets, config keys, and
keybind examples — theming, menu, notifications, OSD, panels, clipboard,
calendar, now playing, lock screen, screensaver, and picker. Product
overview, screenshots, features, and install instructions live in
[`README.md`](../README.md); the dev/verification loop lives in
[`CLAUDE.md`](../CLAUDE.md).

- [Bar](#bar)
- [Theming](#theming)
- [Menu](#menu)
- [Notifications](#notifications)
- [OSD](#osd)
- [Panels](#panels)
- [Clipboard](#clipboard)
- [Calendar](#calendar)
- [Now playing](#now-playing)
- [Lock screen](#lock-screen)
- [Screensaver](#screensaver)
- [Picker](#picker)

## Bar

Three regions — `left`/`center`/`right` — each independently reorderable
from `settings.json`, with no config needed to get today's default
arrangement:

```jsonc
{
  "bar": {
    "layout": {
      "left": ["workspaces", "activeWindow"],
      "center": ["clock", "nowPlaying"],
      "right": ["battery", "audio", "network", "bluetooth", "weather", "tray", "indicators", "custom:cpu"]
    },
    "modules": [
      { "id": "cpu", "type": "command", "command": ["my-cpu-script"], "interval": 5000, "timeout": 5000 }
    ]
  }
}
```

Builtin widget names: `workspaces`, `activeWindow`, `clock`, `nowPlaying`,
`battery`, `audio`, `network`, `bluetooth`, `weather`, `tray`, `indicators`.
An absent region falls back to its own default arrangement above (an
absent `bar` key entirely is the same as an absent region for all three);
a present-but-empty region (`[]`) stays empty. An unknown widget name, or
a `"custom:<id>"` entry with no matching `bar.modules[].id`, is dropped
with a console warning — never a crash.

`bar.modules[]` entries are referenced from `bar.layout` by
`"custom:<id>"` and come in two `type`s:

- **`command`** — runs `command` (an argv array) on an interval
  (`interval`, ms, default 5000) and parses stdout as
  Waybar-JSON-compatible `{"text": "…", "tooltip": "…", "class": "…"}`;
  only `text` renders today. `class: "warning"` renders an accent-filled
  cell, `"critical"`/`"urgent"` renders the urgent fill, anything else
  renders plain. A non-zero exit, a timeout (`timeout`, ms, default 5000),
  malformed JSON, or a command that fails to start at all all render the
  same honest `MODULE ERROR` cell rather than a stale value.
- **`qml`** — loads a `source` file (an absolute path) into a `Loader`.
  This isolates only *load-time* failures (bad syntax, an unresolvable
  import) as the same `MODULE ERROR` cell — a file that parses fine has
  the exact same engine access as any built-in widget (`qs.Core`,
  `qs.Services`, `Process`, …). It is not a runtime sandbox.

**Tray** — every real `org.kde.StatusNotifierItem` registered on the
session bus (`Quickshell.Services.SystemTray`) renders as its own cell:
left click activates it, middle click secondary-activates it, right click
opens its `DBusMenu` if it has one. Past 4 visible items the rest collapse
into one more cell (`+N`) that expands the row to reveal them all.

**Indicators** — DND and idle-inhibit each render as their own glyph, only
while the condition holds; the whole slot disappears when neither does.
Recording has no glyph yet — nothing in this shell or a reachable service
reports screen recording as of 2026-07-29.

```bash
qs ipc --any-display -p <store-path>/share/formalshell call tray status     # {"items":[…],"expanded":…}
qs ipc --any-display -p <store-path>/share/formalshell call tray expand    # same action as clicking the "+N" cell
qs ipc --any-display -p <store-path>/share/formalshell call tray collapse
```

## Theming

Colors are wallpaper-derived end to end, no restart required:

1. Setting a wallpaper (`wallpaper set`, below) persists it to
   `$XDG_STATE_HOME/formalshell/state.json` via the `State` singleton.
2. `ThemeEngine` notices the change, builds a merged matugen config in the
   spec's order — the user's own `~/.config/matugen/config.toml` `[config]`
   section, the shell's own `theme.json`/`niri-border.kdl` template
   registrations, the user's `[templates.*]` blocks, then any drop-in
   `*.toml` fragments from `~/.config/formalshell/matugen.d/` — and runs
   `matugen image <wallpaper> -m <mode> -c <merged-config>` (matugen runs are
   serialized; a wallpaper/mode change mid-run supersedes the pending run,
   never kills one in flight).
3. matugen's output is atomically published to
   `$XDG_STATE_HOME/formalshell/theme.json` and `niri-border.kdl`. `Theme`
   (the shell's color singleton) watches `theme.json` live, so every bar
   token recolors on the next paint. With no wallpaper set, `theme.json` is
   written straight from the static Flexoki fallback instead, so the
   pipeline is uniform from a fresh install.
4. A per-screen `Background` surface (background Wayland layer) shows the
   current wallpaper, or a flat `Theme.color.background` fill when none is
   set.
5. `ThemeEngine` reloads the compositor's running config
   (`CompositorService.applyThemeFragment()`) so niri's window borders pick
   up the new `niri-border.kdl` immediately.

Add this once to your niri config so window borders track the theme:

```kdl
include "~/.local/state/formalshell/niri-border.kdl"
```

(`ThemeEngine` creates the file empty at startup if it's missing yet, so the
`include` never errors on a fresh install.)

Wallpaper and theme are driven over the same IPC surface as everything else:

```bash
qs ipc --any-display -p <store-path>/share/formalshell call wallpaper set /path/to/image.jpg
qs ipc --any-display -p <store-path>/share/formalshell call theme mode toggle    # dark <-> light
qs ipc --any-display -p <store-path>/share/formalshell call theme status         # {"wallpaper":…,"mode":…,"themeJsonPresent":…}
```

## Menu

One keyboard-driven, fuzzy-searchable surface is app launcher, system/power
menu, and a `select`/`input` dmenu replacement at once — Omarchy-style,
themed as a ruled ledger (see `docs/DESIGN.md`).

**The tree.** FormalShell ships `shell/Menu/default-menu.jsonc`, a flat
JSONC object keyed by dotted id (`system.power.reboot` implies parents
`system` and `system.power`, auto-created as submenus if not declared
themselves). An entry's kind is inferred from its keys: `action` → runs a
command, `target` → link to another node, `provider` → populated at
tree-build time (the `apps` node uses the `apps` provider, which turns every
installed `.desktop` entry into a launchable row), anything else → plain
submenu. `when`/`checked` are shell condition strings, batched into one
`Process` per condition on menu-open (never per keystroke) — `when: "false"`
hides a node outright, a real command's exit code decides visibility live
(e.g. `system.logout`'s `test -n "$NIRI_SOCKET"` guard).

**User overrides.** `~/.config/formalshell/menu.jsonc` merges **per-key over**
the default tree — user wins field-by-field, and `"hidden": true` removes a
default entry (and its whole subtree) without needing to redeclare it:

```jsonc
// ~/.config/formalshell/menu.jsonc
{
    "system.suspend": { "hidden": true },
    "system.custom-user-node": { "label": "My Script", "action": "~/bin/my-script" }
}
```

**Custom power buttons.** `~/.config/formalshell/settings.json`'s
`menu.customPowerButtons` array is the first-class way to add entries under
`System` — no `menu.jsonc` needed for the common case:

```json
{
  "menu": {
    "customPowerButtons": [
      { "label": "Windows", "icon": "󰖳", "command": "systemctl reboot --boot-loader-entry=auto-windows", "confirm": true }
    ]
  }
}
```

Each button becomes `system.custom.<i>` in the tree; `confirm: true` requires
a second Enter on the row before the command runs (`CONFIRM <label>?`).

**IPC.** Every route is summonable for direct compositor keybinds:
`toggle(route)` (open if closed/close if open), `summon(route)` (always
open), `close()`, `refresh()` (force a re-read of default+user jsonc —
`settings.json` is already watched live, this is a manual fallback for an
editor save an fs watcher missed), `ping()`. `route` is a node id
(`"system"`) or alias, or `""` for root. Bind it directly in niri:

```kdl
binds {
    Mod+Ntilde { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "menu" "summon" "clipboard"; }
}
```

**`select`/`input` — the dmenu replacement.** `qs ipc call` is synchronous
request/response but can't block on the menu's UI answer, so `select`/`input`
correlate by a caller-supplied token and hand the answer back through a file
instead of the IPC reply:

```bash
qs ipc --any-display -p <store-path>/share/formalshell call menu select "Pick a window" ' ["a","b","c"]' tok1
qs ipc --any-display -p <store-path>/share/formalshell call menu input "Rename to" tok2

# poll/read the answer:
cat $XDG_STATE_HOME/formalshell/menu-selection.txt
# => {"token":"tok1","value":"b"}          (a choice was made)
# => {"token":"tok1","cancelled":true}     (Escape, or superseded by another open)
```

The leading space in `' ["a","b","c"]'` is required, not cosmetic: `qs ipc
call`'s CLI11 argument parser auto-splits any positional argument that
literally starts with `[` and ends with `]` (its vector-literal shorthand),
which shreds a bare JSON array into extra positional arguments before it ever
reaches the handler. A leading space defeats that check while `JSON.parse`
still tolerates the whitespace.

## Notifications

A mako-replacement stack: a freedesktop `NotificationServer`, a pure-JS
three-tier reducer (`popups` → `pending` → `past`), independent card toasts
(M8b Task 5: each its own bordered, opaque-filled card rather than fused
ledger rows), and a summonable history center — see `docs/DESIGN.md` and
`docs/superpowers/specs/2026-07-27-formalshell-design.md` §6.

**Three tiers.** A notification lands in `popups` (a top-right toast, capped
at 4 — the oldest overflows to `pending`) unless DND is on, in which case it
goes straight to `pending`. A popup that times out (6s default, sticky for
`urgency: critical`) moves to `pending`, unseen. Opening the history center
marks everything in `pending` seen and moves it to `past`, which self-prunes
after 15 minutes.

**DND bypass is deliberately narrow** (Omarchy's rule, not a general
"urgent" exception): only `urgency: critical` notifications sent by the
literal `notify-send` CLI bypass DND. A chat app or any other sender marking
its own notifications critical does **not** bypass — the check is on the
sender's app name (`notification.appName === "notify-send"`), never inferred
from urgency alone.

**DND persists** in `state.json` (`Core.State.dnd`), same as wallpaper/mode
— it survives shell restarts and `keepOnReload` generation switches instead
of silently resetting to off.

**IPC** (`target: "notifications"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call notifications showHistory     # toggle the center
qs ipc --any-display -p <store-path>/share/formalshell call notifications toggleDnd       # flip DND, returns "on"/"off"
qs ipc --any-display -p <store-path>/share/formalshell call notifications dndState        # "on" | "off"
qs ipc --any-display -p <store-path>/share/formalshell call notifications markAllSeen     # drain pending -> past
qs ipc --any-display -p <store-path>/share/formalshell call notifications dismissAll      # clear popups
qs ipc --any-display -p <store-path>/share/formalshell call notifications clearPending    # drop pending outright
qs ipc --any-display -p <store-path>/share/formalshell call notifications clear           # dismissAll + clearPending
qs ipc --any-display -p <store-path>/share/formalshell call notifications invokeLast      # fire the newest popup/pending entry's default action
```

Bind the center to a key in niri, same pattern as the menu:

```kdl
binds {
    Mod+N { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "notifications" "showHistory"; }
}
```

The menu also has a `System > Notifications` row wired to the same
`showHistory` route (`shell/Menu/default-menu.jsonc`'s `system.notifications`
node).

## OSD

One bottom-centered, jitter-free card (icon | label | value, three fixed
columns) for volume, brightness, and media — `shell/Surfaces/Osd/Osd.qml`.
Column widths are constants measured once off a calibration glyph/label set,
never off the live value, so a percentage ticking or a track title swapping
in never reflows the card.

**Triggers.** Volume/mute auto-shows on `AudioService.changed` — any change
to the default sink, ours or external (`wpctl`, `pavucontrol`, hardware
keys). Brightness and media have no such signal to hook (`BrightnessService`
has no polling loop; there is no media-player service yet) and only ever
show via IPC (`target: "osd"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call osd volume       # manual show, current AudioService state
qs ipc --any-display -p <store-path>/share/formalshell call osd brightness   # refreshes BrightnessService, then shows
qs ipc --any-display -p <store-path>/share/formalshell call osd media "Artist - Track"
qs ipc --any-display -p <store-path>/share/formalshell call osd close
qs ipc --any-display -p <store-path>/share/formalshell call osd state        # {"visible":…,"kind":…,"mediaText":…}
```

A brightness keybind runs `brightnessctl` itself, then pokes the OSD to pick
up the new value — `BrightnessService` only re-reads on demand:

```kdl
binds {
    XF86MonBrightnessUp { spawn "sh" "-c" "brightnessctl set 5%+ && qs ipc --any-display -p <store-path>/share/formalshell call osd brightness"; }
}
```

## Panels

Six per-widget popouts share one component, `shell/Components/Panel.qml` — a
ledger-table popout (header `MetaLabel` row, rows sharing hairline rules,
`WlrLayershell` top layer, keyboard `OnDemand`, closes on Escape and on
click-outside) anchored under the bar cell that opened it, or falling back to
the bar's right region when opened over IPC with no cell to anchor under
(Wayland gives clients no cross-window global coordinates for a real anchor).
Each panel binds a first-party quickshell service directly — no intervening
service wrapper, the same pattern `AudioPanel` establishes for the rest:

| Panel        | Backing                                    | Bar cell            |
| ------------ | ------------------------------------------- | -------------------- |
| `audio`      | `Quickshell.Services.Pipewire`              | `AudioWidget.qml`    |
| `calendar`   | `Calendar/progress.js` + local `.ics` events | `Clock.qml`          |
| `network`    | `Quickshell.Networking`                     | `NetworkWidget.qml`  |
| `bluetooth`  | `Quickshell.Bluetooth`                      | `BluetoothWidget.qml`|
| `power`      | `Quickshell.Services.UPower`                | `Battery.qml`        |
| `weather`    | `LocationService` + open-meteo              | `WeatherWidget.qml`  |
| `media`      | `Quickshell.Services.Mpris`                 | `NowPlaying.qml`     |

Every bar cell shows the Omarchy-style panel-open accent dot while its panel
is open. `AudioPanel` lists Pipewire output nodes then input nodes as
full-width sliders (flat accent fill, no round thumb) with a `MUTE` toggle
cell per row. `NetworkPanel` groups connections under `WIRED`/`WI-FI`
headers, the active connection inverted, Wi-Fi signal strength drawn as a
discrete 5-segment block-character bar (the flat-fill slider idiom is
reserved for continuous values like volume). `BluetoothPanel` shows paired
devices with connect/disconnect as a row action, or a single dim `NO
ADAPTER` cell when `Bluetooth.defaultAdapter` is null — the test VM's honest
state, not a fabricated device. `PowerPanel` pairs a status row (an honest
`AC POWER` cell rather than a lying `0%` when `UPower.displayDevice.isLaptopBattery`
is false) with a keyboard-navigable power-profile picker (Up/Down to move,
Enter to apply) under power-profiles-daemon, plus a breathing-opacity
charging pulse while genuinely charging; `Battery.qml`'s bar cell goes
further and drops out of the bar entirely on the same condition, rather than
showing a stub `0%`. `WeatherPanel` shows current conditions as a header row
and a forecast ledger (one row per open-meteo daily period, glyph + weekday
+ high/low mono temps pinned right), falling back to an honest `NO LOCATION`
or `UNAVAILABLE` cell (with openmeteo.js's specific failure code) rather
than a stale or invented forecast.

**IPC** (`target: "panel"`, a documented spec addendum — see
`docs/superpowers/plans/2026-07-28-m6-clipboard-and-panels.md`'s header note
— since per-widget popouts otherwise have no summon path for compositor
keybinds and no way to be verified headlessly):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call panel open audio
qs ipc --any-display -p <store-path>/share/formalshell call panel toggle network
qs ipc --any-display -p <store-path>/share/formalshell call panel close        # closes whichever panel is open
qs ipc --any-display -p <store-path>/share/formalshell call panel state       # "" | "audio" | "calendar" | "network" | "bluetooth" | "power" | "weather"
```

An unknown panel name returns `error: unknown panel '<name>'` rather than a
silent no-op. Bind a panel to a key in niri, same pattern as the menu:

```kdl
binds {
    Mod+A { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "panel" "toggle" "audio"; }
}
```

## Clipboard

`ClipboardService` captures via a long-running `wl-paste --type text --watch`
`Process` (verified against the wl-clipboard man page): every clipboard
change forks a `sh -c` one-liner that forwards the selection over stdout,
NUL-delimited (clipboard text can itself contain newlines). A capture is
skipped entirely — no NUL emitted — when `wl-paste` sets
`CLIPBOARD_STATE=sensitive`, the signal it derives itself from an
`x-kde-passwordManagerHint` mime; that's the cheap password-manager filter,
nothing more elaborate.

History is a pure reducer (`shell/Clipboard/history.js`, `.pragma library`,
TDD'd first in `tests/tst_clipboard_history.qml`): capped at 300 entries
(oldest dropped), de-duplicated by content — re-copying an entry already in
history moves it to the front (keeping its original id) rather than
inserting a duplicate — and persisted to
`$XDG_STATE_HOME/formalshell/clipboard.json` via the same `FileView` +
`JsonAdapter` pattern `Core/State.qml` uses for `state.json`.

A `clipboard` menu provider node lists history entries as menu rows, newest
first; `formalshell menu summon clipboard` (or `qs ipc call menu summon
clipboard`) opens straight to them, and selecting a row re-copies it through
the same `clipboard copy <id>` IPC verb below — the menu row is just that
call, not a separate code path.

**IPC** (`target: "clipboard"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call clipboard list     # JSON array, newest first
qs ipc --any-display -p <store-path>/share/formalshell call clipboard copy <id>
qs ipc --any-display -p <store-path>/share/formalshell call clipboard remove <id>
qs ipc --any-display -p <store-path>/share/formalshell call clipboard clear
```

## Calendar

`CalendarPanel`'s month grid carries a year-progress bar below it — a
full-width flat accent-fill cell (`Calendar/progress.js#yearFraction()`,
pure and TDD'd, leap-year correct via `Date.UTC` boundaries) with its
percentage as mono text, mirroring `AudioPanel`'s slider idiom.

**Life-progress easter egg.** Double-clicking the progress bar prompts,
through the menu's own existing `input` mode (no new dialog surface), first
for a birth year then an expected lifespan; both persist to
`$XDG_STATE_HOME/formalshell/state.json` via `Core.State.setCalendarLifeProgress()`,
the same alias + writeAdapter pattern `wallpaper`/`mode`/`dnd` already use.
`~/.config/formalshell/settings.json`'s `calendar.birthYear` /
`calendar.lifeExpectancy` keys declaratively override those two persisted
state values when present (settings wins, state is the fallback — Config's
usual read-only-settings rule). Once both values resolve, the bar defaults
to showing `LIFE` (% of life lived) instead of `YEAR`; a further
double-click toggles back.

**Events.** An EDS/GNOME-Online-Accounts D-Bus feasibility spike
(`docs/spikes/2026-07-28-eds-calendar-events.md`) concluded **not feasible**
in pure QML: Evolution Data Server reaps the calendar backend the moment a
one-shot `gdbus`/`busctl` connection closes, and EDS's real client API needs
`libecal`'s persistent connection handling, which `CLAUDE.md` forbids (no
compiled companion binary). The implemented path instead is
`CalendarEventsService` reading local `.ics` files (a khal/vdir-style
directory) via `shell/Calendar/ics.js` (pure RFC 5545 VEVENT parsing, no
RRULE expansion — a documented v1 limitation). `calendar.icsDir` in
`settings.json` points at the directory; unset means zero events, the same
honest-empty-state contract every other M6 panel follows. When set, days
carrying an event get a small accent dot in the grid, and a `TODAY` ledger
section below lists today's events by summary (or a single dim `NO EVENTS`
row).

## Now playing

`MediaService` (`shell/Services/MediaService.qml`) wraps
`Quickshell.Services.Mpris`: it picks an actually-playing player over the
rest when several are registered, otherwise the first registered one,
otherwise `available: false` — the same honest-nothing-to-show contract
every other M6/M7 service follows, never a stubbed "not playing" state.
`NowPlaying.qml`'s bar cell (note glyph + elided title + panel-open accent
dot) is hidden entirely with no player present; `MediaPanel.qml` shows the
album art, a `NOW PLAYING / <app>` meta row, title/artist, a flat
accent-fill progress cell (draggable to seek when the player supports it),
and transport cells that invert on hover rather than the usual alpha-hover
(DESIGN's "selection = inversion" rule applied to primary controls, not
passive rows).

**Apple Music animated album art** (`AppleMusicArtService.qml`,
`shell/Media/applemusic.js`) is **opt-in** — `media.appleMusicArt` in
`settings.json`, off by default — and resolves via iTunes Search plus
amp-api's `editorialVideo` field, an **undocumented API**: every failure
path (no match, a scraped web-player token expiring, a plain network
failure) falls back to the static art above rather than erroring, and the
setting off makes `_schedule()` bail before any network call at all. A hit
downloads an MP4 to `~/.cache/formalshell/applemusic-art/` (per-lookup temp
file + atomic rename), a miss is cached too (`{}`-shaped cache keyed by
`artist/album`, so a track without animated art is never re-fetched every
play), and a 30-day prune runs once at startup. The muted, looping video
(`AnimatedAlbumArt.qml`, layered over the static art) plays only while the
panel is open and the track is actually playing.

**IPC** (`target: "media"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call media playPause
qs ipc --any-display -p <store-path>/share/formalshell call media next
qs ipc --any-display -p <store-path>/share/formalshell call media previous
qs ipc --any-display -p <store-path>/share/formalshell call media status     # {"available":…,"identity":…,"title":…,"artist":…,"album":…,"isPlaying":…,"position":…,"length":…}
```

## Lock screen

`shell/Surfaces/Lock/Lock.qml` wraps a `WlSessionLock`; `LockSurface.qml` is
the `Component` it instantiates once per output on its own — unlike every
other multi-output surface here, there's no manual `Variants` loop to write.
Authentication is `Quickshell.Services.Pam`'s `PamContext` directly, no
external binary, against a dedicated `formalshell-lock` PAM service (not
`login`, whose console-specific checks a lock screen has no business
inheriting). **A real deployment must declare
`security.pam.services.formalshell-lock = { };`** (or whatever name is
chosen) **system-side** — the home-manager module alone cannot create a PAM
service, only nixos/system config can (`nix/testvm.nix`'s own declaration is
the reference).

DESIGN.md's **one exception in the whole shell**: the blurred
current-wallpaper backdrop (`LockSurface.qml`'s `Image` + `MultiEffect`,
client-side QtQuick blur, tuned to Omarchy's own blur/contrast values — a
`ScreencopyView`-based capture was tried first and crashes the whole shell
outright, see the file's header comment for why it's never coming back).
Everything else on the lock surface stays flat, drawn by the shared
`Components/AuthPrompt.qml` plate (M8b Task 6) both `LockSurface.qml` and
`greeter/greeter.qml` instantiate unchanged: one bordered card holding an
oversized clock, the uppercase date, a dividing rule, and a single
3px-outlined field with centred placeholder text and shrink-to-fit `●`
masking so a long password never clips silently. Failed auth swaps the
field's border to `Theme.color.urgent` and shows an italic uppercase error
message (`WRONG PASSWORD` / `PAM ERROR` / `ACCOUNT LOCKED`, distinguished by
`PamResult`) — no shake, no bounce. A fingerprint glyph pins inside the
field's right edge when `lock.fingerprintPamService` names a reader, with
symmetric horizontal reserve so the centred dots stay centred either way.

**Hardening** on top of that base: idle blanking after
`lock.blankAfterSeconds` (default 30) once locked, driven by a dedicated
`IdleMonitor` with `respectInhibitors: false` (a locked screen should blank
regardless of an app-held inhibitor); a **wall-clock resume guard** compares
`Date.now()` across a 1s ticker rather than trusting a monotonic timer, so a
suspend/resume gap blanks the surface immediately on wake instead of leaving
it unlocked-but-blanked or trusting a stale idle countdown; and fingerprint
as a **parallel** PAM flow when `lock.fingerprintPamService` names one
(empty by default — no reader exists in the test VM, so the honest,
verified state is no prompt appears and the password field is unaffected) —
a separate `PamContext` with its own conversation, so a pending scan never
blocks or disables the password field, and either can succeed.

The `lock-before-sleep` contract (spec §8): `nix/package.nix` ships
`formalshell-lock-before-sleep`, a wrapper around `qs ipc call lock lock`
that always `exit 0` regardless of the call's own result — verified by
running it with no shell instance up at all and reading `$?`. The
home-manager module's `programs.formalshell.systemd.lockBeforeSleep` (on by
default) wires it to a `systemd --user` oneshot bound to `sleep.target`.

**IPC** (`target: "lock"`, no `unlock()` verb by design — see
`LockIpc.qml`'s header comment: a headless "type this password" shortcut
would bypass the exact `TextInput`/PAM wiring a real unlock exercises, so
`dev/smoke-niri.sh --lock` authenticates with real synthetic keystrokes
(`wtype`) instead):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call lock lock
qs ipc --any-display -p <store-path>/share/formalshell call lock isLocked   # "true" | "false"
qs ipc --any-display -p <store-path>/share/formalshell call lock status     # {"locked":…,"secure":…,"authError":…,"blanked":…}
```

## Screensaver

`IdleService.qml` wraps one shared `IdleMonitor` (`respectInhibitors: true`,
so an app-held idle-inhibit or the compositor's own "input-idle" folding
already keeps the whole session non-idle with no polling of our own) behind
`screensaver.timeoutSeconds` (default 300). `Screensaver.qml` is one
controller `Item` — deciding *when* to show, off `IdleService.isIdle` crossed
live with a media-playback guard — plus a per-monitor `Variants` overlay
(`WlrLayer.Overlay`, `OnDemand` keyboard focus), the same "one controller,
many surfaces" split `Lock.qml` uses. The visual (Omarchy reference:
`bin/omarchy-screensaver`'s `tte`-driven banner, reimplemented rather than
shelling out) loads an ASCII banner — the bundled block-character
`FORMALSHELL` logo at `branding/screensaver.txt`, or a user-supplied file —
and animates it converging into place on a `Canvas`, drawn in the shell's own
mono font and `Theme.color.accent`, no spawned terminal windows.
`shell/Screensaver/effect.js` (TDD'd first, pure functions of a frame
counter — column/cell state, convergence, everything directly testable) owns
five distinct convergence effects:

| Effect | Look |
| --- | --- |
| `decrypt` | every cell scrambles through random glyphs before settling on its target character |
| `rain` | the original matrix-rain: columns of falling glyphs with a brightness-decay trail |
| `expand` | each line grows outward from its own center |
| `slide` | each line slides in from alternating edges |
| `scatter` | every cell starts at a random offset and converges inward |

**Picking an effect.** `screensaver.effect` in `settings.json` is `"random"`
by default — a fresh effect is picked every time the screensaver activates,
seeded off the activation itself so a long idle session still cycles
variants — or pin it to any one of the five names above (an unknown name
falls back to random and logs a warning, never a hard error):

```jsonc
// ~/.config/formalshell/settings.json
{ "screensaver": { "effect": "decrypt" } }
```

**Replacing the banner.** `screensaver.asciiPath` points at any UTF-8 text
file to use instead of the bundled logo — empty (the default) keeps
`branding/screensaver.txt`, and a custom file that fails to load falls back
to the bundled one rather than showing nothing. The path must be absolute:
neither `Config.qml` nor quickshell's `FileView` expands a leading `~`, so a
tilde path silently fails to load and falls back to the bundled banner.

```jsonc
{ "screensaver": { "asciiPath": "/home/youruser/.config/formalshell/my-banner.txt" } }
```

It never activates while `screensaver.guardMediaPlayback` (default true)
holds and `MediaService.isPlaying` is true — a live condition, not a
one-time check, so a track starting or ending mid-idle-stretch flips it
immediately either way. Any real input (key or pointer movement) dismisses
it; `screensaver.lockAfterSeconds` (default 0, disabled) optionally chains
into the lock screen after continuing to show for that much longer.

**IPC** (`target: "screensaver"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call screensaver start
qs ipc --any-display -p <store-path>/share/formalshell call screensaver stop
qs ipc --any-display -p <store-path>/share/formalshell call screensaver status  # {"active":…,"isIdle":…,"guardMediaPlayback":…,"mediaPlaying":…}
```

`dev/smoke-niri.sh --screensaver` additionally accepts `SCREENSAVER_EFFECT`
and `SCREENSAVER_ASCII_TEXT` environment variables (unset by default) to pin
an effect or a custom banner for a single verification run — see the
script's own header comment.

## Picker

`shell/Surfaces/Picker/ImagePicker.qml` is a ledger grid of image cells
(`Components/Cell.qml`, sharing hairline rules — a grid first, Omarchy's
skewed carousel is explicitly a later flourish), keyboard-navigable in 2D
(arrows move the cursor cell, which `Cell`'s own inversion marks; Enter
confirms), scanned via a `find`-backed `Process` from a configured directory
(Quickshell has no directory-listing QML type, same technique
`CalendarEventsService` already uses) — an empty/unset directory renders an
honest `NO IMAGES` cell rather than nothing.

It doubles as two things over the same grid:

- **Wallpaper mode** (`summon()`, scans `picker.directory` from
  `settings.json`): choosing an image calls `Core.State.setWallpaper()`
  directly — the exact call `wallpaper set` makes, so `ThemeEngine`'s
  retheme pipeline runs through the one trigger path, never duplicated.
- **Generic image-selector mode** (`select(directory, token)`, spec §11):
  scans an arbitrary caller-supplied directory; the chosen path (or a
  cancel on close/Escape/click-outside) lands in
  `$XDG_STATE_HOME/formalshell/picker-selection.txt` as `{token, value}` /
  `{token, cancelled: true}` JSON — the same request/answer handshake
  `MenuIpc`'s `select()`/`input()` already established, reused rather than
  reinvented.

**IPC** (`target: "picker"` — a documented spec addendum, same rationale as
`panel`: the spec's own §IPC list predates this surface and doesn't name it,
but per-widget-style popouts otherwise have no summon path for compositor
keybinds or headless verification):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call picker summon                       # open in wallpaper mode
qs ipc --any-display -p <store-path>/share/formalshell call picker select /path/to/dir tok1      # open in select mode, correlated by token
qs ipc --any-display -p <store-path>/share/formalshell call picker choose /path/to/dir/img.png   # same action Enter/click on a cell takes
qs ipc --any-display -p <store-path>/share/formalshell call picker close
qs ipc --any-display -p <store-path>/share/formalshell call picker status   # {"open":…,"mode":…,"directory":…,"count":…,"cursor":…}

# poll/read a select() answer, same convention as menu-selection.txt:
cat $XDG_STATE_HOME/formalshell/picker-selection.txt
```
