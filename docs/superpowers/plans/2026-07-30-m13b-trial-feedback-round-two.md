# FormalShell M13b: e1504g trial feedback, round two

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. M13
> (`2026-07-30-m13-trial-feedback-fixes.md`) landed immediately before this
> plan; its task notes are context for every file touched here.

**Origin, owner ask (2026-07-30, continued daily-drive):** the apps list
shows app IDs and no icons; there is no way to toggle notifications from the
bar; theme mode toggle appears to do nothing; nix run gives no feedback
("there's no state to check it"); and the screensaver should keep cycling:
"a few seconds after the effect finishes, another random effect must happen.
The screen saver animates indefinitely until the laptop sleeps."

**Host diagnosis already done, do not re-derive:**

- Theme toggle: the live host reports `theme status` ->
  `{"wallpaper":"","mode":"dark","themeJsonPresent":true}`. Mode flips but
  matugen only runs with a wallpaper set, and the seeded fallback theme.json
  is static dark, so nothing visibly changes. The fix is a working
  no-wallpaper path, not a keybind fix.
- Apps rows: `providers.js` `appsProvider` already maps `label: entry.name`
  and `icon: entry.icon`, yet the owner sees IDs and nothing in the icon
  slot. The icon slot renders TEXT (glyphs/emoji); an icon-theme name like
  `firefox` draws nothing there. Why the label degrades to an ID on the host
  must be diagnosed on the VM, not assumed.
- Nix runner: works, but the first `nix search` on a real host spends tens
  of seconds on evaluation caches with zero in-flight feedback, and Enter
  gives no visible launch acknowledgment.
- Notifications: the indicators slot only shows a bell-off glyph while DND
  is already on; there is no bar affordance to open the center or flip DND.
- Screensaver: converges once and freezes (`Screensaver.qml` +
  `effect.js`, untouched since M11 apart from the M12 recorder verbs).

## Constraints

- Same as M13: `CLAUDE.md` (as amended) binds, DESIGN.md is the authority,
  verification ONLY on the VM rig, never ssh to e1504g/g815, additive smoke
  changes, one conventional commit per task, tree clean, no push,
  glyph/emoji files by targeted Edit only.
- M13 landed motion tokens (`Theme.motion`), `menu status`/`activate(index)`
  verbs, the shell-wide `//@ pragma UseQApplication`, and
  `NotificationService.notify(summary, body)`; build on those, do not
  duplicate them.

---

### Task 1: Launcher rows: real names + icon images

**Files:** modify `shell/Menu/providers.js`, `shell/Surfaces/Menu/MenuRow.qml`,
`shell/Surfaces/Menu/Menu.qml` if the display path needs it, `docs/DESIGN.md`
(one amendment line), `nix/testvm.nix` (fixture app if the VM lacks a
desktop entry with a real icon), `dev/smoke-niri.sh`, `tests/` sibling.

**Produces:**
1. Diagnosis first: reproduce the IDs-instead-of-names symptom against real
   desktop entries in the VM and record the actual cause in the commit
   (candidates: empty `entry.name` fields, a display path preferring
   `node.id`, or DesktopEntries returning entries whose name IS the id).
   Fix so rows always render the entry's display name, falling back to the
   id only when the name is genuinely empty.
2. Icon images: `MenuRow` gains an image variant of its icon slot; app rows
   resolve `entry.icon` through Quickshell's icon lookup (read the pinned
   source for the API, `Quickshell.iconPath` or equivalent, including its
   fallback argument) and render the themed icon at the glyph cell's size,
   radius 0, no border. Rows whose icon fails lookup fall back to the
   existing glyph slot, never a broken-image box.
3. DESIGN.md amendment: launcher app rows are the sanctioned image-icon
   exception (desktop icon themes, like DMS/omarchy launchers); everything
   else stays Nerd Font glyphs.

**Verify:** `just vm-test` green (provider row shape); `--menu` drive gains
an apps-query assertion returning a display-name label; screenshot read
showing an app row with a real icon image (add a small fixture .desktop +
icon via testvm if needed, honestly installed, not faked). Commit.

### Task 2: Notification bell bar widget

**Files:** create `shell/Surfaces/Bar/widgets/BellWidget.qml`; modify
`shell/Bar/layout.js` (DEFAULT_LAYOUT right region gains `bell` before
`indicators` — an owner-requested default change, update every
"exact default arrangement" expectation honestly: tests, smoke comments,
docs in Task 6), `shell/Surfaces/Bar/Bar.qml`, `tests/tst_bar_layout.qml`,
`dev/smoke-niri.sh`.

**Produces:**
1. Always-visible bell cell: bell glyph (pinned nerd-font cmap, verify the
   codepoint), pending-count meta label (`N`) when
   NotificationService.pending is non-empty, bell-off glyph while DND is on.
2. Left click toggles the notification center (the same surface
   `notifications showHistory` drives), with the panel-open accent dot
   idiom while the center is open. Right click toggles DND (the existing
   single DND state machine via the service, no second one).
