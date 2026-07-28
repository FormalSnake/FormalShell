# FormalShell M8b: Design language revision + system-wide retrofit

> **For agentic workers:** Workflow-driven per `docs/superpowers/workflow-template.md`.
> Read `CLAUDE.md` first. **This plan rewrites `docs/DESIGN.md` in Task 1; from
> Task 2 onward the NEW DESIGN.md is the binding authority.** Runs AFTER M8.

**Origin — owner direction, 2026-07-28, verbatim:**
- *"Reference Omarchy quattro closely for the whole system, with some DMS
  feature influence. No need to attribute as we are reimplementing our own
  thing."*
- *"I love the omarchy style, but I want it to be a tiny bit more like what
  mek.gallery does (it's described, a classic ascii style os)."*
- *"Monospace too."*
- On the lock screen: *"keep the clock, but make it look better. What I saw in
  the screenshots looks too average."*
- On the screensaver: *"there must be multiple screensaver variants that work
  with the 'FormalShell' text in ASCII (or a customizable ASCII) just like
  Omarchy."*

**The re-aim.** `docs/DESIGN.md` today makes mek.gallery the *base* language.
The owner has inverted that: **omarchy quattro is the close reference for the
whole system; mek.gallery is a deliberate accent on top — "a classic ASCII
style OS"; everything monospace.** DMS contributes feature ideas, not looks.

**On attribution.** The owner's instruction is that we are *reimplementing*,
so no attribution headers are needed. That holds precisely because we
reimplement: read omarchy, understand the system, write our own QML. **Do not
copy omarchy files verbatim** — that would be a substantial portion under its
MIT licence and would need its notice. The existing DankMaterialShell
attribution rule in `CLAUDE.md` is unaffected and still applies to real ports.

## Reference facts already established (do not re-derive)

Read from `basecamp/omarchy@quattro` by the orchestrating session:

- `shell/Commons/Style.qml`: `cornerRadius: 0` and `fontFamily: "monospace"`
  are the defaults — omarchy is already a radius-0 monospace system.
  `gapsOut: 5` (half of Hyprland's `gaps_out`) is the panel-to-screen-edge gap.
- **State token vocabulary** — `normal`, `hover-cursor` (mouse hover OR panel
  keyboard cursor), `selected` (persistent current), `focus` (real
  `activeFocus`, defaulting to hover-cursor). Each state carries a colour token
  plus **separate fill and border alphas**. Colour tokens are palette roles
  (`foreground`, `accent`, `urgent`, `background`) or raw hex. A state's border
  width of 0 drops that border.
- **Sizing derives from a rem root**: `fontBaseSize: 12`, `fontScale =
  fontBaseSize / 12`, every font token a multiplier (`caption` 0.833,
  `bodySmall` 0.917, `body` 1.0, `subtitle` 1.083, …). A `spacingScale` (which
  by default tracks the font scale) multiplies a full spacing set: `xxs` 2,
  `xs` 3, `sm` 4, `md` 6, `lg` 8, `xl` 10, `xxl` 12, `xxxl` 14, `huge` 18, plus
  semantic tokens (`controlGap` 8, `controlPaddingX` 10, `controlPaddingY` 6,
  `inputPaddingY` 7, `controlHeight` 28, `popupRowHeight` 28, `rowGap` 8,
  `rowPaddingX` 12, `labelGap` 4, `panelGap` 14, `panelPadding` 18,
  `popupPadding` 14).
- `shell/Commons/Border.qml`: border **specs** carry colour + optional gradient
  + **per-side widths**, so a renderer picks a cheap `Rectangle` or a
  `Shape` ring without duplicating theme parsing.
- `shell/plugins/lock/LockView.qml`: blurred wallpaper (`MultiEffect`
  `blur 1.0`, `blurMax 128`, `blurMultiplier 1.25`, `contrast -0.08`); one
  centred field 381×67 with a 3px outline; centred placeholder; `●` U+25CF
  masking with letter-spacing that **shrinks to fit** so long passwords never
  clip silently; "Checking…" during auth; italic error message **and** an error
  border spec; a fingerprint glyph pinned inside the right edge when enrolled,
  with symmetric horizontal reserve so centred dots stay centred; wake on
  click/move/key; Escape or Ctrl+U clears. **Omarchy has no clock — we keep
  ours.**
- `bin/omarchy-screensaver`: `tte -i ~/.config/omarchy/branding/screensaver.txt
  --frame-rate 120 --anchor-canvas c --anchor-text c --random-effect` in a
  loop, exiting on any keypress or focus loss. `logo.txt` is heavy
  block-drawing characters (`▄ █ ▀`). `omarchy-branding-screensaver` lets the
  user replace the art.

## Plan-wide constraints

- `CLAUDE.md` hard rules still bind: radius 0, no blur (lock backdrop the one
  exception), no shadows, monospace via the fontconfig alias — **never a
  hardcoded family**, Nerd Font glyphs only, opaque compositor ids, shell never
  writes `settings.json`.
- ⚠️ Quickshell percentage/fraction properties are 0..1, not 0..100. This has
  shipped as a bug twice.
- ⚠️ A bare `State` identifier collides with QtQuick's built-in `State` — import
  `qs.Core as Core`.
- ⚠️ Never reintroduce `ScreencopyView` (fatal dmabuf protocol violation).
- ⚠️ Files with Nerd Font glyphs or block-drawing characters: targeted `Edit`
  only, verify bytes afterwards.
- Smoke script changes additive only — the g815 runs `dev/smoke-niri.sh`
  unchanged and that is a live requirement.
- **Every retrofit task must screenshot before and after and Read both**, and
  state what changed visually. "It still renders" is not evidence of a
  retrofit.

---

### Task 1: Design research + rewrite `docs/DESIGN.md`

**Files:** rewrite `docs/DESIGN.md`; update the design-language line in
`CLAUDE.md` if its summary no longer matches.

Read omarchy quattro's shell broadly — at minimum `shell/Commons/{Style,Color,Border}.qml`,
`shell/Ui/{Panel,BarWidget,Button,TextField,PanelSectionHeader,PopupCard}.qml`,
`shell/plugins/bar/Bar.qml`, a couple of `shell/plugins/panels/*`, and
`shell/plugins/lock/LockView.qml`. Use the GitHub API (`gh api
"repos/basecamp/omarchy/contents/<path>?ref=quattro" --jq '.content' | base64 -d`)
— a full clone timed out in this environment. Then look at mek.gallery's
described "classic ASCII style OS" character and at DMS only for feature ideas.

**Produce a rewritten `docs/DESIGN.md`** that is *the* north star:
1. States the new hierarchy explicitly — omarchy quattro close for the whole
   system, mek.gallery as an ASCII-OS accent, monospace throughout, DMS for
   features not looks.
2. Specifies the **token system** we will adopt: the four-state vocabulary with
   fill/border alphas, per-side border specs, the rem-root font scale and
   spacing scale with concrete default values, palette roles.
3. Says concretely what the "classic ASCII OS" accent means in practice —
   box-drawing/ruled character structure, uppercase meta labels, ASCII
   ornament, terminal-grid feel — with rules an implementer can check, not
   adjectives. Where it conflicts with omarchy's look, say which wins.
4. Keeps a **Concrete translations** section covering every surface the shell
   now has: bar, menu, six panels, notifications, OSD, lock, greeter,
   screensaver, picker.
5. Is honest about what changes from the current document, in a short
   "what this supersedes" note, so the M1–M3 retrofit has a checklist.

**Steps:** research → rewrite → self-check that every rule is *checkable* (a
reviewer could tell pass/fail from a screenshot or a grep) → commit
`docs(design): re-aim the design language at omarchy quattro with an ascii-os accent`; push.

---

### Task 2: Theme token system

**Files:** modify `shell/Core/Theme.qml`, `shell/Theme/palette.js`,
`tests/tst_palette.qml`; add `tests/tst_theme_tokens.qml`.

Implement the token system Task 1 specifies: the four interactive states with
separate fill and border alphas, border specs carrying per-side widths, a font
scale derived from a configurable base size, a spacing scale with the semantic
tokens. Keep matugen wiring and the existing Flexoki fallback working. Pure
token maths goes in a `.pragma library` with tests first, per the established
pattern.

Backwards compatibility is **not** required — but every existing surface must
still build and render, so update call sites in the same task where a token is
renamed.

**Steps:** red → implement → green (`just test`) → `just vm-smoke` and
`just vm-smoke --wallpaper` → Read both PNGs and confirm nothing regressed
visually → commit `feat(theme): omarchy-derived state tokens, border specs, and scale roots`; push.

---

### Task 3: Bar retrofit (the M1–M3 surfaces)

**Files:** modify `shell/Surfaces/Bar/Bar.qml`,
`shell/Surfaces/Bar/widgets/*.qml`, `shell/Components/Cell.qml`,
`shell/Components/MetaLabel.qml`.

Retrofit the bar, workspaces and active-window cells — the surfaces that
predate the design language — onto the new tokens and the new look. This is the
retrofit DESIGN.md has deferred since M4; it is now in scope and scheduled.

**Steps:** screenshot BEFORE → implement → `just vm-smoke` and
`just vm-smoke --panel audio` → Read the PNGs → state what changed against the
before shot → commit `feat(bar): retrofit bar and workspace cells to the revised language`; push.

---

### Task 4: Menu + panels retrofit

**Files:** modify `shell/Surfaces/Menu/*.qml`, `shell/Components/Panel.qml`,
`shell/Surfaces/Panels/*.qml`.

**Steps:** screenshot before → implement → `just vm-smoke --menu`, and
`--panel` for audio, network, calendar and power → Read every PNG → commit
`feat(panels): retrofit menu and panels to the revised language`; push.

---

### Task 5: Notifications + OSD retrofit

**Files:** modify `shell/Surfaces/Notifications/*.qml`,
`shell/Surfaces/Osd/Osd.qml`.

**Steps:** screenshot before → implement → `just vm-smoke --notify`,
`--notify --center`, `--osd` → Read every PNG → commit
`feat(notifications,osd): retrofit to the revised language`; push.

---

### Task 6: Lock + greeter craft pass

**Files:** modify `shell/Surfaces/Lock/LockSurface.qml`, `greeter/greeter.qml`,
and factor the shared composition into one component both use.

**The brief is quality.** The owner called the current lock screen *"too
average"*: an oversized mono clock, a thin-underlined input, three loose
stacked items. It must read as designed.

1. **One composed centre block** — clock, date and field in a single
   deliberate composition on one alignment spine, not three floating items.
   State the compositional idea in a comment; it must be visible in the shot.
2. **Typographic ambition on the clock** — the display slot, genuinely large,
   deliberate letter-spacing, tabular figures so digits do not jitter.
3. **The field gains real mass** and every omarchy interaction detail from the
   reference facts above: centred uppercase placeholder, `●` masking with
   letter-spacing, **shrink-to-fit dots**, `CHECKING…`, an error state that
   changes both message and border, fingerprint glyph with symmetric reserve,
   wake-on-any-input, Escape/Ctrl+U to clear. Adapted to our language: radius
   0, our border widths.
4. **Backdrop shaping** — match omarchy's blur parameters including the slight
   negative contrast so the composition reads against the wallpaper.
5. The greeter is the twin: shared component, identical language.

**Steps:** implement → `just vm-smoke --lock` → Read the PNG → **iterate at
least twice more**, each round stating what specifically looked wrong
(proportion, scale, spacing, alignment, contrast) and what changed. A single
pass that stops at "it renders" fails this task. Capture the failed-auth state
and the greeter too, and Read them. → commit
`feat(lock,greeter): composed lock treatment with omarchy-grade input craft`; push.

---

### Task 7: Screensaver — ASCII banner + multiple effects

**Files:** create `branding/screensaver.txt`; modify
`shell/Screensaver/effect.js`, `tests/tst_screensaver_effect.qml`,
`shell/Surfaces/Screensaver/Screensaver.qml`, `shell/Core/Config.qml`,
`nix/package.nix`.

**Produces:**
- A bundled banner spelling **FormalShell** in heavy block-drawing characters
  (`▄ █ ▀`), the same family as omarchy's `logo.txt` — the owner chose this
  style explicitly. Verify it renders without tofu at the sizes used.
- `screensaver.asciiPath` in `settings.json` pointing at any text file,
  defaulting to the bundled one — our equivalent of omarchy's branding command.
- The banner is **the subject**, centred. The current bannerless full-screen
  rain is not what was asked for.
- **At least five distinct effects** animating the banner, each a pure stepping
  function in `effect.js` with tests: `decrypt` (scramble resolving to the
  banner), `rain` (the existing matrix rain, restructured so glyphs **settle
  into** the banner), `expand` (opens from the centre), `slide` (rows/columns
  from alternating edges), `scatter` (cells fly in from random positions).
- `screensaver.effect` accepts a name or `"random"` (**the default**, matching
  omarchy's `--random-effect`); each activation picks fresh so a long idle
  cycles variants. An unknown name falls back to random and says so honestly.
- Tests per effect: determinism for a given frame counter, bounds, and
  **convergence** — every effect must actually reach the finished banner.

**Steps:** red → implement → green → `just vm-smoke --screensaver` **once per
effect** with the effect pinned, **Read all five PNGs** and describe what
distinguishes each. Two effects whose screenshots are indistinguishable are not
two effects. → prove `screensaver.asciiPath` swaps the art → commit
`feat(screensaver): block-ascii banner with five selectable effects`; push.

---

### Task 8: Docs + screenshots

**Files:** modify `README.md`, `docs/ARCHITECTURE.md`, `CLAUDE.md`; refresh
**every** `docs/screenshots/*.png`.

Every published screenshot predates the retrofit and is now misleading.
Recapture all of them, Read each before publishing, and update captions.
README gains the screensaver effect list, how to pin or randomise, and how to
replace the banner art.

**Steps:** verify every documented command by running it → commit
`docs: refresh for the revised design language`; push.
