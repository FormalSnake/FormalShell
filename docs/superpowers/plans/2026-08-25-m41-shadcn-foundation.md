# M41: shadcn foundation

**Date:** 2026-08-25
**Status:** implemented 2026-08-25
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(spec wins on conflict). `docs/DESIGN.md` is the rulebook for every surface.

## Why

The owner redirected the whole visual language on 2026-08-25: Omarchy's
behaviour, shadcn's chrome, the wallpaper's palette, keyboard everywhere,
Hyprland only. This milestone lays the floor every later milestone stands on:
the token set, the icon font, the primitives, the panel and bar chrome, and
a nested Hyprland rig that can screenshot them. One panel (network) and the
bar are ported so the primitives are proven on real surfaces, not in
isolation.

## Scope

In: `tokens.js`, `palette.js`, `Theme.qml`, matugen templates, Lucide font
packaging plus `icons.js` and `Icon.qml`, `Cell`/`Button`/`IconButton`/
`Card`/`SectionLabel`/`Input`/`Track`/`KeyCatcher` primitives, `Panel.qml`
chrome, `NetworkPanel.qml`, `Bar.qml` plus `Workspaces.qml`/`Clock.qml`/
`NetworkWidget.qml`, `dev/smoke.sh` on nested Hyprland with base, `--menu`,
`--notify`, `--panel` legs, tests.

Out: every other panel (M42), the launcher's own chrome (M43), toasts, centre
and OSD (M44), lock/greeter/picker and the dither deletion (M45), the niri
backend deletion (M46). Surfaces outside scope keep compiling and keep
rendering on the new tokens through the compatibility mapping in D3.

## Locked decisions

### D1: token names change in one commit, no aliases

`palette.js`'s `COLOR_KEYS` becomes the shadcn list from the spec. Every
`Theme.color.<old>` read in `shell/` is rewritten in the same task
(`background` and `foreground` keep their names; `backgroundAlt` becomes
`card`, `foregroundDim` becomes `mutedForeground`, `foregroundFaint` becomes
`mutedForeground` too, `rule` becomes `border`, `accent` becomes `primary`,
`onAccent` becomes `primaryForeground`, `urgent` becomes `destructive`,
`onUrgent` becomes `destructiveForeground`, `warning`/`onWarning` become
`warning`/`warningForeground`). A rename is a mechanical sweep across ~60
files: fan it out with `canaryclaude-cheap-subagent`, then `just lint`.

### D2: icons by name, set chosen in settings, Lucide first

