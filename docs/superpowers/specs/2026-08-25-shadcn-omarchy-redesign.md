# FormalShell redesign: Omarchy behaviour, shadcn skin, Hyprland only

**Date:** 2026-08-25
**Status:** approved (owner brief, 2026-08-25). Wins over every plan and over
`docs/DESIGN.md` on conflict.
**Supersedes:** the visual language in `docs/DESIGN.md` (rewritten alongside
this spec) and the "Surfaces", "Theming" and "Compositor layer" sections of
`2026-07-27-formalshell-design.md`. That spec's architecture, IPC contract,
configuration rules and nix layout still stand.

## The brief

The owner's words, condensed: look and feel like Omarchy (quattro) almost 1:1
without copying its code, skinned as stock shadcn/ui as if shadcn followed
pywal (the wallpaper drives the palette). Everything reachable from the
launcher and from keybinds. Hyprland first; niri is gone. Keep what is loved
(the sonner toast stack) and carry no bloat.

Two reference screenshots came with the brief (a shadcn-styled Quickshell
shell by another author). What they pin down: a transparent top strip holding
rounded, bordered pill cells grouped left / centre / right; floating panels
as bordered cards with an icon-and-title header, uppercase muted section
labels (`NETWORKS (1)`), bordered rows, ghost icon buttons, an outline button
in the footer beside one big number; mono type throughout; Lucide icons.

Three calls made here on the owner's behalf, each reversible with one line:

1. The retro dither becomes opt-in (owner, 2026-08-25): `wallpaper.dither`
   defaults to false and a new `lock.dither` (default false) gates the lock
   backdrop. The OSD and pending-row dithers go; nothing else in the shell
   dithers unless one of those two keys says so.
2. Icons are referenced by name and `theme.icons` picks the set: `lucide`
   (the default, an icon font) or `nerd` (the Nerd Font glyphs the mono font
   already carries). The references are unmistakably Lucide, so that ships
   first; the set is a settings key, not a rebuild.
3. The niri backend is deleted only after the nested Hyprland rig proves the
   base leg plus `--menu`, `--notify` and `--panel network` in the VM. Until
   then it stays as dead weight, not as a supported target.

## Non-goals

- Porting Omarchy's plugin system or its `shell.json` layout editor.
- A settings UI. `settings.json` stays the only configuration.
- A hardcoded font family. Faces come from the fontconfig `sans-serif`
  and `monospace` aliases only.
- Shadows. Border does the structural work (see "Depth").
- Cutting any owner-added feature (AirPods, DualSense, Tailscale, usage,
  GitHub, console, reminders, clipssh, share). Every one is restyled, none
  removed, unless the owner names it.

## Visual system

### Color: shadcn vocabulary, matugen values

`theme.json` adopts shadcn's token names. matugen fills them from the
wallpaper; the static fallback is shadcn's own zinc palette. The whole shell
reads `Theme.color.<token>`; nothing reads a matugen role directly.

| token | matugen role | dark fallback (zinc) | light fallback |
| --- | --- | --- | --- |
| background | surface | #09090b | #ffffff |
| foreground | on_surface | #fafafa | #09090b |
| card | surface_container_low | #18181b | #ffffff |
| cardForeground | on_surface | #fafafa | #09090b |
| popover | surface_container | #18181b | #ffffff |
| popoverForeground | on_surface | #fafafa | #09090b |
| primary | primary | #e4e4e7 | #18181b |
| primaryForeground | on_primary | #18181b | #fafafa |
| secondary | surface_container_high | #27272a | #f4f4f5 |
| secondaryForeground | on_surface | #fafafa | #18181b |
| muted | surface_container_high | #27272a | #f4f4f5 |
| mutedForeground | on_surface_variant | #a1a1aa | #71717a |
| accent | surface_container_highest | #27272a | #f4f4f5 |
| accentForeground | on_surface | #fafafa | #18181b |
| destructive | error | #ff6467 | #e7000b |
| destructiveForeground | on_error | #fafafa | #ffffff |
| warning | tertiary | #fbbf24 | #d97706 |
| warningForeground | on_tertiary | #18181b | #ffffff |
| border | outline_variant | #27272a | #e4e4e7 |
| input | outline_variant | #3f3f46 | #e4e4e7 |
| ring | primary | #71717a | #a1a1aa |
| chart1..chart5 | primary, secondary, tertiary, primary_container, secondary_container | zinc ramp | zinc ramp |

