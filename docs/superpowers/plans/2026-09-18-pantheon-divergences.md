# Pantheon divergences from elementary OS 8 (audit, 2026-09-18)

Read-only audit of what the shell draws under `theme.preset: "pantheon"`
against elementary's own sources, fetched from raw.githubusercontent.com on
2026-09-18: `elementary/stylesheet` (main, `src/gtk-4.0/`), `wingpanel`
(`data/styles/Application.css`), `notifications` (`data/application.css`,
`src/*.vala`), `gala` (`src/Misc/`), `applications-menu`, `granite`
(`lib/Styles/Granite/Header.scss`), `greeter`, `pantheon-agent-polkit`, and the
network, sound and notifications wingpanel indicators (master). Commit
b433438 (etched separator, cast and hairline corners) is out of scope.

Severity: **high** reads as un-Pantheon at a glance, **med** is visible on a
second look or on one surface, **low** is a number off or an admitted
approximation. Counts: 9 high, 17 medium, 14 low.

Where the 2026-09-17 spec made a call that the sources contradict, the entry
says so. The spec still wins in this repo; those entries are there so the
owner can decide whether to amend it.

## High

### H1. Palette: matugen Material roles instead of elementary's greys and named accent
- **Ours:** every role is matugen off the wallpaper
  (`shell/Theme/templates/theme.json.tmpl:3-16`: `card` is
  `surface_container_low`, `secondary` `surface_container_high`, `primary`
  the Material primary). The table keeps that on purpose
  (`shell/Theme/themes/pantheon.js:532-535`). In dark mode that puts every
  popover near #111-#1c, tinted by the wallpaper, with a pastel primary.
