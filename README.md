# FormalShell

A from-scratch Wayland desktop shell built on QuickShell (Qt/QML toolkit,
v0.3.x): one long-running process hosting bar, unified menu/launcher,
notifications, OSD, lock screen, screensaver, greeter, panels, clipboard
history, media, weather — compositor-agnostic behind a formal backend
interface (niri primary, Hyprland second), matugen-driven colors,
brutalist/terminal aesthetic, and first-party nix support designed so the
consuming config needs near-zero glue.

## Status

Pre-alpha. M1 (walking skeleton), M2 (compositor layer), M3 (matugen theme
engine), M4 (unified menu), M5 (notifications + OSD), M6 (clipboard +
panels), M7 (now playing, lock, screensaver, picker), and M8 (greeter +
NixOS modules) are done: a
brutalist three-region bar (workspaces/active window, clock, indicator
widgets) backed by a formal `CompositorBackend` contract with working niri
and Hyprland implementations; wallpaper-driven colors that recolor every bar
token live and sync niri's window borders (see Theming below); a
omarchy-card menu (ruled-ledger rows inside) that's app launcher, system/power
menu, and a `select`/`input` dmenu replacement in one fuzzy-searchable
IPC-summonable surface (see Menu below); a mako-replacement notification
stack (freedesktop server, independent card toasts, summonable history
center, strict DND bypass) plus a
jitter-free bottom-center OSD for volume/brightness/media (see Notifications
and OSD below); seven per-widget popout panels (audio, calendar, network,
bluetooth, power, weather, media) sharing one popout component and one
`panel` IPC target, plus a capped clipboard history surfaced through the menu
(see Panels, Clipboard, and Calendar below); and a real `WlSessionLock` +
PAM lock screen, an idle-driven terminal-effect screensaver, and a
ledger-grid image/wallpaper picker (see Now playing, Lock screen,
Screensaver, and Picker below); and a greetd greeter rendering as the lock
screen's visual twin, real authentication over `Quickshell.Services.Greetd`,
plus the two NixOS modules a full system install needs (see Install below).
CI (qmllint + headless qml-tests) and nested-compositor smoke loops are the
verification tools for every change. See
`docs/superpowers/specs/2026-07-27-formalshell-design.md` for the full
design.

## Screenshots

Every screenshot below comes from `dev/smoke-niri.sh`: it builds the package,
launches it inside an isolated **nested** niri session (not the host
desktop), screenshots that nested session, and tears it down. This is the
standard way UI changes get verified in this repo — see `CLAUDE.md`.

![Bar on niri](docs/screenshots/bar-niri.png)

The screenshot above is from `dev/smoke-niri.sh --wallpaper` (M8b revision):
a solid-color test wallpaper is set over IPC before the shot, so the
background layer and the bar's colors are both matugen-derived rather than
the static Flexoki fallback. The bar itself is now Omarchy-style — idle
widgets are borderless, gaining a hairline+fill only on hover/cursor, and the
focused workspace (`1`) is a full-bleed accent cell rather than a bordered
one.

![Menu on niri](docs/screenshots/menu-niri.png)

The screenshot above is from `dev/smoke-niri.sh --menu --wallpaper`: the menu
is summoned over IPC, switched into `select` mode, and screenshotted over the
same matugen-recolored wallpaper. Post-retrofit the menu renders as a
floating omarchy-style card (its own full border, opaque fill) rather than
an edge-to-edge ledger — the uppercase `SELECT / PICK` breadcrumb and
inverted cursor row are unchanged inside it.

![Notifications on niri](docs/screenshots/notifications-niri.png)

The screenshot above is from `dev/smoke-niri.sh --notify --center`: a
summoned history center showing the `DND` toggle cell and a `PENDING / 2`
section, each notification now its own independent omarchy-style card (full
border, opaque fill, separated by a real gap) rather than fused ledger rows.
The center and the toast stack are both top-right anchored, so `Toasts.qml`
suppresses itself for as long as the center is open — a still-sticky
critical popup underneath would reappear the moment the center closes (see
Notifications below).

![OSD on niri](docs/screenshots/osd-niri.png)

The screenshot above is from `dev/smoke-niri.sh --osd`: the bottom-center OSD
card after a manual `qs ipc call osd volume`, showing its own opaque card
border, the fixed three-column layout (icon | label | value), and the flat
accent fill bar. The same run also verifies the real auto-show trigger
(`wpctl set-volume @DEFAULT_AUDIO_SINK@ 30%` firing `AudioService.changed`)
and the brightness variant.