Notes:

- `accent` is shadcn's hover fill, a neutral. The wallpaper colour lives in
  `primary`. Anything the old design painted "accent" (selection, active
  toggle, progress fill) now paints `primary`.
- `ring` is `primary` under matugen so keyboard focus carries the wallpaper
  colour. The zinc fallback keeps shadcn's grey ring.
- `warning` has no shadcn counterpart; the battery cell already needs a
  middle band, so it stays, fed by matugen `tertiary`.
- `palette.js` validates these keys; `theme.json.tmpl`, the pywal template,
  the GTK and Qt templates are regenerated for the new names. The old twelve
  keys are removed, not aliased.

### Depth: borders, one ring, compositor blur, no shadow

Every surface is a `card` (panel, toast, OSD, launcher) or `popover`
(tooltip, tray menu) fill with a 1px `border`. No shadow, no scrim behind
panels, no dither unless `wallpaper.dither` or `lock.dither` opts in. The
launcher and the lock keep a plain black scrim at 0.5 over the desktop
because they are modal.

Blur (owner, 2026-08-25, after Nothing OS 5.0): a flat gaussian blur sits
behind the bar strip, the panels and the launcher card. The shell never
blurs a pixel itself; Hyprland does it behind the layer surface through
`layerrule = blur` plus `ignorealpha` on the `formalshell:bar`,
`formalshell:panel` and `formalshell:menu` namespaces, which the shipped
example config sets. What the shell contributes is translucency:
`theme.surfaceOpacity` (default 0.85) is the alpha of every `card` and
`popover` fill on those three surfaces (`Theme.surface(color)` applies it),
so the blurred desktop shows through the card. The bar strip is now that
fill edge to edge (M47 D1), so `ignorealpha` finds nothing to skip inside
it and the whole band blurs. Under
a compositor with blur off the same alpha reads as a tint, still legible
at 0.85. The scrim, the toasts, the OSD and the lock stay opaque.

Focus is one ring, drawn identically everywhere: border swaps to `ring`, and
a 3px halo of `ring` at 0.5 alpha sits outside the border (shadcn's
`ring-[3px] ring-ring/50`). The ring is the only place the wallpaper colour
appears on chrome that is not selected or active, which is what makes the
keyboard cursor findable at a glance.

### Radius

`Theme.radius` is 10 (shadcn `--radius: 0.625rem`), overridable with
`theme.radius` in `settings.json`. Derived: `radiusSm` 6, `radiusMd` 8,
`radiusLg` 10, `radiusXl` 14. Concentric rule: a nested corner is the outer
radius minus the padding between them, floored at `radiusSm`.

| element | radius |
| --- | --- |
| panel, toast, launcher, OSD card, notification centre | xl |
| bar cell, button, input, list row, inner card | md |
| badge, chip, progress track | sm |
| workspace dot, checkbox | full (height/2) |

### Type

