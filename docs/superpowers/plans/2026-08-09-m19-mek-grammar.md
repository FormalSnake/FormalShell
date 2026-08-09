# FormalShell M19: the mek grammar — live-site study, dog-ears, title bars, ink buttons

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding — especially the
> "Revision 2026-08-07: warm ink hierarchy (the mek ramp)" block this plan
> builds on, and the new "Revision 2026-08-09" block Task 1 adds. The spec
> wins over this plan on conflict.

**Origin, owner ask (2026-08-09):** "Thoroughly study mek.gallery's website
design language. I want to create an omarchy style desktop shell that
matches the look and feel of mek.gallery's style. Then update the shell and
the Design.md."

**Research already done (2026-08-09), do not re-derive.** The live site was
driven in a real browser (Dark Reader defeated via its `darkreader-lock`
meta opt-out — the first naive capture was a Dark Reader recolor, not the
site), measured from computed styles and pixel-sampled screenshots across
home, /about, /pixel, /dev, and the PROJECTS dropdown. Artifacts in
`artifacts/mek-study/` (gitignored).

*Palette, confirmed unchanged from the 2026-08-07 capture:* canvas
`#eee9dc`, panel step `#d9d2c1`, hairlines 1px `#b6b1a3`, faint meta
`#9c9587`, meta ink `#636059`, content ink `#2e2e2e`, one loud blue
`#0099ff` (links, always underlined; 137 uses), fill tint
`rgba(99,96,89,0.08)`. New findings: a warm dark card `#33241e` (the
announcement modal — paper `#eee9dc` as content ink on it, `#9c9587` as the
shared meta ink on both grounds), and the site's own
`prefers-color-scheme: dark` swaps just 9 tokens to a terminal facet
(`#000` canvas, `#161617` surface, `#fff` ink, `#0f0` green accent) while
the paper ramp tokens stay put — the shell's dark mode is that facet of the
same language, not a divergence.

*Grammar measured live that DESIGN.md does not yet encode:*

- **Dog-ear fold marks, not corner squares.** Ledger cells and cards carry
  a small folded-corner triangle at the top-left corner, drawn in the
  hairline ink family. The 6px corner *squares* the 2026-08-07 revision
  cites no longer exist anywhere in the live DOM (a full scan for 4-8px
  square divs found zero).
- **Card title-bar band.** The modal opens with a one-row band: uppercase
  label left in faint ink (`ANNOUNCEMENT`), action right in bright ink
  (`CLOSE X`), a shared 1px rule below. Page sections use the same band
  with a trailing colon (`DROP A MESSAGE:`, `DEV WORKS & PROJECTS:`), and
  the nav's running page title reads `ABOUT MEK.TXT:` — colon included.
- **Trailing colon on every section header.** No exceptions found.
- **Slash-fused meta pairs.** `Jul 2026 / DEV`, link bands
  `SANROK Studio / Exhibition & Media / OBJKT`. (The shell already does
  this — `PENDING / 2`, `appName / relTime` — now named as law.)
- **Hover is ink promotion.** Nav labels idle at meta `#636059` and promote
  to content `#2e2e2e` on hover; background does not change. The current
  nav cell promotes ground instead (panel step → canvas).
- **Ink-fill primary button.** The form's Submit is a full-bleed `#2e2e2e`
  (content ink) fill with paper text. Blue is never a button; it is spent
  only on links/selection.
- **Faint placeholders.** Input placeholder ink sits in the
  hairline/faint band, one band below field labels (`#636059`).
- **No zebra striping.** The PROJECTS dropdown pixel-samples flat
  `#d9d2c1` on every row (what reads as alternation is glyph density).
  Summoned surfaces sit one step below canvas with shared 1px rules.
- **Dings ornament as filler.** Empty column ends carry faint
  asterisk-family glyphs (`✳ ❋`) from the MEK Dings faces.
- **Measured but NOT adopted:** the modal's `box-shadow: 4px 4px 0
  rgba(0,0,0,.25)` hard offset plate (no-shadows hard rule stands); the
  custom bitmap faces (fontconfig `monospace` alias hard rule stands);
  hidden scrollbars (n/a); mek's sub-AA header contrast (`#9c9587` on
  canvas ≈ 2.2:1 — shell headers stay `foregroundDim` per the 2026-08-07
  WCAG stance, a deliberate divergence).

