# FormalShell usage reference

Per-surface reference for FormalShell's IPC targets, config keys, and
keybind examples — theming, menu, notifications, OSD, panels, clipboard,
calendar, now playing, lock screen, screensaver, picker, and screenshots.
Product overview, screenshots, features, and install instructions live in
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
- [Screenshots](#screenshots)

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
      "right": ["battery", "audio", "network", "bluetooth", "weather", "tray", "bell", "indicators", "custom:cpu"]
    },
    "modules": [
      { "id": "cpu", "type": "command", "command": ["my-cpu-script"], "interval": 5000, "timeout": 5000 }
    ]
  }
}
```

Builtin widget names: `workspaces`, `activeWindow`, `clock`, `nowPlaying`,
`battery`, `audio`, `network`, `bluetooth`, `weather`, `tray`, `bell`,
`indicators`, `github`, `usage`, `tailscale` (all three opt-in only — never
part of the default arrangement; `bell` by contrast IS part of the defaults
since M13b, so a config predating it that spells out its own `right` region
won't show the bell until it's added there).
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

**Workspaces** — one cell per *visible* workspace, sorted by the backend's
own per-output ordinal (`idx`; ids stay opaque strings, never parsed). A
workspace renders only if it holds at least one window or is
active/focused, so nine persistent named niri workspaces with two windows
open show two or three cells, not nine (`shell/Bar/workspaces.js`).

**Active window** — the focused window's desktop entry
(`DesktopEntries.heuristicLookup(appId)`, the same lookup the launcher
uses) leads with its themed icon and display name in foreground, the
window title following dimmed. No matching entry falls back to the raw
`appId` dimmed with the title in foreground; no focused window hides the
cell entirely.

**Tray** — every real `org.kde.StatusNotifierItem` registered on the
session bus (`Quickshell.Services.SystemTray`) renders as its own cell:
left click activates it, middle click secondary-activates it, right click
opens its `DBusMenu` if it has one. Items whose SNI `ItemIsMenu` flag says
activation-is-menu get the menu on left click too. The menu renders as a
native-styled popup (quickshell's platform-menu path owns that widget
outright), not a shell-themed surface. Past 4 visible items the rest
collapse into one more cell (`+N`) that expands the row to reveal them all.

**Bell** — an always-visible notification cell (M13b): bell glyph, swapping
to bell-off while DND is on, plus a pending-count meta label whenever
notifications are sitting unseen in the `pending` tier (see
[Notifications](#notifications)). Left click toggles the notification
center — the same surface `notifications showHistory` drives — with the
panel-open accent dot while it's open; right click flips DND through the
one existing DND state machine (`notifications toggleDnd`'s), never a
second one.

**Indicators** — transient session-state glyphs, only while the condition
holds; the whole slot disappears otherwise. Today that means idle-inhibit
alone: the DND bell-off glyph this slot carried since M10 moved to the
always-visible bell cell above, which owns both DND display and its
toggle. Recording has no glyph yet — nothing in this shell or a reachable
service reports screen recording as of 2026-07-29.

**Weather** (M15): a glyph plus rounded current temperature (`14°`) once
`WeatherPanel`'s open-meteo poll has data, refreshed every
`weather.intervalMs` (ms, default 900000) and on every panel open. The
glyph switches between day and night variants of the current condition
(`Weather/openmeteo.js`'s `glyphForCode`) based on the host's local clock.
Before the first fetch lands, or with no location fix, the cell stays a
dim glyph rather than the old static "WEATHER" label or a fake reading —
the same honest-fallback shape every other widget uses. Click toggles the
weather panel (see [Panels](#panels)).

**GitHub** — opt-in via `bar.layout` (add `"github"` to a region); polls one
`gh api graphql` call every `github.intervalMs` (ms, default 300000) for the
count of open PRs you authored and open issues assigned to you, rendered as
a glyph + `N/M` meta cell. Click toggles the GitHub panel anchored under
the cell (see [Panels](#panels)) rather than jumping to the website. Honest
states: `gh` missing from PATH hides the cell entirely;
`gh` present but unauthenticated (its documented exit code 4) renders a dim
`NO AUTH` cell; any other failure or unparsable output renders a dim `NO GH`
cell — never stale or invented counts. The cell also stays hidden until the
first poll answers at all.

**Tailscale** — opt-in via `bar.layout` (add `"tailscale"` to a region); a
single glyph, dim while stopped, normal while connected, polling
`tailscale status --json` every `tailscale.intervalMs` (ms, default 60000).
Click toggles the Tailscale panel (see [Panels](#panels)). Honest states:
`tailscale` missing from PATH hides the cell entirely; any other failure
(daemon unreachable, unparsable output) leaves it hidden too, since the
panel folds both into the same `NO TAILSCALE` state and the widget only
shows once a real answer — good or bad-but-parseable — has landed. The cell
stays dim (rather than accent-colored) whenever `BackendState` isn't
`Running`, including `NeedsLogin`.

**Usage** — opt-in via `bar.layout` (add `"usage"` to a region); a glyph
plus the worst tracked rate-limit window's percent across Claude Code and
Codex, both independently toggleable (`usage.claude`/`usage.codex` in
`settings.json`, default `true`) and polled every `usage.intervalMs` (ms,
default 900000). The whole cell goes full-bleed `urgent` at ≥90%
utilization. Click toggles the usage panel (see [Panels](#panels)). Honest
states: a disabled provider contributes nothing, and the cell stays hidden
until at least one enabled provider has answered at all (its own `NO AUTH`/
`NO CODEX` cell counts as an answer) — never an invented percentage.

```bash
qs ipc --any-display -p <store-path>/share/formalshell call tray status     # {"items":[…],"expanded":…}
qs ipc --any-display -p <store-path>/share/formalshell call tray expand    # same action as clicking the "+N" cell
qs ipc --any-display -p <store-path>/share/formalshell call tray collapse
qs ipc --any-display -p <store-path>/share/formalshell call tray activate <id>   # same action as left-clicking the item's cell
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
   written straight from the bundled Flexoki fallback instead — the variant
   matching the current mode (M13b), so `theme mode toggle` visibly flips
   the whole shell between Flexoki dark and light through the exact same
   theme.json write a matugen run uses, and the pipeline is uniform from a
   fresh install (whose seeded first-boot theme.json stays the dark
   variant).
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

