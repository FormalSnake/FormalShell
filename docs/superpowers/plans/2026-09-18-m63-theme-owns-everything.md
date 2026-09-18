# M63: the theme owns the look, the motion and the layout

**Date:** 2026-09-18
**Status:** planned; starts on `m63-theme-owns` once M62 (the frame ring's
wingpanel paint, the `bar.paint` pin, opaque pantheon panels) is on main.
**Spec:** `docs/superpowers/specs/2026-09-17-pantheon-mode-declarative-themes.md`;
M59 and M60 plans for the mechanism.

## Owner's ask (2026-09-18)

"Make it part of our theme, themes should be able to change animations, the
layout, whatever. The one we have normally should be called metamorphosis,
this one should be called pantheon."

Three things, and nothing a user has to pin:

1. The preset that ships is `metamorphosis`, not `shadcn`. `retro` and
   `pantheon` stay. No alias for the old name (owner's standing rule: no
   compatibility shims); a settings.json still saying `shadcn` resolves to
   the default the way an unknown name does, and the docs say so once.
2. The bar's paint policy is the theme's: pantheon's table says the band
   never fills (transparent, ink by the band's brightness, solid black on a
   maximized window), the `bar.paint` key from M62 stays as the user's
   override on top, defaulting to whatever the table says.
3. Everything a theme could plausibly want to change lives in the table:
   the whole motion table (both clock families and every named clock, not
   just the three M60 added), the chrome scalars the presets carry today
   (radius, opacity, blur, dither, icons, fonts move into the table as its
   `scalars` entry, `presets.js` reading them from there), and the layout
   knobs a theme should own: the panel's gap off the bar (`barMargin`
   today, elementary's 0.5rem), the popup widths, the bar's cell metrics,
   the toast stack's inset and gap, the switcher's icon and inset. Each is
   a `Theme.space` token today; the table gets a `space` entry that
   overrides named tokens, so metamorphosis's entry is empty and pantheon's
   names the handful elementary sizes differently. User keys still win
   over the table where a key exists.

## Decisions

**O1 Rename.** `presets.js` `NAMES = ["metamorphosis", "retro", "pantheon"]`,
`_name()` falls back to `metamorphosis`, the table file keeps its name.
Every fixture, test, leg comment, doc line and the nix example that says
`shadcn` as a preset name changes. The word stays where it names shadcn/ui
the design language (DESIGN.md's vocabulary), which is a different thing.

**O2 Motion in the table.** `style.js` `MOTION_KEYS` grows to the whole of
`Tokens.MOTION` (`spatialFast`, `spatial`, `spatialSlow`, `effectsFast`,
`effects`, `effectsSlow`, `emphasized`, `emphasizedDecel`, `reveal`,
`marquee`, plus M60's `emerge`, `arrive`, `restack`); `Tokens` keeps the
curve and duration constants as the metamorphosis table's values by name,
so `metamorphosis.js` says `spatial: "spatial"` for each and its bytes do
not change, while `pantheon.js` writes elementary's clocks: `in-place`
100ms for the effects family, `open` 250 / `close` 200 / `expand` 300 /
`collapse` 250 on `cubic-bezier(0.4, 0, 0.2, 1)` for the spatial family
(Gala's 350/195 for a window are the compositor's). `Theme.motion` and
`Theme.curves` resolve from the table; `Anim`/`CAnim` do not change.

**O3 Scalars in the table.** `radius`, `icons`, `fonts`, `surfaceOpacity`,
`blur`, `dither` become `STYLE.scalars`; `presets.js` `_TABLE` goes away
and `defaults(name)` reads the table's scalars. `theme.*` keys override
as today.

**O4 Space in the table.** `STYLE.space` is a partial map over
`Tokens.spacingTokens`'s semantic keys; `Theme.space` merges it after the
scale. Pantheon sets `barMargin: 8` (0.5rem), `panelPadding: 6` (their
popover's `0.25rem 0` plus the row padding, read off the CSS), the toast
inset `screenPadding: 16`, and leaves the rest. A key a user sets
(`bar.*`, `menu.*`) still wins. The same entry carries the layout defaults
a theme owns: `barPosition` (pantheon `top`, wingpanel is a top panel;
metamorphosis `top`, the shipped default) and `notificationPosition`
(pantheon `top-right`, elementary's corner; metamorphosis `bottom-right`),
read where `bar.position` and `notifications.position` take their
defaults today. The owner moved their own `bar.position` key to `top` on
2026-09-18 for pantheon; a config without the key gets the theme's.

**O5 Paint policy in the table.** `STYLE.bar.paint` (`"auto"` or
`"transparent"` or a paint name) is the default M62's `bar.paint` key
falls back to; pantheon says `transparent`, metamorphosis `auto` (which
under the strip habit samples nothing). The nix mixin carries no pin.

**O6 The ink glow.** Wingpanel's contrast on a transparent panel is its
text and icon shadow, `0 0 2px black 0.3` plus `0 1px 2px black 0.6` (white
at 0.3 and 0.25 for dark ink), a blurred glow and an offset, which QML
`Text` cannot draw and `Text.Raised` only approximates as a 1px offset.
Owner, 2026-09-18, asked whether a transparent band "will always contrast
decently like pantheon", and chose rendering the shadow as elementary
draws it: a `MultiEffect` glow behind each bar cell's ink under the
wingpanel habit, blurred per the table's `inkShadow` entry (blur radius,
offset, colour, alpha, per paint), off entirely under a table whose ink
carries no shadow. The glow is one layer per cell, drawn once per change
of the cell's content, and the strip's cost stays what `--bar-room`
measures today.

## Tasks

One subagent per task, in order, verification read before each commit,
every VM command through `dev/vm-lock.sh`.

### Task 1: the rename (O1)

Verify: `just test`, lint, `--gallery`, `--retro --gallery`, `--pantheon
--gallery`, `dev/parity.sh --gallery` against `../FormalShell-main`.

### Task 2: motion and scalars (O2, O3)

Verify: `just test`, lint, `dev/parity.sh --join`, `--panel-emerge`,
`--osd`, `--notify` (metamorphosis bytes unchanged), then `--pantheon
--panel-emerge`, `--pantheon --notify-emerge`, `--pantheon --osd` read for
the elementary clocks.

### Task 3: space and paint (O4, O5)

Verify: `just test`, lint, `--pantheon --panel network` (the gap at 8),
`--pantheon --frame-adaptive` or whatever M62 named it (transparent by the
table with no key set), `--bar-adaptive`, metamorphosis `--panel network`,
`--notify`, `dev/parity.sh --panel network --notify --tooltip`.

### Task 3b: the ink glow (O6)

Verify: `just test`, lint, `--pantheon --bar-adaptive` reading a crop of a
cell's glyph over the busy band for the glow (a dark halo around light
ink), `--bar-room` under both presets for the strip's own cost, `--frame-adaptive`,
metamorphosis `--bar-layout` unchanged.

### Task 4: the record and the hosts

`docs/DESIGN.md` §1 Themes (what a table owns now: chrome, habits, motion,
scalars, space, paint), `docs/USAGE.md` (presets: `metamorphosis`, the
table), `CLAUDE.md`, this plan's Status. Merge, push, bump the dotfiles
lock, rebuild e1504g then g815.

## Evidence

Filled per task.
