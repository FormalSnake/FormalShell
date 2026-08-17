# CLAUDE-patterns.md

Established conventions for FormalShell, added to as they solidify. Not
committed (repo rule) — local reference only.

## Token system (M18: the mek ramp, 2026-08-07)

- **Ink hierarchy is law** (`docs/DESIGN.md` §1.4): loudness order on any
  surface is `foreground` (content) > `foregroundDim` (meta/uppercase
  captions) > `foregroundFaint` (disabled/ornament/dither, never content
  ink) > `rule` (structure). Structural borders/rules always draw `rule` @
  alpha 1.0 — never a `foreground` alpha blend. `accent`/`urgent`/`warning`
  sit outside the ramp as full-bleed fills or inversions only, never tints.
- **Palette is 12 roles** (`shell/Theme/palette.js` `COLOR_KEYS`, exact
  order matters — `mergeWithFallback`'s equality test depends on it):
  `background`, `backgroundAlt`, `foreground`, `foregroundDim`,
  `foregroundFaint`, `rule`, `accent`, `onAccent`, `urgent`, `onUrgent`,
  `warning`, `onWarning`. `theme.json` is the whole theming contract —
  matugen (`theme.json.tmpl`), pywal (`pywal-theme.json.tmpl`, user-applied,
  not run by the shell), or a hand-written file all theme identically by
  writing these same 12 keys. Per-key fallback to Flexoki keeps
  pre-expansion theme.json files valid.
- **Selection/hover inversion is always the accent pair**, never a photo
  negative: `Theme.inverted(role)` returns `{bg, fg}` from
  `Tokens.invertedPair(colors, role)`, `role` defaults `"accent"`
  (`{bg: accent, fg: onAccent}`), pass `"urgent"` for urgent-carrying rows.
  No boolean `useAccent` flag exists anymore.
- **`Theme.stateStyle(state, colorToken, borderToken)`**: border color
  always resolves to `Theme.color.rule` at alpha 1.0 unless `borderToken`
  explicitly names a semantic exception (`"urgent"`/`"accent"`).
  `STATE_APPEARANCE` (`tokens.js`) carries only `{fillAlpha, borderWidth}`
  per state — no per-state border color/alpha anymore.
- **No double treatment**: a cell already carrying a full-bleed
  `accent`/`urgent`/`warning`/`selected` fill never also gets hover
  inversion or the pending-row dither — check the exclusion condition when
  adding a new full-bleed state to `Cell.qml`.
- **Ornament components** (`shell/Components/`): `DogEar.qml` (M19: one
  Canvas-drawn `foregroundFaint` right triangle, legs `Theme.space.lg`,
  at the card's top-left border corner — replaced `CornerMarks.qml`'s
  four corner squares after the 2026-08-09 live-site study found mek
  ships fold marks, not squares; drop into any floating card via
  `anchors.fill: parent`) and `DitherFill.qml` (Canvas-painted 2px-period
  `foregroundFaint` checkerboard for track remainders/pending backdrops,
  exposes a `content` default-alias for stacking a fill on top). Both
  registered in `shell/Components/qmldir`. When nesting `DitherFill` inside
  `Cell.qml`'s `content` slot (a padded inset), it fills that inset, not
  the row — use a sibling of the Cell, not a child, to dither the full row.
- **Semantic layout tokens actually have consumers now**
  (`shell/Theme/tokens.js`): `controlPaddingX`(8)/`Y`(4), `labelGap`(4),
  `popupPadding`(14, summoned list surfaces — menu, notification center),
  `panelPadding`(18, bar-anchored panels), `popupWidth{Narrow,Default,Wide,
  Menu}` (280/320/400/560, snap every panel/popup width to the nearest
  step). `Theme.fieldBorderWidth` (`Core/Theme.qml:23`,
  `Math.round(3 * fontScale)`) is the one password-field border spec, used
  by both `AuthPrompt.qml` and `PolkitDialog.qml`.
- **`Theme.fontFamily`** (string) replaced the old `Theme.font` object —
  every call site reads `.family` off it now; there is no `Theme.font`
  anymore.
- **Uppercase action labels** route through `MetaLabel.qml` (or its
  content-ink sibling `ActionLabel.qml`) — `Font.AllUppercase` +
  `Theme.letterSpacing.meta`, never a bare JS `.toUpperCase()` with no
  tracking, except where the string is real external data (e.g. a
  Bluetooth device name) that shouldn't be rewritten.
- **`warning` role**: spend it only where a genuine ok/degraded/critical
  tri-state already exists in the service layer (e.g. `Power/model.js`'s
  `warnEvent()` for battery). Two-state features (connected/disconnected,
  on/off) stay two-state — do not invent a warning band for them.

## Screenshot regeneration (docs/screenshots/*.png)

Not every filename has a 1:1 `just vm-smoke <flag>` mapping — some smoke
legs print a named artifact path that `dev/vm.sh smoke`'s auto-puller
(matches `^SMOKE_[A-Z0-9_]+ <path>`) does NOT pick up automatically
(`theme-dark.png`/`theme-light.png` from `--theme-toggle`,
`menu-apps.png` from `--menu` — both echoed as plain "label: path" lines,
not `SMOKE_NAME path`). Those need a manual `scp -P 2222 -i
dev/.testvm/keys/test_ed25519 test@localhost:formalshell/<tmp-shot-dir>/<file>.png`
after the run, using the path printed in that run's own stdout.

Two docs filenames sometimes map to the exact same producing leg/screenshot
with no more specific leg existing (`bar-niri.png`/`active-window-niri.png`
both from the plain no-flag leg; `clipboard-niri.png`/
`clipboard-image-niri.png` both from `--clipboard`'s single final
screenshot; `notifications-niri.png`/`indicators-niri.png` both from
`--notify` alone) — copy the one artifact to both names rather than
inventing a second run.

## The mek grammar (M19, 2026-08-09)

- **Card title-bar band**: every floating card opens with
  `CardTitleBar.qml` (`shell/Components/`) — left `MetaLabel` with
  `colon: true`, right default-alias slot for slash-meta text or
  bare-label actions. `MetaLabel` is now an `Item` wrapping an inner
  `Text` (colon appended render-side only); `color`/`elide`/`font` etc.
  forwarded via alias.
- **Colon law**: a `MetaLabel` that introduces content below it gets
  `colon: true`; empty states (`NO PLAYER`, `NO ADAPTER`) and
  `LABEL / VALUE` slash-meta rows stay bare.
- **`Cell.ink`**: resting fill `foreground`, content `background`,
  borderless; priority urgent > accent > warning > ink > selected;
  hover/press = accent-pair inversion. Used by notification action
  cells. Confirm-gated menu rows keep `accent` (standing directive).
- **Bare-label hover = ink promotion** (`foregroundDim` → `foreground`,
  no fill); an armed bare label may rest at `accent` ink (DESIGN §1.4
  carve-out — DND is the shipped case).
- **Placeholders** are `foregroundFaint` (AuthPrompt, PolkitDialog —
  the only two real placeholders; menu search has none).
- mek study artifacts (clean screenshots, measured CSS) live in
  `artifacts/mek-study/` (gitignored). Dark Reader poisons naive
  browser captures of mek.gallery; defeat it with a
  `<meta name="darkreader-lock">` injection before sampling.