*Shell code map (2026-08-09, verified file:line):*

- `shell/Components/CornerMarks.qml:1-38` — four 3px `foregroundFaint`
  squares via `Repeater`; instantiated at `shell/Components/Panel.qml:298`,
  `shell/Surfaces/Menu/Menu.qml:1197`,
  `shell/Surfaces/Notifications/Center.qml:324`,
  `shell/Surfaces/Notifications/Toasts.qml:154` (per-toast),
  `shell/Surfaces/Osd/Osd.qml:287`; registered `shell/Components/qmldir:4`.
- `shell/Components/Panel.qml:240-249` — the one existing title row
  (`titleCell`: `Cell` + `MetaLabel { text: root.panelTitle }`).
- `shell/Surfaces/Notifications/Center.qml:191-232` — DND / CLEAR ALL
  action cells (each `selected` on hover), then conditional `MetaLabel`
  headers `"NO NOTIFICATIONS"` (238-240), `"PENDING / N"` (243-249),
  `"EARLIER / N"` (276-282). No card title.
- `shell/Surfaces/Menu/Menu.qml:1071-1073` — breadcrumb `MetaLabel` inside
  `searchCell`; breadcrumb text computed at `Menu.qml:394-406`.
- Section headers are bare `MetaLabel`s, no colons anywhere:
  `AudioPanel.qml:329/408/487`, `BluetoothPanel.qml:678/690/702`,
  `MediaPanel.qml:28`, `PowerPanel.qml:297/304/399`,
  `NetworkPanel.qml:1225/1274/1286`, plus the Center lines above.
- `shell/Components/MetaLabel.qml` — caption-size, `Font.AllUppercase`,
  `Theme.letterSpacing.meta`, fixed `foregroundDim`.
  `ActionLabel.qml` — body-size sibling, caller-colored.
- `shell/Surfaces/Notifications/NotificationCard.qml` — shared
  toast/center card: header `MetaLabel` `appName + " / " + relTime`
  (131-134), dismiss `✕` cell (169-196), action row cells (199-239, hover
  = selected inversion).
- `shell/Components/Cell.qml` — fill priority urgent > accent > warning >
  selected-inversion (184-192); `standalone` bar-cell hover inversion
  (219); shared-rule contract draws bottom+right only (241-257).
- Glyph-bearing files (targeted Edits only — broad PUA scan incl.
  supplementary planes): `AuthPrompt.qml`, `default-menu.jsonc`, the Bar
  widgets (Audio/Battery/Bell/Bluetooth/Github/Indicators/Network/
  NowPlaying/Tailscale/Usage), `Osd.qml`, `MediaPanel.qml`,
  `NetworkPanel.qml`, `WeatherPanel.qml`, `shell/Weather/openmeteo.js`.

## Constraints

- All CLAUDE.md hard rules stand: nested-session testing only, D-Bus
  isolation, radius 0, **border 2**, no blur, **no shadows** (the mek hard
  plate is explicitly not adopted), fontconfig `monospace` alias, Nerd
  Font glyphs via targeted Edits, honest unavailable states, opaque
  compositor ids, conventional commits, verification evidence before
  every commit.
- No feature, IPC, provider, or state-machine changes. Drawn output plus
  the minimal component API additions named below.
- No palette change: the 12 roles cover everything here (`rule` for
  structure, `foregroundFaint` for ornament, `foreground`/`background`
  for the ink button, existing inversion pairs untouched).
- **Matugen compat is a hard requirement (owner, 2026-08-09).** The
  theming contract does not move: `theme.json`'s 12 keys, the matugen and
  pywal templates, and `ThemeEngine` are all untouched. Every new drawn
  element resolves a `Theme.color` role — never a literal hex — so any
  matugen/pywal/hand-written theme recolors the new chrome identically to
  the old. Task 5's `--wallpaper` leg is the proof gate: the dog-ear,
  title bars, and ink buttons must visibly recolor with the wallpaper
  theme, not fall back to Flexoki.
