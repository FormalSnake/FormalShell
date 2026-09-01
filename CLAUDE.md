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

- `just build`: `nix build .#formalshell`. **`git add` first**, flakes only
  see git-tracked files, so an unstaged file is invisible to the build.
- `just test`: headless `qmltestrunner` over `tests/` (`QT_QPA_PLATFORM=offscreen`).
- `just lint`: `nix flake check -L` (qml-tests + qmllint).
- `just smoke` / `dev/smoke.sh <flags>`: the runtime loop. Builds the shell,
  brings up an isolated Hyprland session under `dbus-run-session`, drives
  the legs the flags asked for, screenshots, tears it down. **Read the PNGs
  rather than assuming they look right.**
- `just vm-smoke <flags>`: the same script inside the mac VM, screenshots
  pulled back to the mac (the mac rig section below).
- `just vm-greeter` / `dev/smoke-greeter.sh`: not a flag on the rig. greetd's
  `default_session` is a standing system service, so this drives the
  already-running greeter session (restart greetd, screenshot pre-auth, a
  wrong password then the real one over `wtype`) and pulls
  `artifacts/greeter/`. It fails unless the session log shows a real
  `pam_authenticate: AUTH_ERR` on the wrong attempt.

How a run works:

- Session mode is decided by the machine, never by a flag: a real host nests
  Hyprland in the running session, and the VM, whose pixman sway parent
  advertises no `zwp_linux_dmabuf_v1` and hands out no render node, runs it
  on the `vkms` software KMS card instead (`nix/testvm.nix`).
- Flags combine into one session: `leg_<n>_order` sets the order, timings are
  max-merged so a combination outlives its slowest half, and a leg that
  cannot share the session takes the run over (`--screensaver-gif`).
- Legs sharing a surface wait on the owner's marker (`picker_done_path`), and
  a leg covering the whole output starts at its own `<leg>_t0`, past any
  desktop sampler, which is why `--wallpaper` pushes `--menu` and `--lock`
  back and leaves a matugen-recoloured desktop behind them.
- Every run prints `SMOKE_OK <path>` for its own frame and `SMOKE_<NAME>
  <path>` for each named artifact; `dev/vm.sh smoke` scps all of them plus
  the run's stdout JSON into `./artifacts/` on the mac.
- The VM holds one checkout and `dev/vm.sh sync` rsyncs over it with
  `--delete`, so every VM command from a worktree goes through
  `dev/vm-lock.sh just vm-smoke <flags>`, which serialises them on a lockfile.
- matugen's source colour is pinned to its own rank 0 rather than left to
  `--prefer`, which is a bad proxy for what colour a wallpaper is;
  `shell/Theme/ThemeEngine.qml`'s header carries the why. Force the source
  the same way if you run matugen by hand while debugging.

Every leg is one file, `dev/smoke.d/<name>.sh`, whose header carries the
detail; `dev/smoke.d/README.md` is the file contract. What each proves:

- `bar_layout.sh` `--bar-layout`: user `bar.modules` and a reordered layout
  resolved from settings.json alone, every `CommandModule` failure path in
  the one frame.
- `bar_position.sh` `--bar-position <edge>`: the strip on a bottom, left or
  right edge, read off the compositor's own layer geometry, with a chevron
  collapsing and expanding along it and a panel hanging off its inner edge.
- `capture.sh` `--capture`: the shell's own region picker (smart pick, tab
  cycling, commit) measured against the compositor's output, the toolbar's
  record commit, and the cancel path.
- `capture_edit.sh` `--capture-edit`: the SAVED notification's EDIT action
  reaching a real editor with the capture's own path on argv.
- `center.sh` `--center`: the notification centre listing the pending tier,
  with the toast stack suppressed for as long as it is open, content-tall on
  a short history and capped and scrolling on thirty rows.
- `chevron.sh` `--chevron`: a right-region chevron holding the five cells
  before it off the strip entirely, and `bar chevron expand` opening them in
  the second bar under it, the two frames asserted to differ.
- `clipboard.sh` `--clipboard`: the ledger's capture order and in-process row
  activation, with the image entry's preview and a copied-markup row's own
  angle brackets in the frame.
- `clipssh.sh` `--clipssh`: the clipssh route's send, its bar indicator and
  its copied/failed toasts, against a shimmed binary.
- `clipssh_image.sh` `--clipssh-image`: the two sends that resolve a host out
  of `clipssh.alias` rather than off a row, `clipssh.autoSendImages` and
  Shift+Enter on a history image row, each checked against the sha256 of
  what the clipboard actually held when the shimmed binary read it.
- `config_reload.sh` `--config-reload`: a settings.json whose symlink is
  retargeted (what home-manager does on every activation, the one write a
  file watch cannot see) still reaching a running shell, read off the bar's
  own edge moving right to left.
- `console.sh` `--console`: the quake console parking on a special workspace
  and coming back with the same window id.
- `dump.sh` `--dump`: the `debug` target's whole state dump, saved as the
  run's JSON sidecar and read by other legs for what the shell resolved.
