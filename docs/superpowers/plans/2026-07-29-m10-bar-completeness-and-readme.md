# FormalShell M10: Bar completeness + README restructure

> **For agentic workers:** Workflow-driven per `docs/superpowers/workflow-template.md`.
> Read `CLAUDE.md` and `docs/DESIGN.md` first, both binding.

**Why this exists.** M9's final review found that three items the spec puts in
v1 scope were never built, and `docs/SWITCHOVER.md` had claimed no feature gap
existed. Spec §Surfaces-1, verbatim:

> **Bar** — three regions (left/center/right), top-layer. Widgets:
> workspaces, active window, **SNI tray (grouped drawer)**, **indicators slot
> (DND, idle-inhibit, recording…)**, clock, battery, audio, network/BT
> glyphs, now-playing. **Custom user modules in settings: `command` type
> (Waybar-JSON-compatible `{text, tooltip, class}`, polled) and `qml` type.**
> Panel-open accent dot on the owning widget (Omarchy detail).

Confirmed absent on 2026-07-29: `rg -il "systemtray|statusnotifier" shell/`
returns nothing, there is no indicators slot, and `settings.json` has no
widget-layout or custom-module keys. The bar has nine working widgets but a
user cannot reorder it, add their own, or receive tray icons.

Second ask, from the owner: the README is 930 lines and reads as a reference
manual rather than a product README. Its Screenshots section alone spans 156
lines for 12 images, each with a paragraph of prose. The owner wants a proper
product README with the screenshots in a table.

## Plan-wide constraints

- `CLAUDE.md` hard rules bind: radius 0, no blur outside the lock backdrop, no
  shadows, monospace via the fontconfig alias, Nerd Font glyphs only, opaque
  compositor ids, the shell never writes `settings.json`.
- `docs/DESIGN.md` (rewritten in M8b: omarchy quattro close reference,
  mek.gallery ASCII-OS accent) is the binding design authority. New bar
  widgets use the `standalone` `Cell` mode the other bar widgets use, and
  carry the panel-open accent dot where they own a panel.
- **No feature may be removed or narrowed.** Matugen stays load-bearing.
- ⚠️ Quickshell percentage/fraction properties are 0..1, not 0..100. Shipped
  as a bug twice, caught both times only on real hardware.
- ⚠️ A bare `State` identifier collides with QtQuick's `State`; import
  `qs.Core as Core`.
- ⚠️ Files carrying Nerd Font glyphs: targeted `Edit` only, verify bytes.
- Regression gate every task: `just test` green, `just vm-smoke --wallpaper`
  still recolours, and the smoke modes covering touched surfaces still pass.

---

### Task 1: SNI tray with grouped drawer

**Files:** create `shell/Surfaces/Bar/widgets/Tray.qml`; modify
`shell/Surfaces/Bar/Bar.qml`, `shell/shell.qml`, `nix/testvm.nix`,
`dev/smoke-niri.sh`.

**Produces:** a tray widget on `Quickshell.Services.SystemTray`. **Read that
module's qmltypes and C++ source before writing** — it has never been used in
this project. Icons render as bar cells in the right region; the spec's
"grouped drawer" means overflow collapses into a single cell that expands,
rather than an unbounded row. Left click activates, right click opens the
item's `DBusMenu` context menu (`Quickshell.DBusMenu` is available). Honest
empty state: with no tray items the widget is absent entirely, not an empty
box.

**VM enablement:** the test VM has no tray producers. Add something that
genuinely registers a StatusNotifierItem so the widget has real items to show.
Verify what is available in the pinned nixpkgs rather than assuming; if
nothing suitable exists, a minimal Python/GLib SNI stub committed under
`dev/` is acceptable, but it must register a real item on the session bus, not
be faked inside the shell.

**Steps:** implement → add a `--tray` smoke mode → `just vm-smoke --tray` →
Read the PNG: real tray items as cells, and the drawer expanding → `just test`
+ `just vm-lint` → commit `feat(bar): sni tray widget with grouped drawer`; push.

---

### Task 2: Indicators slot

**Files:** create `shell/Surfaces/Bar/widgets/Indicators.qml`; modify
`Bar.qml`, `shell/shell.qml`, `dev/smoke-niri.sh`.

**Produces:** a compact slot showing transient session state, each indicator a
glyph that appears only while its condition holds:
- **DND**, from the existing `NotificationService` DND state.
- **Idle inhibit**, from the existing `IdleService` / `IdleInhibitor` wiring.
- **Recording**, if and only if a real source of truth exists. Check whether
  anything in the shell or a reachable service actually reports screen
  recording. If nothing does, **do not invent one**: implement DND and
  idle-inhibit, and record in the docs that recording awaits a real source.
  DESIGN.md's breathing pulse is the sanctioned idiom for an active recording
  state when it does arrive.

