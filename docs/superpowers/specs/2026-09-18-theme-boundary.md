# What a theme owns, and what is the shell's

Owner, 2026-09-18: one layout and one behaviour for every theme, each
theme still recognisably its own, and as little per-theme maintenance as
possible. This wins over the 2026-08-25 and 2026-09-17 specs where they
disagree.

## The rule

A theme is one table file (`shell/Theme/themes/<name>.js`) and nothing
else. It changes how a thing looks and moves, never what is on screen,
where, or what a key does. No surface tests a theme name or a
layout-shaped habit; a surface draws through `Theme.box()` roles and the
shared components, and a new role is declared in every table (the
`tst_theme_style.qml` check already enforces it).

## Global: one implementation for every theme

- Layout and structure of every surface: the launcher, panels, the
  notification centre, lock, OSD, the bar's cell set and order.
- Behaviour: keys, focus, cursor model, pointer handling, what each
  surface offers (the Alt+Tab switcher included: it becomes a user
  setting, not a pantheon habit).
- The component set in `shell/Components/`.
- Spacing rhythm and the type scale (`tokens.js`), and text casing:
  headings are sentence case everywhere.
- The palette's source: matugen off the wallpaper, for every theme.
- Copy, empty states, icon names (which icon a thing uses).
- Surface sizes and the card sizes a surface settles on.

## Theme: the table's

- Material per role: fills and their alphas, borders, lit rims, faces,
  casts, washes, separators, the cursor ring, the scrim.
- Radii, the border width, surface translucency.
- Font families (sans and mono) and weights, not sizes.
- The icon set (`theme.icons`: Lucide, Nerd, elementary's own).
- The bar: its edge, its band paint (wingpanel's is a paint policy, not
  a layout) and the screen frame.
- Motion: clocks, curves, and how a card arrives (join or popover, row
  or bubble), since those are how a surface moves, not what it holds.
- Hyprland's window chrome (gaps, borders, shadow) and the dither pass.

## Keeping it cheap

- Retro stays a re-export of metamorphosis with other scalars; a new
  theme should start the same way and override roles only.
- A theme difference that needs a surface to branch is a sign it belongs
  on the global side, or is a missing role.
- Existing habits are sorted by this: `bar`, `emerge`, `notification`,
  `frame`, `paint` stay (look and motion); `launcher` is deleted (M72
  T2); `switcher` moves to settings.
