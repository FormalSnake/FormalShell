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
  fallback, not just that `theme.json` was written.
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
  `lock lock` over IPC (screenshotted as `lock-locked.png` — oversized
  clock, blurred wallpaper backdrop if `--wallpaper` is combined in, one
  bordered input cell), `lock isLocked` confirms `true`, `wtype` (a real
  virtual-keyboard-unstable-v1 client — `LockIpc.qml` deliberately has no
  "type this password" shortcut) types a wrong password and Return
  (screenshotted as `lock-error.png` — inverted input cell, uppercase
  `WRONG PASSWORD` meta row), then retypes the VM's real throwaway test
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
  full-screen matrix-rain in the mono font/theme accent). `screensaver
  stop` dismisses it, then a final explicit `start`/screenshot
  (`screensaver-manual.png`)/`stop` proves the manual IPC path
  independently of the idle timer.
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
  back to confirm `{token, value}` landed.
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
- matugen runs (`ThemeEngine`) need a live TTY-free color decision: an
  unprefixed `matugen image` prompts on an ambiguous/near-solid source color,
  which hangs forever under `Process` (no stdin). `ThemeEngine` always passes
  `--prefer darkness|lightness` matched to `State.mode`. If you invoke
  matugen by hand while debugging, do the same or pass `--fallback-color`.

## macOS verification loop (mac e2e rig)

The Linux hosts (g815, e1504g) are currently offline. Until one returns, a
macbook running Determinate Nix under nix-darwin is the only place any of
this gets verified — nix-darwin's `nix.linux-builder.enable` is unavailable
under `determinateNix.enable = true`, so the rig is hand-rolled as two
layers, both driven from this repo (`docs/superpowers/plans/2026-07-28-mac-e2e-rig.md`
has the full design rationale):

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
back to `./artifacts/` on the mac), `shell` (interactive ssh). `justfile`
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