- The 2026-08-07 owner directives stand: bar-cell hover stays accent
  inversion; ledger selection stays the accent pair; the photo-negative
  *selection* stays retired. The ink button (Task 4) is a resting
  affordance, not a selection state — Task 1 words that carve-out.
- Motion rules untouched. Dog-ears and title bars are static.
- `just build` needs `git add` first. Every visual claim needs a
  `just vm-smoke` leg with the PNG actually Read (VM is up:
  `dev/vm.sh status` → running, ssh on 127.0.0.1:2222).
- Commits exclude `CLAUDE.md`/`CLAUDE-*.md`. No Co-Authored-By lines.

### Task 1: DESIGN.md revision 2026-08-09 — the mek grammar

Add a revision block after the 2026-08-07 one, and amend the body text it
touches, encoding the study above:

- **§2 item 7 rewritten:** corner marks become the **dog-ear fold mark** —
  one small right triangle (legs along the top and left border edges,
  `Theme.space.lg`-sized at scale 1.0), `foregroundFaint`, at the
  top-left corner of every floating card's border ring, replacing the
  four corner squares. Record the live-site correction (squares no longer
  exist; the fold mark is what ships) and that ours stays in the ornament
  band (`foregroundFaint`) per §1.4 while mek draws it hairline-colored.
- **§2 new item: card title-bar band.** Every floating card opens with a
  one-row band: uppercase meta label + trailing colon, left,
  `foregroundDim`; optional right-aligned meta or bare-label actions; one
  shared rule below. Menu's breadcrumb row and the panels' existing title
  row are this band; the notification center gains one.
- **§2 new item: trailing colon on section headers** (and the title-bar
  label). Inline meta pairs (`PENDING / 2`, `APP / 2M AGO`) take no colon
  and fuse with ` / ` — the slash idiom named as law.
- **§2 new item: the ink button.** A committing action's resting cell
  fills `foreground` with `background` ink — full-bleed, borderless,
  radius 0. Hover/press keep the accent-pair inversion. Explicitly
  distinct from the retired photo-negative *selection*; accent remains
  selection/current, urgent remains critical, blue-as-button stays
  banned.
- **§1.1 amendment: ink-promotion hover for bare labels.** A label-only
  control inside a title-bar band (no cell chrome of its own) hovers by
  promoting its ink one band (`foregroundDim` → `foreground`), fills
  untouched — mek's nav behavior. Cells keep the fill-alpha/inversion
  model; the bar-cell accent-inversion directive stands.
- **Placeholders:** field placeholder ink is `foregroundFaint` (one band
  under field labels/meta).
- **Study notes:** the warm dark card `#33241e` with paper ink and shared
  `#9c9587` meta (recorded as reference, no role added); the terminal
  facet of mek's own dark scheme; the measured-but-not-adopted list
  (hard plate shadow, bitmap faces, hidden scrollbars, sub-AA headers);
  no-zebra correction; dings-filler idiom (permitted as a faint empty
  state ornament, never mandated).

Verify: doc-only — re-read the diff against this plan's research section;
no build claim needed.

### Task 2: Dog-ear fold mark replaces CornerMarks

- New `shell/Components/DogEar.qml`: one `Canvas`-free triangle (a
  rotated/clipped `Rectangle` is fine, or `Shape`-less: two stacked
  rectangles won't make a clean hypotenuse — use a tiny `Canvas` like
  `DitherFill.qml` precedent, repainting only on resize/color change) at
  the frame's top-left, legs `Theme.space.lg * Theme.spacingScale` along
  the top and left border edges, `Theme.color.foregroundFaint`, sitting on
  the border ring like CornerMarks did.
