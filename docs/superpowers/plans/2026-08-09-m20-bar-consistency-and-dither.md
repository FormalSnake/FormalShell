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