- `emoji.sh` `--emoji`: the launcher's emoji route by search and by order:
  `:e sob` reaching 😭 through CLDR's keywords (its Unicode name has no
  "sob" in it), and one copy through the row's own Enter path putting that
  emoji at the head of its own rank and no higher, with no settings key
  written.
- `flexoki.sh` `--flexoki`: a wallpaper under a `flexoki/` directory, and
  the rewrite reaching a user template, its `post_hook`, and the shell's own
  GTK and Qt palettes: Flexoki green and yellow, which no Material scheme
  seeded on Flexoki blue can produce.
- `frame.sh` `--frame`: pins `frame.thickness` in the settings fixture so the
  bar's window grows to the output and paints the frame round it, and reads
  that box and the four exclusion zones off the compositor's own layer list.
- `gallery.sh` `--gallery`: the dev gallery sheet, every shared component
  drawn against the live theme.
- `gpu.sh` `--gpu`: both cards of a hybrid laptop this rig is not, and the
  four PRIME offload variables reaching a launched child.
- `hotcorner.sh` `--hotcorner`: both hot corner surfaces mapped on the right
  layer, which is all a rig with no synthetic pointer can observe.
- `hotcorner_relock.sh` `--hotcorner-relock`: locks from the corner, unlocks
  by typing, proves the corner stays quiet while the pointer sits in it and
  fires again only after a leave plus the 400ms cooldown.
- `instance.sh` `--instance`: a second daemon taking the lock, exactly one
  survivor, and the survivor being the new pid.
- `keybinds.sh` `--keybinds`: the launcher's binds route rendering rows off
  Hyprland's own expanded bind table.
- `lock.sh` `--lock`: the lock round trip over real PAM, wrong password to
  unlocked, typed by a real virtual-keyboard client.
- `media.sh` `--media`: the media panel read off a real MPRIS player, both
  marquee states, shuffle/loop/volume set over IPC and read back out of mpv,
  and the players switcher.
- `menu.sh` `--menu`: the launcher at root, its fuzzy ranking against the
  live tree, and the select round trip.
- `mic.sh` `--mic`: the opt-in mic cell rendering its honest no-device state
  on a machine with no capture device.
- `monitor.sh` `--monitor`: the monitor bar cell, its panel and the
  launcher's monitor view, against this machine's own `/proc` and `/sys`.
- `nightlight.sh` `--nightlight`: the wlsunset-backed night light on and off,
  honest about a session that cannot gamma-control.
- `notify.sh` `--notify`: the toast stack collapsed and expanded, critical
  holding the front slot over a newer normal, the icon resolution order over
  three cards, and the layer surface the same size either way.
- `ocr.sh` `--ocr`: the `capture` target's text and colour verbs against a
  window carrying known text on a known background.
- `osd.sh` `--osd`: the OSD pill on a manual call, on a real `wpctl` change,
  and on a machine with no backlight.
- `panel.sh` `--panel <name>`: one popout opened over the `panel` route, with
  `panel state` agreeing it is the only open one.
- `panel_at.sh` `--panel-at <n>`: `panel toggleAt <n>` walking the resolved
  right region and stopping on a panel-bearing cell.
- `panel_keys.sh` `--panel-keys`: row-level keyboard navigation inside a
  panel, driven by real keystrokes rather than the IPC shortcuts.
- `picker.sh` `--picker`: the wallpaper grid, the pick becoming the
  wallpaper, the select token round trip, the Dark/Light variants, and
  ThumbnailService's prerendered cache backing every cell (the cache
  directory's own contents, since a warmed cell and a fallback cell paint
  the same picture).
- `plugins.sh` `--plugins`: a plugin directory dropped into the config home
  placing its own bar cell, no `bar` key involved.
- `polkit.sh` `--polkit`: a real `pkexec` conversation through the shell's
  agent, the prompt, the error state and pkexec's own exit code.
- `processes.sh` `--processes`: the process table's search, the two-press
  TERM, and `monitor restart` re-running the same argv under a new pid.
- `record.sh` `--record`: `record` start to finished GIF through a real
  wf-recorder child, with the bar's recording cell mid-run.
- `reminder.sh` `--reminder`: a real countdown firing inside the run and
  bypassing DND into the popup tier.
- `retro.sh` `--retro`: pins `theme.preset` to `retro` in the settings
  fixture and rides any other leg, so `--retro --gallery` is the sheet
  square, mono and dithered.
- `screensaver.sh` `--screensaver`: the live media guard, auto-activation off
  the idle timer alone, and the manual start/stop path.
- `screensaver_gif.sh` `--screensaver-gif`: five ttfx effects recorded frame
  by frame into `docs/media/`, one session each, taking the run over.
- `screenshot.sh` `--screenshot`: the `screenshot` target's region cancel and
  full-screen routes.
- `share.sh` `--share`: the share route present (the copied text reaching
  LocalSend as a real file) and honestly absent with no binary on PATH.
- `speedtest.sh` `--speedtest`: `network speedtest` settling both phases in
  the network panel.
- `systemupdate.sh` `--systemupdate`: the flake-inputs-behind cell and panel
  reading this repo's own flake through one shared poll.
