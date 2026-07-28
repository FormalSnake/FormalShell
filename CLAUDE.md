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
*FLAGS` — the mac-side equivalents of `build`/`test`/`lint`/`smoke` above.
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
- **Design language**: every UI surface follows `docs/DESIGN.md` (mek.gallery-derived
  ruled-ledger grid: shared hairline rules, cells not cards, inversion for
  selection, accent as full-bleed cells, uppercase meta labels, radius 0).
  Read it before building or restyling any surface.
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
  hardcoded family name), icons = Nerd Font glyphs (no SVG icon sets).
- License MIT. Every file substantially ported from DankMaterialShell keeps
  a `// Portions from DankMaterialShell (MIT, Copyright 2025 Avenge Media LLC)`
  header line.
- ⚠️ Nerd Font glyphs are raw multi-byte codepoints; whole-file rewrites can
  corrupt them (Omarchy's `AGENTS.md` documents this). Use targeted `Edit`
  operations on files containing glyphs; never rewrite such files wholesale.
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