`nix/lucide-font.nix` fetches the pinned `lucide-font-1.34.0.zip` from
`github.com/lucide-icons/lucide/releases` (asset name verified 2026-08-25),
installs `lucide.ttf` under `share/fonts/truetype`, and `nix/package.nix`
adds it to the wrapper's fontconfig path the same way the mono font reaches
the VM (`nix/testvm.nix:541`). `tools/gen-lucide-icons.sh` parses the
release's `lucide.css` into `shell/Theme/icons/lucide.js` (`var ICONS = {
"wifi": "\ue9xx", ... }`) and asserts at least 1500 entries.
`shell/Theme/icons/nerd.js` is hand-written: the same names, Nerd Font
codepoints, only the names this milestone's surfaces use. `shell/Theme/icons.js`
exposes `glyph(set, name)` (falls back to the set's `circle-help`) and
`family(set)` (`"lucide"`, or `""` meaning the mono font). `Components/Icon.qml`
is a `Text` reading `Config.get("theme.icons", "lucide")`, size from the
neighbouring text. Nerd Font literals are replaced only in files this
milestone touches; the rest go with their milestone.

### D3: old Cell props survive M41 as mapped states

59 files instantiate `Cell`. Rewriting them all here would make one
unreviewable commit, so `Cell.qml` keeps `selected`, `accent`, `urgent`,
`warning`, `ink`, `standalone`, `pending`, `interactive`, `hovered`,
`tooltipText` as properties and maps them: `accent` and `ink` paint the
`active` state (`primary` fill), `selected` paints `accent` fill, `urgent`
paints the `destructive` border and ink, `warning` paints the `warning`
border and ink, `standalone` and `pending` do nothing. Shared-rule borders,
inversion and `Theme.inverted()` are deleted now; nothing outside `Cell`
read them (`rg -l 'Theme.inverted' shell` is `Cell.qml` alone). M45 deletes
the mapped props together with their last consumers.

### D4: the rig moves before niri goes

`dev/smoke.sh` is `dev/smoke-hyprland.sh` grown into the legs M41 needs.
`dev/smoke-niri.sh` is untouched and still runs; it is the reference for
what each leg proves. `dev/vm.sh smoke` gains `--compositor hyprland|niri`
(default `hyprland`) so both can run until M46 deletes niri. The gate: base,
`--menu`, `--notify` and `--panel network` green on nested Hyprland in the
VM, PNGs read. If two attempts at Task 7 fail, stop and report; the spec's
risk section names the fallback and the owner decides.

## Tasks

Each task runs in its own subagent, sequentially. A task ends with its
verification commands run and their output read; the commit follows the
evidence, never precedes it.

### Task 1: tokens and palette

Files: `shell/Theme/tokens.js`, `shell/Theme/palette.js`,
`shell/Core/Theme.qml`, `shell/Theme/templates/theme.json.tmpl`,
`shell/Theme/templates/pywal-theme.json.tmpl`, `tests/tst_tokens.qml`,
`tests/tst_palette.qml`, every `Theme.color.*` consumer (D1).

1. `palette.js`: `COLOR_KEYS` = spec table; `fallback(mode)` = the zinc
   values verbatim; `mergeWithFallback` unchanged in shape.
2. `tokens.js`: `SPACING_BASE` unchanged (spec "Spacing");
   `SEMANTIC_SPACING_BASE` re-valued and extended per the spec
   (`controlHeight` 32, `barCellHeight` 28, `barMargin` 6, `controlPaddingX`
   12, `controlPaddingY` 6, `rowGap` 4, `iconGap` 8, `sectionGap` 16, popup
   widths 320/380/480/560/840/900); add `WEIGHTS = { normal: 400, medium:
   500, semibold: 600 }` and `radiusTokens(base)` returning `{ sm: base-4,
   md: base-2, lg: base, xl: base+4 }` floored at 2; `invertedPair` returns
   the primary pair. `motionTokens` keeps its shape with `slide` 4. State
   and border-spec helpers stay until Task 3.
3. `Theme.qml`: `radius` reads `Config.get("theme.radius", 10)`; expose
   `radiusSm/Md/Lg/Xl`, `weight`, `borderWidth: 1`, `ringWidth: 3`,
   `ringAlpha: 0.5`. Keep `fieldBorderWidth`, `stateStyle`, `inverted`,
   `stateAppearance` and their `tokens.js` helpers compiling (Cell and
   AuthPrompt still read them) but rebind `inverted()` to `{ bg: primary,
   fg: primaryForeground }`; Task 3 deletes what Cell no longer needs, M45
   the rest.
4. Templates: `theme.json.tmpl` emits the new keys from the matugen roles in
   the spec table; the pywal template maps `color4` to `primary`, `color8`
   to `mutedForeground`, `color0` to `card`/`border`, `color1` to
   `destructive`, `color3` to `warning`.
5. Sweep every `Theme.color.<old>` read per D1 (cheap subagents, one per
   directory under `shell/Surfaces`).
6. Tests: `tst_tokens.qml` covers `radiusTokens`, spacing values, weights;
   `tst_palette.qml` covers validation with the new key list and the
   fallback's mode selection.

Verify: `just test`; `just lint`; `rg -n 'foregroundDim|backgroundAlt|onAccent|onUrgent|color\.rule|color\.accent\b' shell` returns nothing.
Commit: `feat(theme): adopt shadcn color tokens and radius scale`.

### Task 2: Lucide icon font and Icon

Files: `nix/lucide-font.nix`, `nix/package.nix`, `nix/testvm.nix`,
`tools/gen-lucide-icons.sh`, `shell/Theme/icons.js`,
`shell/Theme/icons/lucide.js`, `shell/Theme/icons/nerd.js`,
`shell/Components/Icon.qml`, `shell/Components/qmldir`,
`tests/tst_icons.qml`, `docs/USAGE.md` (`theme.icons`).

1. `nix-prefetch-url --unpack` the pinned release zip; write the derivation
   per D2. `nix build .#lucide-font` and `ls result/share/fonts`.
2. Generator: `sed`/`awk` over `lucide.css` (`.icon-NAME:before { content:
   "\eXXX" }`) to `icons.js`; run it; commit the output.
