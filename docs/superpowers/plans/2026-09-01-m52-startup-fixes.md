# M52: startup reveal, model-identity churn, and the audit's fixes

**Date:** 2026-09-01
**Status:** in progress on `m52-startup-polish` (worktree, branched from
0d3ae65 while the chevron-overflow work is in flight on the main checkout;
whoever lands second rebases).
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(spec wins on conflict). `docs/DESIGN.md` is the rulebook.

## Owner's ask (2026-09-01)

"On startup for a few seconds when the shell is loading, I can see that the
shell still has to resize, which gives a buggy feel. I want caelestia level
polish." Plus a general fixes-and-optimizations pass.

## Diagnosis (root-cause pass, 2026-09-01)

Nothing gates first paint on readiness: `shell.qml` maps Background, Bar,
Frame and Toasts at process start, and only IdleService and NightLightService
read `Config.loaded`. The visible "still resizing" feel is the sum of:

1. ~11 bar cells carry an ungated `Behavior on implicitWidth`
   (tokens.js durMed 130ms), so every async service answer over the first
   seconds animates a cell open. The strip slides continuously.
2. The bar is destroyed and rebuilt at least twice after first paint:
   `Bar.qml` `_layout` is a raw binding over `Config.get("bar", ...)` and
   `PluginService.barPlugins`, and `layout.js` `_resolveRegion` returns
   fresh arrays every evaluation, so all three region Repeaters lose model
   identity when Config lands (`Config.qml:331` assigns a new `({})` even
   with no settings.json) and again when the plugin scan finishes
   (`PluginService.qml:155` assigns a fresh array even with zero plugins).
   Known failure class, `CLAUDE-troubleshooting.md:30`.
3. Window geometry is config-derived and settles after map (`_framed`,
   `bar.position`), the most violent case when it bites.
4. Palette flash: boot on zinc, hard cut when theme.json's FileView lands,
   full matugen pipeline (seconds on zinc) when there is no theme.json.
5. `Background.qml` spends its first-paint hard-cut path on the empty
   `State.wallpaper`, so the real wallpaper arrives via the 400ms crossfade
   off a zinc ground.
6. `ThemeEngine._publishHyprChrome` rewrites `formalshell-chrome.conf`
   unconditionally and fires `hyprctl reload` on every startup (both FileView
   branches), re-arranging every layer.
7. Workspaces and tray pop in unanimated once their sockets answer.

## Audit findings folded in (fixes A, optimizations B)

- A1 `PowerPanel` sits in a lazy `PanelSlot`, so `Power.warnEvent`'s only
  consumer does not exist until the battery cell is clicked: low/critical
  battery warnings never fire. Its own header claims the opposite.
- A2 `Center.qml` headroom slots render opacity-0 cards at y 0 without
  `visible: false`; opacity-0 items still hit-test, so the top row of each
  section is unclickable and handlers deref a null slot. `Toasts.qml:420`
  already guards this.
- A3 `_publishStatic` writes theme.json via truncate-then-write on the one
  file `Core/Theme.qml` watches; a reload catching the truncation flips the
  shell to fallback zinc. The matugen path already renames atomically.
- A4 `PolkitService`, `LocationService`, `AppleMusicArtService` read config
  before settings.json lands (agent registered then torn down, geoclue2
  D-Bus-activated against an explicit override, cache prune skipped).
- A5 A Process whose binary is missing emits no `exited`, so
  `ThemeEngine.running` and `RecordingService.finalizing` latch forever.
  `recProc` already carries the `onRunningChanged` FailedToStart guard.
- A6 `search.js` slugs the full dotted node id, so a single-letter query
  alias-matches every `apps.*` and `clipboard.*` node at tier 400.
- B1 `Workspaces.qml` feeds `visibleModel(workspaces, windows, ...)` straight
  into `model:`, so every window title tick rebuilds every dot, defeating
  the backend's own workspaces/windows split.
- B2 `Menu.qml` `_liveWindows` re-runs the whole tree build on title ticks
  while the launcher is open; `appmatch.js` only ever reads `appId`.
- B3 458KB of emoji JSON is parsed character-by-character by
  `Model.parseJsonc` at every boot; the only JSONC-ness is a 5-line `//`
  header. This is the M51 heap note's allocation behaviour.
- B4 An absent settings.json means `Config.qml`'s 300ms rewatch timer polls
  forever; `ConfigReopen`'s 5s tick already re-runs the open.
- B5 `HyprlandBackend.outputs` and `NetworkPanel._wifiSorted` republish
  without identity guards, rebuilding open-panel delegates every poll tick
  and dropping keystrokes in the wifi passphrase input mid-scan.
- B6 `search.js` recomputes `normalize(query)`/`slug(q)` per node per
  keystroke, and `_emojiRank` frecency-decorates and comparator-sorts ~3000
  emoji per keystroke when one emoji has ever been copied.

## The shape of the startup fix

A reveal gate, not a loading screen: hold the boot surfaces unmapped until
`Config.loaded && Theme._paletteReady && PluginService.loaded` (all three
flip on their failure branches too, none can hang), with a short Timer
backstop so a wedged FileView can never leave the screen bare. Map once at
final geometry (kills 3), publish the exclusive zone exactly once, then
reveal the bar content with the shell's own `Presence` grammar and only then
arm the cells' width Behaviors (kills 1). Model-identity guards kill 2. The
first real wallpaper hard-cuts (kills 5), the chrome file is only written
and Hyprland only reloaded when the rendered text changed (kills 6).

An unmapped layer surface reserves nothing, so tiled windows shift once when
the bar maps: one shift under the reveal, versus seconds of reflow now.
Never re-set `exclusiveZone` after map (`Bar.qml:105` documents the frozen
zone bug); `ExclusionMode.Auto` stays the mechanism.

## Tasks (one subagent each, sequential)

1. **Model-identity guards.** Keep `Config.settings` identity when the
   resolved object is JSON-equal (covers the `({})` reassign), guard
   `PluginService.plugins`, `HyprlandBackend.outputs`, the Workspaces
   visible model, `NetworkPanel._wifiSorted`, and memoize Bar `_layout` on
   the resolved regions' JSON. Key `Menu._liveWindows` on a derived
   `id + "\0" + appId` string. (Causes 2, B1, B2, B5.)
2. **Startup reveal.** The ready gate plus backstop, mapped-once boot
   surfaces, `Presence`-driven bar reveal, Behavior arming, and the
   Background first-paint fix. (Causes 1, 3, 5, 7.)
3. **Theme pipeline.** Byte-compare before writing the chrome file and
   before `hyprctl reload`, hold the retheme Connections until
   `Config.loaded`, atomic `_publishStatic`, FailedToStart guards in
   ThemeEngine and RecordingService. (Causes 4, 6; A3, A5.)
4. **Correctness batch.** Eager PowerPanel (A1), Center headroom
   `visible` guard (A2), the three `Config.loaded` service gates plus the
   prune call (A4), rewatch retry cap (B4).
5. **Launcher batch.** Last-segment slug (A6), native emoji parse plus lazy
   emoji FileView (B3), per-keystroke hoisting and ledger-only emoji
   reorder (B6).
6. **Docs.** DESIGN.md startup paragraph, memory-bank touch-ups, this
   plan's status.

Verification per task: `just build` from the worktree, `just vm-test`, and
the smoke legs the task touches (`--bar-layout`, `--wallpaper`,
`--theme-toggle`, `--center`, `--menu`, `--emoji`, `--workspaces`), run
individually where the M51 plan records combined-run rig races. Every VM
command from this worktree goes through `dev/vm-lock.sh`.
