# R9 parity backlog

Differences from the QML shell that milestone agents reported and left.
Each is fixed, or kept with the owner's say-so, before R9 cuts over. Grouped
by surface; one line each.

## Panels
- Calendar: the life-progress prompt needs the launcher's input answer routed back to the
  panel (`wayland/launcher.rs`'s resolved tokens), which the R4b launcher agent holds.

## Media
- Header Radio button (needs the Radio Atlas surface, Globe and search, not
  ported) not ported.
- The animated album art runs in the media panel only; the bar's now-playing
  cover (`media.animatedBarCover`) still draws the static art.

## Launcher
- Clipboard split preview, width/height size morph, row add/remove motion.

## Headset card
- Escape only after a click gives it focus; no click-away dismissal (owner
  to decide).

## Rig
- `--screensaver-gif` README media are older than the current QML look.
- The real 33 ms bar-gap budget during a launcher open is measured on
  e1504g, not in the software-rendered VM.