Two faces by context, the way Nothing OS 5.0 pairs its sans with its mono
(owner, 2026-08-25): `Theme.fontFamilySans` is the fontconfig `sans-serif`
alias and `Theme.fontFamilyMono` the `monospace` alias, never a hardcoded
family. The intended pair is Geist Sans and Geist Mono (`pkgs.geist-font`,
also shadcn's own default), set through the user's fontconfig defaults; the
VM fixture and the nix example config pin both aliases to them.

Sans carries words: titles, labels, button text, section labels, row
labels and descriptions, hints, breadcrumbs, toast text, tooltips. Mono
carries values: every number and unit (percent, temperature, speed,
battery, clock and date digits), identifiers (BSSID, PID, IP, hostname,
path, command), keybind chords, clipboard and terminal content, workspace
numbers. A row that mixes the two (`FORMALTEST` at 100%) sets each `Text`
by that rule; nothing switches family inside one string.

Base 13, size tokens unchanged (`caption` 11, `bodySmall` 12, `body` 13,
`subtitle` 14, `title` 15, `heading` 17, `display` 26, `displayLarge` 30).
Weights `normal` 400, `medium` 500, `semibold` 600.

| role | face | size | weight | colour | case |
| --- | --- | --- | --- | --- | --- |
| panel title | sans | subtitle | semibold | foreground | sentence |
| row label | sans | body | medium | foreground | sentence |
| row detail, caption | sans | bodySmall | normal | mutedForeground | sentence |
| section label | sans | caption | medium | mutedForeground | upper, tracking `meta` |
| bar cell value | mono | body | medium | foreground | as given |
| bar cell label (app title) | sans | body | medium | foreground | as given |
| big number (footer stat) | mono | display | semibold | foreground | tabular |
| clock (bar, lock) | mono | body / displayLarge x3 | medium / semibold | foreground | tabular |

Section labels are shadcn's `text-xs uppercase tracking-wider
text-muted-foreground`. They carry no trailing colon; the old `NETWORK:`
form is gone.

### Spacing

New work uses semantic keys: `controlHeight` 32, `barCellHeight` 28,
`barMargin` 6, `controlPaddingX` 12, `controlPaddingY` 6, `rowGap` 4,
`iconGap` 8, `panelPadding` 12, `sectionGap` 16, `trackThickness` 6. Popup
widths: `Narrow` 320, `Default` 380, `Wide` 480, `Menu` 560, `MenuSplit`
840, `MenuApp` 900. The raw steps (`xxs` 2 through `huge` 18) keep their
names and values: 357 reads across 60 files depend on them, and each
surface moves to the semantic keys in its own milestone. M45 prunes the
steps nothing reads any more.

### Motion

Unchanged tokens (`fast` 100, `standard` 130, `reveal` 400, `slide` 4,
`motion.enabled` zeroes durations). Enter: opacity 0 to 1 plus 4px translate
toward the anchor. Exit: opacity only. Cursor moves in a list are instant; the
hover fill fades on `fast`. Nothing scales on press.

### Icons

Named, with the set chosen by `theme.icons` (`lucide` default, `nerd`).
`shell/Theme/icons.js` exposes `glyph(set, name)` and `family(set)`;
`shell/Theme/icons/lucide.js` is generated by `tools/gen-lucide-icons.sh`
from the `lucide-font-<v>.zip` GitHub release's CSS (name to codepoint,
committed), and `shell/Theme/icons/nerd.js` maps the same names onto Nerd
Font codepoints by hand, growing as surfaces are ported. A name missing from
the active set falls back to that set's `circle-help`. `nix/lucide-font.nix`
installs `lucide.ttf` under fontconfig (ISC); the `nerd` set renders in the
mono font itself, as today. `Components/Icon.qml` renders one: `Icon {
name: "wifi"; size: Theme.fontSize.body }`, colour from the parent. Surface
files never contain a raw codepoint; the "glyph corruption on whole-file
rewrite" hazard goes with them. Tray pixmaps and desktop-entry app icons
stay images. Size rule: an icon beside text is the text's font size.

## Surfaces

Positions, grouping and behaviour follow Omarchy quattro; chrome follows the
tokens above.

**Bar** (amended 2026-08-25, M47 D1; the floating pills this paragraph
described are gone, not optional). One continuous strip across the top of
the output: `card` fill at `surfaceOpacity`, a 1px `border` along its bottom
edge and no other edge, `barCellHeight + 2 * barMargin` tall, no side or top
margin. Regions inset `md` from both screen edges; cells sit `barMargin`
down from the top, `barCellHeight` tall, `radiusMd`, `sm` gap between cells.
Cells are ghost items: no fill and no border at rest, since the strip
carries both. Groups (workspaces, indicators) are one cell holding several
items. Left: launcher glyph cell, workspaces. Centre: clock, bell (media
cell when playing, Omarchy's placement). Right: the `bar.layout` right region
as today. Hover: `accent` fill. Open panel: `primary` 2px underline on the
cell's bottom edge (the old open dot). Workspaces: a row of 6px dots,
`mutedForeground`; the active one is a `primary` pill 16px wide; an urgent
one is `destructive`. The chevron keeps its collapse behaviour.

**Panels.** A `card`, `radiusXl`, 1px `border`, `panelPadding`, anchored
`barMargin` under its cell (IPC opens fall back to the right region, as
today). Header: icon, title (subtitle/semibold), right-aligned ghost icon
buttons (refresh, close). Body: sections with a section label, rows as
bordered `radiusMd` items `controlHeight` tall (icon, label, trailing meta
or icons). A hero card (network's connected AP, audio's active sink) is a
bordered inner card with a two-line body. Footer: outline button on the
left, big number on the right. Panel width `Default`; media, monitor and
calendar use `Wide`.

**Launcher.** shadcn's Command palette. A `card`, `radiusXl`, width `Menu`,
centred at 30% from the top. Input row: search icon, text, no border except
a 1px `border` bottom rule. Breadcrumb as `secondary` chips above the list
when inside a submenu. Rows: icon, label, muted detail; the cursor row is
`accent` fill with `accentForeground` text (no inversion, no ring: the list
cursor is the only focus in a modal surface). Footer: `caption`
`mutedForeground` hints `↑↓ move  ↵ open  esc back`. Grid routes (wallpaper
picker) keep the cursor as a `ring` around the cell. App views (monitor)
keep their layout with the new tokens.

**Toasts.** The sonner stack stays exactly as built (depth stack, integer
step narrowing, critical wins the front). Card chrome: `card`, `radiusXl`,
1px `border`; critical gets a `destructive` 1px border and a `destructive`
icon, never a full-bleed fill. Actions are outline buttons.

**Notification centre.** Right-anchored full-height `card` with a 1px
left `border`. Header: title, DND toggle (a shadcn switch: `muted` track,
`primary` when on), clear-all ghost button. Rows as above; unread rows carry
a `primary` 6px dot.

**OSD.** Bottom-centre pill, `card`, `radiusXl`, icon plus a `sm` track
(`muted`) with a `primary` fill, percentage in `bodySmall` tabular.

**Lock and greeter.** Wallpaper, plain 0.5 scrim, centred column: clock
(`displayLarge` x3), date as a section label, a shadcn input (`input` border,
`radiusMd`, `ring` while focused, `destructive` border plus caption `Wrong
password` after a failure). The wallpaper is plain unless `lock.dither`.

**Screensaver.** ttfx banner unchanged (Omarchy parity).

**Picker.** Grid of `radiusMd` thumbnails with a 1px `border`; cursor is the
ring; `Dark | Light` is a shadcn segmented control (`muted` group,
`background` active segment).

**Tooltip.** `popover` fill, `radiusSm`, `caption` text, 1px border, 6px
below the cell.

**Polkit, console, capture, hot corners, background.** Same tokens; no
per-surface exceptions. The background draws the wallpaper plain unless
`wallpaper.dither` is on.

## Keyboard model

The rule: anything a pointer can do on a shell surface has a key, and the
key's target is visible.

1. Every panel wraps its content in `Components/KeyCatcher.qml`
   (Omarchy's `PanelKeyCatcher` contract, written fresh): Escape closes,
   Tab/Shift+Tab move between sections, arrows and `hjkl` move the cursor,
   Enter/Space activate, `x` deletes where a row has a delete, any other
   printable goes to `textKey`. `blocked: editor.activeFocus` hands keys to
   an inline editor. The cursor is the ring. A panel opened by pointer shows
   no cursor until the first key or hover (today's `cursorActive`).
2. `panel toggleAt <n>` opens the nth panel-bearing cell of the bar's right
   region, counting from the screen centre outward, skipping cells with no
   panel (the tray). Omarchy binds `SUPER+CTRL+1..9` to this.
3. Every panel is a launcher route (the `panels` route exists) and every
   toggle is a launcher row (the `toggles` route exists). `menu toggle`
   opens the root and `menu summon <route>` is the keybind entry for each
   Omarchy menu: `apps`,
   `capture`, `toggles`, `system`, `theme`, `wallpaper`, `share`,
   `reminder`, `keybinds`, `emoji`, `clipboard`.
4. Notifications over IPC: `dismissAll`, `invokeLast`, `showHistory` and
   `toggleDnd` exist; `dismissOne` (drop the front toast) is added.
5. `keybinds` route reads `hyprctl binds -j` only. The cheat sheet groups by
   the description Hyprland stores for each bind.

Default bindings ship as `docs/examples/hyprland/formalshell.conf` (plain
hyprlang, sourced from the user's config). Omarchy's chords, the shell's
IPC:

| chord | action |
| --- | --- |
| SUPER+SPACE | `menu toggle` (root) |
| SUPER+ALT+SPACE | `menu summon apps` |
| SUPER+CTRL+E | `menu summon emoji` |
| SUPER+CTRL+C | `menu summon capture` |
| SUPER+CTRL+O | `menu summon toggles` |
| SUPER+CTRL+S | `menu summon share` |
| SUPER+CTRL+R | `menu summon reminder` |
| SUPER+CTRL+SPACE | `wallpaper next` |
| SUPER+SHIFT+CTRL+SPACE | `menu summon theme` |
| SUPER+ESCAPE | `menu summon system` |
| SUPER+K | `menu summon keybinds` |
| SUPER+CTRL+Q | `menu summon calc` |
| SUPER+CTRL+V | `menu summon clipboard` |
| SUPER+CTRL+A / B / W / P / D / ALT+D | `panel toggle audio / bluetooth / network / power / display / calendar` |
| SUPER+CTRL+1..9 | `panel toggleAt n` |
| SUPER+comma / SHIFT+comma / ALT+comma / SHIFT+ALT+comma | `notifications dismissOne / dismissAll / invokeLast / showHistory` |
| SUPER+CTRL+comma | `notifications toggleDnd` |
| SUPER+CTRL+I / N | `screensaver idle toggle` / `nightlight toggle` |
| SUPER+SHIFT+SPACE | `bar toggle` |
| SUPER+CTRL+L | `lock lock` |
| PRINT / SUPER+CTRL+PRINT / ALT+PRINT | `screenshot region` / `capture text` / `record toggle` |
| XF86Audio* / XF86MonBrightness* | `osd volume` / `osd brightness` after the wpctl/brightnessctl call, as today |

## Hyprland first

- `CompositorService` instantiates `HyprlandBackend` only. `BackendBase`
  loses `applyThemeFragment`; Hyprland reloads on config write.
- `shell/Theme/templates/hyprland-colors.conf.tmpl` replaces the niri
  border template: `$primary`, `$border`, `$destructive` as `rgb(...)`
  variables written to `~/.config/hypr/formalshell-colors.conf`, sourced by
  the user's `hyprland.conf` for `col.active_border` and friends. The
  example config sources it.
- `keybinds.niriConfigPath` is removed; `Compositor/keybinds.js` keeps the
  `hyprctl binds -j` leg only.
- `Compositor/park.js` keeps the `special:formalshell-console` path; the
  niri workspace-park path goes.
- Verification rig: `dev/smoke-niri.sh`'s legs move into `dev/smoke.sh`,
  which boots nested Hyprland (the current `dev/smoke-hyprland.sh` is the
  seed). Compositor calls (`niri msg`) become `hyprctl -j`. Legs that read
  niri-only facts (`--hotcorner`'s layer namespaces, `--screensaver`'s
  output list) read the Hyprland equivalents. The gate in "The brief" item 3
  is the first plan's last task; the niri deletion is a plan of its own.
  Outcome (2026-08-25): the gate went green in the VM on a `vkms` software
  KMS card (the pixman sway parent has no dmabuf feedback or render node of
  its own to hand a nested compositor), while a real host with a real GPU
  nests Hyprland directly. Base, `--menu`, `--notify` and `--panel network`
  all passed.
- `nix/testvm.nix` keeps sway as the headless parent; only the nested child
  changes.

## Deletions

`Components/DogEar.qml`, `PanelOpenDot.qml` (folded into the bar cell);
the OSD and pending-row dither uses (`DitherImage`/`DitherFill`/`dither.js`
stay for the two opt-in keys); Cell's `ink`, `pending`, `standalone`,
`accent`, shared-rule border; `Theme.inverted()` and `invertedPair`;
`Compositor/niri/`, `niri-border.kdl.tmpl`, `keybinds.niriConfigPath`,
`dev/smoke-niri.sh` (after the gate); every `docs/screenshots/*-niri.png`
(recaptured as `*-hyprland.png`).

## Configuration

New: `theme.radius` (int, default 10), `theme.icons` (`lucide` |
`nerd`, default `lucide`), `theme.surfaceOpacity` (0..1, default 0.85),
`lock.dither` (bool, default false).
Changed: `wallpaper.dither` defaults to false. Removed:
`keybinds.niriConfigPath`. Everything else keeps its key and meaning.

## Verification

- `just test`: token maths (`tst_tokens`), palette validation with the new
  keys, `icons.js` has every name `Icon` consumers use (a test greps
  `Icon { name:` across `shell/`).
- `just vm-smoke` on nested Hyprland: base, `--menu`, `--notify`,
  `--center`, `--osd`, `--panel network`, `--panel audio`, `--wallpaper`
  (matugen recolour proves `primary` and `border` moved off zinc), `--lock`,
  `--picker`. Each PNG is read, not assumed.
- Contrast: `mutedForeground` on `card` at or above 4.5:1 in both fallback
  modes (zinc-400 on zinc-900 is 7.0:1; zinc-500 on white is 4.6:1). matugen
  pairs are Material's own and pass by construction.
- Screenshots in `docs/screenshots/` recaptured and `README.md` updated.

## Build order

- M41 foundation: tokens, palette, Lucide, `Icon`, `Cell`/`Button`/
  `SectionLabel`/`KeyCatcher`, `Panel` chrome, bar, network panel, nested
  Hyprland rig for the four gate legs, then sans/mono by context and
  surface translucency on everything M41 built.
  (`2026-08-25-m41-shadcn-foundation.md`)
- M42 panels: the other sixteen panels on the new primitives, `toggleAt`,
  keyboard cursor in each.
- M43 launcher: Command palette chrome, grid and app views, tooltip, tray menu.
- M44 notifications and OSD: toast and centre chrome, notification IPC
  additions, OSD pill.
- M45 modal surfaces: lock, greeter, picker, polkit, console, capture,
  background plain by default, `lock.dither` wiring, removal of the mapped
  Cell props and unused spacing steps.
- M46 niri removal: backend, templates, rig, docs, screenshots, example
  Hyprland config, keybind cheat sheet.

All six milestones landed on 2026-08-25; each plan's own "Landed" section
lists its commits.

## Risks

- Nested Hyprland in the VM was flakier than niri. If M41's gate cannot be
  made green in two attempts, the fallback is to keep `NiriBackend` as a
  rig-only backend and say so in CLAUDE.md, rather than lose the rig.
  Outcome (2026-08-25): a `vkms` software KMS card gave the VM's pixman
  sway parent the dmabuf feedback and render node aquamarine needs, and the
  gate went green without it.
- matugen's dark `surface` sits lighter than zinc-950. Acceptable: the
  brief asked for the wallpaper to drive the palette. If the owner wants the
  near-black of the references, `theme.contrast` can pin surface tones
  later; not in scope now.
- Lucide's font release layout may differ between versions. The nix task
  pins one version and the generator script asserts the codepoint count.
