# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Standing orders

- Plans are created autonomously — no user approval gate before writing one.
- Implementation, mapping, testing, and docs all run through subagent
  workflows (one subagent per plan task, sequential, verification evidence
  required before commit — see `docs/superpowers/plans/`).
- The approved design lives at `docs/superpowers/specs/`. Plans live at
  `docs/superpowers/plans/`. **The spec wins over any plan on conflict.**

## Verification loop

- `just build` — `nix build .#formalshell`. **`git add` first**: flakes only
  see git-tracked files, so an unstaged file is invisible to the build.
- `just test` — headless `qmltestrunner` over `tests/` (`QT_QPA_PLATFORM=offscreen`).
- `just lint` — `nix flake check -L` (qml-tests + qmllint).
- `just smoke` — builds the shell, launches it inside an isolated **nested**
  niri session, screenshots that session, tears it down, and prints the PNG
  path. This is THE visual verification loop for any bar/surface change —
  **Read the PNG, don't assume it looks right.**
- `dev/smoke-niri.sh --wallpaper` — same, plus generates a solid-color test
  PNG, drives it through the `wallpaper set` and `theme status` IPC targets
  in-session before screenshotting, and prints the `theme status` JSON. This
  is THE visual verification loop for any theming change — confirms the
  background layer and bar tokens actually recolored away from the Flexoki
  fallback, not just that `theme.json` was written. It then crossfades to a
  SECOND wallpaper, a gradient, and samples both frames for the dither
  contract (DESIGN.md §2 item 12): the solid one must be its own exact color
  end to end (`wallpaper-solid.png` — an image-derived palette holds a
  monotone source's own color, so it must paint with no dots at all), and a
  full-width strip of the gradient must carry at least three colors and no
  more than `wallpaper.ditherColors` of them. The dither never reaches
  matugen either way: `ThemeEngine` runs `matugen image <path>` against the
  wallpaper FILE, and nothing dithered is ever written to disk.
- `dev/smoke-niri.sh --dump` — same, plus calls the `debug` IPC target and
  cats the JSON reply; the two flags can combine.
- `dev/smoke-niri.sh --menu` — same, plus drives the `menu` IPC target
  in-session: `summon` opens it at root, `debug query` ranks a fuzzy search
  against the live tree, `select` switches it into select mode (the
  screenshot lands here — ledger cells, inverted cursor row, uppercase
  breadcrumb), then `close` cancels the pending select and the resulting
  `menu-selection.txt` is read back to confirm the `{cancelled:true}` write.
  Combine with `--wallpaper` to verify the menu over matugen-recolored
  colors (`docs/screenshots/menu-niri.png` is captured this way).
- `dev/smoke-niri.sh --notify` — same, plus fires `notify-send -u normal`
  then `-u critical` in-session and screenshots the resulting toasts (normal
  card + a full-bleed accent cell for the critical one).
- `dev/smoke-niri.sh --center` — same as `--notify` (combine the two flags),
  plus fires one more `notify-send`, waits for it to auto-expire into
  `pending`, then summons the notification center over the `notifications`
  IPC target and screenshots it (DND cell, `PENDING / n` header, per-row
  cells). The sticky critical popup from `--notify` is still live in
  `NotificationService.popups`, but Toasts.qml suppresses its own
  Overlay-layer stack for as long as the center is open (both surfaces are
  top-right anchored, so left un-suppressed the popup would sit on top of
  the center's own corner) — the screenshot shows the center alone, and the
  popup reappears once the center closes.
- `dev/smoke-niri.sh --osd` — drives the bottom-center OSD three ways: a
  manual `qs ipc call osd volume` (screenshotted separately as
  `osd-manual.png`), a real `wpctl set-volume @DEFAULT_AUDIO_SINK@ 30%` (the
  `AudioService.changed` auto-show trigger, screenshotted as this run's
  `SMOKE_OK` artifact), then `qs ipc call osd brightness` (screenshotted as
  `osd-brightness.png`). On a host/VM with no default sink or no backlight
  device, the corresponding leg still renders the card honestly (0%, empty
  fill) rather than faking a value — that's proof the surface works, not
  proof hardware exists.
- `dev/smoke-niri.sh --panel <name>` — same, plus drives the real `panel`
  IPC route: `qs ipc call panel open <name>` opens the named popout (no
  bar-cell click happened, so `Panel.qml`'s `anchorX` stays unset and the
  frame falls back to sitting under the bar's right region), left open
  through the run's normal screenshot. `name` is one of
  `audio`/`calendar`/`network`/`bluetooth`/`power`/`weather` — the panels
  registered in `PanelIpc.qml`'s registry. `--panel calendar` additionally
  proves real events render: the isolated `HOME` carries a one-event `.ics`
  fixture dated today, pointed at by `settings.json`'s `calendar.icsDir`.
- `dev/smoke-niri.sh --clipboard` — same, plus `wl-copy`s three fixture
  strings, dumps `clipboard list` twice (proving capture, newest-first
  order, and that re-copying an existing entry moves it to the front rather
  than duplicating it), then activates a second entry via the exact
  self-targeting `qs ipc --any-display -p <shellDir> call clipboard copy
  <id>` invocation `Menu/providers.js`'s `clipboardProvider` builds and
  reads the system clipboard back to confirm it landed, before summoning
  the menu's `clipboard` route so the screenshot shows the provider's rows
  rendered as real menu cells.
- `dev/smoke-niri.sh --clipssh` — writes a two-alias `~/.clipssh/aliases`
  into the isolated HOME and drives the menu's clipssh route over `menu
  activate` (the rig's Enter stand-in) against a PATH-shimmed `clipssh`
  speaking the real one's output contract: `box` takes six seconds and
  succeeds, `nohost` fails at once. Four frames off one timeline —
  `clipssh-route.png` (both rows), `clipssh-sending.png` (in flight: the
  bar's own indicator cell plus the SENDING toast), `clipssh-copied.png`
  (COPIED, carrying the remote path clipssh printed), `clipssh-failed.png`
  (a full-bleed urgent card carrying clipssh's own `Error:` line). The shim
  stands in for the binary because what needs proving is the shell's path
  (row → `@ipc:clipssh.send:` → `ClipsshService` → `Process` → exit code →
  toast + indicator), not whether the rig can reach an ssh host; same line
  `--panel github`'s `gh` shim draws.
- `dev/smoke-niri.sh --media` — plays a real MPRIS player in-session (`mpv`
  with its own `mpris.lua` script, a generated silent fixture track tagged
  with a title/artist, into the pipewire null sink), opens the media panel
  over the `panel` IPC route, and screenshots it (album art cell, `NOW
  PLAYING / mpv` meta row, transport cells, flat progress fill). `media
  status` is dumped and cross-checked against the fixture track's own tags
  before mpv is killed by PID.
- `dev/smoke-niri.sh --lock` — drives the whole lock round trip over real
  PAM. First, before the nested session even starts, runs
  `result/bin/formalshell-lock-before-sleep` with **no shell instance
  running at all** and records its exit code (must be `0` — the
  `lock-before-sleep` exit-0-always contract, spec §8). Then in-session:
  `lock lock` over IPC (screenshotted as `lock-locked.png` — the shared
  `AuthPrompt` plate: oversized clock, blurred wallpaper backdrop if
  `--wallpaper` is combined in, one 3px-outlined field), `lock isLocked`
  confirms `true`, `wtype` (a real virtual-keyboard-unstable-v1 client —
  `LockIpc.qml` deliberately has no "type this password" shortcut) types a
  wrong password and Return (screenshotted as `lock-error.png` — the field's
  border swaps to `urgent`, italic uppercase `WRONG PASSWORD` message), then
  retypes the VM's real throwaway test
  password (`nix/testvm.nix`'s `users.users.test.password`) and Return
  (screenshotted as `lock-unlocked.png`), with `lock isLocked`/`lock status`
  proving the round trip flipped back to unlocked.
- `dev/smoke-niri.sh --screensaver` — shortens `screensaver.timeoutSeconds`
  to 3s via the isolated settings.json fixture (a real `IdleMonitor`, not a
  fake clock) and plays the same fixture track `--media` uses so
  `MediaService.isPlaying` is genuinely true. Proves the live media guard
  (`screensaver status` reports `active:false` even though `isIdle` already
  reads `true`), then kills mpv and waits past the timeout to prove the
  screensaver auto-activates purely from the guard clearing — no
  `screensaver start` call involved — screenshotted (`screensaver-auto.png`,
  the block-character `FORMALSHELL` banner converging via one of ttfx's 37
  effects, in the mono font and that effect's own upstream gradient;
  `SCREENSAVER_EFFECT`/`SCREENSAVER_ASCII_TEXT` env vars pin an
  effect or banner for a single run). `screensaver
  stop` dismisses it, then a final explicit `start`/screenshot
  (`screensaver-manual.png`)/`stop` proves the manual IPC path
  independently of the idle timer.
- `dev/smoke-niri.sh --screensaver-gif` — records five ttfx effects as GIFs,
  one independent nested-niri session per effect: pins `screensaver.effect`
  via the settings fixture, starts the screensaver, pins `screensaver frame
  0` (which is what makes a streaming run's frame count knowable at all),
  reads that count off `screensaver frameInfo`, then steps `screensaver
  frame(n)` across a strided sample of the run plus an 8-frame hold on the
  converged banner, `grim`-screenshotting each (frame-stepped, not
  wall-clock-timed, so the VM's llvmpipe rendering can't produce uneven
  spacing) before assembling `docs/media/screensaver-<effect>.gif` with
  imagemagick (resized to 640px wide, palette capped, `-layers Optimize`,
  frame delay derived from the stride so playback is real time). Confirms
  `frameInfo` reports the pinned effect name **and** `"engine":"ttfx"`
  before accepting the run — a missing ttfx would otherwise record a
  perfectly plausible GIF of the builtin fallback. `matrix`/`thunderstorm`
  are deliberately not in the list: both are gated on wall-clock time, so
  the same frame index means something different on the next machine.
- `dev/smoke-niri.sh --picker` — generates a handful of solid-color fixture
  PNGs (imagemagick) into a directory pointed at by settings.json's
  `picker.directory`, then drives the `picker` IPC target: `summon` opens
  the wallpaper-mode grid (screenshotted as `picker-grid.png` — cursor cell
  inverted, ledger rules shared between cells), `choose` picks a non-first
  fixture — the same action Enter/click on a cell take, exposed over IPC
  rather than depending on unproven real keyboard/pointer delivery into an
  `OnDemand`-focus layer surface — and `theme status` confirms it actually
  became the wallpaper. Then `select` reopens the grid over the same
  directory in the generic image-selector mode with a caller token,
  `choose` picks a different fixture, and `picker-selection.txt` is read
  back to confirm `{token, value}` landed. Every leg above runs against a
  FLAT directory (`picker-status-flat.json`: `hasVariants:false`, all 20
  images), then staged `Dark`/`Light` subdirectories are moved into place
  underneath the running shell and the route re-summoned — which also proves
  the scan re-runs per entry: `picker-status-dark.json` must report the theme
  mode's own set, `picker variant light` (the `DARK | LIGHT` switcher's own
  action over IPC, same division as `choose`) must answer `ok`, and
  `picker-variant.png`/`picker-status-light.json` must show the other set.
- `dev/smoke-niri.sh --hotcorner` — asks niri itself (`niri msg -j layers`)
  which layer surfaces exist and asserts exactly two carry the
  `formalshell:hotcorner` namespace, on the `Top` layer with
  `keyboard_interactivity: None`. Two, not four: the default corner set
  leaves both TOP corners at "none" (the bar owns that edge) and this run
  writes no `hotCorners` config at all, so the count also proves a corner
  set to "none" costs no surface. Entering a corner cannot be driven here —
  the rig has no synthetic pointer, same limit the tray's overflow cell hits
  — so what this leg proves is that the surfaces map, at the resolved
  corners, with the per-corner `PanelWindow.anchors` bindings intact.
- `dev/smoke-niri.sh --tray` launches six real `dev/sni-stub.py`
  StatusNotifierItem producers (a minimal PyGObject SNI client, registers
  for real on the isolated session bus, never faked inside the shell),
  dumps `tray status` (proves all six registered, and that no drawer,
  bucket or expand key comes back at all) and screenshots the whole strip
  (`tray-strip.png`), then calls `tray activate tray-fixture-2` and reads
  the stub's own `--activate-file` back to prove the D-Bus Activate round
  trip reached that item and only that item. Six items with no visible
  limit is the point since M24: every one is its own cell, and bounding a
  long strip is the bar chevron's job (`--chevron` below), not the tray's.
  The stub processes are killed by PID right before niri quits.
- `dev/smoke-niri.sh --chevron` points `settings.json`'s `bar.layout` at
  today's exact default right region reordered around `chevron`: the five
  governed names (bluetooth/weather/tray/bell/indicators) lead the region,
  then `chevron`, then battery/audio/network sit outboard against the screen
  edge. A right-region chevron governs what PRECEDES it (M25), so the group
  opens inward into empty bar and the chevron plus every cell outboard of it
  keeps its x: that is what the two screenshots are read for, as much as
  which cells appeared. The bar boots collapsed, which is the shipped default
  and the claim itself: `bar chevron status` is dumped and asserted
  (`chevron-status-collapsed.json` must name exactly one chevron region and
  report the five names before it under both `collapses` and `hidden`), then
  screenshotted (`chevron-collapsed.png`). `bar chevron expand` follows, the
  rig's stand-in for a click on the cell since no synthetic pointer exists
  here, deliberately with no region argument because a single-chevron layout
  is meant to infer it; the second dump must show `hidden` empty with
  `collapses` unchanged, and the second shot is `chevron-expanded.png`, taken
  three seconds after the expand so the animated reveal
  (`Theme.motion.standard`, 130ms) is long settled and the frame is the end
  state rather than one mid-glide. The two PNGs are then asserted to differ,
  the cheapest guard there is against shipping a correct IPC contract over a
  bar that rendered nothing. Both carry a `SMOKE_CHEVRON_*` marker line so
  `dev/vm.sh` pulls them back to the mac. ⚠️ Any file reaching the `State`
  singleton while also importing QtQuick must `import qs.Core as Core` and
  say `Core.State`: QtQuick exports its own `State` type, and the bare name
  silently reads back undefined, which is exactly how M24's chevron shipped
  rendering-dead while its own IPC status reported the right answer.
- `dev/smoke-niri.sh --bar-layout` — points `settings.json`'s `bar.layout`
  at a left region led by six `bar.modules` entries (swapped ahead of the
  reordered builtins — `activeWindow` before `workspaces`, away from
  today's default): one `command` module printing known Waybar-JSON
  (happy path), four more each exercising one of `CommandModule.qml`'s
  failure paths (non-zero exit, malformed JSON, a run that outlives its
  configured timeout, a binary that doesn't exist at all), and a `qml`
  module (a fixture file that itself imports `qs.Core` and reads `Theme`,
  proving a loaded user component shares the shell's own engine). No drive
  script needed — `Bar/layout.js` resolves this from `settings.json` at
  startup like any other `Config`-driven surface — so the run's own
  `smoke.png` already shows all of it; `bar-layout.png` is the same shot
  under a name that doesn't depend on remembering which run produced
  `smoke.png`. Every other mode still omits the `bar` key entirely, so
  their own screenshots keep proving the no-config fallback renders today's
  exact default arrangement.
- `dev/smoke-greeter.sh` (`just vm-greeter`) — a sibling of the other smoke
  scripts, not a flag on `smoke-niri.sh`: greetd's `default_session`
  (`nixosModules.formalshell-greeter`) is a persistent system service, not a
  fresh nested compositor composed per run, so this drives the
  **already-running** `formalshell-greeter` session instead of spawning one.
  Restarts greetd for idempotency, waits for the greeter's own Wayland
  socket (`/run/formalshell-greeter`), screenshots pre-auth, then types a
  wrong password and the VM's real throwaway `test` password via `wtype`
  across the `test` -> `greeter` system-account boundary (`sudo env
  XDG_RUNTIME_DIR=... WAYLAND_DISPLAY=... grim`/`wtype` — root bypasses the
  greeter runtime dir's 0700 mode the same way it bypasses any other user's
  files). Fails loudly unless the session log shows a real
  `pam_authenticate: AUTH_ERR` on the wrong attempt and `Authentication
  complete.` / `Quitting.` on the real one; pulls both screenshots plus the
  session log and `journalctl -u greetd` into `artifacts/greeter/`.
- `dev/smoke-hyprland.sh` — the same loop for the second backend (nested
  Hyprland, `hyprctl`/exec-once instead of niri's `spawn-at-startup`). Nested
  Hyprland is flakier than nested niri in a sandboxed dev environment; if it
  won't screenshot, fall back to verifying the backend via qmllint plus the
  `debug` IPC dump (`qs ipc call debug dump`) rather than skipping
  verification.
- matugen runs (`ThemeEngine`) need a live TTY-free source-color decision: an
  unforced `matugen image` prompts whenever an image yields more than one
  candidate (50 of the owner's 57 wallpapers do), which hangs forever under
  `Process` (no stdin). `--prefer` answers that prompt with a scalar tiebreak
  over the candidates, and every one of them is a bad proxy for "what color
  is this wallpaper": the old fixed `--prefer lightness` read a small warm
  highlight as the image's color, which is what turned blue wallpapers orange
  (2026-08-14). `ThemeEngine` now probes first (`matugen -d image <wp>
  --dry-run`), reads rank 0 off the ranking matugen prints on stderr (its own
  material Score order), and pins the real run to it with `--prefer
  closest-to-fallback --fallback-color <rank0>`; a probe that finds no
  ranking falls back to `--prefer saturation` and warns. Whichever path runs,
  the pick is a function of the wallpaper alone, never of `State.mode`:
  matching it to the mode made the same wallpaper flip hue family across a
  mode toggle (2026-08-09). If you invoke matugen by hand while debugging,
  force the source the same way rather than letting `--prefer` choose.

## macOS verification loop (mac e2e rig)

Both Linux hosts (g815, e1504g) are reachable again over ssh, and both were
rebuilt onto HEAD on 2026-08-12 (`nix flake update formalshell` in
`~/.config/nix`, then `sudo nixos-rebuild switch --flake .#<host>`; both have
passwordless sudo, and their `formalshell.service` user unit restarts onto the
new store path as part of the home-manager activation — their nix config
consumes this repo as `github:FormalSnake/FormalShell`, so a change has to be
pushed before a rebuild can pick it up). That makes them the place to confirm
what the VM's llvmpipe/no-desktop-bus environment cannot show — real GPU
rendering, a real session bus owner, real hardware devices — but it does NOT
make them a test target: the host-session-safety and lock-screen rules below
still forbid running the shell, the ThemeEngine or any compositor action
against a live session there. Rebuild them and look; anything that drives a
surface goes through the nested rig.

Sessions themselves run from a macbook, which has no Wayland at all, so that
rig is where verification happens. nix-darwin's `nix.linux-builder.enable` is
unavailable under `determinateNix.enable = true`, so it is hand-rolled as two
layers, both driven from this repo
(`docs/superpowers/plans/2026-07-28-mac-e2e-rig.md` has the full design
rationale):

- **Build layer** — `dev/linux-builder.sh {start|stop|status|register}` boots
  the stock `darwin.linux-builder` VM in the background and registers it in
  `/etc/nix/machines`, giving `nix build .#packages.aarch64-linux.<x>` a real
  remote builder from the mac. Its only job is compiling aarch64-linux
  closures (`formalshell`, quickshell, the testvm image itself); it does not
  run any part of the shell.
- **Runtime layer** — `nixosConfigurations.testvm` (`nix/testvm.nix`,
  `packages.aarch64-darwin.testvm`) is a headless aarch64 NixOS VM booted
  under HVF, pre-staged with `formalshell`/quickshell/niri/sway/matugen so
  in-VM builds are near no-ops. Inside it, a systemd **user** service runs a
  headless wlroots parent compositor (sway, `WLR_BACKENDS=headless`,
  `WLR_RENDERER=pixman`) publishing `WAYLAND_DISPLAY` into the systemd user
  environment — the same lookup `dev/smoke-niri.sh` already falls back to on
  a real host. `dev/smoke-*.sh` then run **completely unchanged** inside,
  nesting their own niri/Hyprland as a winit/wayland client of that parent
  (software rendering throughout — Mesa llvmpipe for the nested compositor's
  EGL, pixman for the parent — the same concession any CI-grade wlroots
  testing makes).

`dev/vm.sh` is the driver: `start` (build+boot headless, wait for ssh),
`stop`, `status`, `sync` (rsync the **working tree** — not a commit — into
`~/formalshell` inside the VM), `run <cmd…>` (ssh with cwd at the repo and
the session env exported), `smoke [flags…]` (sync, run `dev/smoke-niri.sh`
inside, then `scp` the `SMOKE_OK` screenshot plus any dump/status/query JSON
back to `./artifacts/` on the mac; `--screensaver-gif` additionally rsyncs
the VM's `docs/media/screensaver-*.gif` straight into the real repo's
`docs/media/` on the mac, since those are committed output, not scratch
artifacts — otherwise the next `sync`'s `rsync --delete` would just wipe the
VM's copies before anyone could commit them), `shell` (interactive ssh). `justfile`
wraps this as `vm-up`/`vm-down`/`vm-build`/`vm-test`/`vm-lint`/`vm-smoke
*FLAGS`/`vm-greeter` — the mac-side equivalents of
`build`/`test`/`lint`/`smoke`/`dev/smoke-greeter.sh` above (`vm-greeter`
syncs, runs `dev/smoke-greeter.sh` inside, then pulls `artifacts/greeter/`
back with a plain `scp` — greetd's `default_session` is a standing system
service already up in the VM, not a fresh nested compositor `vm-smoke`
spins up itself, so it needs no flag of its own).
Screenshots and JSON always land on the **mac** filesystem under
`./artifacts/` (gitignored) — Read-verify them there exactly as you would
`result/`'s output on a Linux host.

The VM has no real desktop bus owner (nothing on the mac plays the role DMS
plays on the Linux hosts), so `busctl --user status
org.freedesktop.Notifications` legitimately answers ENXIO/no-owner every
run; `dev/smoke-niri.sh`'s D-Bus isolation check tolerates that (`|| true` —
a real "no owner" answer, not a connectivity failure) without changing
behavior on hosts where a real owner exists.

## Hard rules

- **Host-session safety**: the owner's live niri session is NOT a test target.
  Never run the shell, the ThemeEngine, or any compositor action (especially
  `load-config-file` / `applyThemeFragment`) in an environment carrying the
  host's `NIRI_SOCKET`/`HYPRLAND_INSTANCE_SIGNATURE` — all runtime testing
  happens inside nested sessions via `dev/smoke-*.sh` (which scrub and restore
  the env). If you must run `qs` ad hoc, `unset NIRI_SOCKET` first or export
  the nested session's socket explicitly. Observed failure mode: host niri
  config reloads firing during isolated testing (2026-07-27).
- **Lock-screen safety**: never run a lock surface (`Lock.qml`'s
  `WlSessionLock`) against anything but a nested test session. All lock
  testing happens inside the nested niri/Hyprland session `dev/smoke-*.sh`
  boots and tears down; a lock bug there is harmless (the whole nested
  compositor gets killed regardless), but the same bug against a real host
  session would leave it genuinely locked. This is the same nested-only
  contract the general host-session-safety rule above already establishes,
  called out separately here because a stuck lock is a much worse failure
  mode than a stuck bar.
- **D-Bus isolation**: the shell's `NotificationService` acquires
  `org.freedesktop.Notifications` on the session bus via
  `Quickshell.Services.Notifications.NotificationServer`. The owner's live
  session bus is owned by DMS on the Linux hosts — NEVER run the shell's
  notification stack against the host bus, acquiring that name would steal it
  out from under the real desktop. `dev/smoke-niri.sh` and
  `dev/smoke-hyprland.sh` wrap the whole nested compositor invocation in
  `dbus-run-session --`, giving every nested run (and `notify-send` fired
  inside it) a private bus; both scripts assert `busctl --user status
  org.freedesktop.Notifications`'s owner PID on the **host** bus is unchanged
  before and after every run (`|| true`-tolerant of a legitimate "no owner"
  answer, e.g. on the mac VM rig, which has no desktop bus owner at all).
- **Design language**: every UI surface follows `docs/DESIGN.md` — Omarchy
  quattro close reference (four-state control tokens, border specs, rem/
  spacing scale roots, bordered floating cards), mek.gallery as an ASCII-OS
  accent on tabular content (ruled rows, uppercase meta labels, fg/bg
  inversion for selection, accent as full-bleed cells), radius 0, monospace,
  DMS for feature ideas only. Read it before building or restyling any
  surface.
- **`panel` IPC target is a spec addendum, not a conflict.** The design
  spec's §IPC target list (`docs/superpowers/specs/2026-07-27-formalshell-design.md`)
  predates per-widget popouts and doesn't name `panel`. The M6 plan added it
  (`panel.open(name)`, `close()`, `toggle(name)`, `state()`) because
  per-widget popouts otherwise have no summon path for compositor keybinds
  and no way to be verified headlessly in the smoke rig — treat it as part
  of the IPC contract going forward, alongside `menu`/`osd`/`notifications`/
  `clipboard`/etc. Unknown panel names return an error string, never a
  silent no-op.
- **Honest unavailable states, never faked data**, as a standing expectation
  for every VM smoke run: a panel/widget with nothing to show from its
  backend renders a single dim cell (`NO ADAPTER`, `NO DEVICES`,
  `NO LOCATION`, an absent battery bar cell, …) rather than a stubbed value
  or an invented device. Enabling a real service in `nix/testvm.nix` so a
  panel has a genuine backend to talk to is the sanctioned way to make a
  screenshot show more — inventing fake `/sys` entries or synthetic devices
  is not.
- Pure QML/JS. No compiled companion binary. No Node/npm/bun anywhere.
  Third-party CLIs the shell shells out to (matugen, grim, cava, ttfx, …)
  are runtime dependencies wired onto the wrapper's PATH in
  `nix/package.nix`, not companion binaries: nothing here is built from
  source we maintain, and every one of them has an honest fallback or
  unavailable state when it isn't installed.
- **ttfx is a spec addendum, not a conflict.** Spec §10 says the
  screensaver renders "TTE-style rain/decrypt/matrix drawn in QML with the
  shell's mono font and palette — no spawned terminal windows". The
  screensaver now runs `ttfx` (`nix/ttfx-package.nix`) as a frame source and
  parses its ANSI stream, still drawing every glyph itself on its own
  Canvas in the shell's own mono font, with no terminal window anywhere —
  what moved out of QML is the frame math, and with it the palette, since
  each ttfx effect carries its own gradient (owner's call: match omarchy
  exactly, 2026-08-11). `shell/Screensaver/effect.js` stays as the engine
  for an install with no ttfx on PATH, so the pure-QML/JS guarantee above
  still holds with nothing installed alongside the shell. `screensaver
  frameInfo` reports which engine is live.
- Compositor window/workspace ids are **opaque strings** end to end. Never
  parse, compare numerically, or assume stability. The one exception is the
  IPC wire boundary in each backend, where niri/Hyprland actions convert the
  string back with `Number(id)` (niri) or use the id verbatim (Hyprland hex
  addresses) — that conversion happens nowhere else.
- The shell only ever **reads** `~/.config/formalshell/settings.json`; it
  never writes it. Runtime-mutable state goes to
  `$XDG_STATE_HOME/formalshell/state.json`.
- Brutalist defaults, non-negotiable: corner radius `0`, no blur, no
  shadows, border width `2`, font = fontconfig `monospace` alias (never a
  hardcoded family name), icons = Nerd Font glyphs (no SVG icon sets). The
  lock screen's blurred wallpaper backdrop (`LockSurface.qml`'s client-side
  `MultiEffect`, DESIGN.md's one named exception) is the **only** blur
  anywhere in the shell — never add blur to any other surface, and never
  reintroduce a `ScreencopyView`-based capture for it (see `LockSurface.qml`'s
  header comment: it crashes the whole shell outright, a fail-open on a
  security-critical surface).
- License MIT. Every file substantially ported from DankMaterialShell keeps
  a `// Portions from DankMaterialShell (MIT, Copyright 2025 Avenge Media LLC)`
  header line.
- ⚠️ Nerd Font glyphs are raw multi-byte codepoints; whole-file rewrites can
  corrupt them (Omarchy's `AGENTS.md` documents this). Use targeted `Edit`
  operations on files containing glyphs; never rewrite such files wholesale.
- ⚠️ Quickshell percentage/fraction-shaped properties are 0..1, not 0..100
  (`UPowerDevice.percentage`, `WifiNetwork.signalStrength` — both confirmed
  from C++ source: `src/network/wifi.hpp:22`, `src/network/nm/network.cpp:260`).
  This has already caused two shipped bugs. Verify any such property against
  its C++ source before rendering it.
- Commits: conventional style, lowercase imperative subject
  (`feat(compositor): …`), no Co-Authored-By lines, no commit descriptions.
- Every task ends with its verification commands actually run and their
  output read. No claiming green without evidence.

## Reference repos

- `github.com/basecamp/omarchy` (branch `quattro`) — architecture/UX
  reference (single-process shell, unified surfaces, IPC contract patterns).
  Read, don't copy — treat as read-reference only; check its license before
  ever porting code from it.
- `github.com/AvengeMedia/DankMaterialShell` (MIT) — niri/Hyprland backend
  prior art and matugen orchestration patterns. MIT, so code can be ported
  directly, but every substantially-ported file needs the attribution
  header above.
- QuickShell source/docs (`git.outfoxxed.me/quickshell/quickshell`, pinned
  flake input) — ground truth for toolkit APIs (`Quickshell.Io.Socket`,
  `IpcHandler`, `Quickshell.Hyprland`, `Singleton`, …). When a QML/JS API's
  behavior is uncertain, read the C++ source or run the built `qs` binary
  rather than guessing.
