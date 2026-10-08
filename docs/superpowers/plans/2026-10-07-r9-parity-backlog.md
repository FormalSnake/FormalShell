# R9 parity backlog

Differences from the QML shell that milestone agents reported and left.
Each is fixed, or kept with the owner's say-so, before R9 cuts over. Grouped
by surface; one line each.

## Panels
- Calendar: the life-progress prompt needs the launcher's input answer routed back to the
  panel (`wayland/launcher.rs`'s resolved tokens), which the R4b launcher agent holds.

## Media
- Radio Atlas: its icon buttons carry no hover tooltips (the launcher's card
  routes none to the tooltip group either).

## Rig
- `--screensaver-gif` README media are older than the current QML look.
- The real 33 ms bar-gap budget during a launcher open is measured on
  e1504g, not in the software-rendered VM.
