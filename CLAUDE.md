# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Standing orders

- Plans are created autonomously — no user approval gate before writing one.
- Implementation, mapping, testing, and docs all run through subagent
  workflows (one subagent per plan task, sequential, verification evidence
  required before commit — see `docs/superpowers/plans/`).
- The approved design lives at `docs/superpowers/specs/`. Plans live at
  `docs/superpowers/plans/`. **The spec wins over any plan on conflict.**
- Since 2026-08-25 the approved design is
  `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md` (Omarchy
  behaviour, shadcn chrome, wallpaper palette, keyboard everywhere, Hyprland
  only). The 2026-07-27 spec still holds for architecture, IPC and config;
  the 08-25 spec wins where the two disagree.

## Verification loop

- `dev/smoke.sh` (`just vm-smoke <flags>`) is the rig now: nested Hyprland
  by default, `--compositor niri` runs the old `dev/smoke-niri.sh` instead.
  Legs ported so far: base, `--menu`, `--notify`, `--panel <name>`,
  `--console`, `--picker`, `--hotcorner`, `--wallpaper`, `--lock`; every
  other leg documented below still lives only in the niri script until M46
  deletes it. `--hotcorner` reads `hyprctl -j layers` and asserts both
  corner surfaces sit on level 2, Hyprland's `top`. `--wallpaper`
  here reads the dither setting rather than assuming it: the run writes no
  `wallpaper.dither` key, so it asserts the plain image reached the screen
  (a full-width strip of the gradient fixture carries far more colors than
  any derived palette allows) while the monotone fixture still has to paint
  its own exact color end to end. `SMOKE_WALLPAPER_DITHER=1` turns the
  opt-in on for one run and flips that same assertion to the palette-capped
  one, so both sides of the key are provable without a second flag.
  `--lock` and `--wallpaper` combine rather than excluding each other: the
  two wallpaper frames are taken first and the lock leg's whole timeline
  shifts to `lock_t0`, which leaves a real matugen-recoloured gradient
  behind the lock column. In the VM, nested Hyprland runs on a
  `vkms` software KMS card: the pixman-rendered sway parent advertises no
  `zwp_linux_dmabuf_v1` and hands it no render node, which aquamarine needs
  to create its backend at all, so `vkms` gives it a real (if virtual) GBM
  device instead; on a real host, with a real GPU behind the parent, it
  nests directly. `nix/testvm.nix` changed twice for this (`e517319`,
  `33fdaca`), so run `just vm-down && just vm-up` once before the first
  `vm-smoke` against it.
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
  colors (`docs/screenshots/menu-niri.png` is captured this way); that
  combination pushes the menu leg's whole timeline back to sleep 11
  (`menu_t0`), since the menu covers the entire output and would otherwise
  be what the wallpaper leg's sleep-8 flatness patch samples. The menu's own
  backdrop is a plain black scrim at 0.5 (omarchy parity). A dithered freeze
  of the screen was built here first and reverted: refreshing it meant the
  capture contained the backdrop it was replacing, and the resample, the
  per-frame palette and the darkening wash each drifted a little per
  generation, so the picture crawled while nothing on screen moved. Only the
  lock screen dithers, and only because its source is one still wallpaper.
