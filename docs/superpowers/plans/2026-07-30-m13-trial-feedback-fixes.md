# FormalShell M13: e1504g trial feedback fixes

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding.

**Origin, owner ask (2026-07-30, first hours of the real e1504g daily-drive
trial):** workspaces render out of order and empty ones don't hide; tray
items ignore left and right click and their icons sit high; the github
widget should open a list panel like DMS's, not the website; there is no
animation anywhere ("I want it to be fast and subtle, it should just look
better"); no way to pick a wallpaper ("you can integrate it into the
spotlight thing"); clicking a calendar day doesn't show that day's events;
the emoji picker should instantly paste as well as copy; win+shift+s shows
no DMS/omarchy-style screenshot UI.

**Host diagnosis already done, do not re-derive:**

- win+space was a keybind arity bug, not a shell bug: `MenuIpc.summon(route)`
  has a mandatory argument and the nix-side bind passed none. Fixed in the
  owner's nix config (`menu summon ""`), commit `e570df16` there. Shell-side
  hardening still wanted: see Task 5.
- win+shift+s DID spawn the capture pipeline: a bare `slurp` sat running for
  over an hour on the host with no dim and no frame (invisible until you
  drag), which reads as "nothing happened". Killing it cleared the state
  honestly (`screenshot status` -> `capturing:false, lastError:"capture
  exited 143"`), so the lifecycle works; what is missing is a visible
  overlay, a watchdog, and a cancel path: see Task 7.
- The shell logs six identical startup warnings for the absent optional
  `~/.config/formalshell/menu.jsonc`; quiet to at most one: see Task 5.
- Host context that shapes Task 1: the owner's niri config declares nine
  persistent named workspaces ("1".."9", glyph + EM SPACE + word labels), so
  all nine always exist compositor-side; DMS hid the empty ones
  (showOccupiedWorkspacesOnly) and ordered by index.

## Constraints

- `CLAUDE.md` hard rules bind (as amended by the M12 spec addendum).
  `docs/DESIGN.md` is the design authority; Task 8 extends it with a motion
  section rather than working around it.
- Verification stays on the mac VM rig (`just vm-test`, `just vm-smoke
  [flags]`, `just vm-lint`, `dev/vm.sh run`). e1504g is the owner's live
  session mid-trial: do NOT ssh to it, do not fire IPC at it. Anything only
  a real host can prove (region drag, real tray menus of real apps, GOA)
  gets recorded as host-trial territory in SWITCHOVER, not faked.
- Quickshell API ground truth is the pinned source (`git.outfoxxed.me`
  checkout in the nix store), not memory: tray activation and menu display
  (`SystemTrayItem`, `QsMenuAnchor`/`QsMenuOpener`) must be read from C++
  before use.
- Existing smoke modes must keep passing; smoke changes additive only.
- Every task: verification run, output/screenshot actually read, one
  conventional commit, clean tree, no push.
- ⚠️ Glyph-bearing files and `emoji.json`: targeted Edit only.

---

### Task 1: Workspaces order + hide empty

**Files:** modify `shell/Surfaces/Bar/widgets/Workspaces.qml`,
`shell/Compositor/*` only if occupancy is not already derivable,
`tests/` sibling, `dev/smoke-niri.sh` only if an assertion is added.

**Produces:**
1. Workspace cells sorted by the backend's numeric position on that output
   (`idx`; ids stay opaque strings per the hard rule, idx is niri's own
   ordinal field, not a parsed id).
2. Empty workspaces hidden: a workspace renders only if it has at least one
   window OR is focused/active. Occupancy comes from
   `CompositorService.windows` (count by workspace id) or the backend's own
   field if one exists; verify against the niri IPC schema in the pinned
   source, then mirror for Hyprland.
3. The nested-niri smoke session has one workspace with a window and niri
   auto-creates a trailing empty one: the bar must show exactly the occupied
   or focused ones, which the existing plain-smoke screenshot already
   captures (read it and confirm the workspace region).

**Verify:** `just vm-test` green (new sort/hide unit coverage over a fake
workspace+window model); `just vm-smoke` PNG read. Commit.

### Task 2: Tray clicks, menus, and centering

**Files:** modify `shell/Surfaces/Bar/widgets/Tray.qml`; read quickshell's
`src/services/status_notifier/*` and `src/dbus/dbusmenu/*` first.

**Produces:**
1. Icon cells vertically centered (same class of fix as commit `8d01eb4`,
   anchors inside the cell content).
2. Left click -> `activate()`; middle click -> `secondaryActivate()`; right
   click -> the item's DBusMenu rendered via quickshell's menu machinery
   (`QsMenuAnchor` or the platform menu path, whichever the pinned source
   supports for layer-shell windows), anchored under the cell. Items whose
   `onlyMenu`/`isMenu` flag says activate-is-menu open the menu on left
   click too.
3. Menu styling follows the shell where the API allows; if QsMenuAnchor
   renders a native-styled popup, accept it and note the limitation in the
   file header rather than half-building a custom renderer.

**Verify:** `just vm-smoke --tray` still passes (collapsed + expanded
states); extend the tray drive to call `activate` on a stub item over the
existing rig (dev/sni-stub.py already registers real SNI items; give the
stub an Activate handler that writes a file, assert the file). Menu OPEN
on a real click cannot be driven headlessly: assert via a `tray` IPC debug
verb or record as host-trial. `just vm-test` green. Commit.

### Task 3: GitHub panel

**Files:** create `shell/Surfaces/Panels/GithubPanel.qml`; modify
`shell/Surfaces/Bar/widgets/GithubWidget.qml`, `shell/Surfaces/Bar/Bar.qml`,
`shell/Ipc/PanelIpc.qml` (registry + name list), `shell.qml` (instantiate),
`dev/smoke-niri.sh` (extend the gh shim with a list payload + a `--panel
github` drive), `docs/` touched only by Task 9.

**Produces:**
1. The widget's poll extends its existing single `gh api graphql` call to
   also fetch titles/urls/repo names (first ~15 of each list); counts cell
   stays as is.
2. Click toggles a GithubPanel anchored under the cell (same
   Panel.qml/accent-dot idiom as every M6 widget) instead of xdg-open:
   ledger rows, uppercase meta section headers `PULL REQUESTS / n` and
   `ISSUES / n`, each row title + dimmed repo, click on a row spawns
   `xdg-open <url>` and closes the panel. Honest states inside the panel
   (`NO AUTH`, `NO GH`, empty lists render a dim `NONE` row).
3. `panel open github` works over IPC (registry entry), so the smoke rig can
   drive it.

**Verify:** `just vm-smoke --panel github` (new) with the extended gh shim:
screenshot read showing both sections with the canned rows; `--bar-layout`
still green. `just vm-test` green. Commit.

### Task 4: Calendar day selection

**Files:** modify `shell/Surfaces/Panels/CalendarPanel.qml`, smoke drive for
`--panel calendar`.

**Produces:**
1. Day cells clickable (hover-cursor state per DESIGN's control states);
   clicking selects that day, the events section lists the selected day's
   events via the existing `eventsOnDate`, and its meta header reads `TODAY`
   for today or the uppercase date (`JUL 31`) otherwise. Month navigation
   keeps selection sane (selecting resets to today on month change or clamps,
   pick one and document it in the file).
2. The selected cell gets the `selected` cell state (fg/bg inversion), the
   today cell keeps its existing accent marker; both visible at once when
   they differ.

**Verify:** extend the calendar drive: seed a second EDS fixture event on
tomorrow, then drive selection over IPC (a small `calendar` debug verb on
the panel's IPC surface, or reuse `panel open calendar` plus a new
`calendar select <iso-date>` verb, additive) and screenshot: tomorrow's
cell inverted, events list showing the tomorrow fixture under the dated
header. `just vm-test` green. Commit.

### Task 5: Wallpaper in the menu + summon hardening

**Files:** modify `shell/Menu/default-menu.jsonc`,
`shell/Ipc/MenuIpc.qml`, `shell/Surfaces/Menu/Menu.qml` (warn quieting),
`tests/` sibling.

**Produces:**
1. A root menu node `WALLPAPER` (picker glyph) whose activation spawns the
   self-targeting `qs ipc call picker summon` invocation
   (`clipboardProvider`'s exact pattern), closing the menu and opening the
   ImagePicker grid over `picker.directory`.
2. `MenuIpc` gains a no-argument `toggle()` verb (root summon if closed,
   close if open) so a keybind can never hit the mandatory-route arity trap
   again; `summon(route)` stays as is for compatibility.
3. The absent optional `menu.jsonc` logs at most one line per path change,
   not six.

**Verify:** `just vm-test` green; `just vm-smoke --menu` extended: `menu
toggle` opens (state via `menu` debug), and the root query for "wall"
returns the WALLPAPER row; `--picker` mode still green. Commit.

### Task 6: Emoji instant paste

**Files:** modify `shell/Menu/providers.js` (emoji action),
`shell/Surfaces/Menu/Menu.qml` if action plumbing needs a post-close hook,
`nix/package.nix` (add `wtype` to the wrapper PATH), `tests/` sibling.

**Produces:**
1. Picking an emoji copies it (wl-copy, as today) AND auto-types it into
   the previously focused window: close the menu first, then after a short
   settle delay (~150ms) run `wtype <char>`. One combined action path, not
   a race: the type step must run from a handler that fires after the menu
   surface actually closed.
2. `wtype` missing or the virtual-keyboard protocol absent: copy still
   happens, one console.warn, no error surface (honest degradation).

**Verify:** `just vm-test` green (action shape test updated); in the VM the
`--menu` mode gains an assertion that drives the emoji action end to end
inside the nested session with a focused `foot`/terminal fixture if the rig
supports it, otherwise: drive the action, assert wl-paste content AND that
wtype was invoked (PATH-shim wtype logging its argv, same shim pattern as
gh/nix), recording real typing as host-trial. Commit.

### Task 7: Screenshot region UX + watchdog

**Files:** modify `shell/Ipc/ScreenshotIpc.qml`, `dev/smoke-niri.sh`.

**Produces:**
1. Styled selection: slurp invoked with a dim background and themed
   selection border (`-d`, `-b`/`-c`/`-s` with Theme-derived hex values
   passed through the Process environment, matugen-current at call time),
   so pressing the bind visibly changes the screen immediately, omarchy
   style. Border weight matches `Theme.borderWidth`.
2. Watchdog: a region capture auto-cancels (kills the pipeline, clears
   state, fires a `SCREENSHOT CANCELLED` notification) after
   `screenshot.timeoutSeconds` (default 90). New `screenshot cancel` verb
   does the same on demand; `status` keeps reporting honestly.
3. Escape in slurp (exit 1) is a cancel, not an error toast.

**Verify:** `just vm-smoke --screenshot` extended: `screenshot region`
started then `screenshot cancel` called, status round-trips through
`capturing:true` -> cancelled with no stuck state, `full` still captures a
valid PNG afterward in the same session. Slurp's visual overlay itself is
host-trial (no synthetic drag exists), recorded as such. `just vm-test`
green. Commit.

### Task 8: Motion pass, fast and subtle

**Files:** modify `docs/DESIGN.md` (new Motion section), `shell/Core/Theme.qml`
(motion tokens), then the surfaces: `shell/Surfaces/Menu/Menu.qml`,
`shell/Components/Panel.qml`, `shell/Surfaces/Osd/Osd.qml`,
`shell/Surfaces/Notifications/Toasts.qml` + `Center.qml`,
`shell/Components/Cell.qml` (hover fill), `shell/Surfaces/Bar/widgets/Workspaces.qml`
(accent swap), `shell/Surfaces/Panels/CalendarPanel.qml` (month swap) as
applicable.

**Produces:**
1. DESIGN.md Motion section, written to the owner's brief ("fast and
   subtle, it should just look better"): durations 90-140ms, one standard
   ease-out curve, opacity plus small translate (4-8px) only, no scale, no
   bounce, no blur, radius stays 0; full-bleed accent/selection state
   swaps stay instant (ledger inversion is a state, not a transition);
   every animation must be interruptible.
2. Theme motion tokens (duration.fast/standard, the easing curve) and the
   surfaces above animating enter/exit and hover fills through them. No
   surface gains layout jump: animations are additive polish only.
3. `prefers-reduced-motion` has no Wayland analog here; a `motion.enabled`
   settings key (default true) short-circuits every duration to 0 instead.

**Verify:** `just vm-test` green; `just vm-lint` green; every existing
smoke mode re-run green with screenshots read (stills must be pixel-honest:
end states identical to before, only transitions added); pick two surfaces
(menu, OSD) and verify end-state screenshots match the prior captures.
Commit.

### Task 9: Docs + screenshots sweep

**Files:** `README.md`, `docs/USAGE.md`, `docs/SWITCHOVER.md`, recaptured
`docs/screenshots/*.png` where a surface changed.

**Produces:** USAGE covers the github panel, calendar day selection, menu
`toggle` verb, wallpaper menu entry, emoji paste behaviour (and its wtype
dependency), screenshot region styling/watchdog/cancel, motion tokens and
`motion.enabled`. SWITCHOVER: M13 update paragraph, parity rows amended
(tray interactions, github panel, workspaces behaviour), host-trial items
listed (region drag visual, real tray menus, real typing into a focused
app). Recapture: tray, bar-layout or plain bar (workspace region), calendar
(selected-day state), any panel whose chrome moved in Task 8.

**Verify:** heading rg checks, PNGs read, `just vm-test` + `just vm-smoke`
green at HEAD. Commit.