![Panels on niri](docs/screenshots/panels-niri.png)

The screenshot above is from `dev/smoke-niri.sh --panel audio --wallpaper`:
`panel open audio` over IPC opens the audio popout (no bar-cell click, so it
falls back to sitting under the bar's right region — see Panel.qml), now a
floating omarchy-style card sitting `Theme.space.panelGap` below the bar
rather than flush against it, showing the OUTPUT header, a `Virtual Sink
30%` row, a `MUTE` toggle cell, and the flat accent-fill slider with no round
thumb, over the same matugen-recolored wallpaper as the other panels'
screenshots.

![Calendar on niri](docs/screenshots/calendar-niri.png)

The screenshot above is from `dev/smoke-niri.sh --panel calendar --wallpaper`:
the month grid (weekday meta row, today inverted with an event dot under
it), a `TODAY` section listing the fixture `.ics` event by summary, and the
year-progress bar as a full-width flat accent fill with its percentage as
mono text, all inside the panel's own omarchy-style card frame.

![Clipboard on niri](docs/screenshots/clipboard-niri.png)

The screenshot above is from `dev/smoke-niri.sh --clipboard --wallpaper`:
three `wl-copy` fixture strings captured newest-first, then the second entry
re-copied through the exact self-targeting IPC call the menu's clipboard row
uses, moving it back to the front — the menu summoned at the `clipboard`
route shows the reordered rows as real cells inside the menu's card
(`MENU / CLIPBOARD` breadcrumb).

![Now playing on niri](docs/screenshots/media-niri.png)

The screenshot above is from `dev/smoke-niri.sh --media`: a real MPRIS player
(`mpv` with its own `mpris.lua` script, playing a generated silent fixture
track into the pipewire null sink) drives the bar cell (note glyph + elided
title + panel-open accent dot) and the opened media panel — `NOW PLAYING /
mpv` meta row, title/artist, a flat accent-fill progress cell, and the three
transport cells — with `media status` cross-checked against the fixture
track's own tags.

![Lock screen on niri](docs/screenshots/lock-niri.png)

The screenshot above is from `dev/smoke-niri.sh --wallpaper --lock`: the
locked `WlSessionLock` surface over a matugen-recolored wallpaper, showing
DESIGN.md's one blur exception (the blurred backdrop) behind the shared
`Components/AuthPrompt.qml` plate — one bordered card holding the oversized
clock, the uppercase date, a dividing rule, and the single 3px-outlined
`ENTER PASSWORD` field (M8b Task 6, replacing the old three loose
independently-floating items). The same run also drives a full round trip —
a wrong password inverts the field's border and shows an italic uppercase
`WRONG PASSWORD` message, then the VM's real throwaway test password unlocks
back to the normal session — and proves `formalshell-lock-before-sleep`
exits 0 even with no shell instance running at all (the
`lock-before-sleep` exit-0-always contract, spec §8).

![Screensaver on niri](docs/screenshots/screensaver-niri.png)

The screenshot above is from `dev/smoke-niri.sh --screensaver`: the
full-screen `FORMALSHELL` block-character banner (`branding/screensaver.txt`,
user-replaceable) shown converged, drawn on a `Canvas` in the shell's own
mono font and `Theme.color.accent` (`Screensaver/effect.js`). This shot
proves the auto-activation path specifically: with the fixture MPRIS track
still playing, `screensaver status` reports `active:false` despite
`isIdle:true` (the live media guard holding); only once the track is killed
does the screensaver activate purely from the real compositor idle timer, no
`start` call involved. See Screensaver below for the full effect list and how
to pin one or swap the banner.

![Picker on niri](docs/screenshots/picker-niri.png)

The screenshot above is from `dev/smoke-niri.sh --picker`: five generated
solid-color fixture images scanned from `picker.directory` into a grid
inside the picker's own card frame (`WALLPAPER` meta header, cursor cell
highlighted with its own border). The same run proves both picker contracts
over IPC — `choose`-ing one fixture sets it as the wallpaper exactly like
`wallpaper set` (confirmed via `theme status`), and a separate `select` call
with a caller token returns a different fixture's path through the same
request/answer file `MenuIpc`'s `select`/`input` already establish.

![Greeter on greetd](docs/screenshots/greeter-niri.png)