- Replace the five call sites (`Panel.qml:298`, `Menu.qml:1197`,
  `Center.qml:324`, `Toasts.qml:154`, `Osd.qml:287`), update
  `shell/Components/qmldir`, **delete `CornerMarks.qml`** and any test
  referencing it (update, don't skip).
- Verify: `git add -A && just build && just test && just lint`; `just
  vm-smoke --menu`, Read the PNG: the menu card's top-left corner shows
  the fold triangle, the other three corners show plain 2px border.

### Task 3: Card title-bar band + trailing colons

- New `shell/Components/CardTitleBar.qml`: a `Cell`-based band — left
  `MetaLabel` with the colon appended, optional default-alias right slot
  for meta text or bare-label actions. Shared-rule contract as today
  (band draws its bottom rule; frame erasers unchanged).
- `MetaLabel.qml` gains `property bool colon: false` appending `":"`
  (rendering only — never mutates externally sourced strings).
- `Panel.qml` `titleCell` (240-249) → `CardTitleBar` (panel titles gain
  the colon).
- `Center.qml`: gains `CardTitleBar { title: "NOTIFICATIONS" }` with DND
  and CLEAR ALL as its right-side bare-label actions (replacing the
  191-232 action-cell row); their hover becomes ink promotion (Task 1's
  §1.1 amendment) instead of selected-inversion. Section headers
  (`PENDING / N`, `EARLIER / N`, `NO NOTIFICATIONS`) set `colon: false`
  explicitly — they are slash-meta rows, not headers... except
  `NO NOTIFICATIONS`, which is an empty state and stays bare.
- Menu breadcrumb (`Menu.qml:1071-1073`) sets `colon: true`.
- Panel section headers gain `colon: true` at the mapped call sites
  (`AudioPanel.qml:329/408/487`, `BluetoothPanel.qml:678/690/702`,
  `MediaPanel.qml:28` stays bare (`NO PLAYER` is an empty state, not a
  header), `PowerPanel.qml:297/304/399`,
  `NetworkPanel.qml:1225/1274/1286`). Rule of thumb, from the study:
  a label that *introduces content below it* gets the colon; an empty
  state or inline meta row does not. NetworkPanel and WeatherPanel are
  glyph-bearing — targeted Edits only.
- Verify: `git add -A && just build && just test && just lint`;
  `just vm-smoke --notify --center` and `--panel audio`, Read both PNGs:
  center shows the `NOTIFICATIONS:` band with DND/CLEAR ALL right, audio
  panel headers read `OUTPUT:`/`INPUT:`/`APPS:`.

### Task 4: Ink buttons + faint placeholders

- `Cell.qml` gains an `ink` state flag: fill `Theme.color.foreground`,
  content ink `Theme.color.background`, borderless, sitting in the fill
  priority between `warning` and `selected`; hover/press on an ink cell
  keeps today's accent-pair inversion. Extend the existing Cell QML tests
  for priority order.
- Apply: `NotificationCard.qml` action-row cells (199-239) and the
  polkit dialog's confirm affordance (`PolkitDialog.qml` — locate its
  confirm cell; cancel stays plain). Menu confirm rows keep `accent`
  (selection-grade, per the standing directive).
- Placeholders → `foregroundFaint`: menu search `TextInput`
  (`Menu.qml:1075-1145` region) and `AuthPrompt.qml`'s
  `ENTER PASSWORD` placeholder (glyph-bearing file — targeted Edit).
  Field *labels* stay `foregroundDim`.
- Verify: `git add -A && just build && just test && just lint`;
  `just vm-smoke --notify`, Read the PNG: a toast with actions shows
  full-bleed ink-fill action cells with paper text; `--lock` leg, Read
  `lock-locked.png`: placeholder visibly quieter than before against the
  field label.

### Task 5: Full smoke sweep + screenshot regeneration

- Legs, each PNG Read and judged against Tasks 2-4's checkable claims:
  plain (bar), `--menu`, `--notify --center`, `--osd`,
  `--panel audio`, `--panel power`, `--picker`, `--lock`, `--wallpaper`
  (ramp survives matugen retheme with the new chrome).
- Regenerate the touched `docs/screenshots/*-niri.png` per the mapping in
  the code map (menu, menu-apps, share-menu, notifications,
  notifications-center, indicators, osd, panels set, picker, lock,
  clipboard pair — anything whose surface chrome changed), including the
  manual-scp names (`theme-dark/light`, `menu-apps`) per
  the capture notes in `docs/SWITCHOVER.md`. Update README captions only
  if a caption's wording is now wrong.
- Verify: every regenerated PNG Read; `git add -A && just build && just
  test && just lint` green as the final gate.