3. `Icon.qml` per D2, plus `implicitWidth` equal to the font size so a row
   can lay it out like a character.
4. `tst_icons.qml`: every name the shell uses resolves in BOTH sets (the
   test file lists the names this milestone uses and the M42+ tasks append
   to it); an unknown name yields each set's `circle-help`; `family("nerd")`
   is empty and `family("lucide")` is `"lucide"`.

Verify: `just build` (font on the wrapper's path: `result/bin/formalshell`'s
`FONTCONFIG_FILE` or `XDG_DATA_DIRS` includes the font store path,
`fc-list | rg lucide` inside the VM); `just test`.
Commit: `feat(icons): ship lucide as a font and render icons by name`.

### Task 3: primitives

Files: `shell/Components/Cell.qml`, `Button.qml`, `IconButton.qml`,
`Card.qml`, `SectionLabel.qml`, `Input.qml`, `Track.qml`,
`KeyCatcher.qml`, `Tooltip.qml`, `MetaLabel.qml` (becomes a thin
`SectionLabel` until M45 removes it), `qmldir`,
`tests/tst_cell_geometry.qml`, `tests/tst_cell_hover_inversion.qml`
(renamed `tst_cell_states.qml`), `tests/tst_keycatcher.qml`.

1. `Cell.qml` per DESIGN.md §2 and D3: one background `Rectangle` (`card`,
   `radiusMd`, 1px `border`), one hover layer (`accent`, fades on `fast`),
   one ring layer (outside the border by `ringWidth`, `ring` at
   `ringAlpha`, visible on `cursor`), `active`/`destructive`/`warning`
   states, no shared rule, no inversion, no `pending` dither loader
   (`DitherFill`/`DitherImage` stay in `Components/` for the wallpaper and
   lock opt-ins). Keep the pointer contract (`interactive`, `hit`,
   `clicked`, `wheeled`, `pointerMoved`, tooltip loader). Then delete
   `Theme.stateAppearance`/`stateStyle`/`inverted` and the matching
   `tokens.js` helpers, rewriting AuthPrompt's reads to `Theme.borderWidth`
   and the primary pair.
2. `Button.qml`: `variant`, `text`, optional leading `Icon`, `controlHeight`,
   `radiusMd`, the four states. `IconButton.qml` wraps it square.
3. `Card.qml`, `SectionLabel.qml`, `Input.qml` (a `TextInput` inside a
   `Cell`-like frame with `input` border and the ring on `activeFocus`;
   error state), `Track.qml`.
4. `KeyCatcher.qml`: signals `moveRequested(dx, dy)`, `activateRequested`,
   `closeRequested`, `deleteRequested`, `tabRequested(direction)`,
   `textKey(text)`, property `blocked`. `Keys.priority: Keys.BeforeItem`.
5. `Tooltip.qml`: `popover`, `radiusSm`, `caption`, no uppercase.
6. Tests: geometry (implicit size from padding tokens and content), states
   (which layer is visible per flag combination), key dispatch (each key
   fires exactly one signal; `blocked` fires none).

Verify: `just test`; `just lint`.
Commit: `feat(components): shadcn primitives and a shared key catcher`.

### Task 4: panel chrome and the network panel