The screenshot above is from `dev/smoke-greeter.sh` (`just vm-greeter`), a
sibling script rather than a `dev/smoke-niri.sh` flag: greetd's
`default_session` is a persistent system service, not a fresh nested
compositor composed per run, so this drives the *already-running*
`formalshell-greeter` session with real `wtype` keystrokes across the
`test` -> `greeter` system-account boundary instead. It shows the lock
screen's exact visual twin at rest — the same `AuthPrompt` plate, its
`masked: false` mode swapping the field's placeholder to `ENTER USERNAME` —
mid a real `create_session`/`auth_message` greetd conversation. The same run
also proves a wrong password inverts the field with the genuine PAM failure
text (`PAM_AUTHENTICATE: AUTH_ERR`, never a fabricated message) and that the
correct password reaches `Greetd.launch()` (`Authentication complete.` /
`Quitting.` in the session log).

The Hyprland backend is implemented and its `debug` IPC dump has been
verified against a live nested Hyprland session (workspaces, focused window,
`compositor: "hyprland"` all correct), but nested Hyprland does not reliably
reach a screenshot in this dev sandbox (its wlroots-in-Wayland backend either
fails to composite a frame for `grim` or hangs on exit) — no `bar-hyprland.png`
is published until that's fixed. `dev/smoke-hyprland.sh` is the script to
retry once the environment allows it.

## Install

FormalShell installs as a whole system, not just a user shell: one
home-manager module for the shell itself, and two NixOS modules for the
system-side pieces home-manager cannot provide (a PAM service, geoclue2 +
its agent, greetd). Add the flake input first:

```nix
{
  inputs.formalshell.url = "github:FormalSnake/FormalShell";
}
```

### `nixosModules.formalshell` — system-side prerequisites

`services.formalshell.enable = true;` turns on everything M6/M7 need from
the system side that home-manager has no access to. Each backend is its own
sub-option, defaulted on via `lib.mkDefault` so a config that already manages
one of these its own way can still override it without a definition conflict
— see `nix/nixos-module.nix` for the full rationale behind each entry:

| Sub-option | Backs | Default |
| --- | --- | --- |
| `pam.enable` | `security.pam.services.formalshell-lock` — the exact service name `Lock.qml`'s `PamContext` authenticates against | `true` |
| `geoclue.enable` | `services.geoclue2` + its demo agent — `LocationService`'s default position source | `true` |
| `networkmanager.enable` | `networking.networkmanager` — `NetworkPanel`'s only backend | `true` |
| `bluetooth.enable` | `hardware.bluetooth` — `BluetoothPanel`'s backend | `true` |
| `upower.enable` | `services.upower` — the battery bar cell and `PowerPanel` | `true` |
| `powerProfiles.enable` | `services.power-profiles-daemon` — `PowerPanel`'s profile picker | `true` |
| `pipewire.enable` | `services.pipewire` — the audio bar cell, audio panel, and volume OSD | `true` |

**Without this module (or an equivalent hand-written
`security.pam.services.formalshell-lock = { };`), the lock screen cannot
authenticate at all** — `PamContext` has nothing to talk to. **Without
`geoclue.enable`'s agent, geoclue never answers** `LocationService`'s
position requests either.

### `nixosModules.formalshell-greeter` — greetd wiring

`services.formalshell-greeter` wires `services.greetd` to run
`packages.<system>.formalshell-greeter` as the `default_session`, under a
wlroots compositor (`compositorPackage`, default `pkgs.sway`):

```nix
{
  services.formalshell-greeter = {
    enable = true;
    package = inputs.formalshell.packages.${pkgs.system}.formalshell-greeter;
    sessionCommand = [ "niri" ]; # argv a successful login launches
  };
}
```

`sessionCommand` is the one option a real deployment usually needs to set —
it's written into a static `settings.json` for the `greeter` system account
(whose own passwd `HOME` is unwritable, hence the module's own separate
`runtimeDir`/`stateDir`). `extraEnvironment`, `sessionLogFile`, and
`postGreeterCommand` exist for a nonstandard seat or verification tooling; a
normal login never touches them — see `nix/nixos-greeter-module.nix`.

### `homeModules.formalshell` — the shell itself

```nix
{
  imports = [ inputs.formalshell.homeModules.default ];
  programs.formalshell = {
    enable = true;
    package = inputs.formalshell.packages.${pkgs.system}.default;
  };
}
```

`programs.formalshell.settings` (JSON) is written once to
`~/.config/formalshell/settings.json` and only ever read by the shell — see
`nix/hm-module.nix`.

### Minimal working `flake.nix`

