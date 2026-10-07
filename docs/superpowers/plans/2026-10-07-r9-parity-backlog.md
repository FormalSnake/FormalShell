# R9 parity backlog

Differences from the QML shell that milestone agents reported and left.
Each is fixed, or kept with the owner's say-so, before R9 cuts over. Grouped
by surface; one line each.

## Bar
- Indicators is one cell, not the QML rail of cells: a rail needs the strip to host
  several independent hover and click cells inside one slot, which the cell model
  does not do yet. All seven indicators are wired into the one cell.

## Panels
- Tray menu: no click-outside dismiss, no wheel scroll past the height cap,
  no animated height morph; second-bar card keeps its opening size when
  items change while open; no per-item hover tooltips.
- Wired network row click does nothing (QML connects or disconnects); the
  Wi-Fi forget icon shows on cursor rather than hover alone.
- `bluetooth` IPC verbs not ported.
- Power: low-battery notification watcher, charging and tailscale-dot
  pulses, iPhone figure in PowerFlow, "Open monitor" only closes.
- Calendar: life-progress prompt, month-swap slide.
- App menu populated state (hero, actions, windows) never rendered in a leg.
- `--pantheon --systemupdate` never opens its panel (check QML too).

## Notifications
- Desktop-entry step in the icon order; iPhone source mark on cards; the
  30 s relative-time refresh; two-line wrapping of summary and body;
  restack and arrive motion for row toasts; centre header shows the host's
  close button (QML has none); bell pending dot and count; bubble's
  pantheon shadow draws outside the unfold clip while arriving.

## Lock and auth
- Polkit card's slide-in off the top line and its identity avatar.
- Lock wake from idle blank is instant, not a fade.
- Hot corners don't hide under fullscreen.

## Media
- Lyrics resync button in the header, not the pane corner; unlit rows lack
  the 0.85 scale; no lit-row arrival fade; keyboard cursor can't enter the
  lines; sink latency polled from pw-dump every 10 s, not PipeWire events.
- Header Radio button and the animated album art not ported.
- `media outputs`/`output` and pipewire `stream:` rows.

## Launcher
- Clipboard split preview, width/height size morph, row add/remove motion.

## Headset card
- Escape only after a click gives it focus; no click-away dismissal (owner
  to decide).

## Rig
- `--screensaver-gif` README media are older than the current QML look.
- The real 33 ms bar-gap budget during a launcher open is measured on
  e1504g, not in the software-rendered VM.