Files: `shell/Components/Panel.qml`, `shell/Components/CardTitleBar.qml`
(deleted; the header is Panel's own), `shell/Components/PanelHero.qml`,
`shell/Surfaces/Panels/NetworkPanel.qml`, `tests/tst_network_panel.qml`
if present.

1. `Panel.qml`: `Card` frame `radiusXl`, `panelWidth` default
   `popupWidthDefault`, `barMargin` under the bar, header row (`Icon`
   `panelIcon`, title `subtitle`/`semibold`, `titleActions` slot right-
   aligned as `IconButton`s, a close `IconButton` always last), content
   column with `sectionGap`, a `KeyCatcher` around it wired to `keyPressed`
   consumers through `cursor` bookkeeping (`cursorIndex`, `cursorSection`,
   `moveCursor`, `activateCursor`), keep the focus prime and `cursorActive`
   logic.
2. `PanelHero.qml`: an inner `Card` with `radiusMd`, two-line body, no
   dither.
3. `NetworkPanel.qml` to the reference layout: hero (connected AP: name,
   signal as `bodySmall` `mutedForeground`, BSSID as caption), a stats card
   (`Track`-free: sparkline stays if it exists, else two labelled numbers),
   `SectionLabel` `NETWORKS (n)`, one `Cell` per network with a lock `Icon`
   and a check `Icon` on the connected one, footer `outline` `Speed test`
   Button. Keyboard: arrows move the cursor across rows, Enter connects,
   Tab reaches the footer button, the passphrase `Input` blocks the catcher
   while focused.

Verify: `just lint`; `just test`; Task 7's `--panel network` screenshot.
Commit: `feat(panel): shadcn card chrome and keyboard cursor, network first`.

### Task 5: bar chrome

Files: `shell/Surfaces/Bar/Bar.qml`, `widgets/Workspaces.qml`,
`widgets/Clock.qml`, `widgets/NetworkWidget.qml`, `widgets/BellWidget.qml`,
`widgets/LauncherWidget.qml`, `shell/Components/PanelOpenDot.qml`
(deleted), `tests/tst_bar_layout.qml` if it asserts cell geometry.

1. `Bar.qml`: transparent window, height `barCellHeight + 2*barMargin`,
   `exclusiveZone` to match, regions laid out with `sm` gaps and
   `barMargin` insets. `_cellHeight` reads `barCellHeight`.
2. `Workspaces.qml`: one `Cell` holding dots per DESIGN.md §3; active pill
   animates width on `fast`.
3. `Clock.qml`, `NetworkWidget.qml`, `BellWidget.qml`, `LauncherWidget.qml`:
   `Icon` plus label inside a `Cell`; the open-panel underline replaces
   `PanelOpenDot`. Other widgets keep compiling through D3 and are restyled
   in M42 with their panels.

Verify: `just lint`; `just test`; Task 7's base screenshot.
Commit: `feat(bar): pill cells on a transparent strip`.

### Task 6: docs

Files: `docs/ARCHITECTURE.md` ("Theme engine data flow" and the token
paragraphs), `docs/USAGE.md` (`theme.radius`, the removed dither keys are
M45's), `CLAUDE-decisions.md` (entry already added 2026-08-25), `README.md`
(one line pointing at the redesign spec; screenshots are M46).

Verify: `rg -n 'foregroundDim|backgroundAlt|inverted' docs/ARCHITECTURE.md docs/USAGE.md` returns nothing.
Commit: `docs: describe the shadcn token set and radius setting`.

### Task 7: nested Hyprland rig, four legs

Files: `dev/smoke.sh` (from `dev/smoke-hyprland.sh`), `dev/vm.sh`,
`justfile`, `nix/testvm.nix` (only if a Hyprland runtime dependency is
missing).

1. Port from `dev/smoke-niri.sh` into `dev/smoke.sh`: the isolated HOME
   and settings fixture, `dbus-run-session`, the host-bus owner assertion,
   the `SMOKE_OK` screenshot, `--menu`, `--notify`, `--panel <name>`.
   `niri msg` calls become `hyprctl -j`; the fixture window is `foot` via
   `hyprctl dispatch exec`.
2. `dev/vm.sh smoke --compositor hyprland` is the default; `--compositor
   niri` runs the old script unchanged.
3. Run in the VM: `just vm-smoke`, `just vm-smoke --menu`, `just vm-smoke
   --notify`, `just vm-smoke --panel network`. Read every PNG under
   `artifacts/`: pill cells with a visible 1px border on a transparent
   strip, the network panel as a rounded card with the header row and
   `NETWORKS (n)` label, the launcher and toasts still rendering on the new
   tokens (their own chrome is later milestones).
4. Two failed attempts at a green base leg means stop and report per D4.

Verify: the four runs above, PNGs read and described in the task report.
Commit: `feat(dev): nested hyprland smoke rig with menu, notify and panel legs`.

### Task 8: sans and mono by context, translucent surfaces

Owner additions on 2026-08-25 after Nothing OS 5.0: two faces by context
and a flat gaussian blur behind the bar, the panels and the launcher card.
Spec sections "Type" and "Depth" are the contract; DESIGN.md §1 restates it.

Files: `shell/Core/Theme.qml`, `shell/Theme/tokens.js` if a helper fits
there, `shell/Components/{Button,IconButton,Card,SectionLabel,Input,Tooltip,
MetaLabel,Panel,PanelHero,Cell,Icon}.qml`, `shell/Surfaces/Panels/NetworkPanel.qml`,
`shell/Surfaces/Bar/Bar.qml` and the widgets Task 5 restyled,
`shell/Surfaces/Menu/Menu.qml` (only its card fill),
`nix/testvm.nix` (fonts), `docs/examples/hyprland/formalshell.conf`
(created here if Task 7 did not), `docs/USAGE.md`, tests.

1. `Theme.qml`: `fontFamilySans: "sans-serif"`, `fontFamilyMono:
   "monospace"`, `surfaceOpacity` from `Config.get("theme.surfaceOpacity",
   0.85)` clamped to 0..1, `function surface(color)` returning the colour at
   that alpha. `fontFamily` stays bound to `fontFamilyMono` for files not
   yet ported; M45 deletes it.
2. Every `Text` in the files above picks a face by the spec rule: sans for
   words, mono for values. `SectionLabel`, `Button`, `Input`, `Tooltip`,
   `MetaLabel`, Panel's title are sans; Cell does not own text and needs no
   change beyond its fill; `Icon` is untouched. In `NetworkPanel`, SSIDs,
   the hero name and every label are sans; signal percent, BSSID, the
   speed figures and the unit are mono. In the bar, `Clock` is mono
   medium, `NetworkWidget`'s label is sans if it is a name and mono if it
   is a value, `Workspaces` has no text.
3. Translucency: `Cell` (bar cells), `Card`, `Panel`'s frame and Menu.qml's
   card fill paint `Theme.surface(Theme.color.card)`; Tooltip paints
   `Theme.surface(Theme.color.popover)`. Toasts, OSD, lock and the menu
   scrim keep opaque fills. `Bar.qml` sets `WlrLayershell.namespace:
   "formalshell:bar"` (it has none today) so a layerrule can target it.
4. `docs/examples/hyprland/formalshell.conf`: `decoration { blur {
   enabled = true; size = 8; passes = 2; } }` and, for each of
   `formalshell:bar`, `formalshell:panel`, `formalshell:menu`: `layerrule =
   blur, <ns>` and `layerrule = ignorealpha 0.2, <ns>`. Note in a comment
   that Omarchy's defaults ship blur off and this file turns it on. If the
   file already exists from Task 7 or M46 planning, add to it.
5. `nix/testvm.nix`: `pkgs.geist-font` in `fonts.packages`;
   `fontconfig.defaultFonts.sansSerif = [ "Geist" ]` and `monospace = [
   "Geist Mono" ]` (check the family names with `fc-list | rg -i geist`
   inside the VM before writing them). The nix config examples in
   `docs/USAGE.md` show the same two lines for a real host.
6. Tests: `tst_theme_tokens.qml` covers `surface()` alpha and clamping;
   a test asserts `SectionLabel`/`Button` use `fontFamilySans` and the
   bar clock uses `fontFamilyMono` if the existing test harness can
   instantiate them (Task 3's tests show how).

Verify: `just test`, `just lint`, `just vm-lint`; `just vm-smoke` and
`just vm-smoke --panel network` on the Hyprland rig, PNGs read: sans on
labels and titles, mono on the clock, percentages and BSSID, and the panel
card visibly translucent over the fixture window (blur itself may or may
not render under llvmpipe; translucency must).
Commit: `feat(theme): sans and mono by context, translucent surfaces`.

## Done when

All eight commits are in, `just test` and `just lint` pass, the four rig
legs are green on nested Hyprland with their PNGs read, and no file under
`shell/` reads a removed token name. Task order: 1 to 5, 7, 8, then 6
(docs last, so they describe what landed).

## Landed

1. `05447c4` feat(theme): adopt shadcn color tokens and radius scale
2. `4b8a6e1` feat(icons): ship lucide as a font and render icons by name
3. `582d69a` feat(components): shadcn primitives and a shared key catcher
4. `05691a6` feat(panel): shadcn card chrome and keyboard cursor, network first
5. `0ef000e` feat(bar): pill cells on a transparent strip
6. `e517319` feat(dev): nested hyprland smoke rig with menu, notify and panel legs
7. `33fdaca` feat(theme): sans and mono by context, translucent surfaces
8. Task 6, this docs pass: `docs: shadcn redesign spec, rulebook and m41 plan`
   and `docs: describe the shadcn token set, icons and the hyprland rig`