```nix
{
  inputs.formalshell.url = "github:FormalSnake/FormalShell";

  outputs = { self, nixpkgs, home-manager, formalshell, ... }: {
    nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        formalshell.nixosModules.formalshell
        formalshell.nixosModules.formalshell-greeter
        {
          services.formalshell.enable = true;
          services.formalshell-greeter = {
            enable = true;
            package = formalshell.packages.x86_64-linux.formalshell-greeter;
          };
        }
        home-manager.nixosModules.home-manager
        {
          home-manager.users.me = {
            imports = [ formalshell.homeModules.default ];
            programs.formalshell = {
              enable = true;
              package = formalshell.packages.x86_64-linux.default;
            };
          };
        }
      ];
    };
  };
}
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
to the bundled one rather than showing nothing:

```jsonc
{ "screensaver": { "asciiPath": "~/.config/formalshell/my-banner.txt" } }
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

## Dev loop

```bash
nix develop              # qs, qt6.qtdeclarative (qmllint/qmltestrunner/qmlls), matugen, just
just build               # nix build .#formalshell
just test                # headless qmltestrunner over tests/
just lint                # nix flake check -L (qml-tests + qmllint)
just smoke               # nested niri + screenshot — the visual verification loop
./dev/smoke-niri.sh --wallpaper # same, plus sets a test wallpaper over IPC first
./dev/smoke-niri.sh --menu      # same, plus drives the menu IPC (summon/select/close) in-session
./dev/smoke-niri.sh --notify    # same, plus fires notify-send (normal + critical) and screenshots the toasts
./dev/smoke-niri.sh --center    # combine with --notify: also summons the history center over IPC
./dev/smoke-niri.sh --osd       # same, plus drives the osd IPC target (volume/brightness) and wpctl for the auto-show leg
./dev/smoke-niri.sh --panel audio    # same, plus opens the named panel over the panel IPC target and leaves it open through the screenshot
./dev/smoke-niri.sh --clipboard      # same, plus wl-copies fixture strings, proves dedup-to-front via clipboard IPC, then summons the menu's clipboard route
./dev/smoke-niri.sh --media          # same, plus plays a real MPRIS fixture track (mpv+mpris.lua) and opens the media panel
./dev/smoke-niri.sh --lock           # same, plus locks/wrong-password/unlocks over real PAM+wtype keystrokes, proving the exit-0-always lock-before-sleep wrapper too
./dev/smoke-niri.sh --screensaver    # same, plus proves the media guard and the real idle-timeout auto-activation, then the manual start/stop IPC path
./dev/smoke-niri.sh --picker         # same, plus scans generated fixture images and proves both the wallpaper-mode and select-mode IPC round trips
./dev/smoke-hyprland.sh  # nested Hyprland equivalent (see Screenshots above)
```

### On a macbook

Linux boxes aren't always around. On Determinate Nix under nix-darwin, a
two-layer rig reproduces every command above from the mac itself — see
`CLAUDE.md`'s "macOS verification loop" for the full design:

```bash
dev/linux-builder.sh start   # once: aarch64-linux builder (nix build .#packages.aarch64-linux.*)
dev/linux-builder.sh register

just vm-up                   # boot the headless aarch64 test VM (nix/testvm.nix)
just vm-build                # nix build .#formalshell, inside the VM
just vm-test                 # qmltestrunner, inside the VM
just vm-lint                 # nix flake check -L, inside the VM
just vm-smoke                # dev/smoke-niri.sh, unchanged, against a headless
                              # sway parent compositor — screenshot pulled to ./artifacts/
just vm-smoke --wallpaper --menu --notify --center --osd   # same flags dev/smoke-niri.sh takes
just vm-smoke --panel calendar                              # --panel <name>/--clipboard work the same way
just vm-smoke --media --screensaver --picker                 # M7 surfaces, all headlessly driven over IPC
just vm-smoke --wallpaper --lock                             # run --lock on its own; combine flags freely otherwise
just vm-down
```

`dev/vm.sh sync` pushes the working tree (not a commit) into the VM before
every `run`/`smoke`, so the edit-build-screenshot loop matches editing
locally. Screenshots and JSON dumps land on the mac under `./artifacts/`
(gitignored) instead of `result/`.

## License

MIT — see `LICENSE`.

## Credits

Built on [QuickShell](https://quickshell.org/). Architecture and UX
(single-process shell, unified surfaces, IPC contract) are generalized from
[Omarchy](https://github.com/basecamp/omarchy)'s `quattro` branch off
Hyprland. Service patterns for the multi-compositor backend layer are ported
with attribution from [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
(MIT).