- `dev/smoke-niri.sh --notify` — same, plus fires `notify-send -u normal`
  then `-u critical` in-session and screenshots the resulting toasts:
  bottom-right by default since M34 (`notifications.position`,
  `shell/Notifications/model.js`'s `positionSpec`), collapsed into a
  sonner-style depth stack (critical wins the front slot over a newer
  normal, older popups peek a fixed sliver out from behind it, each level
  sized narrower by an integer `Theme.space` step — never a fractional
  `transform: scale`). `notifications expand on` then `off` over IPC (the
  rig's stand-in for hovering the stack) reflows it into the full column
  and back, screenshotted separately (`toasts-expanded.png`).
- `dev/smoke-niri.sh --center` — same as `--notify` (combine the two flags),
  plus fires one more `notify-send`, waits for it to auto-expire into
  `pending`, then summons the notification center over the `notifications`
  IPC target and screenshots it (DND cell, `PENDING / n` header, per-row
  cells). The sticky critical popup from `--notify` is still live in
  `NotificationService.popups`, but Toasts.qml suppresses its own
  Overlay-layer stack unconditionally for as long as the center is open:
  Center.qml stays a fixed right-anchored, full-height Top-layer card no
  matter where `notifications.position` puts the toast stack, so this is
  one rule with no corner-collision math — the screenshot shows the
  center alone, and the
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
  than duplicating it), then calls `clipboard copy <id>` on a second entry
  and reads the system clipboard back to confirm it landed. Then the leg
  that matters: a sentinel string is copied, the `clipboard` route is
  summoned, `menu filter` narrows it to one known row, `menu activate 0`
  (the rig's Enter stand-in) fires, and the clipboard is read back — it has
  to hold the ROW's entry, not the sentinel. Enter used to spawn `qs ipc …
  clipboard copy <id>` through the compositor, which worked only here,
  because `nix/testvm.nix` installs the whole quickshell package; nothing
  puts `qs` on a real session's PATH, so it was a silent exit 127 on every
  actual install. Row activation is in-process now
  (`@ipc:clipboard.copy:<id>`). The paste keystroke Enter also synthesizes
  is not observable in a nested session with no focused client. The route
  is left summoned so the screenshot shows the provider's rows rendered as
  real menu cells.
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
  before mpv is killed by PID. The rest of MPRIS is driven the same way,
  since an inverted cell in a screenshot says nothing about whether the
  D-Bus call landed: `media shuffle on`, `media loop track` and `media
  volume 30` are set over IPC and read straight back out of mpv
  (`media-controls-status.json`, `media-controls.png`), and a SECOND mpv
  then joins the bus so the panel's PLAYERS switcher exists at all (it is
  hidden by design with one player), with `media select` handed the id that
  is NOT the one the pick chose (`media-players.json`) and the resulting
  `media status` proving the whole shell moved to it
  (`media-players.png`). Both players are killed by PID before niri quits.
- `dev/smoke-niri.sh --lock` — drives the whole lock round trip over real
  PAM. First, before the nested session even starts, runs
  `result/bin/formalshell-lock-before-sleep` with **no shell instance
  running at all** and records its exit code (must be `0` — the
  `lock-before-sleep` exit-0-always contract, spec §8). Then in-session:
  `lock lock` over IPC (screenshotted as `lock-locked.png`: the shared
  `AuthPrompt` column, oversized clock over the wallpaper under a 0.5 black
  scrim, with `--wallpaper` combined in setting the GRADIENT fixture and
  skipping the crossfade/monotone-flatness legs entirely, because niri
  refuses `screenshot-screen` on a session the lock leg locked at sleep 3.
  `dev/smoke.sh`'s own port has no such exclusion), `lock isLocked`
  confirms `true`, `wtype` (a real virtual-keyboard-unstable-v1 client —
  `LockIpc.qml` deliberately has no "type this password" shortcut) types a
  wrong password and Return (screenshotted as `lock-error.png`: the input's
  border swaps to `destructive` under a `Wrong password` caption), then
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
  effect or banner for a single run). Only one output animates, and which
  one is `display.outputPriority`'s first connected entry — the fixture
  sets it to two connectors this session doesn't have followed by one it
  does, so the `mainOutput` in that same status, checked against `niri msg -j
  outputs` (`screensaver-outputs.json`), proves the list was walked in order
  rather than a single-output session having one obvious answer. The rest of
  the multi-head rules (port prefixes, the `internal`/`external` aliases,
  what a plug or unplug does to a run in flight) live in
  `tests/tst_display_priority.qml`, since a nested session has one head.
  `screensaver stop` dismisses it, then a final explicit `start`/screenshot
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
- `dev/smoke-niri.sh --console` — points `settings.json`'s `console.command`
  at a real foot on a known blue background and drives the quake console
  (M37) over three `console toggle` calls off one timeline: open
  (`console-open.png` — the terminal covering the top half, the tiled
  fixture window and the bar still visible around it), parked
  (`console-parked.png`), and back (`console-return.png`), with a `console
  status` dump beside each frame. The claim the screenshots cannot make
  lives in those dumps: `windowId` has to be the SAME string in all three,
  including the parked one. A console that closed and respawned its
  terminal would produce three perfectly good frames and throw the session
  away, which is the whole feature. niri has no hide primitive of any kind,
  so parking means a move onto the trailing empty workspace
  (`shell/Compositor/park.js`) — the extra workspace visible in the bar's
  cell while parked is that, not a bug — while Hyprland parks on
  `special:formalshell-console`.
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
- `dev/smoke-niri.sh --monitor` (M38) — points `settings.json`'s
  `bar.layout` at the opt-in `monitor` builtin leading the right region,
  opens its compact panel over `panel open monitor`, then summons the
  launcher's FULL monitor route (`menu summon monitor`, the one route
  `Menu/appviews.js`'s registry names so far — the process table is the
  bottom half of that same view). Three screenshots off one
  timeline (`monitor-bar.png`, `monitor-panel.png`, `monitor-view.png`)
  with `monitor status` and `monitor gpu` dumped beside them. The honest
  no-GPU state is the actual claim: the mac VM's `/sys/class/drm` holds no
  cards at all, so `monitor gpu` has to report `available:false` over an
  empty card list (the view's own `NO GPU` cell) while `monitor status`,
  taken in the same breath, carries real non-null CPU and memory numbers
  off the VM's own `/proc` — a monitor showing nothing at all, or a GPU
  appearing out of nowhere, fails the run instead of producing a plausible
  screenshot.
- `dev/smoke-niri.sh --gpu` (M38) — the same three surfaces against a
  two-card machine the rig doesn't have. Two PATH shims draw it, the same
  hermetic-producer line the `gh` and `clipssh` shims already draw: an
  `nvidia-smi` emitting the owner's real g815 bytes verbatim (fan speed
  `[N/A]`, a value nvidia-smi genuinely emits for a laptop GPU, which has
  to render unavailable rather than 0), and a `sh` that intercepts exactly
  the one `sh -c` invocation matching the collector's own
  `/sys/class/drm/card*` glob, splices `tests/fixtures/gpu-hybrid.txt`'s
  `@drm` rows into its output, and passes every other `sh -c` straight
  through to the real shell. No `/sys` entry is invented anywhere — the
  collector still runs against this VM's own filesystem, only its view of
  `/sys/class/drm` is spliced. `monitor gpu` and the launcher's monitor
  view then have to show both cards for real (card0 nvidia/discrete via
  `boot_vga`, card1 i915/integrated with its ACPI label, the external HDMI
  hanging off the dGPU). Then the claim no screenshot can make: `monitor
  launch` against a fixture `.desktop` entry whose Exec is a probe script
  that writes its own argv and environment to a file, read back to confirm
  all four `__NV_PRIME_RENDER_OFFLOAD`/`__NV_PRIME_RENDER_OFFLOAD_PROVIDER`/
  `__GLX_VENDOR_LIBRARY_NAME`/`__VK_LAYER_NV_optimus` variables reached the
  child (the exact set NixOS's own `nvidia-offload` wrapper exports) and
  that the Exec's `%U` field code did not — `nvidia-offload`/`prime-run`
  are deliberately left unshimmed so `offloadArgv` takes that four-variable
  branch. An environment variable is invisible to a screenshot, which is
  why this leg reads a file back instead of trusting the frame.
- `dev/smoke-niri.sh --processes` (M39) drives the process table end to
  end against two fixture processes it starts itself. The table lives
  INSIDE the launcher's monitor view (btop's layout, M40: stats above,
  table below, one route — it had a route of its own for a day and the
  owner asked for it folded in, 2026-08-19), so this leg summons `monitor`
  and the search field it types into is that route's own. The fixtures are
  copies of **bash** (not coreutils `sleep`, which nixpkgs builds as one
  multi-call binary that dispatches on argv[0] and exits at once under any
  other name) spinning on a builtin loop, so each one is findable by a
  whole 15-byte comm, is the busiest thing on the machine, and dies on TERM
  with no foreground child to wait out. Four frames off one timeline:
  `processes-full.png` (the whole table, CPU-sorted, kernel threads
  carrying `KERNEL` where an argv would be), `processes-view.png` (`menu
  filter smokevictim` narrowed it to one row), `processes-confirm.png` (the
  armed row full-bleed urgent under `CONFIRM TERM`), `processes-killed.png`
  (`NO MATCH`, with the TERM's own result in the header). The kill runs
  through `menu activate` rather than `monitor kill`, since that is the
  rig's Enter stand-in and so exercises the whole path a keypress takes;
  it is called TWICE on purpose, and the `kill -0` written between the two
  calls is what proves the arming press did not already kill. The restart
  leg proves what no screenshot can: `monitor restart` TERMs a process,
  waits for the pid to leave /proc, and re-runs the same argv, so exactly
  one `smokerestart` is alive afterwards under a DIFFERENT pid.
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
  environment — the same lookup `dev/smoke.sh` and `dev/smoke-niri.sh` already fall back to on
  a real host. Both then run **completely unchanged** inside, nesting their
  own Hyprland/niri as a winit/wayland client of that parent
  (software rendering throughout — Mesa llvmpipe for the nested compositor's
  EGL, pixman for the parent — the same concession any CI-grade wlroots
  testing makes).

`dev/vm.sh` is the driver: `start` (build+boot headless, wait for ssh),
`stop`, `status`, `sync` (rsync the **working tree** — not a commit — into
`~/formalshell` inside the VM), `run <cmd…>` (ssh with cwd at the repo and
the session env exported), `smoke [flags…]` (sync, run `dev/smoke.sh` on nested
Hyprland by default, or `dev/smoke-niri.sh` with `--compositor niri`,
then `scp` the `SMOKE_OK` screenshot plus any dump/status/query JSON
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
run; the smoke rig's D-Bus isolation check tolerates that (`|| true` —
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
- **Design language**: every UI surface follows `docs/DESIGN.md`: shadcn/ui
  chrome (`card` fill, 1px `border`, `radiusMd` controls and `radiusXl`
  cards, one `ring` for focus, `accent` hover, `primary` for the wallpaper
  colour) on Omarchy quattro's surface set and habits. Read it before
  building or restyling any surface. mek.gallery and the ledger grammar are
  gone (2026-08-25).
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
- Chrome defaults (2026-08-25): radius `Theme.radius` (10, `theme.radius`
  in settings.json), 1px `border`, no shadow, no gradient, no blur drawn by
  the shell (Hyprland blurs behind the translucent bar/panel/launcher cards
  via layerrules; `theme.surfaceOpacity`, default 0.85), dither only behind
  `wallpaper.dither`/`lock.dither` (both default false), fonts = the
  fontconfig `sans-serif` alias for words and `monospace` for values (Geist
  Sans/Mono by intent, never a hardcoded family), icons by name
  through `Components/Icon.qml` with the set picked by `theme.icons`
  (`lucide` default, `nerd`; no raw glyphs in surface files, no SVG icon
  assets). Nothing in the shell blurs or shadows
  anything: a modal surface sits over a plain 0.5 black scrim, every other
  surface sits over the desktop with its border doing the work. Never
  reintroduce a `ScreencopyView`-based capture anywhere (see
  `LockSurface.qml`'s header comment: it crashes the whole shell outright,
  a fail-open on a security-critical surface).
- License MIT. Every file substantially ported from DankMaterialShell keeps
  a `// Portions from DankMaterialShell (MIT, Copyright 2025 Avenge Media LLC)`
  header line.
- ⚠️ Until M45 finishes the sweep, some files still carry raw Nerd Font
  glyphs (multi-byte codepoints that whole-file rewrites corrupt). Use
  targeted `Edit` operations on those files; new icon uses go through
  `Icon { name: ... }` and `shell/Theme/icons.js`, never a raw codepoint.
- Hyprland is the only supported compositor (owner, 2026-08-25). The niri
  backend and `dev/smoke-niri.sh` stay only until M46 deletes them, after
  the nested Hyprland rig (`dev/smoke.sh`) is green on the M41 gate legs.
  New compositor work goes in `shell/Compositor/hyprland/` only.
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