**Motion.** Transitions across the shell run off `Theme.motion` tokens
(`docs/DESIGN.md` §4): 100ms for hover fills, 130ms for surface
enter/exit, one ease-out curve, opacity plus a 6px translate only — no
scale, no bounce, end states pixel-identical to the unanimated shell.
Full-bleed accent/selection swaps (the ledger inversion, the focused
workspace's fill) are states, not transitions, and stay instant. The
wallpaper crossfade is the one carve-out outside that band: setting a new
wallpaper (`wallpaper set`, the picker) fades it in over
`Theme.motion.reveal` (400ms, `Easing.InOutQuad`) while the previous
wallpaper stays painted underneath, instead of a hard cut.
`motion.enabled: false` in `settings.json` zeroes every duration —
including `reveal` — the shell's reduced-motion switch, since Wayland has
no `prefers-reduced-motion` to inherit:

```jsonc
// ~/.config/formalshell/settings.json
{ "motion": { "enabled": false } }
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

**App rows.** Each launchable app shows the entry's display name (falling
back to its id only when the name is genuinely empty) and renders the
entry's icon-theme icon as an image at the glyph cell's size — radius 0,
no border, `docs/DESIGN.md`'s one sanctioned image-icon exception (M13b;
before that the raw icon *name*, which conventionally equals the app id,
rendered as literal text in the icon slot). An icon the current theme
can't resolve means the row simply has no leading image — never a
broken-image box.

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

**Wallpaper.** The root `WALLPAPER` node opens the [Picker](#picker) grid
over `picker.directory`: its activation spawns the same self-targeting
`qs ipc call picker summon` invocation the clipboard rows use, so the
picker opens only after the menu surface has closed and never fights its
keyboard-exclusive focus. The node is injected at tree-build time
(`providers.js`'s `wallpaperEntry()` — static jsonc can't know the running
shell's own path), but overrides address it by its `"wallpaper"` id like
any declared node, including `"hidden": true`.

**Calculator.** A root-menu query that parses as an arithmetic expression
(`+ - * / % ^`, parentheses, unary minus, decimals — a real
recursive-descent parser in `shell/Menu/calc.js`, never `eval`) leads the
ranked results with a `= <result>` row carrying a full-bleed accent `CALC`
tag; Enter copies the result via `wl-copy` and closes. `menu summon calc`
opens a dedicated surface showing only that live result row. Parse failures
are silent — no row, never an error row.

**Emoji.** `menu summon emoji` opens a fuzzy name search over a vendored
Unicode dataset (`shell/Menu/emoji.json` — fully-qualified `emoji-test.txt`
entries, Emoji 17.0; regenerate with `dev/gen-emoji.sh`, never edit by
hand). Rows render the char plus its uppercase name; Enter copies the char
via `wl-copy` and closes, and the clipboard history captures it like any
other copy. On top of the copy, the char is auto-typed into whatever window
focus returns to: the menu surface closes first, then after a 150ms settle
`wtype <char>` runs (the package wrapper bundles `wtype`, suffixed on PATH
so an environment `wtype` can shadow it). `wtype` missing or the
compositor lacking the virtual-keyboard protocol degrades to the copy that
already happened — one console warning, no error surface. From anywhere,
the root trigger `:e <query>` narrows to the
same rows (`:e thumbs` → 👍); a bare `:e` browses the head of the list.

**Nix package runner.** `menu summon nix` (or the `:nix <query>` root
trigger) searches nixpkgs as you type: a debounced (500ms, one in-flight,
stale results dropped) `nix search nixpkgs <query> --json`, rows showing
attr name + version with a dimmed description. Every state renders
honestly as a single dim, non-activatable note row (M13b — a real host's
first `nix search` can spend tens of seconds warming evaluation caches,
which used to look like nothing happening): `SEARCHING` while a run is in
flight, `NO RESULTS` for a clean zero-hit answer, `SEARCH FAILED` for a
non-zero exit or unparseable output, and `NO NIX` when the binary is
missing from PATH entirely. Enter on a result spawns the package in a
throwaway terminal (`ghostty -e sh -c 'nix run nixpkgs#<attr>; read'` —
`read` holds the window open after it exits) and immediately fires a
`NIX RUN <attr>` notification through the shell's own stack, so the launch
is visible even while the terminal is still seconds from mapping.

**IPC.** Every route is summonable for direct compositor keybinds:
`toggle()` (deliberately no-argument — root summon if closed, close if
open; the verb to bind a bare menu key to, after a compositor keybind
passing no route to a route-taking toggle was rejected by IPC arity
checking before the handler ever ran), `summon(route)` (always open),
`close()`, `refresh()` (force a re-read of default+user jsonc —
`settings.json` is already watched live, this is a manual fallback for an
editor save an fs watcher missed), `status()` (`{isOpen, level}`, for
headless assertion), `ping()`. `route` is a node id
(`"system"`) or alias, or `""` for root. An absent optional
`~/.config/formalshell/menu.jsonc` logs at most one line per path change,
never a warning per internal retry. Bind it directly in niri:

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
goes straight to `pending`. A popup that times out moves to `pending`,
unseen — the duration is Omarchy's own band, honoring a sender's own
`expire_timeout` hint when it falls inside the band: 5s floor for
`urgency: low`, 8s floor otherwise, 30s cap either way, sticky (never times
out on its own) for `urgency: critical`. Hovering a popup pauses its
countdown; it resumes from wherever it left off once the pointer leaves.
Opening the history center marks everything in `pending` seen and moves it
to `past`, which self-prunes after 15 minutes.

**Card density** (M15): summary clamps to 2 lines, body to 3 — rendered as
`Text.StyledText` so raw `\n` can become `<br/>` (`StyledText` otherwise
ignores it). The server never advertises body-markup support
(`NotificationServer.bodyMarkupSupported: false`), so a sender's own
`&`/`<`/`>` are escaped rather than interpreted as tags — real markup shows
as literal text, the same as before M15, instead of being misparsed and
silently truncating the rest of the body. `sanitizeBody` always strips `<img>` tags
(the icon slot below already carries any real image) and, for
Chromium-derived senders (Chrome/Brave/Vivaldi/Edge/Opera, matched on app
name or icon), strips the leading URL-as-link or bare-URL line those
browsers glue to the front of the body — the fix for GitHub web
notifications reading as an unreadable wall of link markup. A single-line
entry (no body) gets tighter vertical padding than one with a body. The
icon slot (40×40) shows the notification's own image, else the sender's
themed app icon, hidden entirely when neither resolves.

**DND bypass is deliberately narrow** (Omarchy's rule, not a general
"urgent" exception): only `urgency: critical` notifications sent by the
literal `notify-send` CLI bypass DND. A chat app or any other sender marking
its own notifications critical does **not** bypass — the check is on the
sender's app name (`notification.appName === "notify-send"`), never inferred
from urgency alone.

**DND persists** in `state.json` (`Core.State.dnd`), same as wallpaper/mode
— it survives shell restarts and `keepOnReload` generation switches instead
of silently resetting to off.

**The bar's bell cell** (see [Bar](#bar)) drives the same machinery with a
pointer: left click toggles the center `showHistory` drives, right click
flips the same DND flag `toggleDnd` does, and its pending-count meta label
reads the same `pending` tier `status` reports.

**The center's `CLEAR ALL` cell** (beside DND) drops every row currently
listed there — `pending` and `past` — through the same `clearPending`/
`dismissOne` verbs the IPC surface exposes; live popups (Toasts.qml's own
surface) are untouched, same as DND only ever governing what lands here.

**IPC** (`target: "notifications"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call notifications showHistory     # toggle the center
qs ipc --any-display -p <store-path>/share/formalshell call notifications status          # {"dnd":…,"pending":…,"popups":…,"centerOpen":…}
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

Nine per-widget popouts share one component, `shell/Components/Panel.qml` — a
ledger-table popout (header `MetaLabel` row, rows sharing hairline rules,
`WlrLayershell` top layer, keyboard `OnDemand`, closes on Escape and on
click-outside) anchored under the bar cell that opened it, or falling back to
the bar's right region when opened over IPC with no cell to anchor under
(Wayland gives clients no cross-window global coordinates for a real anchor).
On a multi-monitor rig, a click on any *other* screen closes the panel too
(`Components/DismissTwins.qml`, M16 Task 7) — the compositor only ever hands
pointer input to the backdrop on the panel's own output, so a transparent
twin window per other screen exists for as long as the panel is open, purely
to catch that click; the Menu and notification center use the same
component. Single-monitor rigs (the VM smoke rig included) spawn zero twins.
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
| `github`     | one `gh api graphql` poll (shared with the bar cell) | `GithubWidget.qml` |
| `usage`      | `~/.claude/.credentials.json` + Anthropic OAuth usage endpoint, `codex app-server` JSON-RPC | `UsageWidget.qml` |
| `tailscale`  | `tailscale status --json` poll (shared with the bar cell) | `TailscaleWidget.qml` |

Every bar cell shows the Omarchy-style panel-open accent dot while its panel
is open. `AudioPanel` is an omarchy-style mixer (M15 Task 4): `OUTPUT` is one
master slider row for the current default sink (flat accent fill, `MUTE`
cell, 0..1) followed by one selectable row per candidate sink — click or
Enter-on-cursor sets `Pipewire.preferredDefaultAudioSink`, the active row
inverted; `INPUT` is the same shape for sources, the whole section (header
included) omitted when no input hardware exists; `APPS` lists real playback
streams (`Audio/model.js.isPlaybackStream`, filtered without ever reading a
pre-bind node's `properties`) as label/percent/`MUTE` rows with their own
0..1.5 overdrive track and a hairline notch at the 1.0 mark, omitted
entirely with no streams. Stream labels resolve `application.name` →
`node.description` → `media.name` → `node.name`, read only once
`node.ready`. Keyboard: Up/Down walk one combined cursor across every row
(a master slider counts as its own row), `h`/`l` step whichever slider-shaped
row the cursor is on by 5%, `m` mutes it, Enter activates (default-switch on
a device row, mute-toggle everywhere else); wheel over any track, or over
the bar cell itself, steps 5% too. `NetworkPanel` groups connections under a
`WIRED` header (a
plain connect/disconnect row, unchanged) and a `WI-FI` section with omarchy's
own behavior: a `WI-FI POWER` toggle, rows sorted by `Network/model.js`
(connected, then known, then signal strength descending) under `KNOWN`/
`AVAILABLE` headers, Wi-Fi signal strength drawn as a discrete 5-segment
block-character bar (the flat-fill slider idiom stays reserved for
continuous values like volume), a lock glyph on secured networks, and a
status subline (`CONNECTING…`, a `connectionFailed` reason, or `TIMED OUT`
if a 15-second fallback timer catches a stuck action). Clicking (or
Enter-on-cursor) a connected row disconnects; a secured network with no
saved credentials expands an inline passphrase row instead of connecting
straight away (masked `TextInput`, Enter submits via `connectWithPsk`,
Escape collapses just the prompt without closing the panel); 802.1x/EAP
networks get an extra `IDENTITY` field above the passphrase and connect
through an `nmcli` Process that reads the password over stdin, never argv,
and reports a `NO NMCLI` status if the binary is missing rather than a
silent failure. Known, disconnected rows reveal a `FORGET` action on hover.
`BluetoothPanel` groups devices under `CONNECTED`/`PAIRED`/`AVAILABLE`
headers via `Bluetooth/model.js`'s buckets (available devices, discovered
scan results with a real name, only list while the adapter is actively
discovering); a 1-second timer keeps nudging `adapter.discovering = true`
while the panel is open and the adapter enabled — BlueZ rejects
`StartDiscovery` while the adapter is powering up and lets discovery lapse
on its own — and discovery stops the moment the panel closes. Clicking (or
Enter-on-cursor) a connected row disconnects; a paired row connects; an
available row runs a native pair-trust-connect sequence (`pair()`, then
once BlueZ reports the device paired, `trusted = true` followed by
`connect()` — the same sequence omarchy shells out to bluetoothctl for,
expressed with the toolkit's own device methods). A 20-second fallback
timer clears a stuck action to an honest `TIMED OUT` status, since
`BluetoothDevice` has no failure signal to key off. Paired, disconnected
rows reveal a `FORGET` action on hover, same restriction as the network
panel's known rows. Honest states: a single dim cell reading `NO ADAPTER`
when `Bluetooth.defaultAdapter` is null, `TURN ON TO SCAN` when the adapter
is off, or `SCANNING…` when it's on and discovering but nothing has turned
up yet — the test VM has no adapter at all, so `NO ADAPTER` is what its
smoke screenshot shows. `PowerPanel` pairs a status row (an honest
`AC POWER` cell rather than a lying `0%` when `UPower.displayDevice.isLaptopBattery`
is false) with a keyboard-navigable power-profile picker (Up/Down to move,
Enter to apply) under power-profiles-daemon, plus a breathing-opacity
charging pulse while genuinely charging and dim meta rows for time-to-full/
time-to-empty/charge rate wherever `UPowerDevice` reports them
(`timeToFull`/`timeToEmpty`/`changeRate`, each rendered only when nonzero —
no rotation, no invented value). `Battery.qml`'s bar cell goes
further and drops out of the bar entirely on the same condition, rather than
showing a stub `0%`, and goes full-bleed `urgent` at/below
`battery.criticalPercent` while discharging. `PowerPanel` also carries a
`DISPLAY` section, one `BRIGHTNESS` row per controllable monitor — the
internal backlight (`BrightnessService`, `brightnessctl`-backed) labeled
`INTERNAL`, plus one row per DDC-capable external monitor `ddcutil` can
reach, keyed by DRM connector name; wheel, or `h`/`l` while hovering a row,
steps it 5%, detection runs once per panel open (never a poll loop — `
ddcutil`'s I2C round-trips are seconds-slow), and the section collapses to a
single dim `NO BACKLIGHT` row when nothing is controllable — the test VM's
expected state. `Power/model.js`'s `warnEvent()` hysteresis (persisted on
the panel, which stays live in the background regardless of whether it's
open) fires a normal `LOW BATTERY` toast crossing `battery.warnPercent`
(default 10) while discharging, and a sticky, DND-bypassing
`CRITICAL BATTERY` toast at `battery.criticalPercent` (default 5); either
threshold re-arms the instant the battery starts charging, so unplugging
again while still low warns again. `WeatherPanel` shows current conditions as a header row
and a forecast ledger (one row per open-meteo daily period, glyph + weekday
+ high/low mono temps pinned right), falling back to an honest `NO LOCATION`
or `UNAVAILABLE` cell (with openmeteo.js's specific failure code) rather
than a stale or invented forecast. The open-meteo poll lives in the panel,
not the widget (M15 Task 3, `GithubPanel`'s own pattern): `WeatherWidget`
flips `pollEnabled` on for background polling every `weather.intervalMs`,
and `panel open weather` re-polls on open regardless. `GithubPanel` lists
open PRs you authored and open issues assigned to you as two ledger sections
(`PULL REQUESTS / n`, `ISSUES / n` — the first 15 of each), every row a
title plus dimmed repo slug; clicking a row opens its URL via `xdg-open`
and closes the panel. The `gh api graphql` poll lives in the panel, not
the widget, so `panel open github` renders honestly even when `bar.layout`
never names the github widget (the widget stays the opt-in switch for
*background* polling; opening the panel always re-polls). Its honest
states mirror the bar cell's: dim `NO GH` / `NO AUTH` cells, `LOADING`
before the first answer, a dim `NONE` row under an empty section.
`UsagePanel` shows a `CLAUDE` section (Anthropic OAuth usage) and a `CODEX`
section (`codex app-server` JSON-RPC), each independently toggleable
(`usage.claude`/`usage.codex`, default `true`) and skipped entirely when
disabled; each section is a tier meta row (`Max 20x`, or the raw plan type)
then one row per rate-limit window — an uppercase label (`5-HOUR`,
`WEEKLY`), the percent, a full-width flat `accent` fill track that swaps to
`urgent` at ≥90%, and a dim `RESETS 2H 14M` meta line. Claude reads
`~/.claude/.credentials.json`'s OAuth token (never logged, never exposed on
any IPC/debug surface) and hits `api.anthropic.com/api/oauth/usage`;
missing, empty, or expired credentials render `NO AUTH` without probing.
Codex speaks newline-delimited JSON-RPC to `codex -s read-only -a untrusted
app-server` over its own stdin/stdout, matching replies by their `id`
rather than assuming order; `codex` missing from PATH renders `NO CODEX`,
any RPC-level failure (timeout, malformed reply) renders `ERROR` — never a
fabricated percentage either way.
`TailscalePanel` (M16 Task 8) pairs a `STATUS` action cell (`CONNECTED`/
`STOPPED`, the running state inverted) with a self hostname+IP row (click
copies the IP via `wl-copy`) above a `MACHINES` ledger — one row per peer
(name, dim IP, an `ONLINE`/`OFFLINE` indicator that only breathes,
`PowerPanel`'s charging-pulse idiom, while a `tailscale up` toggle is
actively in flight), click copies that peer's IP. Clicking or
Enter-on-cursor the `STATUS` cell runs `tailscale up`/`down`; a permission
failure (a non-operator user lacks rights to toggle the daemon) renders an
inline `NOT OPERATOR` state rather than pretending it worked — see
[SWITCHOVER.md](SWITCHOVER.md) for the `tailscale set --operator=$USER`
host-side prerequisite. The `tailscale status --json` poll lives in the
panel, not the widget (`GithubPanel`'s own pattern), so `panel open
tailscale` renders honestly even when `bar.layout` never names the
tailscale widget. Honest states: `tailscale` missing from PATH or any other
unparsable response renders a dim `NO TAILSCALE` cell (the VM smoke rig's
own expected state — no tailscaled at all), `BackendState: "NeedsLogin"`
renders a dim `NEEDS LOGIN` cell, `LOADING` before the first answer.

**IPC** (`target: "panel"`, a documented spec addendum — see
`docs/superpowers/plans/2026-07-28-m6-clipboard-and-panels.md`'s header note
— since per-widget popouts otherwise have no summon path for compositor
keybinds and no way to be verified headlessly):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call panel open audio
qs ipc --any-display -p <store-path>/share/formalshell call panel toggle network
qs ipc --any-display -p <store-path>/share/formalshell call panel close        # closes whichever panel is open
qs ipc --any-display -p <store-path>/share/formalshell call panel state       # "" | "audio" | "calendar" | "network" | "bluetooth" | "power" | "weather" | "media" | "github" | "usage" | "tailscale"
```

An unknown panel name returns `error: unknown panel '<name>'` rather than a
silent no-op. Bind a panel to a key in niri, same pattern as the menu:

```kdl
binds {
    Mod+A { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "panel" "toggle" "audio"; }
}
```

**Network IPC** (`target: "network"`, a spec addendum in the same tradition —
drives `Quickshell.Networking`'s wifi flow headlessly so the hwsim smoke rig
and compositor keybinds have a target beyond just opening the panel):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call network status                          # JSON: {wifiEnabled, networks: [{name, known, connected, stateChanging, secured, signal}]}
qs ipc --any-display -p <store-path>/share/formalshell call network connect FORMALTEST somepassword  # empty string = plain connect() (open network, or a known network's saved secrets)
qs ipc --any-display -p <store-path>/share/formalshell call network connectEap FORMALTEST-EAP user@domain somepassword
qs ipc --any-display -p <store-path>/share/formalshell call network forget FORMALTEST
qs ipc --any-display -p <store-path>/share/formalshell call network wifi true                        # radio power
```

An unknown ssid returns `error: unknown ssid '<ssid>'`. `connect`/`connectEap`
take the secret as a plain IPC argument, which lands in argv — world-readable
via `/proc` on a multi-user system — so these two verbs exist for the
headless rig, not as the recommended interactive path: a real session should
type the passphrase into the panel's own inline prompt (stdin-fed, never
argv, see the WI-FI section above).

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

Images ride a SECOND, independent `wl-paste --type image/png --watch`
`Process` alongside the text one, same sensitive-capture skip. Each capture
streams to a mktemp file under `$XDG_STATE_HOME/formalshell/clipboard-images/`
and is content-addressed to `<sha256>.png` — an existing hash drops the temp
file and reuses the stored one, so a capture is de-duplicated by content the
same way text is. Entries carry `kind: "text"|"image"` (entries persisted
before images existed have no `kind` field and read as text); image entries
additionally carry `path`/`mime` instead of `text`, and de-dupe by `path`
rather than re-hashing. `copy(id)` branches on `kind`: image entries
`wl-copy --type image/png` the stored file back rather than re-emitting
text. Eviction (the 300-entry cap, `remove`, `clear`) deletes any
newly-orphaned image file — the one place `ClipboardService` ever runs `rm`,
and only ever on a path already confirmed to live under
`clipboard-images/`.

A `clipboard` menu provider node lists history entries as menu rows, newest
first; `formalshell menu summon clipboard` (or `qs ipc call menu summon
clipboard`) opens straight to them, and selecting a row re-copies it through
the same `clipboard copy <id>` IPC verb below — the menu row is just that
call, not a separate code path. Image rows render a thumbnail (twice a text
row's height, width capped, aspect preserved) with an `IMAGE` label and the
capture time instead of a text preview.

**IPC** (`target: "clipboard"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call clipboard list     # JSON array, newest first — kind/path/mime included for image entries
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

**Events.** `CalendarEventsService` merges two coexisting backends by UID:

- **Local `.ics` files** — `calendar.icsDir` in `settings.json` points at a
  khal/vdir-style directory; unset means no local files, the same
  honest-empty-state contract every other panel follows.
- **EDS / GNOME Online Accounts** — `calendar.eds` (bool, default `true`)
  reads Evolution Data Server over D-Bus via the `formalshell-eds`
  companion CLI (M12; the one compiled binary in the shell, an owner-
  authorized exception to the pure-QML rule — see the spec's 2026-07-30
  addendum). The original spike
  (`docs/spikes/2026-07-28-eds-calendar-events.md`) proved EDS's whole
  `OpenCalendar -> Open -> GetObjectList` handshake must run over **one
  held bus connection** — EDS reaps the backend the moment the calling
  connection closes, so no chain of `gdbus`/`busctl` one-shots can work.
  The CLI does the whole handshake in one process over one sd-bus
  connection and prints raw ICS, which feeds the exact same
  `shell/Calendar/ics.js` parser the local files use. Any calendar EDS
  knows about — including Google/Nextcloud/… calendars added through GNOME
  Online Accounts (GNOME Settings → Online Accounts; on NixOS the host
  needs the GOA/EDS system services enabled, e.g.
  `services.gnome.evolution-data-server.enable` +
  `services.gnome.gnome-online-accounts.enable`) — shows up with zero
  shell config. Unreachable EDS (no bus, no EDS installed) degrades
  silently to ics-only after the first failed run: one console.warn, no
  error cell, no retry storm.

The CLI's contract (`formalshell-eds --help`):

```
formalshell-eds sources                       # JSON [{uid, displayName, backend}]
formalshell-eds events [--days N] [--source UID ...]
                                              # raw ICS, yesterday..today+N (default 45)
formalshell-eds seed <summary> <YYYY-MM-DD>   # test-rig helper, writes one real VEVENT
```

`events` exits 0 with empty output when there are simply no events, and
exits 1 with a stderr line only when the bus or EDS is unreachable — it
never invents data. Refresh cadence for both backends: `icsDir` change,
every 5 minutes, and calendar-panel open.

Recurring events (`RRULE`) expand into concrete instances within the query
window: `FREQ=DAILY/WEEKLY/MONTHLY/YEARLY`, `INTERVAL`, `COUNT`, `UNTIL`,
`BYDAY` on weekly rules, and `EXDATE` as simple date matches. Anything
outside that subset (`BYSETPOS`, `BYMONTHDAY`, ordinal `BYDAY` like `1MO`,
…) leaves the anchoring event as a single occurrence at its `DTSTART` —
honest under-expansion, never a guessed instance (`shell/Calendar/ics.js`'s
header documents the full boundary).

Days carrying an event get a small accent dot in the grid, and a dated
ledger section below lists the selected day's events by summary (or a
single dim `NO EVENTS` row).

**Day selection.** Every day cell is clickable (hover-cursor chrome):
clicking selects that day, the events ledger lists that day's events, and
its meta header reads `TODAY` for today or the uppercase date (`JUL 31`)
otherwise. The selected cell inverts (the ledger selection state); today's
cell keeps its accent marker — both visible at once when they differ.
Clicking an adjacent-month padding day selects it and aligns the view to
its month. Month navigation (`<`/`>`) resets selection to today rather
than clamping the day-of-month, and opening the panel resets both the view
month and the selection to today. The same action is scriptable
(`target: "calendar"`, additive next to `panel open calendar`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call calendar select 2026-07-31   # strict YYYY-MM-DD, invalid dates rejected
qs ipc --any-display -p <store-path>/share/formalshell call calendar status              # {"open":…,"selected":…,"today":…,"view":…}
```

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

## Polkit

`PolkitService.qml` (`shell/Services/`) registers a native
`Quickshell.Services.Polkit.PolkitAgent` (path `/org/formalshell/PolkitAgent`)
behind `polkit.enabled` in `settings.json` (default **true**) — the setting
is checked before the agent element is even constructed (a `Loader`, not a
property on the element itself), since registration is attempted the
instant a `PolkitAgent` is created. `PolkitDialog.qml`
(`shell/Surfaces/Polkit/`) is the one surface it drives: a centered
omarchy-style card (radius 0, border 2, monospace) shown for as long as a
real authentication request is in flight — uppercase `AUTHENTICATION
REQUIRED` header, the requesting action's own message, the identity being
asked to authenticate as a dim meta row, and the same `AuthPrompt` field
idiom the lock screen uses (masked `●` input, `CHECKING…` while an attempt
is in flight, `WRONG PASSWORD` in urgent italic on retry — no shake).
Escape cancels the request; the typed password only ever reaches the
agent's own `AuthFlow.submit()`, never logged, mirrored into
settings/state, or surfaced by the `debug` IPC dump.

**Only one polkit agent can register per session.** If another one is
already running — a desktop environment's own agent, or (on the e1504g
specifically, as of 2026-08-03) `polkit-kde-authentication-agent-1` — this
agent's `isRegistered` stays false, one line is logged, and
`PolkitDialog.qml` simply never has anything to show; it never fights the
other agent over the registration. See `docs/SWITCHOVER.md` for what has
to be dropped from a host's config before this agent can register there.

No dedicated IPC target: unlike the lock screen or menu, a polkit request
is triggered by the OS (`pkexec`, a GUI app's own privileged action), never
by the shell itself, so there is nothing to summon. `dev/smoke-niri.sh
--polkit` verifies the whole flow with a real `pkexec` invocation and real
`wtype` keystrokes, the same "type into it for real" idiom `--lock` uses.

## Night light

`NightLightService.qml` (`shell/Services/`) is an opt-in warm-temperature
filter, off by default (`nightlight.startOn`, `settings.json`, default
**false**), driving a real `wlsunset` process (`wlr-gamma-control-unstable-v1`
— reimplemented against the pinned 0.4.0 source rather than ported from
omarchy, which drives Hyprland's own `hyprsunset` IPC instead). "Fixed-temp
mode, not schedule": wlsunset has no such mode of its own, so
`NightLightService` uses its documented `SIGUSR1` runtime control (cycles
OFF -> forced-high -> forced-low -> OFF/automatic) to pin the low
temperature permanently the moment it starts — never a day/night cycle —
each signal sent only after wlsunset's own stderr confirms the previous one
landed. `nightlight.temp` (default 4000) sets the pinned Kelvin value.
`Indicators.qml`'s bar slot shows a `md-lightbulb_night` glyph while active;
that same live binding is what wakes the singleton at shell startup so
`nightlight.startOn` actually takes effect (PolkitService's own
`PolkitDialog.qml` binding is the established precedent for this).

`wlsunset` missing from PATH, or a nested/windowed compositor backend that
doesn't implement the gamma-control protocol at all, surfaces as an honest
`active: false` with `lastError` populated — never a silent no-op.

**IPC** (`target: "nightlight"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call nightlight enable
qs ipc --any-display -p <store-path>/share/formalshell call nightlight disable
qs ipc --any-display -p <store-path>/share/formalshell call nightlight toggle
qs ipc --any-display -p <store-path>/share/formalshell call nightlight status  # {"active":…,"temp":…,"lastError":…}
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
| `expand` | one diamond opens outward from the banner's centre, not per-line |
| `slide` | each line slides in from alternating edges |
| `scatter` | every cell pops in at its own hashed frame with a brief fade-in — nothing moves |

**Picking an effect.** `screensaver.effect` in `settings.json` is `"random"`
by default — a fresh effect is picked every time the screensaver activates,
seeded off the activation itself so a long idle session still cycles
variants — or pin it to any one of the five names above (an unknown name
falls back to random and logs a warning, never a hard error):

```jsonc
// ~/.config/formalshell/settings.json
{ "screensaver": { "effect": "decrypt" } }
```

**Continuous cycling** (M13b). After converging, the banner holds for
`screensaver.holdSeconds` (default 6), then the surface rerolls and
animates again, indefinitely, until real input dismisses it —
`"random"` picks a fresh effect each cycle and never repeats the
immediately previous one, a pinned name replays itself with a fresh
activation seed so the run still looks different. The loop takes no idle
inhibitor, so system suspend fires exactly as it would without it.
`screensaver frameInfo` reports the resolved effect, its convergence
frame, and a `cycles` counter (completed reroll count, 0 until the first
one) so cycling is observable without screenshots.

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
qs ipc --any-display -p <store-path>/share/formalshell call screensaver frameInfo  # {"effect":…,"convergenceFrame":…,"cycles":…}
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

## Screenshots

`shell/Ipc/ScreenshotIpc.qml` (M12 — a spec-addendum surface, same pattern
as `panel`/`picker`) wraps grim/slurp behind one IPC target: `full` grabs
the whole output, `region` runs `slurp` first for an interactive rectangle.
Either way the capture lands as
`<screenshot.directory>/screenshot-<timestamp>.png` (`screenshot.directory`
in `settings.json`, default `~/Pictures/Screenshots`, created on first
capture) AND on the clipboard as `image/png` via `wl-copy`, and a
`SCREENSHOT SAVED` notification with the path fires through the shell's own
notification stack — visible feedback with no bar surface involved.

`region`'s slurp overlay is styled so pressing the bind visibly changes
the screen immediately: a dim theme-background wash, the selection border
in the theme accent at `Theme.borderWidth`, a transparent selection
rectangle, and a live dimension readout — colors resolved at call time, so
they track the current matugen palette. Pressing Escape (or
right-clicking) inside slurp is a cancel, not an error: no toast, no
`lastError`. A watchdog auto-cancels an unanswered region selection after
`screenshot.timeoutSeconds` (default 90) with a `SCREENSHOT CANCELLED`
notification, and the `cancel` verb does the same on demand — no more
invisible slurp sitting stuck for an hour.

The IPC reply is the destination path the capture is writing toward, not a
completion signal: `qs ipc call` replies synchronously while `slurp` blocks
on user interaction indefinitely. A runtime failure (grim error, slurp
failing to start) fires a `SCREENSHOT FAILED` notification and lands in
`status()`'s `lastError` — loud and queryable, never a silent no-op.

**IPC** (`target: "screenshot"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call screenshot full     # replies with the destination path
qs ipc --any-display -p <store-path>/share/formalshell call screenshot region   # slurp rectangle, then same pipeline
qs ipc --any-display -p <store-path>/share/formalshell call screenshot cancel   # kill an in-flight capture, clear state
qs ipc --any-display -p <store-path>/share/formalshell call screenshot status   # {"capturing":…,"lastPath":…,"lastError":…,"lastCancelled":…}
```

Bind both in niri, same pattern as every other target:

```kdl
binds {
    Print { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "screenshot" "full"; }
    Mod+Print { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "screenshot" "region"; }
}
```