- `theme_toggle.sh` `--theme-toggle`: `theme mode toggle` both ways, and with
  `--wallpaper` that a toggle re-runs matugen instead of resetting to the
  fallback palette.
- `toggles.sh` `--toggles`: the toggle hub's rows repainting from a `@state:`
  snapshot without the surface moving under them.
- `tooltip.sh` `--tooltip`: rides `--panel <name>`; the tooltip surface
  absent before the pointer parks on a header button and present after.
- `tray.sh` `--tray`: six real StatusNotifierItem producers on a strip pinned
  to carry them (`tray.maxVisible: -1`), the D-Bus Activate round trip, and
  the shell-owned menu.
- `tray_overflow.sh` `--tray-overflow`: the shipped default, the whole tray
  in its second bar behind the strip's dots toggle with no settings at all,
  read off `tray status`.
- `visualizer.sh` `--visualizer`: the `cava` child owned and killed with
  playback, proven by pgrep rather than by the frame.
- `wallpaper.sh` `--wallpaper`: the matugen recolour on a set wallpaper, the
  crossfade to a second one, and both sides of the opt-in dither key.
- `wifi.sh` `--wifi`: the network panel against two real hostapd radios:
  scan, wrong password, connect, forget, and the enterprise round trip.
- `wheel.sh` `--wheel`: a virtual-pointer scroll moves the picker grid
  (`menu status` `scrollTop`) without moving the cursor, and a wheel over the
  bar's audio cell still steps the volume.
- `workspaces.sh` `--workspaces`: the bar's workspace indicator as one pill
  that travels, read off the bar region alone before, 80ms into, and after a
  workspace switch.

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
  under HVF, pre-staged with `formalshell`/quickshell/hyprland/sway/matugen
  so in-VM builds are near no-ops. Inside it, a systemd **user** service runs
  a headless wlroots parent compositor (sway, `WLR_BACKENDS=headless`,
  `WLR_RENDERER=pixman`) publishing `WAYLAND_DISPLAY` into the systemd user
  environment, the same lookup `dev/smoke.sh` already falls back to on a real
  host. The script then runs **completely unchanged** inside, except that its
  own session-mode pick lands on `vkms` rather than nesting: that pixman
  parent advertises no `zwp_linux_dmabuf_v1` and hands out no render node, so
  Hyprland renders on the software KMS card the kernel's vkms module draws
  (software rendering throughout, Mesa llvmpipe for Hyprland's EGL and pixman
  for the parent, the same concession any CI-grade wlroots testing makes).

`dev/vm.sh` is the driver: `start` (build+boot headless, wait for ssh),
`stop`, `status`, `sync` (rsync the **working tree** — not a commit — into
`~/formalshell` inside the VM), `run <cmd…>` (ssh with cwd at the repo and
the session env exported), `smoke [flags…]` (sync, run `dev/smoke.sh`,
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

- **Host-session safety**: the owner's live session is NOT a test target.
  Never run the shell, the ThemeEngine, or any compositor action in an
  environment carrying the host's `HYPRLAND_INSTANCE_SIGNATURE`. All runtime
  testing happens inside nested sessions via `dev/smoke-*.sh` (which scrub and
  restore the env). If you must run `qs` ad hoc, unset that variable first or
  export the nested session's own explicitly. Observed failure mode: host
  compositor config reloads firing during isolated testing (2026-07-27).
- **Lock-screen safety**: never run a lock surface (`Lock.qml`'s
  `WlSessionLock`) against anything but a nested test session. All lock
  testing happens inside the nested Hyprland session `dev/smoke.sh` boots and
  tears down; a lock bug there is harmless (the whole nested
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
  out from under the real desktop. `dev/smoke.sh` wraps the whole nested
  compositor invocation in `dbus-run-session --`, giving every nested run (and
  `notify-send` fired inside it) a private bus; it asserts `busctl --user status
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
  parse, compare numerically, or assume stability. Hyprland's window ids are
  hex addresses and reach its dispatchers verbatim, as an `address:0x…`
  selector built at the backend's own wire boundary and nowhere else.
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
  anything: a modal surface sits over a plain 0.5 black scrim (the
  compositor blurring the desktop behind that scrim, since the polkit
  layer takes the same blur layerrule its card's translucency implies),
  every other surface sits over the desktop with its border doing the
  work. Never
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
- Hyprland is the only supported compositor (owner, 2026-08-25). New
  compositor work goes in `shell/Compositor/hyprland/` only;
  `shell/Compositor/BackendBase.qml` stays as the contract every surface is
  written against, so a second backend would be a new file rather than a
  sweep.
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
- `github.com/AvengeMedia/DankMaterialShell` (MIT): Hyprland backend
  prior art and matugen orchestration patterns. MIT, so code can be ported
  directly, but every substantially-ported file needs the attribution
  header above.
- QuickShell source/docs (`git.outfoxxed.me/quickshell/quickshell`, pinned
  flake input) — ground truth for toolkit APIs (`Quickshell.Io.Socket`,
  `IpcHandler`, `Quickshell.Hyprland`, `Singleton`, …). When a QML/JS API's
  behavior is uncertain, read the C++ source or run the built `qs` binary
  rather than guessing.
