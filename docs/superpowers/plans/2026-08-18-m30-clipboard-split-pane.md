# FormalShell M30: clipboard history split pane

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. Runs after M29
> (`2026-08-18-m29-device-panels.md`); no file overlap with it.

**Origin, owner ask (2026-08-18):** "Copy omarchy's clipboard history
layout. It's way better."

**Research already done (2026-08-18), do not re-derive:**

- The referenced layout is omarchy quattro's
  `shell/plugins/clipboard/Clipboard.qml` (local read-reference clone at
  `~/Developer/omarchy`, commit `f32ebbdb`). What it is: one centered
  card (~875 wide, ~600 tall, both capped to the screen), a search line
  as the header, then a **50/50 horizontal split** — left half a list of
  history rows (image rows lead with a thumbnail, text rows carry a
  single-line preview), right half a **full preview pane** behind one
  vertical hairline: the cursor row's complete text, wrapped and
  top-aligned, or the full image `PreserveAspectFit`. Typing filters the
  history **route-locally** (never a global search), and an empty list
  renders a centered empty state ("Clipboard is empty" / "No matches").
  The card height is fixed, not content-sized, so the preview pane is
  always tall enough to be useful.
- We **reimplement in our own language** (DESIGN.md: omarchy is a close
  reference, read-only; no code is copied, no attribution header
  applies). The menu stays the surface and the clipboard level becomes
  the menu's second view swap — the precedent is the picker grid
  (DESIGN.md §3 Menu: "a view swap over one level, not a second
  surface"): same card, same search cell, same cursor state, same action
  bar, same close paths, same `menu summon clipboard` smoke drive.
- Data already exists: `ClipboardService.items` entries are
  `{id, text, capturedAt}` or `{id, kind: "image", path, capturedAt}`;
  `Providers.clipboardProvider` builds the rows (truncated
  `previewLabel`, `thumbSource` for images). What the rows do NOT carry
  today is the full text — the preview pane needs it.
- Today's gaps vs the reference, which are the milestone: (1) no preview
  pane — a 60-char truncated label is all you ever see of an entry;
  (2) typing at the clipboard level falls through to whole-tree
  `Search.rank`, so the list stops being clipboard history the moment
  you filter; (3) an empty history renders zero rows with no honest
  note; (4) the 560px menu step is too narrow to split.

## Constraints

- CLAUDE.md hard rules bind: runtime testing ONLY on the VM rig
  (`just vm-test` / `vm-lint` / `vm-smoke`), honest unavailable states,
  targeted Edits on glyph-bearing files, conventional commits (one per
  task, pushed, tree clean).
- DESIGN.md is the authority and this plan schedules the restyle: rows
  keep the ledger idiom (§2.1 shared rules, §2.2 accent inversion),
  meta text through `MetaLabel` (§2.3), ` / ` fusion and no colon on
  content meta / empty states (§2 item 10), every size a
  `Theme.space`/`Theme.fontSize` token (§1.3 — the new width is a named
  token step, documented in the table, never a literal), ink bands per
  §1.4. Preview imagery stays **true-color**: §2 item 12 names menu
  thumbnails out of the dither list, and the preview pane is the same
  content at a bigger size.
- The `--clipboard` smoke leg's existing assertions (capture order,
  copy round trip, image dedup) must stay green untouched; only its
  screenshot changes.
- No service or IPC changes: `ClipboardService`, `ClipboardIpc`, and
  the rows' activation actions are untouched. Layout only.

---

### Task 1: provider rows carry preview data; route-local filter; honest empty rows

**Files:** modify `shell/Menu/providers.js`,
`tests/tst_menu_clipboard.qml`.

