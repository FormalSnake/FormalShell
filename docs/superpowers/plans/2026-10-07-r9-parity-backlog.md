# R9 parity backlog

Differences from the QML shell that milestone agents reported and left.
Each is fixed, or kept with the owner's say-so, before R9 cuts over. Grouped
by surface; one line each.

## Bar
- Meta labels have no letter spacing (the text style has no tracking field).
- Monitor cell's icon slot is narrower than the QML one.
- ActiveWindow lacks the app icon, desktop-entry name and name crossfade.
- NowPlaying title crossfade between tracks is not ported.
- Spaces chip label colour transition is not ported; touchpad wheel steps
  once per event (no magnitude).
- Indicators is one cell, not the QML rail of cells; nightlight, overnight,
  clipssh, airplay and reminder indicators need wiring.
- Weather location has no GeoClue path and no place name.
- No re-poll when the network comes back.

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
- Spaces preview: one sideways notch scrolls 32 px in Rust, 72 px in QML.

## Notifications
- Desktop-entry step in the icon order; iPhone source mark on cards; the
  30 s relative-time refresh; two-line wrapping of summary and body;
  restack and arrive motion for row toasts; centre header shows the host's
  close button (QML has none); bell pending dot and count; bubble's
  pantheon shadow draws outside the unfold clip while arriving.

## Lock and auth
- Polkit card's slide-in off the top line: the dialog is one full-output
  surface with the scrim baked in; the Drawer/join pipeline (Card, scrim
  band and dim surfaces, bar join) is launcher-specific and would need to
  be generalised first.

## Media
- Sink latency is read off `pw-dump` on a poke and every 10 s; QML does the
  same (its graph events only trigger the re-read), but the Rust side lacks
  the default-sink and link-change triggers. A PipeWire-event read needs
  port, link and Latency param pods in fs-audio: kept as is.
- Header Radio button (needs the Radio Atlas surface, Globe and search, not
  ported) and the animated album art (needs a video decode path) not ported.

## Launcher
- Clipboard split preview, width/height size morph, row add/remove motion.

## Headset card
- Escape only after a click gives it focus; no click-away dismissal (owner
  to decide).

## Rig
- `--screensaver-gif` README media are older than the current QML look.
- The real 33 ms bar-gap budget during a launcher open is measured on
  e1504g, not in the software-rendered VM.
