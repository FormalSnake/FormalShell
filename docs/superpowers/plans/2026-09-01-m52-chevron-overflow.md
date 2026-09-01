# M52: the bar chevron gets the tray's second bar

**Date:** 2026-09-01
**Status:** implemented 2026-09-01.
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(spec wins on conflict). `docs/DESIGN.md` §3 Bar is amended with the
chevron's own overflow, beside the tray's.

## Owner's ask (2026-09-01)

"When there's audio playing, and i open the chevron in the bar, i cant see
the hidden stuff as it gets clipped. I need a solution similar to the tray."

## What was wrong

The centre region is uncapped and the two end regions clip against it
(`Bar.qml`'s `Math.min` on each end region's width). A playing track widens
the centre by the length of its title, so a right-region chevron could expand
a group into room that was no longer there: the state flipped, the cells were
laid out, and the strip cut them off at the centre's edge. Nothing was
broken about the collapse; the bar simply had no answer for a group that
does not fit.

The tray already has that answer (M-tray, `widgets/Tray.qml` +
`TrayOverflow.qml`): what does not fit moves WHOLE into a second bar hanging
off the cell that would have carried it, the way Ice and Bartender give the
macOS menu bar a second row.

## What landed

1. **The fit** (`shell/Bar/chevron.js`, `Bar.qml`). Per region, does the
   governed group still fit on the strip? `groupAlong()` is what an expanded
   group costs (each governed cell's own implicit extent plus one `spacing`
   each, measured off the Loaders rather than predicted), `fitsInline()`
   compares it against the strip's leftover room. Capacity, not slack, is
   the invariant term (`slack + (expanded ? need : 0)`), which is what stops
   the answer oscillating: collapsing the group frees room, and that must not
   read back as "room again". Written by a `_refit()` pass on a timer past the
   reveal's own animation, never bound, for the same reason `Tray.qml`
   documents at length.
2. **The gate** (`Bar.qml`'s region delegate). No room outranks the stored
   state: the group is off the strip whatever `state.barCollapsed` says, so
   the two surfaces never draw it twice. The state itself is never written by
   the fit, so the group returns to the strip, open, the moment the room does.
3. **The surface** (`shell/Surfaces/Bar/BarOverflow.qml`). A headerless
   `Panel`, one shared instance in `shell.qml` like `TrayOverflow`. It renders
   `Bar.qml`'s OWN region delegate, handed over by whichever chevron attached,
   over copies of the governed entries with the `collapsible` annotation
   cleared (`layout.js`'s `overflowEntries`). A `Component` carries its
   creation context, so a cell instantiated there still resolves the panels,
   screen and menu only `Bar.qml` has: no second widget registry, and a new
   widget joins this surface by being on the bar. No keyboard cursor: a bar
   cell has no activation contract beyond a click, unlike a `TrayCell`.
4. **The control** (`ChevronWidget.qml`). Off the strip the cell toggles that
   bar instead of the collapse, shows the open-panel mark while it is up, and
   its glyph tracks the second bar rather than the state. The tooltip says
   what it now is: `BAR / n ITEMS`, the tray's own words.
5. **The IPC** (`BarIpc.qml`). `bar chevron toggle|expand|collapse` address
   the second bar while a region is off the strip, so one control keeps one
   summon path however crowded the bar is, and `chevron status` gains
   `offStrip`/`overflowOpen` per region. That is the only headless read of a
   fit that is otherwise measured per output, and the new smoke leg is built
   on it.

## Verification

- `just test`: 2038 passed, 0 failed, including
  `tests/tst_bar_chevron_fit.qml` (the cost arithmetic, the room answer, the
  same-answer-in-either-state claim the whole design rests on, and
  `overflowEntries` leaving the strip's own entries annotated).
- `just vm-lint`: all checks passed (qmllint + qml-tests, aarch64-linux).
- `just vm-smoke --chevron`: unchanged. The group still opens in place on a
  bar with room, `offStrip:false` throughout, both frames read.
- `just vm-smoke --chevron-overflow` (new leg): `offStrip:true` on a bar with
  a 1600px centre, `bar chevron expand` opens the second bar
  (`overflowOpen:true`) with `collapsed:true` untouched, the two frames
  differ, and `collapse` shuts it. Both frames read: the strip keeps the
  chevron and the cells outboard of it, and the card under the chevron
  carries the three governed cells this rig actually shows.

## Not done

The "room came back" path (the second bar closing itself when the centre
narrows again) is `noteOffStrip()`'s own branch and is not covered by a leg:
the rig has no way to resize a bar cell mid-session. The fixture that would
need it is a live MPRIS player whose title changes length, which
`--media` owns.