**Produces:**
1. `clipboardProvider` rows additionally carry `fullText` (the entry's
   whole text, `""` for images) and `time` (the existing
   `_capturedAtLabel` HH:MM, now on every row, not just images —
   `desc`'s image-only behavior stays exactly as shipped so the left
   list doesn't change).
2. `clipboardSearch(rows, query)` — pure: case-insensitive substring
   match over `fullText` (falling back to `label`, which is what image
   rows carry), empty/whitespace query returns `rows` unchanged.
3. `clipboardEmptyRow()` and `clipboardNoMatchRow()` — dim
   non-activatable note rows (`kind: "note"`, `dim: true`, mirroring
   `_nixNoteRow`'s shape) labeled `CLIPBOARD EMPTY` / `NO MATCHES`
   (§2.10: empty states take no colon).
4. Tests extend `tst_menu_clipboard.qml`: `fullText`/`time` present on
   text and image rows; search matches beyond the 60-char label
   truncation (a >60-char entry found by its tail); image rows found by
   "image"; case-insensitivity; empty query passthrough; both note-row
   shapes.

**Verify:** `just vm-test`, `just vm-lint`. Commit
(`feat(menu): clipboard rows carry preview data and a local filter`).

### Task 2: the split-pane clipboard level in Menu.qml

**Files:** modify `shell/Surfaces/Menu/Menu.qml`,
`shell/Surfaces/Menu/MenuRow.qml`, `shell/Theme/tokens.js`,
`docs/DESIGN.md`.

**Produces:**
1. `tokens.js`: `popupWidthMenuSplit: 840` — the menu's own split-pane
   step (1.5× `popupWidthMenu`), added to DESIGN.md §1.3's width-step
   table and its "four snap points" sentence updated to five.
2. `_isSplitRoute` in Menu.qml: `_mode === "menu"` and `currentNodeId`
   is `"clipboard"` or `"share.history"` (both levels list the same
   history; the share picker gets the identical layout for free).
   `implicitWidth` snaps to `popupWidthMenuSplit` on the route.
3. **Route-local rows** in `_displayRows`, branched exactly where the
   picker route branches (before the trigger checks): the level's
   `visibleChildren` through `Providers.clipboardSearch(rows, q)`; an
   empty history yields `[clipboardEmptyRow()]`, a query with no hits
   `[clipboardNoMatchRow()]`. Whole-tree rank never runs on the route.
4. **The split**: on the route `rowsView` takes the left half of
   `_contentWidth`; the right half is the preview pane — one vertical
   `Theme.color.rule` hairline at `Theme.borderWidth` (shared-rule
   contract: the pane draws it, rows don't double it), then
   `popupPadding`-inset content bound to `_cursorNode`:
   - a `MetaLabel` meta pair at the top, `TEXT / 14:02` or
     `IMAGE / 14:02` (§2.10 fusion, no colon), from the row's
     kind + `time`;
   - below it the full content: wrapped complete text
     (`Theme.fontSize.body`, `foreground` ink, `Text.WrapAnywhere`,
     top-aligned, clipped at the pane) or the true-color image
     (`PreserveAspectFit`, top-aligned, `sourceSize` capped at the
     pane's size like the picker grid's decode cap);
   - a note-row cursor (empty/no-match) renders an empty pane.
5. **Fixed height on the route**: `_rowsAreaHeight` takes the full
   available cap (the existing 60%-of-screen formula) instead of
   content height, omarchy's fixed-card parity — the preview pane is
   never one row tall.
6. `MenuRow`'s label gains a width cap + `elide: Text.ElideRight`
   within the cell (leading slots and the trailing indicator reserve
   subtracted): provider-side truncation normalizes multi-line text,
   but a 60-char label overflows a 420px pane, and the cap fixes every
   route at once.
7. DESIGN.md §3 Menu bullet: name the split pane as the menu's second
   view swap alongside the grid, one sentence in the picker's own
   pattern.

**Verify:** `just vm-test`, `just vm-lint`, `just vm-smoke --clipboard`
— **Read the PNG**: wider card; left half ledger rows with the cursor
row accent-inverted; right half shows the cursor row's meta pair and
full text; exactly one vertical rule between the halves; breadcrumb and
action bar intact; and the leg's `clip-*.json`/`clip-paste.txt`
assertions unchanged. Commit
(`feat(menu): split-pane clipboard history with full preview`).
