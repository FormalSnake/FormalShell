# M49: the retro preset, and three live-session fixes

**Date:** 2026-08-26
**Status:** implemented 2026-08-26
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(spec wins on conflict). `docs/DESIGN.md` is the rulebook.

## Owner's list (2026-08-26)

1. The old dithered design language (everything monospace, radius 0,
   dithered imagery, unblurred) comes back as a configurable theme preset
   of the shadcn system. Same layouts, everything square (Hyprland too),
   dithered icons, monospace fonts. The theme system stays configurable and
   the theme.json / matugen / pywal contract stays as it is.
2. Hovering the active workspace dot grows the grey dot behind the pill,
   which clips. The pill must grow instead.
3. The AirPods panel, and the DualSense panel, take horizontal button rows
   and icons in their layouts.
4. The media panel boxes everything in cards. Make it coherent.
5. The visualizer's bars change their corner rounding with their height
   instead of keeping one radius.

## Locked decisions

- D1 `theme.preset` (`shadcn` default, `retro`) is a table of defaults,
  not a mode. Every knob it sets is an existing or new settings key the
  user can still write explicitly, and an explicit key always wins over
  the preset. Resolution lives in one pure file, `shell/Theme/presets.js`,
  read by `Core/Theme.qml` alone; a surface reads `Theme.*`, never
  `Config.get("theme.…")` and never the preset name.

  | key | shadcn | retro |
  | --- | --- | --- |
  | `theme.radius` | 10 | 0 |
  | `theme.icons` | `lucide` | `nerd` |
  | `theme.fonts` (new: `pair` sans+mono, `mono` mono everywhere) | `pair` | `mono` |
  | `theme.surfaceOpacity` | 0.85 | 1 |
  | `theme.blur` (new, Hyprland only) | true | false |
  | `theme.dither` (new) | false | true |
  | `wallpaper.dither` | `theme.dither` | `theme.dither` |
  | `lock.dither` | `theme.dither` | `theme.dither` |

