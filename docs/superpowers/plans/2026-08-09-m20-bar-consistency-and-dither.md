# FormalShell M20: bar consistency, full inversion, 1-bit dithered imagery

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding — including M19's
> "Revision 2026-08-09: the mek grammar" block. The spec wins over this
> plan on conflict.

**Origin, owner ask (2026-08-09, after reviewing M19's screenshots):**
"In the bar, workspace buttons have margins, other buttons don't, time
and weather only partially invert, and a cool feature that idk if its
doable cheaply is mek.gallery's style of images being like ASCII dithered
or something, would be cool to apply to the apple music GIFS and album
covers. And for consistency, the audio visualizer can also have the
dithered ASCII effect like progress bars."

**Research already done (2026-08-09), do not re-derive. All file:line
verified this session:**

*Bar margins.* Every bar cell pads via `Cell.qml`
`controlPaddingX/Y` (8/4); regions space entries `Theme.space.sm` (4px,
`Bar.qml:296,323,346`) with `lg` outer margins. 16 of 18 widgets root at
`Cell { standalone: true }` — uniform pills. The two outliers:
`Workspaces.qml:26-29` wraps its per-workspace Cells in an inner
`Row { spacing: Theme.space.xxs }` (2px — the only 2px pill gap on the
bar), and `ActiveWindow.qml:17` is a bare `Item` with no Cell wrapper at
all (no padding box, no hover chrome, no pill).

*Partial inversion.* `MetaLabel.qml:34` defaults
`color: Theme.color.foregroundDim`, which never inverts. Call sites
missing the `color: root.dimForeground` override (the documented pattern,
`Cell.qml:120-133`; correct precedent `Battery.qml:113`,
`UsageWidget.qml:62`): `Clock.qml:25-27` (the TIME caption — "time only
partially inverts"), `WeatherWidget.qml:52-56` (temperature). The
conditional-hardcode variant `cond ? root.foreground :
Theme.color.foregroundDim` (dim branch never inverts):
`WeatherWidget.qml:47`, `GithubWidget.qml:57,67`, `TailscaleWidget.qml:63`,
`UsageWidget.qml:35,54`, `Visualizer.qml:74`. Separately,
`PanelOpenDot.qml:18` hardcodes `accent`, and a standalone cell's hover
fill IS accent (`Cell.qml:249-251`), so the panel-open dot vanishes on
hover in all 11 consumer widgets.

*Dithered imagery.* Album art renders once, `MediaPanel.qml:53-76`
(plain `Image`, 96×96). Apple Music animated art is NOT a GIF: it is a
`QtMultimedia` `Video` overlay (`AnimatedAlbumArt.qml:20-29`) behind a
`Loader` (`MediaPanel.qml:85-90`) that degrades to static art when
QtMultimedia is absent. Zero `ShaderEffect`/`.qsb` anywhere;
`nix/package.nix` is `stdenvNoCC` with no buildPhase (the no-compile
posture is structural). Qt 6.8 `Context2D.drawImage()` accepts a loaded
`Image` ITEM directly (status `Ready` required), and
`getImageData`/`putImageData` exist — a Canvas Bayer pass over 96×96 is
cheap and repaints only on art/theme change, same cost profile as
`DitherFill.qml`. `Item.grabToImage()` exists for the video-frame case.

*Visualizer.* One monospace `Text` of six U+2581-2588 glyphs
(`Visualizer.qml:71-79`, glyph chosen by `model.js:71-81`; six bars,
`model.js:26`; frames from `VisualizerService.frameText`). No
filled/remainder split exists. The track idiom to mirror:
`MediaPanel.qml:130-154` — `DitherFill` across the full track with the
solid fill `Rectangle` forwarded into its `content` slot so only the
true remainder shows dither (same at `Osd.qml:272`,
`AudioPanel.qml:273,370,449`, `PowerPanel.qml:252,360`, others).

*Glyph-bearing (targeted Edits only):* `GithubWidget.qml`,
`TailscaleWidget.qml`, `UsageWidget.qml`, `BellWidget.qml`,
`Battery.qml`, `AudioWidget.qml`, `NetworkWidget.qml`,
`BluetoothWidget.qml`, `NowPlaying.qml`, `Indicators.qml`,
`MediaPanel.qml`, `shell/Weather/openmeteo.js`. Clean (rewrite-safe):
`Workspaces.qml`, `ActiveWindow.qml`, `Clock.qml`, `WeatherWidget.qml`,
`Visualizer.qml`, `Cell.qml`, `MetaLabel.qml`, `PanelOpenDot.qml`,
`DitherFill.qml`, `AnimatedAlbumArt.qml`.

## Constraints

- All CLAUDE.md hard rules stand. Radius 0, no blur, no shadows, border
  2, fontconfig monospace, honest states, nested-session testing only.
- **Matugen compat (owner hard requirement, M19):** no literal hexes;
  every color resolves a `Theme.color` role. The dither duotone renders
  in `foreground`/`background` (and `foregroundFaint` for remainder
  texture) so wallpaper themes recolor it.
- **Pure QML/no compile stands:** the dither is Canvas-based; no
  `qsb`/shadertools, no new build phase, no committed binary assets.
- No IPC/provider/feature-state changes. Bar layout token changes only
  where this plan names them.
- Verification on the mac: `just vm-build` / `vm-test` / `vm-lint` /
  `vm-smoke <flags>`; PNGs Read from ./artifacts/. Commits: conventional
  single-line, no body, no Co-Authored-By; never CLAUDE-*.md.

### Task 1: Bar chrome consistency

- `ActiveWindow.qml`: root becomes `Cell { standalone: true }` like the
  other 16 widgets — same padding box, same hover-inversion chrome (its
  icon+title Row moves into the cell's content slot; the icon stays the
  sanctioned image-icon exception). Preserve its `windowVisible`
  gating and width cap behavior.
- `Workspaces.qml:26-29`: inner `Row` spacing moves `xxs` → `sm` so the
  gap between any two adjacent bar pills is one size everywhere (the
  workspace cluster's 2px was the only deviation). DESIGN §1.3's
  between-groups ≥ 2× within-group law now reads on the region gap —
  bump each region's entry spacing (`Bar.qml:296,323,346`) from `sm` to
  `lg` (8px) so widget-to-widget separation stays 2× the intra-cluster
  gap and the grouping stays legible.
- Verify: `git add -A`; `just vm-build && just vm-test && just
  vm-lint`; `just vm-smoke` (plain leg) — Read the PNG: active-window
  cell now a pill matching its neighbors; workspace pill gaps equal the
  gap between any other two pills in a region; region groups still read
  as groups.

### Task 2: Inversion completeness on the bar

- Add `color: root.dimForeground` to `Clock.qml`'s TIME `MetaLabel` and
  `WeatherWidget.qml`'s temperature `MetaLabel`.
- Replace every `cond ? root.foreground : Theme.color.foregroundDim` dim
  branch with `root.dimForeground` (`WeatherWidget.qml:47`,
  `GithubWidget.qml:57,67`, `TailscaleWidget.qml:63`,
  `UsageWidget.qml:35,54`, `Visualizer.qml:74`) — glyph-bearing files
  take targeted single-line Edits.
- `PanelOpenDot.qml`: gains an `inverted` bool (callers bind their
  cell's hover-inverted state); color resolves `inverted ?
  Theme.color.onAccent : Theme.color.accent` so the dot stays visible on
  the accent hover fill. Update all 11 consumer widgets (glyph files:
  targeted Edits).
- Tests: extend the Cell/bar tests — set `hovered: true` on a standalone
  cell hosting a MetaLabel wired via `dimForeground` and assert the
  label's color equals `Theme.color.onAccent`; assert PanelOpenDot flips.
- Verify: `git add -A`; `just vm-build && just vm-test && just vm-lint`
  green (hover isn't drivable headlessly — the unit tests are the
  inversion evidence; the smoke leg proves no rest-state regression).

### Task 3: 1-bit dithered album art

- New `shell/Components/DitherImage.qml`: Canvas that draws a sibling
  `Image` item once `Ready` (`ctx.drawImage(imageItem, …)`), then
  `getImageData` → luminance → 4×4 ordered Bayer threshold →
  `putImageData` duotone: light pixels `Theme.color.background`, dark
  pixels `Theme.color.foreground` (roles only — retheme recolors it).
  Repaints on source/status/theme change only, mirroring
  `DitherFill.qml`'s structure. Register in qmldir.
- `MediaPanel.qml:53-76`: the 96×96 art slot renders through
  DitherImage (the raw `Image` stays as the hidden source item).
  Targeted Edits (glyph file).
- Animated Apple Music art (`AnimatedAlbumArt.qml`): sample the playing
  `Video` via `grabToImage` on a timer at ~8-10fps into the same dither
  pass — the choppy 1-bit cadence is the aesthetic, not a defect. Gate
  the timer on visibility + playback like every motion carve-out. If
  `grabToImage` on a `Video` item proves broken under the VM's llvmpipe
  (a real possibility), fall back honestly: dither the static art only,
  keep the un-dithered video path, and report the limitation — do not
  fake frames and do not ship a black box.
- DESIGN.md: add the imagery idiom to §2 (new item): media/album
  imagery renders 1-bit ordered-dither duotone in theme roles (mek's
  dithered-imagery signature); named surfaces: media panel art (static
  and animated). Nothing else auto-dithers (notification images, menu
  thumbnails, launcher icons stay true-color; the picker gains a study
  note only if trivially cheap — otherwise out of scope).
- The `--media` fixture track must carry real embedded cover art for the
  screenshot to prove anything: if `dev/smoke-niri.sh`'s media leg
  fixture has none, embed one (ffmpeg attached_pic, a generated test
  image — real metadata on a real file, per the honest-fixtures rule).
- Verify: `git add -A`; build/test/lint; `just vm-smoke --media` — Read
  the PNG: album art visibly dithered duotone (individual dither pixels
  resolve when zoomed), progress track unchanged below it.

### Task 4: Visualizer as dithered tracks

- `Visualizer.qml` redesign (file is rewrite-safe): the single glyph
  `Text` becomes six per-column vertical tracks, each the established
  remainder idiom — `DitherFill` (faint checker) across the column with
  a solid fill `Rectangle` in its `content` slot rising to the column's
  level. Fill color `root.foreground` (content ink — accent stays
  reserved; the visualizer must not out-shout the focused workspace),
  so hover inversion recolors it via the Task 2 rules. Column
  width/gap/height from `Theme.space` tokens; levels keep
  `model.js`'s sqrt response (levels feed heights now, not glyph picks
  — keep `levelToGlyph` only if `frameText` still has consumers, else
  delete it and its tests in the same pass).
- `VisualizerService` frame plumbing: expose levels as numbers if
  `frameText` glyphs were the only wire format (check consumers; the
  service currently publishes `frameText` — extend with a numeric
  array rather than parsing glyphs back).
- DESIGN.md §4 item 8 (the visualizer carve-out) amendment: rendering
  is now fill+dither tracks; `motion.enabled: false` and the
  not-playing state render the flat baseline as empty tracks (pure
  dither, zero fill) — same honesty, new geometry. Update the §4.8
  "all-lowest-glyph baseline" wording.
- Verify: `git add -A`; build/test/lint; `just vm-smoke --visualizer`
  — Read the PNG: six columns, solid lower fills, dithered remainders
  above, no glyph row remaining.

### Task 4b: Now-playing art cell + level-colored visualizer bars

Owner ask (2026-08-09, follow-up during Task 4): "the music icon can be
replaced with the dithered album cover (can also be animated) in a
layout similar to the app icon in the menu bar, and the audio visualizer
can potentially be colored bar per bar, keeping the ASCII style ofc."

- `NowPlaying.qml` (⚠️ glyph-bearing, targeted Edits): the static music
  glyph is replaced by a `DitherImage` of `MediaService.artUrl` at the
  same slot size the active-window cell gives its app icon (reuse that
  sizing token; radius 0, no border) whenever art exists; the glyph
  remains the no-art fallback (honest state, not an empty box). The art
  routes through the cell's inversion like all content: on hover the
  duotone pair swaps to the inverted pair (DitherImage's two color
  properties bound to the cell's state, roles only).
- Animated bar art: permitted via the Task 3 grab-timer pattern at bar
  size, but ONLY under the full visualizer-grade gate set
  (`MediaService.isPlaying` AND bar window on screen AND
  `Theme.motionEnabled`), same carve-out discipline as cava. If VM
  profiling shows the extra Video decode is heavy at bar scale, ship
  static bar art and report so, honestly; the panel keeps the animated
  path either way.
- Visualizer per-bar color: each bar's fill color derives from its own
  level, stepping through the ink ramp — below a low threshold
  `foregroundDim`, mid `foreground`, above a high threshold `accent` —
  thresholds as named constants in `model.js`, not magic literals in
  QML. Color-by-level is a meaning (energy), not a per-index rainbow;
  a static per-bar palette was considered and rejected as decoration
  (§1.4's loud-color law). Hover inversion still wins: an inverted
  cell renders all bars in the inverted ink (`onAccent`), dim/accent
  distinctions collapse under inversion like every other ink band.
- DESIGN.md: §3 bar translation gains the now-playing art cell as the
  fourth named image-icon site (dithered duotone, so it stays inside
  the 1-bit language rather than a true-color exception); §4 item 8
  gains the level-color rule and, if shipped, the bar-art animation
  gate.
- Verify: `git add -A`; build/test/lint green; `just vm-smoke --media`
  — Read the PNG: the bar's now-playing cell shows the dithered mini
  cover (fixture art from Task 3) instead of the glyph;
  `just vm-smoke --visualizer` — Read the PNG: bars visibly step
  dim/foreground (accent only if a peak lands in frame; say which the
  frame caught).

### Task 5: Tray icons — duotone silhouettes, one slot size

Owner ask (2026-08-09, follow-up): tray icons have inconsistent margins
and "often look invisible in light mode" (third-party SNI icons are
frequently white/light symbolic marks designed for dark bars — invisible
on paper).

- `shell/Surfaces/Bar/widgets/Tray.qml` (item delegates, per the M19-era
  map at Tray.qml:136 region): every tray icon renders through
  `DitherImage` (Task 3's component) in a new **alpha-mask mode** —
  painted pixels (alpha over threshold, Bayer-dithered at soft edges)
  become `Theme.color.foreground` ink; transparent stays transparent.
  The icon reads as a 1-bit silhouette in both modes, recolors with any
  theme, and a hover-inverted cell swaps it to `onAccent` (route the
  ink through the cell's `foreground` like text). DitherImage gains
  `mode: "duotone" | "mask"` — mask is alpha-driven, duotone stays
  luminance-driven; one component, two thresholds, same Canvas pass.
- Slot normalization: every tray icon pins into one square slot sized by
  a `Theme` token (reuse an existing size token near the bar glyph cell
  size — no new magic number; `sourceSize` pinned, `smooth: false`,
  radius 0) so SNI's arbitrary 16/22/24px pixmaps stop varying the
  cell's padding rhythm.
- DESIGN.md: extend Task 3's imagery item — tray icons are the second
  named 1-bit surface, mask-mode, and the sanctioned answer to
  light-mode-invisible symbolic icons. Note the deliberate tradeoff:
  vendor icon colors are discarded on the bar.
- Verify: `git add -A`; build/test/lint; `just vm-smoke --tray` (six
  real SNI stubs) — Read both the collapsed and expanded shots: every
  icon a uniform ink silhouette in identical slots. Then a light-mode
  proof: the `--theme-toggle` leg (or `--tray` combined with the
  settings fixture pinned light if the rig supports it — check
  `dev/smoke-niri.sh`; otherwise `--tray --wallpaper` with a light
  wallpaper) showing the icons legible on the light ramp — the exact
  failure the owner reported. Read the PNG.

### Task 5b: Color-preserving retro dither + cover-colored visualizer

Owner corrections (2026-08-09): "The dithered images will keep the image
colors right? just like mek.gallery." mek uses both treatments: 1-bit
mono for photographic/engraving imagery, and reduced-palette COLOR
dither on its pixel/game art. Album covers are content, not chrome, so
they keep their own colors. And: "by the audio visualizer color i also
meant that it uses the dithered album cover colors ... i dont want
different options just one default here" — the Task 4b level-band
coloring (dim/content/accent by energy) is SUPERSEDED, not kept as an
option. One default: bars draw the current cover's own colors.

- `DitherImage.qml` gains `mode: "retro"`: per-channel posterization
  (`property int levels: 4`, so 4 steps per RGB channel) with the same
  4x4 Bayer matrix biasing the quantization per pixel — classic
  ordered color dither. Same fillRect write path (putImageData stays
  broken, per CLAUDE-troubleshooting.md). Duotone and mask modes
  untouched. Unit tests: a color fixture renders only palette-step
  colors; hue survives (a red source stays in red steps, never gray).
- `MediaPanel.qml` art slot and `NowPlaying.qml` bar mini-cover switch
  `mode` to `"retro"`. The bar cover no longer swaps palette on hover
  inversion: content imagery keeps its colors on an inverted cell, the
  same ruling the menu's app icons already have (full color on
  inverted rows). `AnimatedAlbumArt.qml`'s grab-timer path follows the
  panel's mode.
- Cover-colored visualizer (replaces Task 4b's level bands): a small
  palette-extraction pass runs once per `artUrl` change — reuse the
  working Canvas pixel path (`drawImage` + `getImageData`, both proven;
  only `putImageData` is broken): posterize samples to the retro palette
  steps, count frequency, take the six most frequent distinct steps,
  order stably (by luminance), expose as a `var` color array. Home:
  a new small `Components/ArtPalette.qml` (invisible Canvas, `source`
  url in, `colors` out) or an output property on DitherImage if that
  reads cleaner against its structure — implementer's call, one
  component either way. `Visualizer.qml` colors bar i with
  `palette[i % n]`; no art or no player falls back to
  `root.foreground` (honest state). Colors do NOT swap under hover
  inversion (content-color ruling, same as the mini-cover). Delete
  `levelColorBand`/`LEVEL_DIM_BELOW`/`LEVEL_ACCENT_FROM` from model.js
  and their tests — no option, no dead path. DESIGN.md §4 item 8 loses
  the level-color rule and gains the cover-palette rule.
- DESIGN.md §2 item 12 amendment: two dither treatments, named — 1-bit
  duotone/mask for chrome-adjacent imagery (tray silhouettes), retro
  color dither for content imagery (album art, animated art). Content
  imagery keeps its own colors and is exempt from matugen retheming by
  design; the visualizer's cover-derived bar colors fall under the same
  content ruling. No em dashes in new prose.
- Verify: `git add -A`; build/test/lint green; `just vm-smoke --media`
  — Read the PNG: album art visibly dithered AND carrying the fixture
  art's own colors (sample pixels: palette-step values of the source
  hues, not the two theme inks); bar mini-cover matches.
  `just vm-smoke --visualizer` — Read the PNG: bars colored from the
  fixture cover's palette (sample a bar fill, match it to a cover
  palette step), not dim/content/accent inks. If the fixture art is too
  monochrome to prove distinct bar colors, regenerate it with real
  color variety in the same script pass (honest fixture, then the
  sample proves hue).

### Task 5c: Watts in the power panel — charge rate / CPU package draw

Owner ask (2026-08-09): "is it possible to see the W usage right next to
the W it's charging with?" Probed on e1504g this session: UPower
energy-rate works (15.5 W charging); the AC adapter exposes NO input
sensor (usage-while-charging is not computable on this hardware); Intel
RAPL package power works (8.5 W measured) but `energy_uj` is root-only
(PLATYPUS mitigation) — user-readability requires a udev rule in the
owner's nix config, which is the owner's security call, made outside
this repo. The shell side ships fallback-honest either way.

- `shell/Power/model.js` + the UPower service layer: expose
  `chargeRateW` (energy-rate, already UPower-provided) and a new
  `cpuPackageW` sampled from
  `/sys/class/powercap/intel-rapl:0/energy_uj` — two reads a fixed
  interval apart (reuse the repo's established file-poll idiom; find a
  sibling — e.g. how brightness or battery sysfs reads are done — and
  mirror it). Unreadable/absent RAPL yields null, never 0, never a
  guess.
- PowerPanel battery section: one slash-meta row —
  `CHARGING <rate>W / CPU <pkg>W` on AC, `DRAW <rate>W / CPU <pkg>W`
  on battery; the `/ CPU` half renders only when `cpuPackageW` is
  non-null (honest absent state). Values tabular, one decimal.
  Wording/idiom per DESIGN §2 item 10 (slash fusion, no colon on a
  value row).
- The VM has RAPL? Check in-VM (`ls /sys/class/powercap/`); a QEMU
  guest typically has none — the smoke shot then proves the honest
  fallback (rate only), and the RAPL half is proven by unit tests over
  the sampling math plus the e1504g deploy itself (read the panel there
  after the Task 6 rebuild).
- Verify: `git add -A`; build/test/lint green; `just vm-smoke --panel
  power` — Read the PNG: the wattage row renders with real fixture
  values and no fake CPU half.

### Task 5d: Tray drawer auto-collapse

Owner ask (2026-08-09): "I want the more button for the system tray to
auto close after a interval if no cursor is on it anymore or no system
tray menu is open."

- `Tray.qml`: when the drawer is expanded, a collapse `Timer` (interval
  = `Theme.motion.rotatePeriod`, the existing ~3s pacing token — no new
  magic number unless a better-named sibling exists) arms only once the
  pointer has entered AND then left the whole tray row (pinned + expanded
  cells + the toggle). Firing collapses the drawer. Pointer re-entry
  cancels and re-arms on next exit. An expanded drawer the pointer never
  visited stays open (keeps the smoke rig's IPC-driven `tray expand`
  screenshot deterministic, and never yanks the drawer away before the
  user reaches it).
- An open tray-item menu blocks collapse: read how Tray.qml opens SNI
  item menus (QsMenuAnchor or equivalent — find the open/visible state
  property in the Quickshell API, grounding against the pinned
  quickshell source if uncertain) and hold the timer while any item
  menu is open; menu close restarts the exit clock. If the menu
  open-state is genuinely not observable from QML, fall back to
  resetting the timer on any item click and say so in the report.
- Respect `motion.enabled: false`: the timer is a behavior, not an
  animation — it still runs (auto-collapse is function, not motion);
  the collapse itself is the existing instant state swap either way.
- Tests: the arm/cancel state machine (entered-then-left arms; re-enter
  cancels; never-entered never arms) via the existing QML test idiom
  for timers/state if a sibling pattern exists; otherwise the smoke leg
  plus code review, stated honestly.
- Verify: `git add -A`; build/test/lint green; `just vm-smoke --tray` —
  Read both shots: unchanged appearance, and the expanded shot still
  captures reliably (the never-entered guard is what the rig exercises).

### Task 5e: Life-progress easter egg shows alongside, not instead

Owner ask (2026-08-09): "for the life progress bar, i dont want the
life progress bar to cancel out the other one. The life progress bar is
an easter egg, if it was double clicked show both."

- Locate the feature first (`rg -n -i "life" shell/` — the
  life-progress percentage is named in DESIGN §2 item 5's tabular-digit
  rule) and read its toggle logic: today activating the easter egg
  replaces the other progress display; the owner wants the double-click
  to ADD the life bar next to the existing one, both visible at once,
  and presumably a second double-click hides it again (keep whatever
  the current dismiss gesture is, just stop it hiding the sibling).
- Layout: both bars render with the same track idiom (fill +
  DitherFill remainder) and the same tokens; the life bar keeps
  whatever meta label distinguishes it today. No new options/settings
  — the double-click IS the toggle, easter-egg semantics preserved.
- Verify: `git add -A`; build/test/lint green; then the narrowest
  smoke leg that shows the surface this lives on (determine from the
  code — likely the plain bar leg or a panel leg; the double-click may
  need the same treatment as other unpointable interactions: if the
  rig cannot deliver a real double-click, drive the same state over an
  existing IPC/debug hook if one exists, else prove via unit test on
  the toggle state plus an honest note). Read the PNG where possible:
  both bars visible simultaneously post-toggle.

### Task 6: Sweep + screenshot regeneration

- Legs, PNGs Read: plain, `--media`, `--visualizer`, `--tray`, `--menu
  --wallpaper` (matugen gate: dithered art, visualizer tracks, and tray
  silhouettes recolor with the wallpaper theme), `--bar-layout` (user
  bar.layout configs still compose with the new ActiveWindow cell).
- Regenerate: `bar-niri.png`, `active-window-niri.png` (bar chrome
  changed), `media-niri.png` (dithered art), `tray-niri.png` (duotone
  icons), the visualizer's committed shot if one exists in
  docs/screenshots (check README's table), `bar-layout-niri.png`.
  Manual-scp names per the capture notes where applicable. README
  captions updated only where now wrong.
- Verify: every regenerated PNG Read; final `git add -A && just
  vm-build && just vm-test && just vm-lint` green.
- Then the owner-requested deploy: push to origin, update the
  `formalshell` flake input in e1504g's `~/.config/nix` (`git add` the
  lock change — flakes only see tracked files), and run the
  `nixos-rebuild switch` over ssh directly — e1504g has passwordless
  sudo (`sudo -n true` confirmed 2026-08-09), so no owner hand-off is
  needed. The owner switches into the session themselves to see it.
