# R9 parity backlog

Differences from the QML shell that milestone agents reported and left.
Each is fixed, or kept with the owner's say-so, before R9 cuts over. Grouped
by surface; one line each.

## Panels
- Calendar: the life-progress prompt needs the launcher's input answer routed back to the
  panel (`wayland/launcher.rs`'s resolved tokens), which the R4b launcher agent holds.

## Notifications
- Restack and arrive motion for row toasts: needs the departing-slot model Toasts.qml
  keeps (a leaving card holds its frozen geometry while it fades), the staggered
  restack springs, the arrive translate and the velocity deform, about 300 lines.

## Lock and auth
- Polkit card's slide-in off the top line: the dialog is one full-output
  surface with the scrim baked in; the Drawer/join pipeline (Card, scrim
  band and dim surfaces, bar join) is launcher-specific and would need to
  be generalised first.

## Media
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
