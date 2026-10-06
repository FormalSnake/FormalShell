# FormalShell in Rust

Owner, 2026-10-06: replace the Quickshell runtime with our own Rust binary.
It looks the same, behaves the same, and costs a fraction of what it costs
now. This wins over the "pure QML/JS, no compiled companion binary" rule in
`CLAUDE.md` and over the 2026-07-27 spec's runtime choice. Every other
decision in the 2026-07-27, 2026-08-25 and 2026-09-18 specs (layout,
behaviour, IPC contract, config and state files, theme boundary, honest
unavailable states, Hyprland and Lua only) carries over unchanged.

## Why

Measured on e1504g (i3-N305, 8 GB, 1920x1080@60, power saver), 2026-10-06,
with nothing open and no media player: quickshell at 556 MB RSS and ~30% of
one core, 22% of it on `QSGRenderThread`. The bar redraws every vsync while
one herdr "working" badge spins (`Workspaces.qml`'s endless
`RotationAnimator`), because a Qt Quick window has one frame clock and no
partial redraw. Our own renderer redraws a 16px rect at that rate instead of
the whole strip, and runs no clock at all when nothing moves.

## Budgets (acceptance, measured on e1504g in a nested session)

These are ceilings. Lower is better, and cheap headroom is taken.

- Idle, nothing moving: 0.0% CPU over 60 s, no frame callbacks requested.
- One herdr spinner running: under 2% of one core.
- Panel open/close, launcher open, workspace switch: no frame over 16 ms.
- Power saver is the benchmark profile: every budget is measured with
  e1504g in its low power mode, never only at full clocks.
- Robustness: no surface ever blocks another. Super+Space to the first
  launcher frame under 50 ms, and the bar keeps animating while the
  launcher opens. The QML shell freezes whole for a visible moment here
  (owner, 2026-10-06); that is the failure this rewrite exists to end.
  Nothing slow (desktop entry scans, ranking, icon and image decode,
  D-Bus round trips, process output) runs on the UI loop: it is done
  ahead of time or off the loop, and a surface opens on what is ready.
- RSS after an hour of use: under 120 MB.
- Cold start to bar mapped: under 300 ms.

## Stack

Versions as of 2026-10-06; check crates.io before bumping.

- Wayland: `smithay-client-toolkit` 0.21 on `calloop` 0.14, protocols from
  `wayland-protocols` 0.32 (layer-shell, ext-session-lock,
  ext-image-copy-capture for thumbnails) and `wayland-protocols-wlr`.
- Rendering: our own retained scene graph. Each node knows its bounds and
  dirties its rect. `vello_cpu` draws into double-buffered `wl_shm` buffers
  and only the damaged rects are drawn and sent with
  `wl_surface.damage_buffer`. A frame callback is requested only while a
  spring or timed animation is live. If R0 shows CPU raster cannot hold
  16 ms on a full-output scrim, those surfaces move to `vello_gpu` (same
  `vello_common` scene); the bar and panels stay on CPU.
- Text: `parley` (fontique reads fontconfig, so `sans-serif`/`monospace`
  and the Lucide and Nerd icon fonts resolve exactly as they do now).
  Text must be at least as crisp as GNOME's. QML text is soft on e1504g
  because Qt Quick's default distance-field rendering ignores fontconfig
  hinting. We honour fontconfig's hinting and antialias settings (hint at
  the real pixel size, slight = vertical only) and snap baselines to whole
  device pixels.
- Layout: `taffy` for flex rows and columns; joined shapes, springs and the
  deform clock are our own code, ported from the QML math.
- Threads, few and fixed (quickshell runs 41 on e1504g):
  - UI thread: one `calloop` loop owning Wayland, the scene, input and
    rendering. It never waits on anything; it applies state diffs that
    arrive over a channel and draws.
  - Service thread: one single-threaded async executor running every
    D-Bus client and server (`zbus` 5), the Hyprland sockets, child
    processes and timers, and keeping derived state warm (the launcher
    index, rankings) so the UI only reads it.
  - Blocking work (desktop entry scans, icon and image decode, file IO)
    goes to a pool of at most two threads that exits when idle, and its
    results land as diffs like everything else.
  - PipeWire: one `fs-pipewire` thread runs PipeWire's own main loop
    (pipewire-rs cannot live on another executor) and posts events to the
    service thread over a channel; writes go back over a pipewire
    channel. It reconnects on a drop.
  - `vello_cpu` renders single-threaded for damage rects and uses its own
    threads only for a full-output frame, if R0 shows that pays.
- Services: `system-tray` (SNI + DBusMenu), `mpris`, `pipewire` (default
  sink through the `default` metadata object), `nmrs` (NetworkManager),
  `bluer`, PAM through `pam-client2`, raw Hyprland sockets (`.socket.sock`,
  `.socket2.sock`, `hyprctl eval` for writes). Written by us on zbus:
  the `org.freedesktop.Notifications` server, the polkit
  `AuthenticationAgent` (MIT; `zbus-polkit-agent` is GPL-3.0), and the
  UPower proxy.
- Child processes stay child processes (matugen, cava, grim, wf-recorder,
  ttfx, localsend-cli, uxplay, ...), spawned and read on the loop.

## Contracts that do not change

- IPC: `formalshell-ipc call <target> <fn> [args...]` with the same 40
  targets, the same function names and byte-identical output strings, over
  a Unix socket under `$XDG_RUNTIME_DIR/formalshell/`. The 640 IPC calls in
  `dev/smoke.d/` are the conformance suite.