- D2 radius 0 means 0. `Tokens.radiusTokens(0)` returns all-zero steps
  (the 2px floor only applies to a positive base), and the pill shapes
  (`radius: height / 2` on the switch, the workspace dots and pill, the
  bell badge, the LED pips, the calendar dot, the centre's unread dot)
  read `Theme.pillRadius(extent)`, which is `extent / 2` on a positive
  base and 0 on a zero one. Tied to the radius, not to the preset, so
  `theme.radius: 0` on the shadcn preset squares the same shapes.
- D3 `theme.dither` is the one texture knob. On, it renders content
  imagery (launcher app icons, the active-window icon, notification
  images, the app-menu icon, album art in the media panel and the bar's
  now-playing cell) through `DitherImage`'s retro pass, and paints the
  `Track` groove as `DitherFill`. Tray icons stay true colour (owner's
  "deep fried" rejection, 2026-08-09, stands). The picker grid and
  clipboard thumbnails stay true colour: those grids exist to choose a
  picture. One new primitive, `Components/Picture.qml`, wraps an `Image`
  and layers the dither over it when `Theme.dither` is on, so a surface
  never branches on the knob itself. Icons under 32px dither at chunk 1,
  larger imagery at chunk 2.
- D4 Hyprland follows the preset through a second published file,
  `~/.config/hypr/formalshell-chrome.conf` (and `.lua`), carrying
  `$rounding` (the radius) and `$blur` (`theme.blur`). Written by
  `ThemeEngine` directly from `Theme`, not by matugen (a template cannot
  read settings.json), on startup and whenever either value changes, then
  the same `hyprctl reload` the colours take. `docs/examples/hyprland/
  formalshell.conf` sources it and reads `decoration.rounding` and every
  blur flag from those two variables.
- D5 the workspace row is `Theme.space.lg` tall so a grown dot never
  clips. Hovering the focused slot grows the pill (height to `lg`, width
  by the same step, centred on its slot) and leaves the dot under it
  alone; hovering any other slot grows that dot as today.
- D6 AirPods: the listening modes are one exclusive `ButtonGroup` (icon
  and label per mode: `circle-off` off, `ear-off` ANC, `ear`
  transparency, `audio-waveform` adaptive), ear detection is a second
  exclusive `ButtonGroup` (`One`, `Both`, `Off`) under its own label, the
  hero keeps `headphones` (Lucide 1.34 has no earbuds glyph; `headset`,
  `ear` and `headphones` are what it ships). Battery rows and the two
  switches stay rows. Left/Right walk the group under the cursor, the
  same wiring `PowerPanel` uses.
- D7 DualSense: still read-only. Every row takes a leading `Icon`
  (`gamepad-2` stays on the hero, `lightbulb` on the lightbar,
  `circle-dot` on the LEDs), and LIGHTBAR and PLAYER LEDS sit side by
  side in one horizontal row of two `Cell`s under one `STATUS` label
  rather than stacking two one-row sections.

- D8 media panel: the panel frame, the art frame, the transport trough
  and the player chips are the only chrome. The now-playing block (art,
  title, artist, album), the transport group, the progress track with its
  two times and the volume track with its label and readout sit flat in
  the panel, separated by `rowGap`, with no `Cell` around any of them.
  The keyboard ring on a track is drawn by `Track` itself: it gains a
  `cursor` property that paints the same ring halo `Switch` does, and a
  hover over the track moves the panel cursor onto it the way a row does.
- D9 visualizer bars keep one radius: the groove's radius is
  `min(radiusSm, width / 2)`, and a fill with a non-zero level is never
  shorter than twice that radius, so a low level draws one full dot rather
  than a squashed one. Under a zero radius both are square.

## Tasks

Each task: implement, run the named checks, read the output, commit.

### T1 presets.js and Theme wiring

- `shell/Theme/presets.js` (`.pragma library`): `NAMES`, `defaults(name)`
  (unknown name resolves to `shadcn`), and `resolve(name, get)` returning
  the final table with explicit keys applied over the preset's defaults.
- `Core/Theme.qml`: `preset`, `iconSet`, `fonts`, `dither`,
  `wallpaperDither`, `lockDither`, `blurBehind`, `pillRadius(extent)`;
  `radius`, `surfaceOpacity` and `fontFamilySans` read the resolved table.
- `Tokens.radiusTokens` zero floor (D2). `Icon.qml` reads
  `Theme.iconSet`; `Background.qml` and `LockSurface.qml` read
  `Theme.wallpaperDither` / `Theme.lockDither`.
- `tests/stubs/qs/Core/Theme.qml` mirrors the new members. New
  `tests/tst_theme_presets.qml`; `tst_theme_tokens.qml` gains the zero
  floor case. `Config.qml`'s header documents the keys.
- Check: `just test`, `just lint`.

### T2 pill radius sweep

- The eight `radius: … / 2` sites plus `Switch.qml`'s three take
  `Theme.pillRadius(...)`. `Track.qml`'s groove becomes a `DitherFill`
  behind the fill when `Theme.dither` is on.
- Check: `just test` (`tst_switch`, `tst_track`), `just lint`.

### T3 workspace pill hover (D5)

- `Surfaces/Bar/widgets/Workspaces.qml` only.
- Check: `just lint`, then `just vm-smoke --workspaces` with the three
  bar frames read.

### T4 Picture primitive and image sites (D3)

- `Components/Picture.qml`, registered in `qmldir`, with a `tst_picture`
  test asserting the dither layer exists only under `Theme.dither`.
- Swap: `MenuRow.qml` app icon, `NotificationCard.qml` `appImage`,
  `ActiveWindow.qml` `appIcon`, `AppMenuPanel.qml` icon, `MediaPanel.qml`
  art, `NowPlaying.qml` both cover layers.
- Check: `just test`, `just lint`.

### T5 Hyprland chrome file (D4)

- `shell/Theme/chrome.js` renders both files from `{ rounding, blur }`;
  `ThemeEngine.qml` publishes them on startup and on change, then
  reloads. `tst_hyprland_chrome.qml` covers the renderers.
- `docs/examples/hyprland/formalshell.conf` sources the file and reads
  `rounding = $rounding` and `blur = $blur` everywhere blur is set.
- Check: `just test`, `just lint`.

### T6 AirPods panel (D6)

- Check: `just lint`, `just vm-smoke --panel airpods` (NO DAEMON is the
  honest frame on the rig; the group layout is proven by
  `tst_button_group` and the gallery).

### T7 DualSense panel (D7)

- Check: `just lint`, `just vm-smoke --panel dualsense`.

### T9 media panel (D8)

- `Components/Track.qml` gains `cursor` (ring) and `hovered` plumbing;
  `MediaPanel.qml` loses its `Cell` wrappers per D8. `tst_track` covers
  the ring.
- Check: `just test`, `just lint`, `just vm-smoke --media` with the frame
  read.

### T10 visualizer radius (D9)

- `Surfaces/Bar/widgets/Visualizer.qml` only.
- Check: `just lint`, `just vm-smoke --visualizer`.

### T8 rig, docs, verification

- `dev/smoke.d/retro.sh`: `--retro` writes `{"theme":{"preset":"retro"}}`
  into the settings fixture and drives nothing; it rides any other leg.
- `docs/DESIGN.md` gains a "Presets" section; `docs/USAGE.md`'s theming
  section documents `theme.preset`, `theme.fonts`, `theme.dither`,
  `theme.blur` and the chrome file; `CLAUDE.md`'s leg list gains
  `retro.sh`.
- Check: `just vm-smoke --retro --gallery`, `--retro --menu`,
  `--retro --panel network`, `--retro --notify`, plus the shadcn
  `--gallery` frame unchanged. Read every PNG.
