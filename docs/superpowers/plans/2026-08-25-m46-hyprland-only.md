# M46: Hyprland only

**Date:** 2026-08-25
**Status:** approved, pre-implementation
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
("Hyprland first", "Keyboard model", "Deletions"). Spec wins on conflict.
**Builds on:** M41's rig (`dev/smoke.sh`, Hyprland on `vkms` in the VM,
nested on a host) and every leg M42 to M45 ported into it.

## Why

`dev/smoke-niri.sh` still carries 45 legs; `dev/smoke.sh` has about 15.
Everything the niri script proves that the Hyprland script does not is a
surface nobody can verify once niri goes. So the port comes first, the
deletion last, and the screenshots and the keybind config land in between.

## Scope

In: a per-leg layout for `dev/smoke.sh`, every remaining leg ported,
`Compositor/niri/` and every niri-only path deleted, the Hyprland colour
template, the full example keybind config, `docs/screenshots/` recaptured,
`CLAUDE.md`'s verification section rewritten around `dev/smoke.sh`, docs
swept of niri. Out: new features; M45 Task 3's sweep (separate).

## Locked decisions

- D1: `dev/smoke.sh` becomes a scaffold plus one file per leg under
  `dev/smoke.d/<leg>.sh`. The scaffold keeps the isolated HOME, the
  settings fixture, `dbus-run-session`, the host-bus assertion, the
  session mode pick (nested or `vkms`), the shell launch, the `SMOKE_OK`
  screenshot and teardown. A leg file declares its flag, its fixture
  additions (a function run before the shell starts), its timeline
  (a function run in-session with the sleep offset it needs) and its
  assertions. The scaffold sources every file, so adding a leg never edits
  `dev/smoke.sh`, and parallel ports never collide.
- D2: a ported leg proves what the niri leg proved, with Hyprland
  primitives: `niri msg -j` becomes `hyprctl -j`, `spawn-at-startup`
  becomes `exec-once`, workspace parking uses `special:formalshell-console`,
  output facts come from `hyprctl -j monitors`, layer facts from
  `hyprctl -j layers`. A leg that depended on a niri-only fact (the
  `--screensaver` output-priority walk over `niri msg outputs`) reads the
  Hyprland equivalent and keeps the same assertion. Nothing is dropped
  silently: a leg that cannot be ported is listed in the report with the
  reason, and CLAUDE.md says so.
- D3: `shell/Theme/templates/hyprland-colors.conf.tmpl` replaces
  `niri-border.kdl.tmpl`: `$primary`, `$border`, `$destructive`,
  `$background`, `$foreground` as `rgb(...)` written to
  `~/.config/hypr/formalshell-colors.conf`; the example config sources it
  and uses `$primary`/`$border` for `col.active_border`/`col.inactive_border`
  and `$destructive` for the urgent group colour. Hyprland reloads on
  write; `BackendBase.applyThemeFragment` and its niri implementation go.
- D4: `docs/examples/hyprland/formalshell.conf` carries the whole keybind
  table from the spec ("Keyboard model"), grouped as Omarchy groups them
  (utilities, media, clipboard), with `$fs = qs ipc call` or whatever
  form Task 6 of M42 established, the `toggleAt` binds already there, the
  colour source line, the blur layerrules. `Hyprland --verify-config` in
  the VM must pass on it.
- D5: `docs/screenshots/*-niri.png` are replaced by `*-hyprland.png`
  captured by the rig legs themselves (each leg already names its
  screenshot); `README.md` and `docs/USAGE.md` reference the new names.
- D6: `CLAUDE.md`'s "Verification loop" becomes a short list: one line per
  leg naming what it proves, pointing at `dev/smoke.d/<leg>.sh` for the
  detail. The 200 lines of per-leg prose move into each leg file's header
  comment, trimmed to what a reader needs.

## Tasks

### Task 1: leg framework

D1. Split the 15 legs `dev/smoke.sh` has after M45 into `dev/smoke.d/`,
scaffold unchanged in behaviour. Verify base, `--menu`, `--notify`,
`--panel network`, `--lock --wallpaper` still green with PNGs read.
Commit: `refactor(dev): one file per smoke leg`.

### Tasks 2 to 5: port the remaining legs (parallel worktrees)

D2. Groups: (2) `capture`, `capture-edit`, `screenshot`, `record`, `ocr`,
`gallery`, `share`; (3) `screensaver`, `screensaver-gif`, `tray`,
`chevron`, `bar-layout`, `visualizer`, `plugins`, `instance`, `prefix`;
(4) `media`, `mic`, `wifi`, `speedtest`, `nightlight`, `theme-toggle`,
`toggles`, `keybinds`, `panel-keys`, `reminder`, `systemupdate`, `polkit`;
(5) `gpu`, `processes`, `clipssh`, `dump` (beyond the basic call). Each
group verifies every leg it ports with the PNGs read and commits
`feat(dev): port the <group> smoke legs to hyprland`.

### Task 6: delete niri

D3 plus the deletions: `shell/Compositor/niri/`, `CompositorService`'s
backend pick, `BackendBase.applyThemeFragment`, `keybinds.js`'s KDL leg
and `keybinds.niriConfigPath`, `park.js`'s niri path, the niri tests
(`rg -l niri tests`), `dev/smoke-niri.sh`, `dev/vm.sh --compositor`,
`justfile smoke-niri`, `nix/testvm.nix`'s niri package, `Display/outputs.js`
niri branches, `ThemeEngine`'s niri template block. `rg -n -i niri shell
dev nix tests justfile` must return nothing. Docs: `docs/ARCHITECTURE.md`
("Reducer data flow (niri)" deleted, "Adding a backend" rewritten),
`docs/USAGE.md` (40 mentions), `docs/SWITCHOVER.md` if it is niri-specific.
Commit: `feat(compositor): hyprland only`.

### Task 7: keybinds and colours

D3's template and D4's config, with `hyprland-colors.conf` verified by the
`--wallpaper` leg (the rendered file's `$primary` equals `theme status`'s
primary) and `Hyprland --verify-config` on the example.
Commit: `feat(hyprland): shell colours and the full keybind set`.

### Task 8: screenshots, CLAUDE.md, README

D5, D6. Every rig leg with a named screenshot runs once more on the final
tree; the PNGs land in `docs/screenshots/*-hyprland.png`; README's
screenshot set and USAGE references updated; CLAUDE.md verification section
rewritten. Commit: `docs: hyprland screenshots and the leg index`.

## Done when

`rg -n -i niri shell dev nix tests justfile` is empty, every leg the niri
script had is either in `dev/smoke.d/` and green or named in CLAUDE.md as
unportable with the reason, the example config verifies, screenshots are
Hyprland captures, `just test` and `just vm-lint` pass.
