# FormalShell usage reference

Per-surface reference for FormalShell's IPC targets, config keys, and
keybind examples — theming, menu, notifications, OSD, panels, clipboard,
calendar, now playing, lock screen, screensaver, picker, screenshots,
recording, reminders, and plugins.
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
- [Polkit](#polkit)
- [Night light](#night-light)
- [Screensaver](#screensaver)
- [Picker](#picker)
- [Screenshots](#screenshots)
- [Text and color capture](#text-and-color-capture)
- [Screen recording](#screen-recording)
- [Reminders](#reminders)
- [Plugins](#plugins)
- [Instance lock](#instance-lock)

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
`indicators`, `github`, `usage`, `tailscale`, `visualizer`, `microphone`,
`keyboardLayout`, `systemUpdate`, `airpods`, `dualsense` (the last nine opt-in
only — never part of the default arrangement; `bell` by contrast IS part of
the defaults since M13b, so a config predating it that spells out its own
`right` region won't show the bell until it's added there).
An absent region falls back to its own default arrangement above (an
absent `bar` key entirely is the same as an absent region for all three);
a present-but-empty region (`[]`) stays empty. An unknown widget name, or
a `"custom:<id>"` entry with no matching `bar.modules[].id`, is dropped
with a console warning — never a crash. A `"plugin:<id>"` entry places a
drop-in bar plugin (see [Plugins](#plugins)) in that region.

Opting a widget in is one edit to the region you want it in. Naming a
region replaces it wholesale, so spell out the builtins you still want
alongside the new one:

```jsonc
{
  "bar": {
    "layout": {
      "right": ["microphone", "keyboardLayout", "systemUpdate", "battery", "audio", "network", "bluetooth", "weather", "tray", "bell", "indicators"]
    }
  },
  "systemUpdate": { "flakeDir": "/home/youruser/.config/nix" }
}
```

`bar.modules[]` entries are referenced from `bar.layout` by
`"custom:<id>"` and come in two `type`s:

- **`command`** — runs `command` (an argv array) on an interval
  (`interval`, ms, default 5000) and parses stdout as
  Waybar-JSON-compatible `{"text": "…", "tooltip": "…", "class": "…"}`.
  `text` renders in the cell and `tooltip` becomes that cell's hover
  tooltip verbatim — the module author's own wording, never reworded here
  (**Tooltips**, below). `class: "warning"` renders an accent-filled
  cell, `"critical"`/`"urgent"` renders the urgent fill, anything else
  renders plain. A non-zero exit, a timeout (`timeout`, ms, default 5000),
  malformed JSON, or a command that fails to start at all all render the
  same honest `MODULE ERROR` cell — with no tooltip, rather than the last
  good one — instead of a stale value.
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
activation-is-menu get the menu on left click too. The menu (M32,
`TrayMenu.qml`) is a shell-owned card anchored under the clicked cell,
built off `QsMenuOpener` over the item's own DBusMenu: ledger rows,
disabled entries dim, a checked entry takes the cursor's `selected` fill,
and a submenu expands in place as indented rows rather than opening a
cascade window. Replaces the old native `QsMenuAnchor` popup, which took
an xdg_popup grab Hyprland's layer-shell path tore down on the tray
icon's own pixmap, closing the menu the instant it opened. Past 4 visible
items the rest collapse into one more cell (`+N`) that expands the row to
reveal them all.

**Bell** — an always-visible notification cell (M13b): bell glyph, swapping
to bell-off while DND is on, plus a pending-count meta label whenever
notifications are sitting unseen in the `pending` tier (see
[Notifications](#notifications)). Left click toggles the notification
center — the same surface `notifications showHistory` drives — with the
panel-open accent dot while it's open; right click flips DND through the
one existing DND state machine (`notifications toggleDnd`'s), never a
second one.

**Indicators** — transient session-state glyphs, only while the condition
holds; the whole slot disappears otherwise. Four cells, in this order: a
live screen recording (the one full-bleed `urgent` cell here, since a
recording is the active thing on screen; click stops it, and the elapsed
clock rides the tooltip so a per-second label can't relayout the bar), a
pending reminder (soonest countdown in the cell, `12:30 / 3` once more than
one is set; click fires the summary notification), stay-awake, and night
light. The DND bell-off glyph this slot carried since M10 moved to the
always-visible bell cell above, which owns both DND display and its toggle.

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
utilization. Click toggles the usage panel (see [Panels](#panels)), and on
a `STALE` Claude leg also has Claude Code refresh its own OAuth pair before
the panel opens. Honest
states: a disabled provider contributes nothing, and the cell stays hidden
until at least one enabled provider has answered at all (its own `NO AUTH`/
`STALE`/`NO CODEX` cell counts as an answer) — never an invented percentage.

**Visualizer** — opt-in via `bar.layout` (add `"visualizer"` to a region);
a live ASCII spectrum next to `nowPlaying`, six caption-size block glyphs
(`▁▂▃▄▅▆▇█`) in one monospace `Text`, driven by a shared `cava` process
(`VisualizerService.qml`) reading real system audio over PipeWire. The
process exists only while a track is genuinely playing AND a bar showing
the widget is on screen AND motion is enabled (DESIGN.md §4 rule 8) —
paused music, a hidden bar, or `motion.enabled: false` kills it outright,
and the widget falls back to its flat baseline row (`▁▁▁▁▁▁`) rather
than a frozen last frame. The cell appears and disappears together with
`nowPlaying` (both gate on `MediaService.available`). Honest states: `cava`
missing from PATH renders a dim `NO CAVA` cell once the one-shot PATH probe
answers, regardless of playback — never a silently-empty cell pretending
to be idle.

The generated `cava.conf` is tuned rather than left at defaults, and the
level-to-glyph map is a square root rather than linear. Both exist to stop
the row sitting pinned near its floor: cava's `autosens` is off in favour of
a fixed 800% sensitivity (auto-gain renormalizes a quiet passage up to the
same full-scale row as a loud one, so nothing appears to respond),
`monstercat = 1.5` bleeds each bar into its neighbours so six bars read as
one connected spectrum, `noise_reduction = 35` tracks transients that cava's
77 default smears, and `higher_cutoff_freq = 12000` gives the top bar
cymbals to show. Below level 2 a bar snaps flat, standing in for cava's
`ignore` knob (deprecated since 0.8.0). The shape is DankMaterialShell's
`CavaService`; the gain is measured against this shell's own eight discrete
glyph steps rather than copied, since DMS renders continuous shader bars
that read fine at heights this row would draw as a flat stroke. None of it
is configurable from `settings.json`.

**Microphone** — opt-in via `bar.layout` (add `"microphone"` to a region);
one glyph for the default capture source, swapping between live and muted,
click toggles its mute, middle click opens the audio panel (M26 Task 9 —
the mic has no panel of its own). No percentage and no wheel handler: input
gain is a panel concern and a mic reads as on or off. Honest state: no
default source at all (the mac VM rig's own state, which has no capture
device) renders a dim `NO MIC` label instead of a glyph, and the cell stays
visible, because it is opt-in and hiding it would be the lie.

**Keyboard layout** — opt-in via `bar.layout` (add `"keyboardLayout"` to a
region); a glyph plus the short form of the active layout, read-only (no
click-to-cycle: niri has the action, Hyprland's equivalent needs a device
name and was never verified against a real Hyprland, and a control that
silently no-ops on one backend is exactly what the honest-unavailable rule
bans). Fewer than two layouts configured hides the cell, since a
permanently static cell is noise. A compositor that can't be asked at all
renders a dim `NO LAYOUT` cell rather than guessing.

The layout is **polled**, once every 2 seconds, per output: `niri msg
--json keyboard-layouts` or `hyprctl devices -j`, normalized by
`shell/Compositor/keyboard.js`. It does not ride the compositor event
stream, so an N-monitor session runs N timers and spawns N processes every
interval. niri already puts `KeyboardLayoutsChanged`/
`KeyboardLayoutSwitched` on the wire and moving that leg onto `reducer.js`
would drop the timer entirely on that backend; it isn't wired yet. The
Hyprland leg's field names come from the Hyprland wiki rather than from
read source, so a wrong guess there lands on `NO LAYOUT`.

**System update** — opt-in via `bar.layout` (add `"systemUpdate"` to a
region); a glyph plus how many of a flake's direct inputs are behind
upstream, going full-bleed `warning` while any are. Click toggles the
system-update panel. It answers exactly one question, *are my flake inputs
behind their upstream refs*, and not *does my running system differ from
what a rebuild would produce*. Point it at a flake and it polls; leave
`systemUpdate.flakeDir` unset and the cell honestly reads `NO FLAKE`
forever rather than checking something else:

```jsonc
{
  "systemUpdate": {
    "flakeDir": "/home/youruser/.config/nix",
    "intervalMs": 10800000
  }
}
```

The cadence is hours (3 by default) because stage 2 costs one network round
trip per direct input: reading `flake.lock` off disk is free, but learning
upstream's rev is a GitHub API call per github input and a `git ls-remote`
per git-forge input. GitHub's unauthenticated limit is 60 requests per hour
per IP, and a 403 lands in the panel's unknown bucket, never in `current`.
An input type with no cheap probe (`path`, `tarball`, `indirect`,
sourcehut) stays `?` forever rather than a fabricated `CURRENT`.

**AirPods** (M29) — opt-in via `bar.layout` (add `"airpods"` to a region); an
earbuds glyph plus the worse of the two buds' battery as `NN%` (the case is
excluded from that headline number — a full case next to a near-dead bud
would read backwards — but joins both buds in the tooltip's `L 97 / R 99 /
CASE 80` breakdown). Hidden entirely with no daemon running or no battery
level known yet, so an ordinary host with no AirPods pays nothing. Click
toggles the AirPods panel (see [Panels](#panels)); see that section for the
`librepods` daemon this cell and its panel both depend on.

**DualSense** (M29) — opt-in via `bar.layout` (add `"dualsense"` to a
region); a gamepad glyph plus battery `NN%`, replacing the old
`custom:dualsense` command module at the same 30-second poll cadence. Hidden
entirely with no controller present. Goes full-bleed `warning` at ≤20%,
`urgent` at ≤10% — the same thresholds the retired `dualsense-bar` script
used. Click toggles the DualSense panel (see [Panels](#panels)), which is
read-only: the shell never writes the controller's lightbar or player LEDs.

**Tooltips** — hovering a bar cell for 400ms opens one omarchy card under
it (`shell/Components/Tooltip.qml`, namespace `formalshell:tooltip`),
carrying a single uppercase meta row that names what the cell is and what
it currently reads. It is its own layer surface rather than an item inside
the bar — the bar window is exactly one cell tall — and takes input on
neither axis: keyboard focus `None`, plus an empty input region so clicks
and hovers pass through to the bar and the desktop underneath. The row
tracks the cell's value live while it's up (a ticking volume, a settling
battery estimate) instead of freezing at hover time, and it suppresses
itself for as long as any panel is open, since a popout anchors at exactly
the same spot under the same cell. The 400ms is a delay, not motion, so it
holds with `motion.enabled: false` too — that setting collapses the
fade-and-slide, not the wait. Leaving the cell hides the card immediately.

Cells carrying one today: workspaces (`WORKSPACE 2 / 3 WINDOWS`, counted
off the live window list), audio (`OUTPUT VOLUME` / `OUTPUT MUTED`, the
state the glyph alone carries), battery (percent plus `FULL IN 1H 20M` /
`2H 5M LEFT` when UPower reports the applicable estimate, the state name
when it reports 0), network (`WI-FI / <ssid> 62%`, `NETWORK / WIRED`,
`NETWORK / OFFLINE`), bluetooth (the connected devices by name), weather
(the condition the glyph draws), now playing (artist plus the whole title
the cell is marquee-scrolling), bell (`DND ON`, `N PENDING`,
`NONE PENDING`), each tray item (its own SNI `ToolTip.title`, falling back
to `Title` then `Id` — another process's words, never reformatted here) and
the overflow cell, github (`N PRS M ISSUES`), tailscale, the stay-awake and
night-light indicator glyphs, and `command` modules (their own `tooltip`
field). Honest states ride along unchanged rather than getting second
wordings: `BLUETOOTH / NO ADAPTER`, `BLUETOOTH / NO DEVICES`,
`GITHUB / NOT AUTHENTICATED`, `GITHUB / UNAVAILABLE`,
`WEATHER / UNAVAILABLE`. A cell with nothing to say sets no tooltip at all
and shows no card.

```bash
qs ipc --any-display -p <store-path>/share/formalshell call tray status     # {"items":[…],"expanded":…}
qs ipc --any-display -p <store-path>/share/formalshell call tray expand    # same action as clicking the "+N" cell
qs ipc --any-display -p <store-path>/share/formalshell call tray collapse
qs ipc --any-display -p <store-path>/share/formalshell call tray activate <id>   # same action as left-clicking the item's cell
qs ipc --any-display -p <store-path>/share/formalshell call tray menu <id>         # same action as right-clicking the item's cell
qs ipc --any-display -p <store-path>/share/formalshell call tray menucursor <delta> # move the open menu's cursor row
qs ipc --any-display -p <store-path>/share/formalshell call tray menuactivate      # same action as Enter on the cursor row
```

**Click, right-click, and scroll** (M26 Task 9) — every widget below
already states its own secondary action in its tooltip:

| Widget | Left | Right | Middle / scroll |
| --- | --- | --- | --- |
| Clock | Calendar panel | Cycle the format ring | Middle: calendar panel |
| Weather | Forecast panel | Refresh | Middle: forecast panel |
| Audio | Audio panel | Mute | Scroll: volume |
| Battery | Power panel | Toggle the `BAT / NN%` label | Middle: power panel |
| Network | Network panel | Toggle the Wi-Fi radio | Middle: network panel |
| Bluetooth | Bluetooth panel | Toggle the adapter radio | Middle: bluetooth panel |
| Now playing | Media panel | Next track | Scroll: previous/next |
| Microphone | Mute | — | Middle: audio panel |

Left/middle both opening the same panel on Clock, Weather, Battery,
Network, and Bluetooth mirrors omarchy's own idiom for a cell whose whole
point is opening a panel (`manual/05-the-top-bar.md`'s Audio row). The
microphone cell has no right-click: left already mutes, and omarchy's own
table has no right-click there either — only left (mute) and middle (audio
panel). No new backend calls exist for any of this; every action above
already existed as a service call or an existing panel method, this table
just wires bar-cell buttons to it. Right and middle clicks have no
synthetic-pointer coverage in the headless smoke rig
(`dev/smoke-niri.sh`'s own limit), so this table is verified by reading
its source rather than by a screenshot of a click landing.

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

`theme.json` is the entire theming contract: twelve color roles
(`shell/Theme/palette.js`'s `COLOR_KEYS`), each with a static Flexoki
fallback so a pre-expansion `theme.json` missing newer roles still merges
per-key rather than falling back whole-object. Any engine that writes these
same twelve keys themes the shell identically — matugen is the shipped
default (`shell/Theme/templates/theme.json.tmpl`), and a documented pywal
template (`shell/Theme/templates/pywal-theme.json.tmpl`) ships alongside it:
drop it at `~/.config/wal/templates/pywal-theme.json`, run `wal -i
<image>`, then point (or hook) pywal's rendered output at
`$XDG_STATE_HOME/formalshell/theme.json` — `Theme`'s live file watch picks
up any writer, not just `ThemeEngine`'s own matugen runs.

| role | meaning |
| --- | --- |
| `background` | canvas |
| `backgroundAlt` | card/panel surface step |
| `foreground` | content ink |
| `foregroundDim` | meta ink (uppercase captions, timestamps) |
| `foregroundFaint` | faint/disabled/ornament ink, never content |
| `rule` | rules and control borders |
| `accent` | the one loud color |
| `onAccent` | ink on accent fills |
| `urgent` | critical/error |
| `onUrgent` | ink on urgent fills |
| `warning` | degraded/low, second loud color |
| `onWarning` | ink on warning fills |

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

**Wallpaper dither.** The wallpaper renders through the same retro pass the
album covers use (`docs/DESIGN.md` §2 item 12), a 90s limited-palette
conversion: six colors are derived from that image by median cut, each cell
takes its nearest one, and an ordered 4×4 Bayer dither only mixes it with its
second nearest, in proportion to how far between the two it sits. So the
image keeps its own hue, a photo comes out as flat bands with dithered
transitions, and a solid or near-solid wallpaper stays perfectly flat — its
own color is in its own palette, so there is nothing to mix it with and no
dots anywhere. Content, not chrome, so it is exempt from matugen retheming
the way a photo is; matugen also reads the wallpaper file itself, never this
rendering, so the dither cannot influence the color scheme.

The grid is sized in **screen** pixels, never source pixels: cells are the
screen's long edge over 480, floored at 2px, so a 4000px photo and a
1200px one land on the same grid on the same display, and a 4K screen gets
larger cells instead of four times as many. The image is cover-cropped to
the screen first (nearest-neighbor, so the scale never introduces a color the
file didn't have), so the dither is square on screen whatever the source's
aspect ratio.

It is on by default. Turn it off for a true-color wallpaper, or raise the
palette for a subtler pass — more colors means less quantization error, so
less of the image dithers at all:

```jsonc
// ~/.config/formalshell/settings.json
{ "wallpaper": { "dither": false } }
{ "wallpaper": { "ditherColors": 12 } }
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
wallpaper stays painted underneath, instead of a hard cut. One more
carve-out (owner-requested, gated subtle): the bar's now-playing title
marquee-scrolls at `Theme.motion.marqueePxPerSec` (~30px/s, no easing)
with a `Theme.motion.marqueeHoldMs` (~2s) hold at the loop start, but only
when the title actually overflows its cell and the bar window is on
screen — a title that fits never moves.
`motion.enabled: false` in `settings.json` zeroes every duration —
including `reveal` — the shell's reduced-motion switch, since Wayland has
no `prefers-reduced-motion` to inherit. The marquee respects it too:
disabled falls back to a plain elide.

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

**Route-summon when-gate guard.** Normal navigation never shows a row for a
node whose own `when` hasn't resolved true — but `menu summon <route>`
(or a compositor keybind wired straight to one) resolves a node by id
directly, bypassing that parent-level check. Landing on a level whose own
`when` isn't satisfied (or hasn't resolved yet) renders one honest, dim,
non-activatable `UNAVAILABLE` row instead of that level's real children —
e.g. `menu summon share` without `localsend_app` on PATH shows
`UNAVAILABLE` rather than `CLIPBOARD`/`PICK FROM HISTORY`/`RECEIVE` rows
that would each exit 127 on activation. The condition still resolves
asynchronously in the background, so the row updates the moment it lands.

**App rows.** Each launchable app shows the entry's display name (falling
back to its id only when the name is genuinely empty) and renders the
entry's icon-theme icon as an image at the glyph cell's size — radius 0,
no border, `docs/DESIGN.md`'s one sanctioned image-icon exception (M13b;
before that the raw icon *name*, which conventionally equals the app id,
rendered as literal text in the icon slot). An icon the current theme
can't resolve means the row simply has no leading image — never a
broken-image box.

**Launch or focus.** Enter on an app row that already has a window focuses
that window instead of spawning a second copy, and pressing it again cycles
through that app's windows. A row in this state carries a dim `FOCUS` note.
Matching (`shell/Compositor/appmatch.js`) is the same comparison quickshell
itself runs, in the same order: the desktop entry's `startupClass` exactly,
then case-insensitively, then its id (the `.desktop` basename, which equals
the app id for most Linux apps). The first tier that hits wins outright,
never a union of two.

There is deliberately no fuzzy third tier. Electron and wrapper-launched
apps commonly report an app id unrelated to their `.desktop` basename, and
chasing that tail buys the worse failure: a miss falls through to the spawn
path, which is the old behavior, while a fuzzy hit focuses the wrong app.
Focusing records a frecency hit, since it is a use of the app.

**Launch ranking.** App rows are ordered by launch frecency — how often an
entry gets launched, decayed by how long ago (`shell/Menu/frecency.js`, a
14-day half-life over a per-entry count). The ledger persists to
`$XDG_STATE_HOME/formalshell/state.json` as `appLaunches`
(`[{ id, count, lastMs }]`, keyed by desktop-entry id, capped at the 200
highest-scoring records on write), the same `Core.State` file wallpaper/
mode/DND already live in — a launch count is runtime state, and
`settings.json` stays read-only. Ranking reach is deliberately narrow: it
decides the order rows are declared in, and `search.js` breaks *equal*-score
ties by declaration order, so frecency picks which of two equally good
matches leads and nothing more. A stronger match tier still wins outright,
and a profile with no launch history browses apps in `DesktopEntries`' own
order exactly as before.

**Launch feedback.** `DesktopEntry.execute()` reports nothing back, so Enter
on an app row baselines the compositor's window count and focused window id
and watches for 2 seconds. A new window (or a focus change) inside that
window IS the feedback and nothing else fires. Only a grace period that
passes with nothing new gets a `LAUNCHING <app>` notification through the
shell's own stack — which is all that is actually known, since a slow cold
start, a second instance handing its argv to an already-open window, and an
`Exec` line that died immediately are indistinguishable from outside.
Success is never claimed and neither is failure. One watch at a time, so a
burst of Enters can't stack toasts; with no compositor backend connected at
all there is nothing to observe, and the notification fires immediately
instead.

**Hover and the keyboard cursor.** Hover moves the cursor row only when the
pointer is genuinely the thing that moved (`shell/Components/PointerMoveGate.qml`).
Qt re-delivers a hover move to whatever row slides under a parked pointer,
so before this every filter keystroke and every arrow key yanked the
keyboard cursor to wherever the mouse happened to be resting. Typing, arrow
navigation, a level change, and close all re-arm the gate; the first real
pointer movement takes the cursor straight back. A click is the pointer
acting, so the level it opens does hand the cursor to whatever row lands
under the still-parked pointer.

**The action bar.** The card's bottom row names what `Enter` will do to the
row under the cursor — `OPEN` for an app, `RUN` for an action, `ENTER` for a
level, `SET WALLPAPER` in the picker grid, `COPY AND TYPE` for an emoji,
`CONFIRM <label>` while a confirm-gated row waits for its second `Enter` —
followed by the keys that always apply: `MOVE` (`↑↓`, or `←→↑↓` in the
grid) and `ESC`, which reads `BACK` wherever there is a level to pop and
`CLOSE` at the root. Clicking the primary does exactly what pressing `Enter`
does; the key legends on the right are legends, not buttons. A row that
can't be activated (an honest-empty `NO NIX`-style note) leaves the left
half blank rather than offering a verb that would do nothing.

**Where the card sits.** Centered on the focused output, and it stays fully
on screen: whatever the row count does to the card's height, the top margin
is clamped so the card never runs off the bottom or hugs the top edge. While
a filter query stands, the top is frozen at wherever it was when you started
typing, so the card grows and shrinks downward instead of jumping on every
keystroke. Clearing the query, entering or popping a level, and a fresh
summon all release that freeze, so the card re-centers for the resting row
set rather than staying wherever the last long search left it.

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

**If your `menu.jsonc` predates the `TOGGLES` node, read the rename table
under Toggles below first.** Three ids changed, and an override still keyed on
an old one goes inert without warning.

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

**Toggles.** The root `TOGGLES` node collects the four session switches that
were previously scattered across the tree, each a live checkmark row: night
light (`toggles.nightlight`, hidden unless `wlsunset` is on PATH), stay
awake (`toggles.stay-awake`), do not disturb (`toggles.dnd`), and dark mode
(`toggles.dark-mode`). Activating one flips it and leaves the menu open, so
the checkmark visibly changes under the cursor instead of the surface
vanishing.

The checkmark is live in-process state, not a polled command. A `checked`
value prefixed `@state:` is answered from a snapshot the menu already holds
(`shell/Menu/toggles.js`), never through `sh -c` and never cached, so it
repaints in the same event-loop turn the toggle does. Four paths are legal
and the list is closed: `nightlight.active`, `screensaver.stayAwake`,
`notifications.dnd`, `theme.dark`. A `checked` naming anything else resolves
false rather than falling through to the command cache, so a typo shows an
off checkmark instead of a stale one, and a hand-written `menu.jsonc` has no
route into the QML engine through that field. `@state:` is a `checked`
prefix only: a `when` carrying it is refused with a warning and the node
hides.

`"keepOpen": true` is available on any action row, not just these four. It
holds the surface open after activation, which is what makes a toggle worth
looking at.

```jsonc
// ~/.config/formalshell/menu.jsonc: a fifth toggle of your own
{
    "toggles.my-vpn": {
        "label": "Work VPN",
        "action": "sh -c 'nmcli con up work-vpn'",
        "checked": "nmcli -t -f NAME con show --active | grep -qx work-vpn",
        "keepOpen": true
    }
}
```

(That `checked` is an ordinary shell condition, resolved by one `Process` on
menu open like every other `when`/`checked`. Only the four `@state:` paths
above are answered in-process.)

**BREAKING: the toggle node ids changed.** `theme` and `theme.mode-toggle`
no longer exist, and neither does `system.stay-awake`. A `menu.jsonc` keyed
on the old ids does not error, it goes inert: the override lands on a node
nothing declares, so nothing changes and nothing warns. Rename them:

| Old id | New id |
| --- | --- |
| `theme` | `toggles` |
| `theme.mode-toggle` | `toggles.dark-mode` |
| `system.stay-awake` | `toggles.stay-awake` |

A compositor keybind wired to `menu summon theme` degrades the same quiet
way: an unresolvable route opens the menu at root rather than erroring.
`menu summon toggles` is the replacement.

**Wallpaper.** The root `WALLPAPER` node is a level like any other, except
that the menu draws it as the [Picker](#picker) grid instead of a row list:
descending into it lists `picker.directory` as image cells, the search field
filters them by filename, and Enter sets the wallpaper. A `Dark`/`Light`
subdirectory pair there splits the grid into two variants with a `Tab`-able
switcher (see [Picker](#picker)). It is a plain
`provider` entry in `default-menu.jsonc`, so overrides address it by its
`"wallpaper"` id like any declared node, including `"hidden": true`. There
is no separate picker surface any more — `picker summon` and `menu summon
wallpaper` land on this same level.

**Share (LocalSend).** The root `SHARE` submenu exists only when
`localsend_app` resolves on PATH (`command -v localsend_app`, a live `when`
condition — the same idiom `system.logout`'s `NIRI_SOCKET` guard uses),
never a config toggle; no `localsend_app` means no `SHARE` node at all, no
dim placeholder. `CLIPBOARD` shares the newest clipboard entry: a text entry
is written to a mktemp `.txt` file and launches `localsend_app <tmpfile>`,
an image entry launches `localsend_app <path>` against its existing
content-addressed path — either way spawned detached through the same
`sh -c` action route every other menu action uses. LocalSend has no true
headless auto-send mode (omarchy's own `omarchy-menu-share` script assumes
`localsend --headless send`, but that binary name and those flags don't
exist on the package this shell ships; verified against LocalSend's own
arg parser, `LoadSelectionFromArgsAction`): only a bare path that exists on
disk pre-populates the GUI's send selection, dash-prefixed args like `-t`
are silently skipped and never reach a message, so text has to become a
real file first — the GUI itself still owns picking a device and starting
the transfer. An empty clipboard renders a dim `NOTHING TO SHARE` row
instead of an action. `PICK FROM
HISTORY` lists the same clipboard history rows as the `CLIPBOARD` node, but
Enter shares the chosen entry instead of copying it (`providers.js`'s
`clipboardProvider(items, selfPath, mode)` backs both, `mode: "share"`
swapping only the id prefix and activation). `RECEIVE` launches
`localsend_app` with no arguments, opening the same GUI empty — there is no
in-shell file browser or transfer progress UI. Host-side prerequisite
(package + firewall) is in `docs/SWITCHOVER.md`.

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

**Keybinds.** `menu summon keybinds` lists your compositor's own key
bindings as a searchable ledger: the chord at content ink, padded into a
column, with the action and its arguments dimmed behind it. From anywhere,
the root trigger `:k <query>` narrows to the same rows (`:k screenshot`), and
a bare `:k` browses the whole list, capped at 200 rows. Search is
route-local (exact chord, then chord or action prefix, then word start, then
substring, ties broken by config declaration order) rather than going
through the whole-tree scorer, for the same reason the emoji route is
special-cased: a hundred keybind rows in the root search would drown
everything else.

Where they come from: on niri the config file is scanned directly, with a
real KDL scanner that survives quoted strings holding braces or `//`, line
and block comments, `/-` slashdash node comments, KDL v2 raw and multi-line
strings, node properties, and a `binds` block that isn't the first block in
the file. The menu tries four paths in order and takes the first one it can
read: `keybinds.niriConfigPath` from `settings.json` (default `""`, which
skips the candidate entirely), `$NIRI_CONFIG`,
`$XDG_CONFIG_HOME/niri/config.kdl`, then `/etc/niri/config.kdl`. On Hyprland
it's `hyprctl binds -j`, which is already JSON; `keybinds.niriConfigPath`
does nothing on that backend.

**Rows are inert notes, never activatable**, and that is the point rather
than a missing feature. A bind acts on whatever window has focus, and at
the moment you press Enter that window is the menu, so running one from
here would fire it at whichever window the compositor hands focus back to
instead of the one you were looking at. This surface is for remembering a
chord, not for pressing it.

Honest states, one dim row each: `NO CONFIG` (nothing readable on any of those
candidate paths; the row names the conventional one),
`NO BINDS` (a config with no `binds` block), `BINDS UNAVAILABLE` (`hyprctl
binds -j` failed), and `NO BINDS / niri or hyprland only` on any other
compositor. A half-written config yields the binds above the mistake rather
than an empty surface, which is the honest answer for a file you are
editing right now.

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

**Grouping.** Identical notifications collapse into one card carrying a
repeat count in its meta row (`Signal / 2m ago / x4`). Identical means the
same app name (case- and whitespace-insensitive) and the same summary. Body
is deliberately out of the key: the case this exists for is a chat app
firing one summary with a different body per message, and keying on body
too would degenerate to no grouping at all exactly there. The card shows the
newest member, and a repeat moves the whole group back to the newest slot
rather than adding a row.

The popup cap of 4 counts **groups**, not raw notifications, so five repeats
of one thing can never evict four unrelated toasts. Grouping is derived at
render time and never stored: every notification keeps its own server id and
its own timeout, so each member still expires on its own clock and its
sender is still told when it closes. Hovering a grouped card pauses every
member's countdown, and dismissing it dismisses every member at once.

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

Fifteen popouts, fourteen per-widget plus the IPC-only `display`, share one
component, `shell/Components/Panel.qml`: a ledger-table popout (header
`MetaLabel` row, rows sharing hairline rules, `WlrLayershell` top layer,
closes on Escape and on
click-outside) anchored under the bar cell that opened it, or falling back to
the bar's right region when opened over IPC with no cell to anchor under
(Wayland gives clients no cross-window global coordinates for a real anchor).
On a multi-monitor rig, a click on any *other* screen closes the panel too
(`Components/DismissTwins.qml`, M16 Task 7) — the compositor only ever hands
pointer input to the backdrop on the panel's own output, so a transparent
twin window per other screen exists for as long as the panel is open, purely
to catch that click; the Menu and notification center use the same
component. Single-monitor rigs (the VM smoke rig included) spawn zero twins.

**Keyboard focus** is primed on every open, not just declared: wlroots only
hands an `OnDemand` surface focus once the compositor routes input there —
i.e. after a click — so a panel summoned from a compositor keybind used to
come up with Escape dead and its arrow keys ignored. Every `open()` now
takes focus with `Exclusive` and settles back to `OnDemand` 75ms later, once
that focus has landed. The window is short on purpose: Hyprland routes every
pointer event to an exclusive-focus surface regardless of which output the
cursor is over, so a permanently-exclusive panel would kill clicks on every
other monitor, including the dismiss catchers above. Closing releases focus
on `close()` rather than when the exit fade finishes.

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
| `appmenu`    | the focused window's desktop entry + the compositor's window list | `ActiveWindow.qml` |
| `systemupdate` | `flake.lock` + one upstream probe per direct input | `SystemUpdateWidget.qml` |
| `display`    | the compositor backend's own output contract  | none (IPC only)      |
| `airpods`    | `AirpodsService` (librepods daemon `status.json` + control socket) | `AirpodsWidget.qml` |
| `dualsense`  | `DualsenseService` (sysfs, read-only)        | `DualsenseWidget.qml` |

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
`NetworkPanel` also carries a `SPEED TEST` section (M16 Task 9, omarchy's
feature reimplemented as flat ledger rows: the arc-gauge chrome is left
behind): a `RUN` cell resolves the active interface (`ip route get
1.1.1.1`), confirms `curl` is on PATH, then measures `DOWNLOAD` then
`UPLOAD` in turn, parallel `curl` transfers against Cloudflare's `__down`/
`__up` speed endpoints while a 500ms sampling timer reads
`/sys/class/net/<iface>/statistics/{rx,tx}_bytes`, each phase a flat
accent-fill ledger row (current/expected-max, capped) with a live Mbps
readout and a dim `MEASURING DOWN…`/`MEASURING UP…` meta line. Each phase
runs for a fixed 5 seconds regardless of transfer progress, then kills its
`curl` workers by PID (not just SIGTERM to a wrapper; see
`NetworkPanel.qml`'s own header comment on the bash `trap`/`pkill -P`
mechanism this depends on) before starting the next phase; closing the
panel mid-run kills them the same way. Honest states: no resolvable
interface renders `NO NETWORK`, no `curl` on PATH renders `NO CURL`.
Results stay on screen until the panel closes.

A `SHARE` row with a `QR` toggle expands a scannable code for the network
this machine is already on (omarchy's `bin/omarchy-network-qr` as a
collapsed ledger row rather than its centered scrim overlay): resolve the
active wifi device, read that connection's own settings with `nmcli`, build
a `WIFI:` payload (`shell/Network/wifiqr.js`, pure and TDD'd — the escaping
rules, the WPA/WEP/open branch, and the ASCII-pair collapse), pipe it
through `qrencode --type ASCII`, and draw the collapsed matrix as real
square rectangles rather than block glyphs, since a scanner reads the grid's
geometry and a monospace cell is 2:1. `qrencode` is an optional host binary
— the package wrapper puts only `brightnessctl`, `wl-clipboard`, `curl`,
`grim`, `slurp`, `formalshell-eds` and `wtype` on PATH — so it joins `cava`,
`gh`, `codex`, `tailscale`, `nmcli`, `ddcutil`, `wlsunset` and
`localsend_app` as something the host provides or the surface says it
doesn't have. `nix/testvm.nix` installs it so a smoke run proves the working
path, not only the absent one. Honest states, one dim cell each:
`NO QRENCODE`, `NOT CONNECTED`, `ENTERPRISE CANNOT SHARE`
(802.1x authenticates against a server, so there is no shared secret to
encode), and `ERROR` for any other nmcli/qrencode failure — never a partial
matrix. The payload carries the passphrase, so it goes to qrencode over
stdin, never argv, and the rendered code lives exactly as long as the
expanded row: collapsing it or closing the panel drops it.

A `PASSWORD` row with a `SHOW`/`HIDE` toggle reveals the saved secret for
that same connected network, for reading out to someone. It rides the QR
share's own `nmcli` read rather than running a second one, and the read only
happens when `SHOW` is pressed — nothing reads secrets speculatively. Until
then the row shows a fixed-width `●` mask, deliberately unrelated to the
real length. The revealed text is dropped on `HIDE`, on the panel closing,
and on roaming to another network; it is never logged, never written to
disk, and no IPC verb can reach it (there is deliberately no reveal route —
an IPC reply is exactly the surface a secret must never reach). The row only
exists while a wifi network is actually connected; past that, honest states
one dim cell each: `OPEN NETWORK`, `ENTERPRISE`, `NO NMCLI`, and
`NO PASSWORD SAVED` when nmcli answers with nothing usable.

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
panel's known rows.

Any device BlueZ reports as `paired` also reveals a `TRUST`/`UNTRUST`
toggle on hover, next to `FORGET`, with a persistent `TRUSTED` marker on
the row's status line. Trust is the one action here that cannot confirm
itself: quickshell stores the new value and fires `trustedChanged` *before*
it pushes the D-Bus `Set`, and a rejected `Set` is only warned about, never
rolled back — so reading `trusted` back as asked proves nothing, and BlueZ
emits no `PropertiesChanged` for a property that never changed either. The
row therefore stays `TRUSTING…`/`UNTRUSTING…` for a 2-second settle window,
and that window ends in a real read-back of `bluetoothctl info <address>`'s
own `Trusted:` line rather than in an assumption: agreement clears the row,
disagreement fails it to `TRUST FAILED`/`UNTRUST FAILED`, and a missing
`bluetoothctl` or a device BlueZ no longer knows fails it to `UNVERIFIED`
rather than inventing an outcome. The `TRUSTED` marker stays hidden for as
long as a write on that row is still settling, so it never asserts a state
the panel hasn't finished verifying.

Honest states: a single dim cell reading `NO ADAPTER` when
`Bluetooth.defaultAdapter` is null, `TURN ON TO SCAN` when the adapter
is off, or `SCANNING…` when it's on and discovering but nothing has turned
up yet — the test VM has no adapter at all, so `NO ADAPTER` is what its
smoke screenshot shows.

**`AirpodsPanel`** (M29, retiring the M17 `AIRPODS NOISE` row that used to
sit at the bottom of `BluetoothPanel`) is a dedicated popout for the
`omarchy-pods` `librepods` daemon — an unrelated GPL-3.0 project, built and
run out-of-repo (see [SWITCHOVER.md](SWITCHOVER.md) for the host
prerequisite). `AirpodsService` watches the daemon's own
`$XDG_STATE_HOME/librepods/status.json`, one line of sorted-key JSON the
daemon writes on every change and removes on quit — the absent file IS the
"daemon down" signal, so the panel needs no separate liveness probe. Honest
states first: no status file at all renders a dim `NO DAEMON` cell; a daemon
that is running but has never seen a battery packet and reports the link
down renders `NO AIRPODS`. Past those, a `PanelHero` opens on the device's
own name and a state line (`NOISE CANCELLATION / LID OPEN`, or
`NOT CONNECTED` when the link is down but battery is still known — the buds
keep reporting battery over BLE adverts while sitting in the case). A
`BATTERY` section lists up to three rows (Left/Right/Case, each a full-width
track plus `NN%` and an `IN EAR`/`CHARGING` hint), shown whenever any
component has reported a level, in-case included; a `LISTENING MODE`
section (gated on the link being up) lists only the modes the device
actually has — Off omitted on a Pro 3, Adaptive shown only on Pro models —
each row selectable and read-back-accurate, with an interactive
`ADAPTIVE NOISE` track appearing while that mode is active. Pro models get
two bare-label toggles, `Conversation awareness` and `One-bud ANC`, each ON
in accent / OFF dim. An `EAR DETECTION` row cycles the daemon's host-side
policy (pause on one bud out / both out / never) — this is not a device
setting, so it stays visible whenever anything about the device is known at
all. One flat keyboard cursor walks every actionable row, same pattern as
`BluetoothPanel`'s own address-keyed cursor.

**`DualsensePanel`** (M29) is a read-only sysfs readout for a Sony
DualSense controller — no daemon, `hid-playstation`'s own `power_supply`
and `leds` sysfs nodes. The title band carries a dim `READ ONLY` tag: the
owner's own host units already own the lightbar and player-LED writes, so
this panel only ever displays what sysfs reports. Honest state first: no
matching `power_supply` node renders a dim `NO CONTROLLER` cell — the test
VM's expected state, since it has no `hid-playstation` device. Past that,
the hero's readout IS the battery percent (unlike `AirpodsPanel`, one
number is genuinely the whole point here), with a `LIGHTBAR` row (a small
color swatch plus the hex code, read from `multi_intensity`) and a
`PLAYER LEDS` row (five dots, lit ones at content ink) each shown only
while their own sysfs node was readable. `PowerPanel` pairs a status row (an honest
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
then one row per rate-limit window — an uppercase label, the percent, a
full-width flat `accent` fill track that swaps to `urgent` at ≥90%, and a
dim `RESETS 2H 14M` meta line. Claude reads `~/.claude/.credentials.json`'s
OAuth token (never logged, never exposed on any IPC/debug surface) and hits
`api.anthropic.com/api/oauth/usage`; missing or empty credentials render
`NO AUTH` without probing.

An *expired* access token is a separate state. That file's `accessToken`
lives about 12 hours while its `refreshToken` lives about 10 days, and only
a `claude` run refreshes the pair on disk — so a machine that hasn't run
Claude Code today is still fully logged in with a token this shell can't
use. That renders `STALE` in the bar cell, never `NO AUTH`.

The shell never redeems that refresh token itself: Anthropic rotates it on
use, so redeeming it here would invalidate the copy Claude Code still holds
and log you out of your own CLI. It asks the CLI to do it instead, so the
cell heals without you opening a terminal. A stale leg (and a click on a
stale bar cell, which skips the once-a-minute cooldown) runs `claude auth
status --json`, the cheapest invocation that makes Claude Code refresh its
own pair: with an expired token it reaches the OAuth token endpoint, with a
live one it opens no connection at all, and neither case calls a model, so
a refresh costs no usage. Its stdout is dropped unread (it answers with
account identity, not usage) and only the exit code picks the panel's
second line: `STALE / REFRESHING` while it runs, `STALE / NO CLAUDE CLI`
when `claude` isn't on `PATH` (exit 127), `STALE / RUN CLAUDE AUTH LOGIN`
on any other failure (logged out, expired refresh token, no network), and
`STALE / RUN CLAUDE TO REFRESH` when the helper ran clean and the token is
still stale. The refreshed file arrives through the same watch as any other
write, so the state still settles on the server's answer, never on what the
CLI said. A token that lapses between two polls would otherwise sit `STALE`
for up to `usage.intervalMs`, so a one-shot armed at the token's own expiry
re-polls (and therefore refreshes) the moment it lapses.

The local `expiresAt` is advisory only —
a probe fires whenever a token exists at all and the server settles the
state (`401`/`403` → `STALE` when a refresh token is present, `NO AUTH`
when it isn't) so a skewed clock can't hide real numbers. A failed read of
the credentials file retries after 300 ms rather than waiting out the full
`usage.intervalMs`, since Claude Code rewrites that file by rename and a
poll can land in the gap. The CLAUDE rows are not a fixed pair:
`shell/Usage/usage.js`'s `parseUsage` enumerates every key in the response
shaped like a rate window (an object carrying `utilization`) rather than
naming buckets, so a future window (a `fable` bucket, another per-model
key) renders with zero code changes the day the API adds it. Labels derive
from the key — `five_hour`→`5-HOUR`, `seven_day`→`WEEKLY`, any
`seven_day_*` key→`WEEKLY <REST>` (`seven_day_opus`→`WEEKLY OPUS`,
`seven_day_sonnet`→`WEEKLY SONNET`), anything else uppercased with
underscores turned to spaces. Row order is stable: `5-HOUR`, `WEEKLY`, then
the rest alphabetically by key. A bucket with absent or `null` utilization
is skipped honestly rather than rendered as 0%.
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
`AppMenuPanel` is the focused app's menu, opened by clicking the bar's
`activeWindow` cell (or `panel open appmenu`) — macOS's app-name menu, in
the place the app name already sits. It is sourced entirely from data the
desktop already publishes, so there is no per-app list to maintain: the
window's app-id resolves a desktop entry through the same
`DesktopEntries.heuristicLookup` the cell's icon and name already use, that
entry's own `Actions=` groups become the `ACTIONS` rows (clicking one runs
it and closes the panel), the compositor's window list filtered by the same
app-id becomes the `WINDOWS` rows (the current window inverted, clicking
another focuses it), and a final `Close window` row closes the current one.

This is deliberately not a global menu bar. Reading an app's real File/Edit
menus needs `org.gtk.Menus` (only GTK4 apps that set a menubar, which
libadwaita apps do not), the DBusMenu registrar (keyed by X11 window id, so
XWayland only), or the kde-appmenu Wayland protocol (KWin only — neither
niri nor Hyprland implements it), and Quickshell exposes no generic D-Bus to
QML for any of them. Launcher actions plus the window list are what can be
sourced honestly today. Honest states: nothing focused renders `NO WINDOW`,
an app-id with no desktop entry renders `NO DESKTOP ENTRY`, and an entry
declaring no actions renders `NO ACTIONS`.

The cell keeps naming its app while the menu is open. Both compositors drop
their focused window the moment one of the shell's own layer surfaces takes
keyboard focus, which used to empty the cell and reflow the bar's left
region every time any panel opened; `shell/Compositor/focus.js` holds the
last focused window across that gap, bounded by the focused workspace so a
genuinely empty workspace still reads as empty. `CompositorService.focusedWindowId`
is unchanged for everything else; the held value is
`heldFocusedWindowId`, and `debug dump` reports both.

`SystemUpdatePanel` lists a flake's direct inputs, one row each: the input
name, its locked rev short-form, and whether upstream has moved. The poll
lives in the panel rather than the widget (`GithubPanel`'s own pattern), so
`panel open systemupdate` renders honestly even when `bar.layout` never
names the widget. Stage 1 reads `<systemUpdate.flakeDir>/flake.lock` through
a `FileView`, which costs nothing and re-reads for free the moment you run
`nix flake update` yourself; stage 2 probes upstream one input at a time,
strictly queued. Only direct inputs are walked: a nixpkgs pinned into some
dependency by a `follows` is not something you update. Honest states, one
dim cell each: `NO FLAKE` (no `systemUpdate.flakeDir`), `NO LOCK`, `CHECKING`
before anyone has asked, and `NO NETWORK` when the probes cannot reach
upstream. An input type with no cheap probe stays `?` rather than a
fabricated `CURRENT`, and the summary counts it separately (`2 BEHIND / 1 ?`).

`DisplayPanel` (M17) is the one panel with no bar cell of its own —
`panel open display` is the only way in — and lists every connected output
as a row: name, an `ON`/`OFF` toggle, a status meta line
(`2560x1440@59.95 / 1.5X`, `MIRRORS DP-1`, or just `DISABLED`), the make
and model when the compositor reports them, and a flat accent-fill `SCALE`
track from 1x to 3x in 0.25 steps. Press or wheel the track to commit one
value (no drag-to-scrub — every step is a real output reconfiguration), or
use the keyboard: Up/Down move the cursor, Enter toggles that output,
`h`/`l` step its scale, the same binding `PowerPanel`'s brightness rows
use. The focused output's row is inverted. A `MIRROR` section below points
every other enabled output at the focused one, and off clears every output
currently mirroring anything.

Everything reads and writes through the compositor backend contract
(`outputs`/`refreshOutputs`/`setOutput*`), never `niri msg` or `hyprctl`
from the panel. Neither compositor pushes output changes, so an open panel
re-reads every 5 seconds; nothing reconfigures an output at startup or on
open, and the panel's only unprompted traffic is that read. Output names are
opaque strings end to end, exactly like window and workspace ids. Honest
states: `NO OUTPUTS` when the backend reports none (including "no compositor
detected", which needs no branch of its own — it simply has no outputs);
`MIRROR UNSUPPORTED` under niri, whose IPC has no mirroring primitive at
all; `SINGLE DISPLAY` when fewer than two outputs are enabled and there is
nothing to mirror onto; and a dimmed, unclickable `ON` cell on the last
enabled output, since both compositors would happily leave the session with
nothing on screen and no surface left to undo it from. A disabled output
reports a zero mode rather than its last known one, which is why its status
line says only `DISABLED`.

**IPC** (`target: "panel"`, a documented spec addendum — see
`docs/superpowers/plans/2026-07-28-m6-clipboard-and-panels.md`'s header note
— since per-widget popouts otherwise have no summon path for compositor
keybinds and no way to be verified headlessly):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call panel open audio
qs ipc --any-display -p <store-path>/share/formalshell call panel toggle network
qs ipc --any-display -p <store-path>/share/formalshell call panel open display   # the display panel has no bar cell; this is its only summon path
qs ipc --any-display -p <store-path>/share/formalshell call panel close        # closes whichever panel is open
qs ipc --any-display -p <store-path>/share/formalshell call panel state       # "" | "appmenu" | "audio" | "calendar" | "network" | "bluetooth" | "power" | "weather" | "media" | "github" | "usage" | "tailscale" | "systemupdate" | "display" | "airpods" | "dualsense" | "plugin:<id>"
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
qs ipc --any-display -p <store-path>/share/formalshell call network speedtest                        # starts a SPEED TEST run (M16 Task 9)
qs ipc --any-display -p <store-path>/share/formalshell call network speedstatus                      # JSON: {running, phase, downMbps, upMbps, error}
```

An unknown ssid returns `error: unknown ssid '<ssid>'`. `connect`/`connectEap`
take the secret as a plain IPC argument, which lands in argv — world-readable
via `/proc` on a multi-user system — so these two verbs exist for the
headless rig, not as the recommended interactive path: a real session should
type the passphrase into the panel's own inline prompt (stdin-fed, never
argv, see the WI-FI section above). `speedtest` returns `error: speed test
already running` while one is in flight rather than starting a second
overlapping run; `phase` is one of `idle`/`resolving`/`down`/`up`/`done`.

**Bluetooth IPC** (`target: "bluetooth"`, M16 Task 10, omarchy `f54edbe`
parity — `toggleBluetooth`, radio power for compositor keybinds and the
smoke rig; bound directly to `Quickshell.Bluetooth`, same as
`BluetoothPanel.qml`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call bluetooth status   # JSON: {available, enabled, connected, devices: [{address, name, paired, trusted, connected}]}
qs ipc --any-display -p <store-path>/share/formalshell call bluetooth toggle   # flips adapter power
qs ipc --any-display -p <store-path>/share/formalshell call bluetooth power on # or "off"
qs ipc --any-display -p <store-path>/share/formalshell call bluetooth trust AA:BB:CC:DD:EE:FF     # headless path for the panel's TRUST cell
qs ipc --any-display -p <store-path>/share/formalshell call bluetooth untrust AA:BB:CC:DD:EE:FF
```

`status` always answers with JSON, `available: false` when
`Bluetooth.defaultAdapter` is null (the test VM's expected state). `toggle`/
`power` return `error: no bluetooth adapter` under the same condition, and
`power` rejects any argument that isn't `on`/`off` — never a silent no-op.
`trust`/`untrust` write the device's `trusted` property directly rather than
routing through the panel, so they never arm its in-flight row state and
`ok` means the write was issued, exactly as it already does for `power`.
`status`'s `devices[].trusted` is NOT proof the write reached BlueZ and no
smoke assertion may treat it as such: quickshell never rolls back a `Set`
BlueZ rejected, so that field reports what was asked for whenever the two
disagree. `bluetoothctl info <address>`'s `Trusted:` line is the only real
read-back, and it is what the panel itself settles against.
Addresses match case-insensitively (BlueZ hands them out uppercase). An
address no device on the adapter answers to returns
`error: unknown device '<address>'`, and one BlueZ hasn't paired returns
`error: device '<address>' is not paired`.

**AirPods IPC** (`target: "airpods"`, M29, the same spec-addendum tradition
as `panel`/`bluetooth`: compositor keybinds and the smoke rig both need a
headless path onto the librepods daemon's control socket, since it takes a
raw write, no reply, no CLI of its own):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call airpods status              # JSON: the parsed daemon state, or {"available":false}
qs ipc --any-display -p <store-path>/share/formalshell call airpods noise transparency   # off | anc | transparency | adaptive
qs ipc --any-display -p <store-path>/share/formalshell call airpods ca on                # or "off"
qs ipc --any-display -p <store-path>/share/formalshell call airpods onebud off           # or "on"
qs ipc --any-display -p <store-path>/share/formalshell call airpods ear both             # one | both | off
qs ipc --any-display -p <store-path>/share/formalshell call airpods adaptive 40          # 0-100, meaningful only while noise mode is adaptive
```

Every verb is validated against `AirpodsService`'s own wire allow-list
before the socket ever opens; an unknown mode/state or an unset
`XDG_RUNTIME_DIR` both come back as `error: refused '<verb>'` rather than a
silent no-op. There is no `dualsense` IPC target — that panel is read-only
by design, so there is nothing here to drive beyond `panel open dualsense`.

**Dev gallery** (`target: "gallery"`) is a component-QA sheet, not a user
surface: it renders the REAL shared components (`Cell`, `MetaLabel`,
`MarqueeText`, `AuthPrompt`, the type/spacing/color scales, `Panel` itself)
in one screenshot-sized `Panel`, so a regression in any of them shows up
where it can be seen. Nothing loads until it is summoned, no bar cell opens
it, no `bar.layout` entry names it, and it is deliberately absent from
`panel`'s registry — asking for it by name over its own target is the only
way in. The one component it can't paint is the tooltip, since `Tooltip.qml`
hides itself while any panel is open; that row carries a real `tooltipText`
and says plainly that the card won't appear here rather than standing a
lookalike in its place.

```bash
qs ipc --any-display -p <store-path>/share/formalshell call gallery open
qs ipc --any-display -p <store-path>/share/formalshell call gallery close
qs ipc --any-display -p <store-path>/share/formalshell call gallery toggle
qs ipc --any-display -p <store-path>/share/formalshell call gallery status   # {"isOpen":…}
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
many surfaces" split `Lock.qml` uses. It loads an ASCII banner — the bundled
block-character `FORMALSHELL` logo at `branding/screensaver.txt`, or a
user-supplied file — and animates it converging into place on a `Canvas` in
the shell's own mono font, no spawned terminal windows.

**The engine is `ttfx`** (`omacom-io/ttfx`, MIT), the same
terminal-text-effect binary Omarchy's own screensaver runs, packaged at
`nix/ttfx-package.nix` and on the shell wrapper's PATH. The shell runs it
against a canvas measured in this screen's own cells, splits its stdout on
the cursor-up sequence it emits between frames, and paints each frame's
truecolor runs itself — so the animation is ttfx's, the glyph rendering is
the shell's. That buys all 37 of its effects, and their colors: each effect
arrives in its own upstream gradient (decrypt amber, matrix green, rain
blue), which is exactly what Omarchy does — it passes no gradient overrides
either, so a random effect is what makes the color change. `ttfx --help`
lists the full set:

`beams` `binarypath` `blackhole` `bouncyballs` `bubbles` `burn` `colorshift`
`crumble` `decrypt` `errorcorrect` `expand` `fireworks` `highlight`
`laseretch` `matrix` `middleout` `orbittingvolley` `overflow` `pour` `print`
`rain` `randomsequence` `rings` `scattered` `slice` `slide` `smoke`
`spotlights` `spray` `swarm` `sweep` `synthgrid` `thunderstorm` `unstable`
`vhstape` `waves` `wipe`

**Without ttfx on PATH** — a bare `qs -p shell/` dev run, or an install that
skipped the wrapper — the surface falls back to `shell/Screensaver/effect.js`
instead of going blank: five hand-written convergence effects (`decrypt`,
`rain`, `expand`, `slide`, `scatter`), pure functions of a frame counter,
drawn in `Theme.color.accent`. `screensaver frameInfo` reports which engine
is live. This fallback is why the shell stays pure QML/JS with nothing
installed alongside it.

**Picking an effect.** `screensaver.effect` in `settings.json` is `"random"`
by default — a fresh effect is picked every time the screensaver activates,
seeded off the activation itself so a long idle session still cycles
variants — or pin it to any name the live engine knows (an unknown name
falls back to random and logs a warning, never a hard error).
`screensaver.frameRate` (default 60) is how fast ttfx is asked to produce
frames; lower it on a machine where a full-screen canvas can't keep up:

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
`screensaver frameInfo` reports the live engine, the resolved effect, its
convergence frame, and a `cycles` counter (completed reroll count, 0 until
the first one) so cycling is observable without screenshots. Under ttfx an
effect converging *is* its process exiting, and the convergence frame is
how many frames that run really produced — known only once a pinned run
has completed, so `frameInfo` answers 0 until one has, rather than
guessing.

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

**Stay awake.** `IdleService.stayAwake` (omarchy's own StayAwake indicator
semantics, read-only reference `omarchy/shell/plugins/bar/indicators/
StayAwake.qml`) is an explicit, session-only toggle — never persisted, a
shell restart always comes back off — that holds the whole
screensaver/auto-lock idle chain exactly like the existing media guard,
gating `Screensaver.qml`'s own activation (`lockAfterSeconds`'s auto-lock
timer only ever runs while the screensaver is active, so gating activation
is enough to hold that chain too). The bar's coffee-glyph indicator cell
binds ONLY to this toggle — clicking it turns stayAwake off; a media
player keeping the screensaver at bay no longer shows a glyph of its own,
only the explicit toggle does. `Menu`'s `System` section carries a
`STAY AWAKE` row that flips the same toggle through the shell's own IPC
self-target.

**IPC** (`target: "screensaver"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call screensaver start
qs ipc --any-display -p <store-path>/share/formalshell call screensaver stop
qs ipc --any-display -p <store-path>/share/formalshell call screensaver stayAwakeOn
qs ipc --any-display -p <store-path>/share/formalshell call screensaver stayAwakeOff
qs ipc --any-display -p <store-path>/share/formalshell call screensaver stayAwakeToggle
qs ipc --any-display -p <store-path>/share/formalshell call screensaver status  # {"active":…,"isIdle":…,"guardMediaPlayback":…,"mediaPlaying":…,"stayAwake":…}
qs ipc --any-display -p <store-path>/share/formalshell call screensaver frameInfo  # {"engine":…,"effect":…,"convergenceFrame":…,"cycles":…}
```

`dev/smoke-niri.sh --screensaver` additionally accepts `SCREENSAVER_EFFECT`
and `SCREENSAVER_ASCII_TEXT` environment variables (unset by default) to pin
an effect or a custom banner for a single verification run — see the
script's own header comment.

## Picker

The picker is a **route inside the menu**, not a surface of its own. The
`WALLPAPER` row (or `menu summon wallpaper`, or `picker summon`) descends
into a level whose rows are the images in a directory, and the menu renders
that one level as a ledger grid of image cells (`Components/Cell.qml`,
sharing hairline rules — a grid first, Omarchy's skewed carousel is
explicitly a later flourish) instead of as a row list. Everything else is
the menu's: the search field filters the grid by filename, arrows move the
cursor cell in 2D (Left/Right by one, Up/Down by a row) with `Cell`'s own
inversion marking it, Enter confirms, Escape and backspace-on-empty pop back
out to the level above, and the action bar names what Enter will do.

The listing is scanned by a `find`-backed `Process` on every entry into the
route (Quickshell has no directory-listing QML type, the same technique
`CalendarEventsService` already uses), and dropped again on the way out, so
a directory edited between visits is picked up and a visit's decoded
thumbnails do not outlive it. An empty or unset directory is an empty grid.

**Dark/Light variants.** The scan also looks one level down, into `Dark` and
`Light` subdirectories (either name, any case). If either exists, the grid
shows one variant at a time and a `DARK | LIGHT` switcher sits between the
search field and the grid, the live one inverted; `Tab` (or a click on either
cell) swaps it, and the route always opens on the variant matching the
theme's current mode. Files sitting directly in the directory are not listed
in that case. A directory with neither subdirectory is listed flat and shows
no switcher at all, so nothing changes for a setup that doesn't use them.

The route doubles as two things:

- **Wallpaper mode** (the menu row, `menu summon wallpaper`, `picker
  summon`; scans `picker.directory` from `settings.json`): choosing an
  image calls `Core.State.setWallpaper()` directly — the exact call
  `wallpaper set` makes, so `ThemeEngine`'s retheme pipeline runs through
  the one trigger path, never duplicated.
- **Generic image-selector mode** (`picker select <directory> <token>`,
  spec §11): scans an arbitrary caller-supplied directory; the chosen path
  (or a cancel from Escape, a level pop, or the menu closing) lands in
  `$XDG_STATE_HOME/formalshell/picker-selection.txt` as `{token, value}` /
  `{token, cancelled: true}` JSON — the same request/answer handshake
  `MenuIpc`'s `select()`/`input()` already established, reused rather than
  reinvented. It stays a file of its own, distinct from
  `menu-selection.txt`: two documented channels with different callers, and
  merging them would let one answer the other's poll.

**IPC** (`target: "picker"` — a documented spec addendum, same rationale as
`panel`: the spec's own §IPC list predates this surface and doesn't name it,
but per-widget-style popouts otherwise have no summon path for compositor
keybinds or headless verification). The target keeps its own name and verbs
even though the menu is what answers them: every existing bind and caller
uses it, and `menu`'s own `select()`/`input()` mean something different:

```bash
qs ipc --any-display -p <store-path>/share/formalshell call picker summon                       # open in wallpaper mode
qs ipc --any-display -p <store-path>/share/formalshell call picker select /path/to/dir tok1      # open in select mode, correlated by token
qs ipc --any-display -p <store-path>/share/formalshell call picker choose /path/to/dir/img.png   # same action Enter/click on a cell takes
qs ipc --any-display -p <store-path>/share/formalshell call picker variant light                 # same action Tab and the DARK | LIGHT cells take
qs ipc --any-display -p <store-path>/share/formalshell call picker close
qs ipc --any-display -p <store-path>/share/formalshell call picker status   # {"open":…,"mode":…,"directory":…,"count":…,"variant":…,"hasVariants":…,"darkCount":…,"lightCount":…,"cursor":…}

# poll/read a select() answer, same convention as menu-selection.txt:
cat $XDG_STATE_HOME/formalshell/picker-selection.txt
```

**Memory**: each cell decodes at its own on-screen size (`sourceSize` capped
to the cell's rendered dimensions × `devicePixelRatio`), not the source
file's native resolution — a directory of 6000×4000 photos costs kilobytes
per cell, not tens of megabytes. Leaving the route (Escape, a level pop, the
menu closing) drops the whole decoded set; re-entering re-scans and
re-decodes, which is cheap. The grid is a `GridView`, so a listing taller
than the card only ever decodes the cells actually on screen. To confirm on the host, compare
`/proc/$(pgrep -f quickshell)/smaps_rollup` before and after opening/closing
the picker:

```bash
grep -E "Rss|Pss" /proc/$(pgrep -f quickshell)/smaps_rollup
```

Expect the post-close reading to settle back near the pre-open one, and the
open-state reading to scale with how many cells are on screen, not with the
source images' file sizes. Steady state with a 1080p wallpaper is typically
in the 150–300MB RSS band.

## Screenshots

`shell/Ipc/ScreenshotIpc.qml` (M12 — a spec-addendum surface, same pattern
as `panel`/`picker`) puts every capture behind one IPC target: `full` grabs
the whole output with no interaction, `pick` opens the shell's own region
picker (below — the one you want for a `Print` bind), and `region` runs bare
`slurp` for an interactive rectangle, kept for anyone who prefers it.
However the rectangle is chosen, the capture lands as
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

### The region picker

`pick` opens the shell's own picker (`shell/Surfaces/Capture/RegionPicker.qml`,
M22) instead of slurp: a full-screen Overlay surface holding exclusive
keyboard focus. Before it maps, `grim` captures every output and the surface
renders those frames at 1:1, so screen content cannot shift while you choose,
and the capture then photographs that freeze with the chrome hidden for a
frame. Nothing on screen is live, and the overlay can never appear in its own
screenshot.

Four modes, matching the names omarchy uses so a ported keybind reads the
same: `smart` (freeform drag with window and display rectangles hinted, and a
bare click under 20px² snapping to whatever it landed in), `region` (freeform
only), `windows` (snap to a window, no freeform), and `fullscreen` (the focused
output, no interaction and no surface).

#### The toolbar

The picker carries a toolbar along its bottom edge, the shell's answer to
macOS's Cmd+Shift+5 panel — bind it to `Mod+Shift+S` and you get the same
thing: one surface where you choose what to capture, whether to shoot or
record it, and then commit.

Six cells, in two groups of three, plus the commit button:

| Cell | Key | Selects |
| --- | --- | --- |
| SHOT SCREEN | `1` | The display under the pointer, preselected to the focused one |
| SHOT WINDOW | `2` | A window, highlighted or named (see the compositor split below) |
| SHOT REGION | `3` | Freeform drag, snapping to a window or display on a bare click |
| REC SCREEN | `4` | The same display, recorded instead of shot |
| REC WINDOW | `5` | The same window, recorded instead of shot |
| REC REGION | `6` | The same rectangle, recorded instead of shot |

The two halves are orthogonal: the group picks *what* the selection is, the
row picks whether `Return` shoots or records it. A record tool swaps the
selection border to the `urgent` role and the commit cell to RECORD, so the
surface never looks the same in the two states.

Recording starts through `RecordingService` exactly as `record start` does —
same wf-recorder child, same destination, same `RECORDING SAVED` notification
carrying a real frame from the finish and its `PLAY` and `GIF` actions. It
picks up audio from `recording.audio` in
`settings.json` (`none` by default, or `desktop` / `desktopmic`); every other
recording setting applies unchanged. Unlike a shot, the picker **unmaps
itself** before the recorder starts: wf-recorder records live content, so an
overlay still on screen would be the first thing in the file.

Keys, once it is open:

| Key | Does |
| --- | --- |
| `Return` | Capture (or record) what is selected |
| `Ctrl+Return` | Capture the whole display under it |
| `Tab` / `Shift+Tab` | Cycle windows in reading order |
| Arrows | Move the selection spatially |
| `1`–`6` | Select a toolbar cell |
| `Escape`, right-click | Cancel |

A second argument picks what happens with the result: `default` saves to disk
**and** the clipboard then offers the editor, `copy` is clipboard only
(nothing touches disk, so no editor is offered), and `save` writes the file
and stops there, no clipboard and no editor.

**Both arguments are required.** IPC arity is an exact-equality check
(quickshell's `ipccomm.cpp`), so `screenshot pick smart` gets rejected before
the handler ever runs. A keybind written that way silently does nothing.
Spell the processing out even when you want the default:
`screenshot pick smart default`.

**One difference between compositors, and it is the compositor's, not the
shell's.** On Hyprland every window has a rectangle, so hovering or cycling
highlights it in place. niri reports a pixel position only for *floating*
windows: in niri v26.04, `Tile::ipc_layout_template` hardcodes
`tile_pos_in_workspace_view: None` (`src/layout/tile.rs:869`), `floating.rs:336`
fills it in, and the tiled layout inherits the `None`
(`src/layout/scrolling.rs:2426`). A tiled niri window therefore has no box to
draw. Rather than drop the capability, the picker **names** those windows
instead, in a centered card of title over dim app id, and captures the chosen
one by id through niri's `ScreenshotWindow` action, which crops server-side
(niri also puts the PNG on the clipboard itself, so that path skips
`wl-copy`). Window selection works identically on both; only the affordance
differs. The split is on whether a rectangle exists, never on a compositor
name, so a future niri that reports tiled geometry gets the highlight
behaviour with no configuration.

That split costs REC WINDOW something a shot does not pay. wf-recorder crops
with `-g` and nothing else, and niri's server-side `ScreenshotWindow` has no
video counterpart, so a window with no rectangle cannot be recorded at all.
Under REC WINDOW those windows stay listed, dimmed, under a
`CANNOT RECORD: NO COMPOSITOR GEOMETRY` header, and `Return` refuses them by
name. On Hyprland, and for floating niri windows, REC WINDOW records the
window's box like any other rectangle.

`processing` does not reach that one path. `ScreenshotWindow` always writes
the file and always copies it, so a named niri window taken with `copy` still
lands in `screenshot.directory`, and one taken with `save` still lands on the
clipboard. Only the notification follows what you asked for.

### Annotating a capture

The `SCREENSHOT SAVED` notification carries an `EDIT` action, and clicking the
card body does the same. Both hand the PNG to `screenshot.editor`
(`settings.json`, default `tensaku-edit`), as does `screenshot edit` from a
keybind. The default is [Tensaku](https://tensaku.dev), a Wayland annotation
editor built and shipped by this flake (`nix/tensaku-package.nix`); it takes
its input as a flag rather than a positional argument, which is what the
`tensaku-edit` wrapper adapts. Any editor accepting `<editor> <path>` works
just as well. A launch failure is its own `EDITOR FAILED` notification and
never reports the capture as failed, since by then the PNG is already saved
and on the clipboard.

**IPC** (`target: "screenshot"`):

```bash
qs ipc --any-display -p <store-path>/share/formalshell call screenshot full                  # whole output, no interaction
qs ipc --any-display -p <store-path>/share/formalshell call screenshot pick smart default    # mode then processing, both required
qs ipc --any-display -p <store-path>/share/formalshell call screenshot pick windows copy     # snap to a window, clipboard only
qs ipc --any-display -p <store-path>/share/formalshell call screenshot region                # legacy slurp rectangle, same pipeline
qs ipc --any-display -p <store-path>/share/formalshell call screenshot edit ""               # "" opens the last capture; a path opens that file
qs ipc --any-display -p <store-path>/share/formalshell call screenshot cancel                # kill an in-flight capture, clear state
qs ipc --any-display -p <store-path>/share/formalshell call screenshot status                # {"capturing":…,"lastPath":…,"lastError":…,"lastCancelled":…}
qs ipc --any-display -p <store-path>/share/formalshell call screenshot pickerStatus          # {"open":…,"mode":…,"action":…,"tool":…,"drawableWindows":…,"namedWindows":…,"selection":…}
qs ipc --any-display -p <store-path>/share/formalshell call screenshot key tab               # drive the picker headlessly (smoke rig)
qs ipc --any-display -p <store-path>/share/formalshell call screenshot key 4                 # select a toolbar cell, same as clicking it
```

`pickerStatus`'s `drawableWindows` and `namedWindows` are the honest
capability report: zero drawable alongside a non-empty named list is the
normal niri answer, not a failure.

**Recommended keybinds.** `screenshot pick smart default` is the route
worth binding to your main capture chord (`Mod+Shift+S`, or whatever your
compositor uses for "area screenshot") — it is the only route with the
toolbar, keyboard window selection, and recording. `screenshot region`
(bare slurp) and `screenshot full` (instant whole output) are both
non-interactive legacy routes: no toolbar, no recording. `full` is still
worth a bind of its own for a plain "whole screen right now" key like
`Print`, but binding `Print` or `Mod+Shift+S` to `region` and expecting the
picker is the mistake that shipped for weeks on one machine before anyone
noticed the bind, not the shell, was wrong.

Bind them in niri, same pattern as every other target:

```kdl
binds {
    Print { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "screenshot" "full"; }               // instant, no toolbar, no recording
    Mod+Shift+S { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "screenshot" "pick" "smart" "default"; } // the picker: toolbar, recording, keyboard select
    Shift+Print { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "screenshot" "pick" "region" "copy"; }
    Ctrl+Print { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "screenshot" "region"; }        // legacy bare slurp, no toolbar, no recording
    Mod+Print { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "screenshot" "edit" ""; }
}
```

Verified by `dev/smoke-niri.sh --capture`, which opens the picker over a
session holding one real tiled window, screenshots it, cycles the selection
with `key tab`, captures with `key ctrl-return`, checks the resulting PNG's
real pixel dimensions against the compositor's own output geometry, drives the
toolbar's REC SCREEN cell with `key 4` into a real wf-recorder child and
checks the mp4 it leaves behind, and proves `key escape` leaves no surface
behind. It asserts a non-zero named window count on purpose: a leg that merely
found no window hints would pass identically against a picker that never
enumerated windows at all.

## Text and color capture

`shell/Ipc/CaptureIpc.qml` is the third leg of the capture family, and its
own target rather than more verbs on `screenshot`, because the split is what
each one leaves behind:

| Target | Leaves behind |
| --- | --- |
| `screenshot` | a PNG on disk, and on the clipboard |
| `capture` | nothing on disk: recognized text, or one pixel's color, on the clipboard |
| `record` | video |

**`capture text`** drags a region with `slurp`, captures it with `grim`,
runs `tesseract` over the PNG, strips the form feed tesseract ends every
page with, and puts the result on the clipboard as `text/plain`. A
`TEXT COPIED` notification carries the recognized text. A region that held
nothing readable is a real answer, not a failure: `NO TEXT FOUND`, no
clipboard write, no `lastError`. `capture.ocrLanguage` (default `eng`) picks
tesseract's language pack.

**`capture color`** picks one pixel with slurp's point mode (crosshairs on,
so it is aimable), reads it back through `grim -t ppm`, and copies
`#RRGGBB`. A `COLOR COPIED` notification carries the hex. The pipeline is
grim plus coreutils rather than a compositor call on purpose: niri does have
a native `PickColor` with a real magnifier grab, but it is niri-only, so
adopting it would build a path Hyprland never runs and leave the smoke rig
verifying the wrong one. `grim -t ppm` behaves identically everywhere and
its P6 output needs no image library to read.

Escape or right-click inside slurp is a decline, not an error: no toast, no
`lastError`. `capture.timeoutSeconds` (default 90) auto-cancels a selection
nobody answers, and `capture cancel` does the same on demand.

**`textAt` and `colorAt`** run those same two pipelines against a rectangle
you already have, skipping the selection. The argument is slurp's own output
format, `X,Y WxH`, quoted because of the space:
`capture textAt "0,0 1276x693"`. `colorAt` reads the rectangle's top-left
pixel, so `"640,360 1x1"` is how you ask for one. They are separate verbs rather than an optional argument on
`text`/`color` because IPC arity is an exact-equality check, and a defaulted
parameter would break the bare `capture text` a keybind actually calls.

Everything after the selection is the same code either way, which is why
`dev/smoke-niri.sh --ocr` drives these two rather than the interactive pair.
The rig has no pointer to answer a real slurp drag with, but it can hand over
a geometry and watch grim, tesseract and `wl-copy` run for real.

**One capture at a time, within this target only.** `text` and `color` share
one busy flag and one watchdog, so they can never race each other for the
pointer. Nothing coordinates this target with `screenshot`'s own slurp,
though: firing `screenshot region` and `capture text` at the same moment
puts two slurp overlays on screen, and the second one gets the click.

```bash
qs ipc --any-display -p <store-path>/share/formalshell call capture text                    # OCR a region to the clipboard
qs ipc --any-display -p <store-path>/share/formalshell call capture color                   # pick a pixel, copy its hex
qs ipc --any-display -p <store-path>/share/formalshell call capture textAt "0,0 1276x693"   # same OCR pipeline, no selection
qs ipc --any-display -p <store-path>/share/formalshell call capture colorAt "640,360 1x1"   # top-left pixel of that rectangle
qs ipc --any-display -p <store-path>/share/formalshell call capture cancel
qs ipc --any-display -p <store-path>/share/formalshell call capture status                  # {"capturing":…,"mode":…,"lastHex":…,"lastText":…,"lastError":…,"lastCancelled":…}
```

The menu's root `CAPTURE` node carries both as rows (`COPY TEXT FROM
SCREEN`, `PICK COLOR`) alongside the recording rows below. `tesseract` and
`grim` both ride the package wrapper's own PATH, so neither is a host
prerequisite.

## Screen recording

`shell/Services/RecordingService.qml` drives one `wf-recorder` child over
the `record` IPC target. `wf-recorder` rather than `gpu-screen-recorder`:
gpu-screen-recorder captures through the KMS backend, which has no meaning
inside a nested compositor or on llvmpipe, so it could never be verified in
the smoke rig. wf-recorder speaks `wlr-screencopy-unstable-v1`, which niri
implements under its nested winit backend, so the code path the owner runs
is the one the rig can exercise.

Two scopes, `screen` (the focused output) and `region` (a `slurp`
rectangle), and three audio modes:

| Audio mode | Records |
| --- | --- |
| `none` | no audio flag at all |
| `desktop` | the default sink's own monitor |
| `desktopmic` | both, mixed |

`desktopmic` exists because wf-recorder stores exactly one audio source and
has no multi-device form. The shell builds a transient null sink plus two
loopbacks with `pactl`, records that, and unloads every module it loaded on
stop, including when a later setup step fails partway. Asking for
`desktopmic` where the default source is itself a monitor fails loudly
(`no microphone: the default source is a monitor`) rather than quietly
recording desktop audio twice. `pactl` is a host binary, not one the wrapper
bundles, so a machine without it fails the setup step rather than recording
silence.

Stopping sends SIGTERM, which is one of wf-recorder's own graceful
termination signals, so the container is finalized rather than truncated. A
recorder that ignores it for 5 seconds is killed, and the notification says
so (`RECORDING TRUNCATED`) instead of reporting a save. Recordings land at
`<recording.directory>/screenrecording-<timestamp>.mp4`. The
`RECORDING SAVED` notification carries a thumbnail pulled from the finished
file, a `PLAY` action that opens it with `recording.player`, and a `GIF`
action that transcodes it in place.

`record gif` is a two-pass ffmpeg palettegen/paletteuse transcode, writing
next to its source rather than into `recording.directory`: the everyday case
is an mp4 someone sent you sitting in `~/Downloads`, and moving the result
elsewhere is friction rather than less of it.

Every setting, with its default:

| Key | Default | Meaning |
| --- | --- | --- |
| `recording.directory` | `~/Videos` | where recordings land, created on first use |
| `recording.framerate` | `30` | wf-recorder `-r` |
| `recording.codec` | `""` | wf-recorder `-c`, empty leaves its own default |
| `recording.audioBackend` | `""` | wf-recorder `--audio-backend`, only sent when a device is being recorded |
| `recording.noDmabuf` | `false` | wf-recorder `--no-dmabuf`, the fallback for a driver whose dmabuf path is broken |
| `recording.timeoutSeconds` | `90` | auto-cancel an unanswered `region` selection |
| `recording.audio` | `"none"` | audio mode the capture picker's REC tools start with; `record start` takes its own argument instead |
| `recording.gifFps` | `12` | GIF frame rate |
| `recording.gifWidth` | `640` | GIF width in pixels, height follows the aspect |
| `recording.player` | `"xdg-open"` | command the SAVED toast's `PLAY` action hands the file to |
| `recording.finalize` | `true` | trim the PipeWire warmup click and loudnorm the audio after wf-recorder exits, before the SAVED notification fires |
| `recording.maxHeight` | `0` | downscale height in pixels via wf-recorder's own `-F` scale filter, `0` means no cap; `record startCapped` overrides it for one run |
| `recording.webcam` | `false` | spawn an mpv overlay of a video capture device before the recording starts |
| `recording.webcamDevice` | `""` | a specific `/dev/video*` node; empty auto-detects the first one found |
| `recording.webcamSize` | `"medium"` | one of `small`/`medium`/`large`, the 8:9 portrait preset the overlay scales to |

A webcam overlay anchors bottom-right of the captured region, sized as a
proportion of it so the camera occupies the same share of the frame at any
resolution. It needs `CompositorService.floatingPlacementAvailable` (niri and
Hyprland both support it; no other compositor is detected here at all): an
unplaceable camera window landing mid-recording is worse than no camera, so
an unsupported compositor, a missing device, or a placement that never
settles all fall back to recording without one, with a `WEBCAM UNAVAILABLE`
or `WEBCAM UNPLACED` notification saying why.

```jsonc
{
  "recording": { "directory": "/home/youruser/Videos/screencasts", "framerate": 60 }
}
```

**IPC** (`target: "record"`, a spec addendum in the `panel`/`nightlight`
tradition). Every argument is required by IPC arity, so pass `""` to take a
default rather than omitting it:

```bash
qs ipc --any-display -p <store-path>/share/formalshell call record start screen none
qs ipc --any-display -p <store-path>/share/formalshell call record start region desktopmic
qs ipc --any-display -p <store-path>/share/formalshell call record startAt "0,0 1280x720" none   # a rectangle you already have, no selection
qs ipc --any-display -p <store-path>/share/formalshell call record startCapped screen none 720    # downscale to 720p regardless of recording.maxHeight
qs ipc --any-display -p <store-path>/share/formalshell call record toggle screen none
qs ipc --any-display -p <store-path>/share/formalshell call record stop            # also cancels a pending region selection
qs ipc --any-display -p <store-path>/share/formalshell call record gif ""          # transcode the last recording
qs ipc --any-display -p <store-path>/share/formalshell call record gif /path/to/clip.mp4
qs ipc --any-display -p <store-path>/share/formalshell call record status          # {"active":…,"scope":…,"audio":…,"path":…,"elapsedMs":…,"transcoding":…,"finalizing":…,"lastGifPath":…,"lastError":…}
```

`start` answers with the destination path rather than a completion signal,
the same contract `screenshot region` has: an IPC reply is synchronous while
a region scope blocks on a human. An unknown scope or audio mode comes back
as an error naming the accepted values, never a silent fallback to something
you did not ask for. `startCapped`'s own third argument follows the same
rule: pass `""` to take `recording.maxHeight`'s own value, anything else has
to be a plain integer height in pixels or it comes back as an error too.

While a recording runs, the bar's indicators slot carries a full-bleed
`urgent` cell; clicking it stops the recording. `active` is the live child
process and nothing else: it is never persisted (a crashed shell would leave
a stale `true` behind) and never derived from `pgrep`.

Bind it in niri:

```kdl
binds {
    Mod+Shift+R { spawn "qs" "ipc" "--any-display" "-p" "<store-path>/share/formalshell" "call" "record" "toggle" "screen" "none"; }
}
```

**`record start window` does not exist**, and the reason is wf-recorder's own
interface rather than a gap in niri's IPC: `wf-recorder` takes an output or a
geometry, never a window id. There is nothing to bind to a window that would
follow it.

Recording a window is reachable anyway, through the capture picker's REC
WINDOW tool: it resolves the window's box and hands that rectangle to
`startAt`. Know what that is, though — a geometry snapshot taken once. Move or
resize the window mid-recording and the frame stays where the window was.
A window the compositor reports no box for (every tiled niri window) cannot be
recorded at all, and the picker says so rather than recording the wrong
rectangle. `startAt` is the same entry point exposed over IPC, for a caller
that already has a rectangle and does not want a selection.

## Reminders

A countdown plus a message, fired through the shell's own notification
stack. `reminder set` takes a duration and a message, both arguments always,
because IPC arity is an exact-equality check:

```bash
qs ipc --any-display -p <store-path>/share/formalshell call reminder set 25m "coffee break"
qs ipc --any-display -p <store-path>/share/formalshell call reminder set 1h30 ""   # message falls back to reminders.defaultMessage
qs ipc --any-display -p <store-path>/share/formalshell call reminder show          # notification listing what is pending
qs ipc --any-display -p <store-path>/share/formalshell call reminder clear         # "ok: cleared 3"
qs ipc --any-display -p <store-path>/share/formalshell call reminder status        # {"count":…,"reminders":[{id,message,dueAt,remainingSeconds,remaining}]}
```

`set` answers with the stored entry, including the wall-clock time it lands
(`dueClock`). A duration that doesn't parse is an error string naming what
was rejected, never a silent no-op.

**Duration syntax.** Tokens of digits plus `h`, `m` or `s`, concatenated
with no spaces. A token with no unit takes the next unit smaller than the
one before it, and the first one defaults to minutes:

| Written | Means |
| --- | --- |
| `10` | 10 minutes |
| `45s` | 45 seconds |
| `2h` | 2 hours |
| `1h30` | 1 hour 30 minutes |
| `5m30` | 5 minutes 30 seconds |
| `1h30m15s` | 1 hour 30 minutes 15 seconds |

There is deliberately no rule for a bare number after seconds, so `30s10` is
a parse failure rather than a silent reinterpretation. Whitespace inside the
duration is illegal too: the message has already been split off by then, so
a space there is a typo. The ceiling is 30 days.

**Menu.** `Reminder > Set Reminder` opens the menu's own input field and
takes duration and message in one line (`25m coffee break`), the same
grammar with the first whitespace run as the separator. `Show Reminders` and
`Clear Reminders` are the other two rows. `Clear Reminders` has no `when`
guard and stays visible on an empty list, where it is a harmless no-op:
`when` runs a shell command and cannot gate on in-process state.

**Firing.** A due reminder is sent at `urgency: critical` and marked as
shell-authored, which is exactly the narrow case DND bypass exists for: you
asked for this one. The same urgency makes its toast sticky until dismissed.
Every fired reminder shares the summary `Reminder`, so two landing close
together collapse into one card carrying a repeat count (see
[Notifications](#notifications)); the newest one's message is the one shown.

**Persistence.** Pending reminders live in
`$XDG_STATE_HOME/formalshell/state.json` under `reminders`, alongside
wallpaper, mode and DND. A reminder whose due time passed while the shell
was down fires on the first tick after state loads. Firing late is honest;
dropping it silently is not, and with durations running to 30 days a reboot
mid-countdown is ordinary rather than exotic.

While any reminder is pending the bar's indicators slot carries a countdown
cell: the soonest one alone, or `12:30 / 3` once there is more than one.
Clicking it fires the summary notification. `reminders.defaultMessage`
(default `Time's up`) fills in an empty message at set time, so a stored
entry always carries real text.

## Plugins

Drop-in QML that loads from `~/.config/formalshell/plugins/<id>/`, without
rebuilding the shell. Each plugin is a directory holding a `manifest.json`
and its entry file:

```
~/.config/formalshell/plugins/
  moon-phase/
    manifest.json
    MoonPhase.qml
```

```json
{
  "apiVersion": 1,
  "id": "moon-phase",
  "kind": "bar",
  "entry": "MoonPhase.qml",
  "name": "Moon Phase",
  "region": "right"
}
```

Exactly eight keys are legal:

| Key | Type | Required | Meaning |
| --- | --- | --- | --- |
| `apiVersion` | number | yes | must be `1`; anything else drops the plugin |
| `id` | string | yes | must equal the directory name, lowercase letters, digits and dashes |
| `kind` | string | yes | `bar`, `panel`, `overlay` or `service` |
| `entry` | string | yes | a path inside the plugin directory, never absolute and never escaping it |
| `name` | string | no | display name, defaults to `id` |
| `region` | string | `bar` only | `left`, `center` or `right`, default `right` |
| `keepLoaded` | bool | `panel`/`overlay` only | keep the content loaded while closed, default `false` |
| `width` | string | `panel` only | `narrow`, `default`, `wide` or `menu` |

`width` is an enum rather than a pixel number because every floating card in
the shell snaps to one of those four tokens (`docs/DESIGN.md` §1.3); a raw
literal would be the first non-token width in the card language.

The entry file is ordinary shell QML. It runs in this process, so the
shell's own imports resolve:

```qml
// ~/.config/formalshell/plugins/moon-phase/MoonPhase.qml
import QtQuick
import qs.Core
import qs.Components

Cell {
    standalone: true
    tooltipText: "MOON PHASE"

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "WAXING GIBBOUS"
        color: parent.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.body
    }
}
```

A `Cell` is not required, it is only what makes a bar plugin look like the
cells beside it. Any `Item` renders.

**The four kinds, and how each is addressed:**

- **`bar`** renders as one cell in a bar region. Place it explicitly with
  `"plugin:<id>"` in `bar.layout`, exactly like a builtin name. A bar plugin
  named in no region at all is appended to the region its own manifest asks
  for, id-sorted, so dropping the directory in is enough to see it; an
  explicit placement always wins, and a plugin named somewhere is never
  appended twice.
- **`panel`** is a bar-anchored card, opened with `panel open plugin:<id>`
  (also `toggle`, `close`, `state`). It inherits the real `Panel`: the card
  frame, title band, gutter, enter/exit fade, Escape, click-outside and
  mutual exclusion with every other panel.
- **`overlay`** is a summoned centered card, opened the same way over the
  `panel` target.
- **`service`** has no surface at all. It is instantiated once at load and
  left running.

The `plugin:` prefix means a plugin can never collide with a builtin panel
name by construction, and duplicate ids are structurally impossible since
`id` must equal a directory name.

**Write the content, not the window.** A `bar`/`panel`/`overlay` entry root
is a plain `Item` loaded into a host the shell owns. Layer, exclusive zone
and keyboard focus stay shell-side deliberately: a permanently-exclusive
surface makes Hyprland route every pointer event on every output to it,
killing clicks shell-wide, and a third-party file getting that wrong would
brick the session. A bar plugin that wants to hide itself sets `shown` on
its own root, the same contract the builtin widgets follow.

```bash
qs ipc --any-display -p <store-path>/share/formalshell call plugins list     # the resolved manifests
qs ipc --any-display -p <store-path>/share/formalshell call plugins status   # {"directory":…,"loaded":…,"count":…,"bar":…,"surface":…,"service":…,"surfaces":[…],"errors":[…],"warnings":[…]}
qs ipc --any-display -p <store-path>/share/formalshell call plugins reload
qs ipc --any-display -p <store-path>/share/formalshell call panel open plugin:moon-phase
```

**Nothing watches the plugins directory.** A newly dropped plugin appears
after `plugins reload` or a shell restart, the same rescan-on-demand
contract the picker and the calendar's ics directory already have. A reload
closes every open plugin surface first, deliberately rather than as a
flicker.

Disable one without deleting it:

```jsonc
{ "plugins": { "disabled": ["moon-phase"] } }
```

A disabled id is skipped with no warning, since it was asked for. Changing
that list rescans on its own, so the toggle takes effect without a reload.

**Failure contract**, the same shape `bar.layout` has: nothing here is ever
fatal. A manifest that cannot be addressed at all (unparsable JSON, a
missing required key, the wrong `apiVersion`, an id that doesn't match its
directory, an unknown kind, an entry path escaping the directory) drops that
one plugin with one warning. Anything smaller drops one key back to its
default and keeps the plugin. An absent or empty plugins directory is zero
plugins and zero warnings, not an error.

**This is not a sandbox, and the isolation is smaller than it looks.** A
`Loader` catches load-time failures only: bad syntax, an unresolvable
import. Those render as a `PLUGIN ERROR` cell or a dim row in the card, and
land in `plugins status`'s `errors`. A plugin file that parses fine has the
exact same engine access as any built-in widget (`qs.Core`, `qs.Services`,
`Process`, `Quickshell.Io`) and can wedge or crash this single-process shell
outright. Nothing contains what a running plugin does.

`plugins status` is the only place a plugin's load outcome is readable from
outside the process. Plugin QML lives outside the repo, so `qmllint` never
sees it and a syntax error would otherwise exist only as an engine message
on stderr that nothing can read back.

## Instance lock

Launching `formalshell` replaces any instance already running — there is no
"two bars" state after a rebuild-and-respawn. On startup the shell binds a
lock at `$XDG_RUNTIME_DIR/formalshell/instance-$WAYLAND_DISPLAY.sock`; if a
live instance already holds it, the new process asks it to quit, waits for it
to exit, and takes over the same lock. This works no matter how the shell is
launched (a compositor `spawn-at-startup`, a terminal, a keybind) and survives
across rebuilds, since the lock lives in the runtime directory rather than
under the nix store path a given build happens to have.

The lock is scoped to one compositor, not one login: a shell running in a
nested test session (`dev/smoke-*.sh`) shares the host's `XDG_RUNTIME_DIR` but
has its own `WAYLAND_DISPLAY`, so it never asks the desktop's real bar to quit.
