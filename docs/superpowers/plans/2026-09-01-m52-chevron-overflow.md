# M52: the bar chevron gets the tray's second bar

**Date:** 2026-09-01
**Status:** implemented 2026-09-01. Landed in two passes: fe0a74b (the second
bar, opened when the group had no room) and the follow-up below, which made it
the group's only home.
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(spec wins on conflict). `docs/DESIGN.md` §3 Bar is amended with the
chevron's own overflow, beside the tray's.

## Owner's ask (2026-09-01)

"When there's audio playing, and i open the chevron in the bar, i cant see
the hidden stuff as it gets clipped. I need a solution similar to the tray."

Then, on the first pass: "Maybe I want the chevron to always open the second
bar just like the three dots." And on the second: "opening the item in the bar
has an issue, clicking an item doesnt leave the bar open and it must displace
from the bar just like the system tray does. Also, the chevron must rotate to
the correct dir."

## What was wrong

The centre region is uncapped and the two end regions clip against it
(`Bar.qml`'s `Math.min` on each end region's width). A playing track widens
the centre by the length of its title, so a right-region chevron could expand
a group into room that was no longer there: the state flipped, the cells were
laid out, and the strip cut them off at the centre's edge.

The tray already had the answer (`widgets/Tray.qml` + `TrayOverflow.qml`):
what does not fit moves WHOLE into a second bar hanging off the cell that
would have carried it, the way Ice and Bartender give the macOS menu bar a
second row. The tray also already had the harder half of that call: the dots
are where the tray lives, not a state a crowded bar falls into.

## What landed

1. **The surface** (`shell/Surfaces/Bar/BarOverflow.qml`). A headerless
   `Panel`, one shared instance in `shell.qml` like `TrayOverflow`. It renders
   `Bar.qml`'s OWN region delegate, handed over by whichever chevron attached,
   over copies of the governed entries with the `collapsible` annotation
   cleared (`layout.js`'s `overflowEntries`). A `Component` carries its
   creation context, so a cell instantiated there still resolves the panels,
   screen and menu only `Bar.qml` has: no second widget registry, and a new
   widget joins this surface by being on the bar. Its `Repeater` model is
   gated on the window being mapped, so a second live copy of a polling widget
   is not left running behind a closed card. No keyboard cursor: a bar cell
   has no activation contract beyond a click, unlike a `TrayCell`.
2. **The group lives there, always.** `Bar.qml`'s region delegate keeps every
   `collapsible` entry off the strip, full stop. M24's collapse gate, M25's
   width animation, `state.json`'s `barCollapsed` and the whole fit
   measurement the first pass shipped (`Bar/chevron.js`, `_regionFits`,
   `_refit`) are deleted rather than left as a second path: one control, one
   place the group can be, nothing measured.
3. **A cell in the card opens on top of the card.** `Panel.openFrom()` now
   resolves `owner` from the anchor cell's own window, so any cell living in a
   popout opens its panel over that popout (one `barMargin` clear of it,
   `_ownerShift`) instead of replacing it. That was already the contract
   between `TrayMenu` and `TrayOverflow`, passed by hand; it is now read off
   the cell, and `TrayMenu.openItem`'s explicit `owner` is left only for its
   keyboard path, which has no cell to read.
4. **The glyph points at the card.** Shut it points away from the bar's edge
   (down from a top bar, up from a bottom one, sideways off a vertical one),
   open it points back at the bar. `governsBefore` decides what is in the
   card, never which way the cell points: nothing travels along the strip any
   more.
5. **The IPC** (`BarIpc.qml`). `bar chevron toggle|expand|collapse` open and
   close that bar. `chevron status` reports `collapses` and `open` per region;
   `collapsed`/`hidden` are gone with the state behind them.

## Verification

- `just test`: 2035 passed, 0 failed. `tests/tst_bar_chevron_overflow.qml`
  covers what the second bar is handed (both governed sides, a module entry
  surviving the copy whole, a region with no chevron);
  `tests/tst_bar_entry_reveal.qml`'s gate follows the delegate's new one.
- `just vm-lint`: all checks passed (qmllint + qml-tests, aarch64-linux).
- `just vm-smoke --chevron` (rewritten): the five governed names off the strip
  with the card shut, `bar chevron expand` opening it, a real `wlrctl` click
  on the card's middle cell opening the weather panel with the card still up
  (`panel state` weather, `open` still true), and `collapse` shutting it.
  Frames read: the panel sits below the card, the card keeps its cells, the
  chevron points up while open.
- `just vm-smoke --tray`, `--tray-overflow`, `--panel network`: unchanged,
  which is what covers the `openFrom` owner change on the paths that already
  had one and the ordinary bar-cell path that must still have none.

## Not done

Keyboard reach into the card. Every other popout has a cursor; this one has
none, because a bar cell exposes no activation beyond a click. Giving `Cell` a
real activate contract is its own task, and would let the card take the same
`cursorCount`/`onCursorActivated` shape `TrayOverflow` already has.
