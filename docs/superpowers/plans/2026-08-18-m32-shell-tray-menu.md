# FormalShell M32: shell-owned tray menus (retire QsMenuAnchor)

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. Runs after M31
> (media art restore); do not start implementation while another workflow
> holds the tree or the VM.

**Origin, owner bug (2026-08-18):** right-clicking a tray item opens its
context menu and it instantly closes on Hyprland (hosts moved
niri→Hyprland 2026-08-17). Refinement from the owner: it insta-closes
"only if i click the icon itself. If i click the margin of the button
(padding i mean) it works as expected."

**Research already done (2026-08-18), do not re-derive:**

- The menu is quickshell's `QsMenuAnchor` (`Tray.qml`), a **native QMenu**:
  transient-parented to the bar's layer surface, mapped as an xdg_popup
  with a keyboard+pointer grab (platformmenu.cpp). Qt requests the grab
  before parenting the popup to the layer surface (niri #1810's trace);
  Hyprland's grab code never adds the layer parent to the grab's accept
  set (`m_parent` stays null on the layer path, XDGShell.cpp), its popup
  grab is pointer+keyboard rather than keyboard-only (its own comment
  says so), and events over a surface outside the accept set tear the
  grab down → `popup_done` → QMenu closes. niri tracks this case
  correctly, which is why the same shell worked before the switch.
- No quickshell commit after our pin (43d4fa9e) changes menu/grab
  behavior; upgrading does not fix it.
- The icon-vs-padding split is not distinguishable in our QML: both
  points land in the same Cell `MouseArea` on the same wl_surface with
  the same anchor rect, so the divergence lives in compositor-side state
  at grab time. It is recorded here as the reproduction hint, and the fix
  removes the entire class rather than modeling it.
- Sibling shells already made this exact move: DankMaterialShell renders
  tray menus itself via `QsMenuOpener` in its own popup after repeated
  Hyprland focus bugs (their #2561, #2978); Caelestia likewise
  (`TrayMenu.qml`); Noctalia never used the native path. A native QMenu
  is also unthemeable — it ignores DESIGN.md entirely today.
- Quickshell's `QsMenuOpener` exposes a DBusMenu as data: `children`
  (QsMenuEntry: text, icon, enabled, separator, buttonType, checkState,
  hasChildren) plus per-entry activation, submenus via openers on child
  entries. Ground-truth every property and signal name against the
  pinned quickshell source before use, per CLAUDE.md.

## Constraints

- The menu surface follows DESIGN.md end to end: a floating card
  (§1.3 gutters, §2.7 dog-ear, §2.9 title band naming the tray item),
  ledger rows sharing rules (§2.1), cursor row inverting through the
  accent pair (§2.2), separators as the shared hairline, disabled
  entries at `foregroundFaint`, checkable state as the `selected` fill,
  radius 0, no blur, borderWidth 2. Keyboard: arrows + Enter + Escape,
  the panel cursor idiom.
- Submenus expand in place (indented rows, the menu's tree idiom) rather
  than spawning cascade windows — one surface, no nested popup grabs,
  which is the entire point of this milestone.
- `//@ pragma UseQApplication` in shell.qml stays untouched: verify what
  else depends on QApplication mode before even thinking about it, and
  removing it is out of scope regardless.
- The `tray` IPC target grows `menu <id>` (open that item's menu, error
  string on unknown id or no menu — never a silent no-op), which is both
  the compositor-keybind path and the smoke drive path the native menu
  never had.
- Honest states: an item with `hasMenu` false gets no menu route; a menu
  whose DBusMenu yields zero entries renders one dim `EMPTY MENU` cell.

### Task 1: TrayMenu surface, Tray.qml switchover, IPC verb, smoke proof

**Files:** create `shell/Surfaces/Bar/TrayMenu.qml` (or
`shell/Components/` if review of Panel.qml suggests reuse — implementer's
call, name the reasoning in the commit); modify
`shell/Surfaces/Bar/widgets/Tray.qml`, `shell/Ipc/TrayIpc.qml`,
`shell/shell.qml` (if the surface needs wiring), `dev/sni-stub.py`,
`dev/smoke-niri.sh`.

**Produces:**
1. The shell-owned menu surface driven by `QsMenuOpener`, per the
   constraints above; `Tray.qml`'s `openMenu(cell)` routes to it (the
   `QsMenuAnchor` block and its rationale comment are deleted — the new
   header records why, citing the Hyprland grab behavior and the owner
   bug). Anchored under the clicked cell exactly like Panel.qml anchors
   (bottom-left of the cell), click-outside and Escape dismiss.
2. `TrayIpc.qml` gains `menu(id)`; unknown id → error string.
3. `dev/sni-stub.py` exports a minimal `com.canonical.dbusmenu` tree
   (GetLayout/Event/AboutToShow; a few entries: plain, disabled,
   checkable-checked, separator, one submenu) and records Event calls to
   its `--activate-file` alongside Activate.
4. `--tray` smoke leg extension: after the existing assertions, `tray
   menu tray-fixture-2` over IPC, screenshot `tray-menu.png` (rows
   visible in ledger chrome, disabled row faint, checked row selected,
   separator hairline), drive the cursor down over the menu IPC-or-key
   path the surface exposes and activate an entry, assert the stub
   recorded the DBusMenu Event round trip for exactly that entry id.
5. Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --tray`, Read
   the PNGs. Commit (`feat(tray): shell-owned context menus`).

### Task 2: docs and closing sweep

**Files:** `docs/USAGE.md`, `docs/ARCHITECTURE.md`, `docs/DESIGN.md`
(the §3 Bar tray note about accepting the native QMenu styling is now
false — rewrite it to record the shell-owned menu and the reason),
`README.md` if the screenshot grid earns `tray-menu.png`.

**Produces:** docs updated; full regression `just vm-test`, `just
vm-lint`, `just vm-smoke --tray` plus a plain `just vm-smoke`; tree
clean, pushed. Commit (`docs: m32 shell tray menus`).

## Review checkpoint

After Task 2: re-run the tray leg, read the menu PNG against §2.1/2.2/
2.7/2.9, hunt grab regressions (the new surface must take NO xdg_popup
grab — it is a layer surface like every other shell popup), stale
QsMenuAnchor imports, sni-stub D-Bus name hygiene (session-bus isolation
unchanged), fake evidence, unpushed commits.