Reuse existing services. Do not add a second DND state machine.

**Steps:** implement → extend the smoke to toggle DND over the existing
`notifications` IPC and screenshot the indicator appearing → Read the PNG →
commit `feat(bar): indicators slot for dnd and idle inhibit`; push.

---

### Task 3: Settings-driven bar layout + custom modules

**Files:** create `shell/Bar/layout.js`, `tests/tst_bar_layout.qml`,
`shell/Surfaces/Bar/widgets/CommandModule.qml`,
`shell/Surfaces/Bar/widgets/QmlModule.qml`; modify `Bar.qml`,
`shell/Core/Config.qml`, `dev/smoke-niri.sh`.

**Produces:**
1. **Layout from settings.** `bar.layout` in `settings.json` names which
   widgets sit in `left`, `center` and `right`, in order. Unknown names are
   skipped with an honest warning rather than crashing. Absent config falls
   back to exactly today's arrangement, so an existing user sees no change.
   `layout.js` is a `.pragma library` with tests written FIRST: resolution
   order, unknown-name handling, empty regions, and the default fallback.
2. **`command` modules**, Waybar-JSON-compatible: run a command on an interval,
   parse `{text, tooltip, class}`, render `text` in a bar cell. A non-zero
   exit, malformed JSON or a timeout renders an honest error state rather than
   a stale value. The poll interval is per-module and defaulted.
3. **`qml` modules**: load a user-supplied QML file into a bar cell via
   `Loader`, isolated so a broken user file cannot take down the bar. Verify
   what `Loader` actually guarantees here and state the real isolation limit
   in the docs rather than overclaiming.

**Steps:** red → implement → green → smoke with a fixture `settings.json`
carrying a reordered layout, a `command` module printing known JSON, and a
tiny `qml` module → Read the PNG showing all three → prove the no-config
fallback still renders today's bar → commit
`feat(bar): settings-driven layout with command and qml modules`; push.

---

### Task 4: README restructure

**Files:** rewrite `README.md`; create `docs/USAGE.md`.

The README is 930 lines. Make it a **product README** someone can read in two
minutes:

1. **Top:** what FormalShell is, in two or three sentences. A single hero
   screenshot. Badges only if they are real.
2. **Screenshots as a table**, not twelve full-width images with paragraph
   captions. A grid (markdown table of thumbnails, two or three per row) with
   a short label per cell and the host it came from. This is the owner's
   specific ask: the current section is 156 lines and dominates the file.
3. **Features**, as a scannable list rather than a section per surface.
4. **Install**, kept in the README since it is what a new user needs: the two
   NixOS modules, the home-manager module, the minimal flake.
5. **Everything else moves to `docs/USAGE.md`**: the per-surface reference for
   menu, notifications, OSD, panels, clipboard, calendar, now playing, lock,
   screensaver, picker, currently roughly 500 lines. Link to it prominently.
   Do not delete content, relocate it.
6. Keep the dev-loop section short and link to `CLAUDE.md`.

**Every command that survives into either file must still be correct.** Verify
the ones that are safe to run on the mac.

**Steps:** restructure → verify links and images resolve (`rg -o
'\]\([^)]*\)' README.md` and check each path exists) → commit
`docs: restructure readme as a product readme with a screenshot table`; push.

---

### Task 5: Docs, screenshots, and closing the gap in the report

**Files:** modify `docs/SWITCHOVER.md`, `docs/ARCHITECTURE.md`,
`CLAUDE.md`, `README.md`/`docs/USAGE.md`; add screenshots for the new bar
features.

1. Capture the new surfaces (tray, indicators, a custom module) and **Read**
   them before publishing. Add them to the README table.
2. `docs/SWITCHOVER.md`: the §Surfaces-1 gap this milestone closes must move
   out of the gap list, with the tray, indicators and layout rows added to the
   parity table at their honest verification level (VM-only unless a Linux
   host was used).
3. `docs/ARCHITECTURE.md`: the bar layout resolution flow and the custom
   module lifecycle.
4. `CLAUDE.md`: the new smoke modes.

**Steps:** verify every documented command → commit
`docs: tray, indicators, bar layout, and the closed surfaces-1 gap`; push.

---

## Then

The remaining v1 gaps are environmental, not code: the greeter has never run
against real greetd on hardware, the lock screen's PAM paths need
`nixosModules.formalshell` installed on a real host, the Hyprland backend has
never been verified on real hardware, and the weather panel was not covered by
the g815 sweep. All four need a host the owner has switched over, which is the
gate `docs/SWITCHOVER.md` describes and the owner's decision to make.