3. The indicators widget keeps idle-inhibit but drops its now-redundant
   DND-only bell display IF that leaves it coherent; otherwise leave it and
   note the overlap in the file header.

**Verify:** `just vm-test` green (layout default updated); `--notify` and
`--center` smoke legs updated: default bar screenshot shows the bell cell,
the `--center` run asserts the count meta appears with pending
notifications and that a `tray`-style IPC-driven click stand-in (or the
existing `notifications` verbs) toggles the center. Commit.

### Task 3: Theme mode toggle without a wallpaper

**Files:** modify `shell/Theme/ThemeEngine.qml`, `shell/Theme/` fallback
palette data (Flexoki light sibling of the existing dark fallback),
`tests/` sibling, `dev/smoke-niri.sh`.

**Produces:**
1. With no wallpaper set, `theme mode toggle` (and `theme mode <m>`) writes
   the bundled Flexoki fallback palette for the requested mode to the same
   state-dir theme.json matugen would write, through the same
   serialized-write queue, so every consumer recolors live via the exact
   pipeline a matugen run uses. One code path, no special fallback branch in
   Theme.qml.
2. With a wallpaper set, behaviour is unchanged (matugen runs, `--prefer`
   matched to mode).
3. The seeded first-boot theme.json stays the dark variant.

**Verify:** in the VM with no wallpaper driven: screenshot before toggle
(dark bar), `theme mode toggle`, `theme status` shows `mode:"light"`,
screenshot read visibly light (both PNGs read and described); toggle back;
then `just vm-smoke --wallpaper` still green (matugen path untouched).
`just vm-test` green. Commit.

### Task 4: Nix runner in-flight and launch feedback

**Files:** modify `shell/Menu/providers.js`, `shell/Surfaces/Menu/Menu.qml`
(in-flight state), `dev/smoke-niri.sh` (blocking-shim leg), `tests/`
sibling.

**Produces:**
1. While a `:nix` search is in flight: one dim `SEARCHING` note row
   (non-activatable). Distinct honest end states: results, `NO RESULTS`
   (clean zero-hit exit), `SEARCH FAILED` (nonzero exit or unparseable
   stdout), `NO NIX` (missing binary, as today).
2. Enter on a result fires
   `NotificationService.notify("NIX RUN", "<attr>")` alongside the existing
   terminal spawn, so launches are visible even if the terminal is slow to
   map.
3. State is queryable: the existing `menu` debug query path exposes the
   note rows, so the rig can assert each state.

**Verify:** `just vm-test` green (state machine unit-covered); `--menu`
extended with a gated shim (blocks on a flag file): assert `SEARCHING` row
while blocked, release, assert canned rows; a failing shim asserts
`SEARCH FAILED`; activate a row and assert the NIX RUN toast in a
screenshot read. Commit.

### Task 5: Screensaver continuous effect cycling

**Files:** modify `shell/Surfaces/Screensaver/Screensaver.qml`,
`shell/Screensaver/effect.js` only if the reroll needs a helper,
`shell/Core/Config.qml` (document the key), `dev/smoke-niri.sh`, `tests/`
sibling.

**Produces:**
1. After an effect converges, hold the banner `screensaver.holdSeconds`
   (default 6), then reroll and animate again, indefinitely:
   `screensaver.effect: "random"` picks a fresh random effect each cycle
   (never the immediately previous one when more than one effect exists); a
   pinned effect replays with a fresh activation seed. Loop runs until the
   screensaver stops; it takes no idle inhibitor, so system suspend fires
   exactly as today.
2. The M11 frame-stepping recorder contract holds: while `frame(n)` has the
   surface pinned, cycling is suspended and resumes when released;
   `--screensaver-gif` must keep recording single, deterministic effects.
3. `screensaver frameInfo` (or `status`) gains a `cycles` counter so the
   rig can observe cycling without screenshots.

**Verify:** `just vm-test` green (reroll logic unit-covered:
no-immediate-repeat, pinned-effect fresh seed); `--screensaver` extended:
shortened `holdSeconds` via the settings fixture, wait past convergence +
hold, assert `cycles` incremented and the reported effect changed with no
IPC nudge; `--screensaver-gif` for ONE effect still records
deterministically (do not regenerate the committed GIFs). Commit.

### Task 6: Docs sweep

**Files:** `README.md`, `docs/USAGE.md`, `docs/SWITCHOVER.md`, recaptures
for surfaces that changed (default bar with the bell cell, an app row with
icon, light-mode toggle pair if worth publishing).

**Produces:** USAGE covers the bell widget (default layout change called
out), launcher icon behaviour, no-wallpaper theme toggle, nix runner
states, `screensaver.holdSeconds` + cycling + the `cycles` field.
SWITCHOVER: M13b paragraph, amended rows, host-trial items (real icon
themes on the host, real nix search timing, cycling wall-clock feel).

**Verify:** heading rg checks, recaptured PNGs read, `just vm-test` +
`just vm-smoke` green at HEAD. Commit.