- `settings.json` (read only, symlink retarget still seen),
  `$XDG_STATE_HOME/formalshell/state.json`, plugin directories, theme
  tables. Theme tables move from `shell/Theme/themes/*.js` to
  `themes/*.json` with the same keys; `tst_theme_style.qml`'s "every role
  in every table" check becomes a Rust test.
- Every rule in `CLAUDE.md`'s hard rules section other than "pure QML/JS".
  The ScreencopyView ban becomes: capture only in the Spaces preview and
  the switcher, and only while their card is open.

## User code: command plugins

Owner, 2026-10-06: Rust cannot host QML, so `bar.modules` entries of type
`qml` and QML plugins under `~/.config/formalshell/plugins/` give way to
command plugins. A plugin is an executable named by its manifest: it
prints JSON lines (text, icon name, tooltip, class, and for panel plugins
rows) on stdout and reads click, scroll and row-activate events as JSON
lines on stdin. Any language, its own process, nothing running in the
shell's address space, no cost while it prints nothing. The manifest keeps
its eight keys and its failure contract (`fs-chrome`'s manifest port);
`entry` names the executable. A crashed plugin renders the dim PLUGIN
ERROR cell and is restarted on a backoff. `CommandModule` stays as it is.

## How we get there

The QML shell stays the shipped shell until the Rust one passes everything.
No dual runtime, no surface split across two processes: the bar and its
panels share one joined shape and the notification bus name has one owner.

- The Rust workspace lives in `crates/` beside `shell/`, built by the flake
  as `.#formalshell-rs`.
- `dev/smoke.sh` takes `FS_IMPL=rust`, swapping the shell binary and the IPC
  command; every leg runs unchanged against either.
- `dev/parity.sh` compares Rust frames against QML frames from the same
  commit. Text is rasterised by a different engine, so glyph edges differ:
  the gate is no difference outside glyph bounding boxes. Inside them the
  Rust text is held to crispness, not to the QML pixels. Geometry, colour and motion timing are exact.
- A milestone is done when its legs pass on `FS_IMPL=rust`, its parity
  frames pass, and its budget holds on e1504g.

Milestones, each a plan under `docs/superpowers/plans/`:

- R0: spike. A bar strip (clock, workspaces with a spinning badge, one
  cell opening one panel through the joined shape) on sctk + vello_cpu,
  measured against the budgets in a nested session on e1504g. Decides CPU
  versus GPU raster for full-output surfaces and whether `vello_cpu` covers
  the blurred casts pantheon's `Box` draws with a shader today. If the
  budgets fail, stop and report before R1.
- R1: core. Config, state, theme tables, matugen palette, IPC server and
  `formalshell-ipc`, Hyprland backend, scene, springs, `FS_IMPL` in the rig.
- R2: the bar, every cell, chevron and tray, all three themes.
- R3: panels and the joined shape, keyboard navigation, tooltips.
- R4: launcher and every route, app grid, emoji, clipboard, mirror.
- R5: notifications server, toasts, centre, OSD, reminders.
- R6: lock, PAM, sleep inhibitor, polkit agent, greeter.
- R7: media, lyrics (blur and glow), visualizer, radio, airplay, iphone,
  and earbuds (M77, `specs/2026-09-30-m77-earbuds.md`): one normalised
  device shape (`shell/Earbuds/model.js`) behind the airpods, nothing,
  soundcore and samsung adapters, the `earbuds` IPC target and bar cell,
  `tests/tst_earbuds_*.qml` ported to Rust tests, `--earbuds` passing
  under `FS_IMPL=rust`. The M77 safety rule carries over unchanged: the
  shell never speaks the Nothing protocol itself, only allow-listed verbs
  through `nothingctl`, and the soundcore and samsung polls run only
  while acquired with a matching BlueZ device connected.
- Headset connect card (owner, 2026-10-06, new in the Rust shell, after
  macOS's AirPods popup): when a Bluetooth audio device (BlueZ class
  audio, or one an earbuds backend claims) goes from disconnected to
  connected, a card buds off the bar's line in the shell's joined-shape
  motion, carrying the device's icon, its name, "Connected", and one
  battery ring per part the backend reports (left, right, case for
  earbuds; BlueZ Battery1 otherwise; no ring when nothing reports a
  level, never an invented one). It never fires for devices already
  connected at startup or on a reconnect inside a few seconds, holds about
  four seconds, dismisses on pointer leave or Escape, opens the earbuds or
  Bluetooth panel on click, and stays down under fullscreen and DND.
  Built with the frontend skills the user's CLAUDE.md lists, in the
  shell's own chrome, not a copy of Apple's.
- R8: capture, record, OCR, screensaver, switcher and Spaces thumbnails,
  everything left in `shell/`.
- R9: cutover. Nix package and modules, PKGBUILD and Debian control point
  at the Rust binary, `shell/` and quickshell are deleted, `CLAUDE.md`
  rewritten for the new tree.
  Done means both Linux hosts run it (owner, 2026-10-06): push, bump
  `formalshell` in `~/.config/nix`, rebuild g815 on itself and e1504g from
  g815 (`nixos-rebuild switch --flake .#e1504g --target-host e1504g
  --sudo`, never building on e1504g), and confirm each host's
  `formalshell.service` runs the Rust binary.
