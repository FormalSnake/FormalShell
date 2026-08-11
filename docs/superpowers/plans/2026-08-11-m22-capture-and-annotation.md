# FormalShell M22: shell-owned capture picker and annotation handoff

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. The spec wins over
> this plan on conflict.

**Origin, owner ask (2026-08-11):** "the latest omarchy quattro added a
really good screenshotting tool. I want it ported to FormalShell", then
"i saw omarchy has like annotation tools and everything, macos style",
then: build all three pieces below, package the editor in the flake, and
"do the same for the wifi QR, i dont have the package rn and it must be
FormalShell".

**Context.** Upstream's capture flow is two separable things, and only one
of them is omarchy's own code.

The picker is `bin/omarchy-capture-region` plus
`bin/omarchy-capture-screenshot`, driving `slurp` over a `hyprpicker -r -z`
screen freeze. Its August 2026 rewrite (PR #6466 and the follow-up "Reach
every window the region picker can highlight") added keyboard control while
the picker is open: `Return` captures the highlighted window, `Ctrl+Return`
the focused display, `Tab`/`Ctrl+Tab` cycle windows in reading order, arrows
move spatially. Overlapping windows resolve to the smallest rectangle
containing the cursor, matching how slurp itself highlights, and a target
whose center is covered by a smaller window is reached by probing eighth
fractions of its box for a point that resolves back to it.

None of that keyboard layer ports literally. It moves the selection by
**warping the cursor** (`hl.dispatch(hl.dsp.cursor.move)`) so slurp's own
hover highlight follows, and the keys are bound by Hyprland Lua reacting to
`layer.opened` on slurp's `selection` namespace
(`default/hypr/bindings/utilities.lua`). niri has neither a cursor-warp IPC
action nor dynamic layer-scoped binds, and the shell cannot inject binds
into either compositor at runtime. So the picker becomes FormalShell's own
Overlay surface, which owns its highlight state directly — no warping, no
compositor binds, one code path on both backends. `Menu.qml:988` already
establishes the mechanism (`WlrLayershell.keyboardFocus: Exclusive`).

The annotation editor is **Tensaku** (`tensaku.dev`, `jondkinney/tensaku`),
an external MPL-2.0 Rust/GTK4 fork of satty. Omarchy contributes no editor
code: `omarchy-capture-screenshot:19` reads
`OMARCHY_SCREENSHOT_EDITOR` (default `tensaku-edit`) and hands it the PNG,
and `omarchy-clipboard-open:33` does the same for clipboard image entries.
There is nothing to port — there is a dependency to package and a handoff to
wire. Tensaku is not in nixpkgs (checked 2026-08-11).

The WiFi QR gap is the same class of bug already shipped: `NetworkPanel.qml`
drives a real `qrencode` Process, but `nix/package.nix`'s wrapper PATH never
listed `qrencode`, so the feature can only work on a host that happens to
have it. Same for `nmcli`, which that panel and the whole network stack
already depend on.

## Constraints

- All CLAUDE.md hard rules stand: radius 0, no blur, border width 2,
  monospace, Nerd Font glyphs, opaque compositor ids, read-only
  `settings.json`, honest unavailable states, no compiled companion
  binary of our own.
- The picker is a **security-adjacent full-screen surface**. Like the lock
  screen it must fail open: any failure to build the freeze frame, resolve
  rectangles, or grab keyboard focus tears the surface down and reports,
  never leaves an undismissable overlay. Escape always closes it.
- No `ScreencopyView`. The freeze frame comes from `grim` to a file, per
  `LockSurface.qml`'s header (ScreencopyView crashes the shell outright).
- Tensaku is MPL-2.0, weak copyleft at file scope. It is packaged and
  invoked as a separate executable, never linked or vendored into shell
  source, so FormalShell stays MIT. The derivation records the license.
- macOS verification loop: `just vm-build` / `vm-test` / `vm-lint` /
  `just vm-smoke <flags>`; PNGs Read from `./artifacts/`.
- Commits conventional single-line, no body, no Co-Authored-By; never
  CLAUDE-*.md.

### Task 1: Close the runtime-dependency gaps in the wrapper PATH

- `nix/package.nix`: add `qrencode` and `networkmanager` (for `nmcli`) to
  the `--prefix PATH` `makeBinPath` list. Both are already hard runtime
  dependencies of shipped features — the WiFi QR share and the whole
  network panel — and neither was declared.
- Audit the rest of the same class in one pass before finishing: `rg -o
  '"[a-z][a-z0-9-]+"' shell/**/*.qml` filtered to argv position zero of
  every `Process.command`, compared against the wrapper list. Add what is
  genuinely missing, list in the commit message what was found. Do not add
  binaries only used by `dev/` scripts.
- Verify: `git add -A`; `just vm-build`; `just vm-smoke --panel network`
  and Read the PNG — the QR cell renders a real matrix, not `ERROR`.

### Task 2: Package Tensaku in the flake

- `nix/tensaku-package.nix`: `rustPlatform.buildRustPackage` from the
  GitHub release tag, `cargoHash` pinned. Build inputs per its README:
  GTK-4, libadwaita, glib, gdk-pixbuf, libepoxy, fontconfig; `wrapGAppsHook4`
  so the GTK app finds its schemas and icon theme at runtime. `meta.license
  = lib.licenses.mpl20`, `mainProgram = "tensaku"`.
- Tensaku takes its input as a flag, not a positional argument (which is why
  upstream ships a `tensaku-edit` wrapper). Ship the same wrapper in the
  derivation so `screenshot.editor`'s default is a real executable.
- `flake.nix`: expose it as `packages.<system>.tensaku` alongside
  `formalshell-eds`, and pass it into `nix/package.nix` for the wrapper PATH.
- Risk to settle here, not later: Tensaku's docs list wlroots compositors
  (Sway, Hyprland, River) and never mention niri. It needs wlr-layer-shell
  and wlr-screencopy, both of which niri implements. Prove it in the rig
  rather than assuming — if it genuinely cannot start under niri, that is a
  finding for the owner, and `screenshot.editor` still works with any other
  annotator.
- Verify: `just vm-build`; inside the VM, `tensaku-edit` on a fixture PNG
  under the nested niri session, screenshotted.

### Task 3: Editor handoff from notification and clipboard

- `NotificationService.notify()` currently hardcodes `actions: []`
  (`NotificationService.qml:326`). Extend it to accept an optional action
  list and route `invokeAction` for shell-originated notifications, mirroring
  the existing live-notification path — the internal and D-Bus-originated
  notifications must invoke through one mechanism, not two.
- `ScreenshotIpc.qml`: `SCREENSHOT SAVED` gains an `EDIT` action launching
  `Config.get("screenshot.editor", "tensaku-edit")` with the saved path.
  Launch failure is an honest `SCREENSHOT FAILED`-class warning, never
  silent — and never reports the capture itself as failed, since the PNG is
  already saved and on the clipboard.
- Clipboard image entries get the same handoff, matching
  `omarchy-clipboard-open:33`.
- Verify: `just vm-smoke --notify` with a capture, Read the PNG for the
  action cell; drive the action over IPC and confirm the editor process
  started.

### Task 4: Window and output rectangles in both backends

- `BackendBase.windows` rows gain `x`, `y`, `width`, `height` in **logical
  compositor coordinates**, documented in the row contract alongside the
  existing fields. Absent geometry is `null`, never 0 — a window the
  compositor did not report a box for must not become a rectangle at the
  origin.
- niri: `layout.tile_pos_in_workspace_view` plus `layout.window_size`
  (falling back to `layout.tile_size`), offset by the window's output origin
  from `outputs`. DankMaterialShell reads exactly these at
  `quickshell/Modules/Dock/DockBody.qml:254`. Confirm against the pinned
  niri's IPC before trusting the field names.
- Hyprland: `hyprctl clients -j` `at` and `size`, skipping `hidden` items.
- Collapse duplicates (tabbed groups, stacked floating windows at identical
  geometry) the way upstream's `window_rects` does with `unique` — duplicates
  stall a Tab cycle on the first copy.
- Verify: `just vm-test` for the reducer units; `just vm-smoke --dump` and
  read the `debug` JSON for real per-window boxes under nested niri.

### Task 5: The picker surface

- `shell/Surfaces/Capture/RegionPicker.qml`: one fullscreen `PanelWindow`
  per screen, `WlrLayer.Overlay`, `exclusiveZone: -1`,
  `keyboardFocus: Exclusive` while open, namespace
  `formalshell:capture`.
- Freeze frame: `grim` each output to a file under
  `$XDG_RUNTIME_DIR` **before** the surface maps, shown as the surface's
  background. This is what makes the capture stable and what the crop reads
  from, so live content cannot shift mid-pick and the overlay cannot
  photograph itself.
- Highlight: dim the frame at the design system's scrim, draw the hovered
  rectangle un-dimmed with an accent border at `Theme.borderWidth`, and a
  `WxH` readout in the mek meta-label idiom. Rectangles come from Task 4
  plus `outputs`; resolution is smallest-box-containing-the-point, matching
  upstream.
- Mouse: drag for freeform; a bare click under 20px² snaps to the rectangle
  it landed in (upstream's rule, same threshold).
- Modes `smart` / `region` / `windows` / `fullscreen` select which
  rectangles are hinted and whether freeform is allowed.
- Escape, right-click, and a re-summon while open all cancel. The existing
  `screenshot.timeoutSeconds` watchdog covers the surface too.
- Verify: `just vm-smoke --capture` (new flag, Task 8), Read the PNG.

### Task 6: The keyboard model

- `Return` captures the highlighted rectangle; `Ctrl+Return` the whole
  output under the cursor; `Tab`/`Shift+Tab` cycle windows in reading order
  (top-to-bottom, then left-to-right); arrows move spatially, scoring
  `primary + perp * 2` over candidate centers as upstream does.
- Because the shell owns the highlight, none of this warps the cursor and
  none of it needs the reachability probing upstream had to invent — that
  whole mechanism exists only to make slurp's hover follow a selection it
  does not know about. Say so in the file header; it is the single biggest
  reason this is not a literal port.
- `Shift+Tab` rather than upstream's `Ctrl+Tab`: upstream avoided Shift
  because slurp reshapes its selection while Shift is held. That constraint
  does not exist here.
- Verify: drive each key over the picker's IPC in the smoke rig and assert
  the resulting geometry, one screenshot per mode.

### Task 7: Crop and processing modes

- Crop the freeze frame to the picked rectangle rather than re-running grim:
  the frozen PNG is the truth, and a second grab would photograph the
  overlay. Clipped `Item` plus `grabToImage` and `ItemGrabResult.saveToFile`
  keeps it pure QML with no new binary.
- Processing modes from upstream: default saves to disk **and** clipboard
  then offers the editor action; `copy` is clipboard only; `save` is disk
  only and skips the editor. Extend the `screenshot` IPC target with these
  rather than inventing a second target.
- Verify: each mode over IPC in the rig; assert file existence, clipboard
  content via `wl-paste`, and the PNG's pixel dimensions against the
  requested rectangle.

### Task 8: Smoke rig and docs

- `dev/smoke-niri.sh --capture`: summon the picker, screenshot it, drive
  keyboard selection over IPC, complete a capture, assert the output PNG's
  dimensions match the picked rectangle, and read `screenshot status` back.
- `docs/USAGE.md` §Screenshots: rewrite for the new modes, keys, config keys
  (`screenshot.editor`), and the editor handoff.
- `docs/DESIGN.md`: the picker is a new surface class (full-screen scrim
  with an un-dimmed cutout) — record its tokens.
- `README.md`: one screenshot of the picker.
- Verify: full gate run plus `just vm-smoke --capture`; Read every PNG.

## Verified findings (2026-08-11, read against pinned source)

**niri exposes no rectangle for a tiled window, and cannot.** The open
question below was answered the inverse of the assumption Tasks 4 to 6 were
drafted on. `Tile::ipc_layout_template` hardcodes
`tile_pos_in_workspace_view: None` (`src/layout/tile.rs:869`); `floating.rs:336`
fills it in; the scrolling layout overrides only `pos_in_scrolling_layout`
(`src/layout/scrolling.rs:2426`) and inherits the None. `pos_in_scrolling_layout`
is a 1-based (column, row) index pair, not pixels. `niri_ipc::Window` carries
no other geometry (`niri-ipc/src/lib.rs:1297`). So on a normal, overwhelmingly
tiled niri session, essentially every window has `rect: null`.

This is a compositor capability limit, not a defect to engineer around, and
it splits the picker's feature matrix:

| | Hyprland | niri |
| --- | --- | --- |
| Freeform region drag | yes | yes |
| Monitor rectangle hint | yes | yes |
| Per-window rectangle hint and hover highlight | yes | **no** |
| Capture a chosen window | crop to its rect | `Action::ScreenshotWindow`, server-side |

`Action::ScreenshotWindow { id, write_to_disk, show_pointer, path }`
(`niri-ipc/src/lib.rs:259`) crops server-side by window id, so window capture
on niri needs no rectangle at all. `path` must be absolute or niri returns
Err, and niri puts the PNG on the clipboard itself, so the pipeline's own
`wl-copy` is redundant on that path.

Consequences to fold into Tasks 5 and 6 before building them:

- The picker highlights windows on Hyprland and outputs on both. Under niri
  it renders the honest reduced surface (outputs plus freeform), not an empty
  window list dressed up as one.
- Tab/arrow window selection on niri cycles by window **id** with no
  rectangle preview, and captures through `ScreenshotWindow`. On Hyprland it
  cycles rectangles as upstream does.
- The `--capture` smoke leg must assert the niri run shows the reduced
  surface. A leg that passes by finding zero window hints under nested niri
  proves nothing, since zero is also what a broken implementation returns.

**Hyprland window boxes go stale.** Quickshell repopulates `lastIpcObject`
from `j/clients` only on connect and `configreloaded`
(`src/wayland/hyprland/ipc/connection.cpp:705`, called from `:92` and `:277`
only; no window event branch refreshes it). Fine for hinting, wrong for
cropping — Task 7 must re-read `hyprctl clients -j` at capture time rather
than trusting the cached rect.

**`networkmanager` was deliberately dropped from Task 1.** The task text
called for it; the implementation ships `qrencode`, `matugen`, `cava`, and
`ddcutil` only. `nmcli` and `bluetoothctl` must match the NetworkManager and
bluez the system actually runs, version skew there is a worse failure than
absence, and both callers already guard with `command -v`.

## Open questions

- Does Tensaku start under niri? Its docs list wlroots compositors and never
  mention niri, though it needs only wlr-layer-shell and wlr-screencopy,
  which niri implements. Settled empirically in Task 2's verification, which
  has not run yet.