- **elementary:** neutral surface ladder `bg-color(0..4)`, SILVER_100 /
  white in light and BLACK_300..700 mixes (#333 background) in dark
  (`src/gtk-4.0/_index.scss` `bg-color()`), and a saturated accent that is one
  of eleven named hues (`variants/blueberry.scss`:
  `mix(@BLUEBERRY_300, @BLUEBERRY_500, 0.25)`, `-dark` 0.5).
- **Fix:** give pantheon its own palette source: the five bg levels as
  fixed greys per mode, and `primary`/`ring` snapped to the nearest of the
  eleven hues (the spec's deferred `theme.accent: "named"`).

### H2. Panel header: icon, title and close button over a rule
- **Ours:** every panel opens with an icon, a semibold `subtitle` title, an
  `x` IconButton and a full-bleed separator
  (`shell/Components/Panel.qml:845-911`; titles such as
  `NetworkPanel.qml:1009` "Wi-Fi", `AudioPanel.qml:43` "Audio").
- **elementary:** indicator popovers have no title bar and no close button.
  The first row is the primary toggle as a `Granite.SwitchModelButton` with
  the `h4` class (bold label left, switch right:
  `wingpanel-indicator-network src/Widgets/WifiInterface.vala:107-108`,
  `wingpanel-indicator-notifications src/Indicator.vala:106` "Do Not
  Disturb"), and the last row is a "... Settings…" menu item
  (`PopoverWidget.vala:110`, sound `src/Indicator.vala:404`).
- **Fix:** under `emerge: "popover"` default `showHeader` to false, let a
  panel promote its main toggle into a bold switch row, and add a settings
  row at the foot.

### H3. Uppercase, tracked, muted section labels
- **Ours:** `SectionLabel` is caption size, medium weight,
  `Font.AllUppercase`, tracked, `mutedForeground`
  (`shell/Components/SectionLabel.qml:38-43`), used 184 times in 31 files,
  plus `CellLabel` meta (`CellLabel.qml:63`) and literal caps states
  (`NetworkPanel.qml:1115` "CONNECTING", `Center.qml:574` "NO
  NOTIFICATIONS").
- **elementary:** section headers are `Granite.HeaderLabel` / `h4`: sentence
  case, weight 700, body size, `opacity: 0.9` on the heading
  (`granite lib/Styles/Granite/Header.scss`, `title-4`). No stylesheet rule
  uppercases or tracks anything; state strings are sentence case with an
  ellipsis ("Scanning for Access Points…", `WifiInterface.vala:75`).
- **Fix:** move the section label's case, weight, tracking and colour into
  the theme table; pantheon takes mixed case, bold, body size, foreground.
  Sentence-case the literal state strings behind the same switch.

### H4. Icon set: Lucide glyphs instead of elementary's symbolic icons
- **Ours:** `pantheon: { icons: "lucide" }` (`shell/Theme/presets.js:33`);
  the only sets are Lucide and Nerd font glyphs
  (`shell/Theme/icons.js:8-11`). Stroke icons at uniform weight.
- **elementary:** its own filled symbolic icon theme, looked up by
  freedesktop name (`channel-insecure-symbolic`,
  `process-error-symbolic` in `WifiMenuItem.vala:55-57`,
  `panel-network-airplane-mode-symbolic` in `PopoverWidget.vala:61`).
- **Fix:** a third `theme.icons` set that maps our names to freedesktop
  `-symbolic` names, resolves them through the installed icon theme
  (`Quickshell.iconPath`) and tints them to the ink; pantheon defaults to it.
  No SVG ships in the repo, so the no-icon-assets rule holds.

### H5. Bar layout is Omarchy's, not wingpanel's
- **Ours:** `DEFAULT_LAYOUT` ignores the habit
  (`shell/Bar/layout.js:58-63`): launcher icon, workspace pill and active
  window title on the left, `hh:mm` plus now-playing in the centre, eight
  cells on the right. The launcher cell is an icon
  (`Surfaces/Bar/widgets/LauncherWidget.qml:63-66`).
- **elementary:** "Applications" as a text label on the left, the date and
  time centred ("Thu Sep 18  3:45 PM"), indicators on the right, no
  workspace indicator and no window title. The spec's own Part 2 says
  "launcher left, clock centre, indicators right".
- **Fix:** a per-habit default layout (`bar: "wingpanel"` gets
  `left: ["launcher"]`, `center: ["clock"]`), a text launcher label under
  the habit, and a weekday-date-12h clock default.

### H6. Monospace values and semibold ink on the band
- **Ours:** every bar value (clock, percentages) is `fontFamilyMono`
  (`shell/Components/CellLabel.qml:60`) at semibold on the band
  (`CellLabel.qml:62`); `fontFamilyMono` appears 85 times in 30 files,
  panels and the lock clock included.
- **elementary:** `.composited-indicator { font-weight: bold }` in the UI
  sans (`wingpanel data/styles/Application.css`); the stylesheet only uses
  monospace behind an explicit `.monospace` class (`_typography.scss`).
- **Fix:** a table key that sends values to the sans with tabular figures
  (`font.features: {"tnum": 1}`) under pantheon, and weight 700 on the band.

### H7. OSD is a bottom pill; elementary's is a confirmation bubble
- **Ours:** bottom-centred pill with icon, track and mono percentage
  (`shell/Surfaces/Osd/Osd.qml:10-13, 160-165, 197`), drawn in the `card`
  role (`Components/Drawer.qml:61`). The spec's own fallback, an `.osd` box
  (BLACK_500 0.9, radius 6, shadow(1)), has no role in the table either.
- **elementary:** Gala's `ShowOSD` sends a notification with a `value` hint
  (`gala src/Misc/DBusAccelerator.vala:144-165`), which
  `io.elementary.notifications` draws as a `Confirmation` bubble: 48px icon
  and a 258px flat progress bar, no number, 2000ms, in the bubble's
  top-right slot (`notifications src/Confirmation.vala:29-45`,
  `src/DBus.vala:204-210`). The spec's "Pantheon has none" is wrong on this.
- **Fix:** under `notification: "bubble"` render the OSD as a bubble in the
  toast stack (icon plus a flat track, same card), replacing in place.

### H8. Lock screen clock and date
- **Ours:** `hh:mm` at 3x `displayLarge` in mono semibold, the date as an
  uppercase SectionLabel (`shell/Components/AuthPrompt.qml:83-92`), bare
  field below.
- **elementary:** the greeter's `.time` is 10em, weight 500,
  `letter-spacing: -0.05em`, white with a two-layer shadow; `.date` is 2em,
  weight 600, white at 0.9 with its own shadow, sentence case
  (`greeter data/Application.css`); the user sits on a card with an avatar.
- **Fix:** habit-driven clock and date styling (sans, tight tracking,
  shadows, 12h per locale) and a card with the account's avatar and name.

### H9. Launcher: centred modal over a scrim, 4 columns, vertical scroll
- **Ours:** the card drops centred from the top edge
  (`shell/Surfaces/Menu/Menu.qml:2302-2314`) over a modal scrim
  (`Menu.qml:2275`); the app grid is as many 128px cells as fit, 4 at
  `popupWidthMenu`, scrolling vertically, names on one elided line
  (`Surfaces/Menu/views/AppGridView.qml:59-69, 107, 195`).
- **elementary:** Slingshot is a popover hanging off the "Applications"
  label at the top left, no dim; pages of 5 x 3 in an `Adw.Carousel` with a
  page switcher under them (`applications-menu src/Views/GridView.vala:8-9,
  47-61`); names wrap to 2 lines at 16 characters
  (`src/Widgets/AppButton.vala:25-29`). The spec asks for 5 x 3 pages too.
- **Fix:** under `launcher: "grid"` anchor the card to the launcher cell as
  a popover, drop the scrim, fix 5 columns x 3 rows per page with paging
  dots, 2-line names.

## Medium

### M1. Switch geometry
- **Ours:** a 32 x 18 track with a 14px knob inset 2px from each end
  (`shell/Components/Switch.qml:82-83, 142, 149`).
- **elementary:** knob `min-height/min-width: rem(24px)` riding over the
  track's own border (`background-clip: padding-box`), 20px inside menus
  (`widgets/_switches.scss`, `_popovers.scss` `%menuitem switch slider`).
- **Fix:** knob size and inset from the table; pantheon 20px in panels,
  inset 0.

### M2. Switch knob material not transcribed (admitted)
- **Ours:** `"switch.knob": { fill: "secondary", radius: "pill" }`
  (`pantheon.js:450-454`, "not transcribed here"); the `on` track is a flat
  primary (`pantheon.js:447`).
- **elementary:** knob is `%outset-background` on `bg-color(0)`,
  `outset-highlight("full")`, a `0 0 0 1px $border-color` ring and
  `outset-shadow(3)`; the checked track takes the face gradient and a
  `shade(@accent_color, 0.85)` border (`_switches.scss`).
- **Fix:** give the knob FACE, HIGHLIGHT, a control-border ring and
  `outset-shadow(3)` (0.12/0.24 pair, same as SHADOW_1 light).

### M3. Scale: accent fill, no knob, no rim
- **Ours:** `track.fill` is `primary` (`pantheon.js:468`), the groove has no
  border, and `Track` draws no knob (`shell/Components/Track.qml:110-121`).
- **elementary:** the default scale's highlight is `rgba($fg-color, 0.7)`
  with a black 0.3 border; accent only on `scale.accent`; the trough has a
  1px border and a lit lip; a 14px raised knob (`widgets/_scales.scss`). The
  sound indicator uses the plain scale (`wingpanel-indicator-sound
  src/Widgets/Scale.vala:29`).
- **Fix:** pantheon `track.fill` to foreground 0.7, a groove rim, and a knob
  role that interactive tracks draw.

### M4. Suggested action is a solid primary
- **Ours:** `button.default` fills `primary` at 1 (`pantheon.js:343-357`).
- **elementary:** `.suggested-action` extends `selection`:
  `alpha(@accent_color, 0.25)` behind `shade(@accent_color, 0.5)` text
  (dark: `alpha(shade(accent, 0.85), 0.5)` and a near-white mix)
  (`widgets/_buttons.scss`, `_exported.scss`).
- **Fix:** fill primary at 0.25 (0.5 dark) with a primary-derived ink;
  needs a table ink key for buttons.

### M5. Tooltip plate follows the palette
- **Ours:** `popover` role fill `popover` at 0.9 (`pantheon.js:280-285`), so
  it is near white in light mode; caption size; 12 x 6 padding
  (`shell/Components/Tooltip.qml:193, 210-212, 239-254`).
- **elementary:** always `rgba($BLACK_700, 0.9)`, white text with
  `0 1px 2px black 0.6`, `padding: rem(6px)` (`widgets/_tooltips.scss`).
- **Fix:** literal black fill and white ink in the role; padding 6.

### M6. Popover rows are inset rounded plates
- **Ours:** content inset `panelPadding` 12 (`tokens.js:91`,
  `Panel.qml:369`), rows `controlHeight` 32 with the R_CONTROL corner.
- **elementary:** `popover.indicator > contents { padding: 0.25rem 0 }`
  (wingpanel CSS) and menu items `border-radius: 0; padding: rem(6px)
  rem(12px)`, hover `fg 0.15` across the whole width (`_popovers.scss`
  `%menuitem`).
- **Fix:** under the popover habit, zero horizontal panel padding, square
  full-bleed rows, 6/12 row padding.

### M7. Keyboard cursor rings rows
- **Ours:** the cursor is the ring border plus a 2px 0.3 halo on every row
  (`pantheon.js:87, 496-499`; `Panel.qml:281-289`).
- **elementary:** list rows and menu items mark focus with the same
  `fg 0.15` fill as hover (`_lists.scss` `row:focus-visible`,
  `%menuitem outline-style: none`); the ring belongs to buttons, entries,
  checks and switches.
- **Fix:** a row cursor state in the table; pantheon's is the wash.

### M8. Checkmarks are trailing bare glyphs
- **Ours:** a trailing Lucide `check` in `primary`
  (`NetworkPanel.qml:1082-1089`, `AudioPanel.qml:320-327`,
  `Surfaces/Bar/TrayMenu.qml:366-375`).
- **elementary:** a leading radio (`WifiMenuItem.vala:36, 46`) or check:
  12px raised box, accent fill when checked, white
  `check-active-symbolic` with a shade shadow (`_checkbuttons.scss`).
- **Fix:** a `check`/`radio` primitive with the raised material, leading.

### M9. Bubble content layout
- **Ours:** an uppercase app-name label and mono timestamp line, a 32px
  icon, a title that wraps to 2 lines, and a muted small body
  (`shell/Surfaces/Notifications/NotificationBubble.qml:83-105, 128-145,
  170-196`).
- **elementary:** no sender or time line; a 48px icon (24px badge) spanning
  two rows, title bold on one ellipsized line, body at normal ink, 2 lines
  (`notifications src/Bubble.vala:86-128`).
- **Fix:** drop the meta line under the bubble habit, 48px icon, one-line
  title, body in foreground.

### M10. Bubble close button
- **Ours:** a ghost round IconButton at the top right, fading on hover
  (`NotificationBubble.qml:153-163`).
- **elementary:** `button.osd` at the top left, overlapping the corner:
  BLACK_500 circle with its own rim and two casts, 24px icon, revealed on
  hover (`src/AbstractBubble.vala:71-82`, `data/application.css`
  `button.osd`).
- **Fix:** a dark round button at the leading corner.

### M11. Urgency styling
- **Ours:** a `destructive` rim (`pantheon.js:268`) and a triangle-alert
  replacing the app icon (`NotificationBubble.qml:97, 110-112`).
- **elementary:** the title takes the error colour and the icon plays the
  `urgent` wobble; no rim (`src/Bubble.vala:164-166`, `application.css`
  `.urgent image`).
- **Fix:** keep the icon, colour the title, drop the rim under pantheon.

### M12. Bubbles default to the bottom-right corner
- **Ours:** `DEFAULT_POSITION = "bottom-right"`
  (`shell/Notifications/model.js:405`), whatever the habit.
- **elementary:** top right, 12px margins under the panel
  (`gala src/Misc/NotificationStack.vala:24-28, 100-105`).
- **Fix:** the bubble habit defaults `notifications.position` to top-right.

### M13. Notification centre is a shadcn sheet
- **Ours:** "Notifications" title, uppercase DND label and a switch, ghost
  "Clear all", PENDING / SEEN sections (`Center.qml:461-490, 574-678`).
- **elementary:** the notifications indicator popover: a "Do Not Disturb"
  switch row on top, entries grouped by app, then "Clear All
  Notifications" and "Notifications Settings…" rows
  (`wingpanel-indicator-notifications src/Indicator.vala:106-131`).
- **Fix:** same structure as H2 under the popover habit.

### M14. Polkit dialog
- **Ours:** uppercase "AUTHENTICATION REQUIRED" and "IDENTITY" labels, a
  mono identity, no icon, "Cancel" / "Authenticate" in solid primary
  (`shell/Surfaces/Polkit/PolkitDialog.qml:256-320`).
- **elementary:** the app's icon with a `dialog-password` badge, a
  `Granite.HeaderLabel` title with the message as secondary text, an
  identity combo, "Don't Allow" / "Allow" with the suggested style
  (`pantheon-agent-polkit src/PortalDialog.vala:97-110`,
  `src/PolkitDialog.vala:78-81`).
- **Fix:** icon plus badge, header label, sentence case; M4 fixes the button.

### M15. Active cells fill solid primary
- **Ours:** `cell.active` is `primary` at 1 (`pantheon.js:328`).
- **elementary:** a checked flat button is `fg 0.15` (`_buttons.scss`
  `.flat:checked`), a checked indicator toggle `@selected_bg_color` with
  `@selected_fg_color` ink (sound `data/indicator.css`
  `.image-button:checked`).
- **Fix:** primary at 0.25 with a primary-derived ink.

### M16. Launcher search row has no field
- **Ours:** a search icon, a bare text field and a rule
  (`Menu.qml:2318-2330`).
- **elementary:** a `Gtk.SearchEntry` (the sunken entry) beside a linked
  grid/category view selector (`applications-menu src/SlingshotView.vala:9,
  49-56`).
- **Fix:** wrap the field in the `input` role under the grid habit.

### M17. Typeface
- **Ours:** the fontconfig `sans-serif` alias, Geist by intent
  (`shell/Core/Theme.qml:305-314`); presets carry no family.
- **elementary:** Inter at 9pt (`_index.scss` `rem()` assumes 9pt;
  greeter's `font-feature-settings: "cv01"` is an Inter feature).
- **Note:** the spec lists fonts as a non-goal (owner runs Geist). Listed
  so the call is explicit; the fix would be an optional `fontFamily` in the
  preset.

## Low

### L1. No scrollbars
Nothing in `shell/` draws one (no `ScrollBar`/`ScrollIndicator`). elementary
shows an overlay slider, `rgba(fg, 0.6)`, 3px growing to 9px on hover
(`widgets/_scrollbars.scss`). Fix: a thin overlay indicator on Flickables
under pantheon.

### L2. Type sizes and weights
Body 13px (`Theme.qml:250`) against 9pt; row text medium 500
(`NetworkPanel.qml:1078`) where menu items reset to `font: initial` (400);
panel titles and bubble titles semibold 600 (`Panel.qml:874`,
`NotificationBubble.qml:176`) where `h4` and `.notification label.title`
are 700. Fix: weights in the table.

### L3. Control height
Buttons are `controlHeight` 32 (`Components/Button.qml:94`); elementary
pads `rem(4px) rem(7px)` for roughly 26px (`_buttons.scss`). Fix: a table
control height.

### L4. Bubble width
The card is 332 (`NotificationBubble.qml:41`, `tokens.js` `popupWidthBubble`),
which is the bubble window's width; the drawn card is 300 inside a 16px
margin (`AbstractBubble.vala:99`, `application.css` `.draw-area margin:
16px`, gala `NotificationStack.vala:28` `WIDTH = 300`). The spec copied 332.

### L5. Bubble rim and fill
Rim is the shared HIGHLIGHT 0.3/0.2/0.07 (`pantheon.js:263`); the bubble's
own is highlight 0.6/0.4/0.14. Fill opaque rather than `@base_color` 0.8
(documented at `pantheon.js:248-251`, no blur layerrule).

### L6. Bubble actions
Outline buttons left-aligned under the text (`NotificationBubble.qml:207-222`);
elementary right-aligns a homogeneous box, 12px above, `min-width: 65px`
(`Bubble.vala:147-160`, `application.css .buttonbox`).

### L7. Inset shadow is an approximation (admitted)
`inset-shadow()` arrives as one unblurred top line and the lit lower lip is
dropped (`pantheon.js:24-27, 51-57`), because Box draws no inset cast and
no outside hairline. Affects entries, troughs, switch tracks, pressed
buttons.

### L8. Translucent-dark band cast dropped (admitted)
`0 1px 3px black 0.15, 0 1px 1px black 0.3` under the panel is not drawn
(`pantheon.js:143-146`); the bar window has no row below the band.

### L9. Maximized open-indicator fill dropped (admitted)
`panel.maximized indicator:checked` is white 0.3; ours uses the one
`ghostOpen` fill on every paint (`pantheon.js:319-326`).

### L10. Tray menu corner
`menu` role radius 6 (`pantheon.js:291-297`); tray menus live inside a
wingpanel `popover.indicator`, radius `0.75rem`.

### L11. Switch off track
No 1px border and a deepened fill (`pantheon.js:440-446`); elementary has
`border: 1px solid $border-color` at black 0.05/0.10 (`_switches.scss`).

### L12. Bar cell hover
Ghost bar cells wash `fg 0.15` on hover (`pantheon.js:327`,
`Components/Cell.qml:172, 199`), in the palette foreground rather than the
band's ink; wingpanel's `indicator > revealer` has no hover rule, only
`:checked`.

### L13. Panel width
`popupWidthDefault` 380 (`NetworkPanel.qml:1010` and siblings); wingpanel
sets `min-width: 20rem` and lets content size the rest.

### L14. Window border colour (deliberate)
`window` role border is the palette `border` (`pantheon.js:576`) where
elementary uses the toplevel black 0.2/0.75 (`_windows.scss`). The table
explains why; listed for completeness.

## Owner decisions (2026-09-18)

- Themes differ in styling (table roles), bar position and motion only.
  Layout findings (panel header, bar layout, OSD, launcher) are out of
  scope: one layout for every theme.
- The wallpaper palette stays for every theme. The palette finding is
  dropped.
- Icon sets may be per theme, so pantheon taking elementary's own
  symbolic icons is in scope.
- Section headings are sentence case in every theme, not uppercase:
  `SectionLabel` drops its uppercasing for all three tables.
