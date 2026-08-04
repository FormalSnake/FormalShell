# FormalShell M17: LocalSend share menu + LibrePods AirPods section

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. M16
> (`2026-08-03-m16-quattro-polish-parity.md`, tasks 1–13 plus the
> instance-lock and battery-threshold addenda) landed immediately before
> this plan and is live on the e1504g.

**Origin, owner ask (2026-08-03/04):** "can localsend and librepods be
optionally integrated?" followed by "Go ahead." Both integrations are
presence-gated: a machine without the tool renders nothing (LocalSend)
or omits the section (LibrePods) — zero cost, zero chrome when absent.

**Research already done (2026-08-03), do not re-derive:**

- **LocalSend, omarchy's own integration** (read-reference at
  `~/Developer/omarchy`): `bin/omarchy-menu-share` — clipboard mode
  pipes `wl-paste` to a mktemp file; send is
  `localsend --headless send <files…>` run detached
  (omarchy uses `systemd-run --user --collect`); receive is just
  launching the LocalSend GUI. Menu entries at
  `default/omarchy/omarchy-menu.jsonc:60,75-78` (`trigger.share.*`:
  Clipboard / File / Folder / Receive). Firewall: 53317 udp+tcp
  (`install/config/firewall.sh:5-7`). FormalShell advantage: clipboard
  **image** entries are already content-addressed files on disk
  (`$XDG_STATE_HOME/formalshell/clipboard-images/<sha>.png`), so images
  share by path directly — no temp file, unlike omarchy.
- **LibrePods** (`github.com/kavishdevar/librepods`): the Linux side
  ships a daemon exposing `org.librepods.Daemon` on the **session**
  D-Bus — battery per bud + case, noise-control mode get/set
  (Off/ANC/Transparency/Adaptive), ear detection — drivable via
  `gdbus`/`busctl`. Exact object path, interface, property, and method
  names were NOT captured in this session's research and MUST be read
  from the librepods source before any QML is written (clone
  read-reference to `~/Developer/librepods`; find the daemon's D-Bus
  registration/introspection XML). If the shipped daemon's interface
  differs from the web-search summary, the source wins — never guess a
  bus name into existence. Sibling prior art if the interface proves
  unclear: `github.com/Anoryth/librepods-gnome` (a GNOME consumer of
  the same daemon) and `github.com/Explor3Universe/LinuxPods` (KDE
  equivalent with its own daemon — read-reference only, GPL caution:
  reimplement, never copy).
- Quickshell has no general-purpose QML D-Bus client API (tray/
  notifications/mpris are dedicated C++ services) — LibrePods talks
  through `busctl --user`/`gdbus` Processes, the shell's established
  subprocess idiom (nmcli, wl-paste, matugen precedents). A monitor
  Process (`gdbus monitor`/`busctl monitor`) may run ONLY while the
  bluetooth panel is open — never a poll loop, never a standing
  session-long subscription (M16 Task 12's hidden-work rule).
- The shell's presence checks are honest-state precedents: `NO NMCLI`,
  `NO CURL`, `NO TAILSCALE` — same pattern here (`localsend` missing →
  the share route simply doesn't exist; daemon absent → no AIRPODS
  section).

## Constraints

- Same as M16: CLAUDE.md binds (host-session safety, D-Bus isolation —
  note the librepods daemon lives on the SESSION bus, so all runtime
  testing happens inside the nested session's private bus; honest
  unavailable states; glyphs verified from the pinned cmap via fonttools
  ttx; targeted Edits on glyph-bearing files), DESIGN.md is the
  authority, verification ONLY on the VM rig, one conventional commit
  per task (no em dashes anywhere in authored text), pushed, tree clean.
- Presence-gating is config-free: no new settings keys unless a real
  need appears (e.g. a custom share directory is NOT needed — the
  clipboard is the source). Bloat guard: no file browser, no transfer
  progress UI — LocalSend's own GUI owns transfers; the shell only
  launches them.
- LibrePods battery values: verify the daemon's units from its source —
  if they arrive 0..1-fraction-shaped anywhere, the CLAUDE.md fraction
  rule applies (convert exactly once, at the boundary).

---

### Task 1: LocalSend share route

**Files:** modify `shell/Menu/providers.js` (or the menu tree source if
share fits the static-tree path — read how `wallpaper`/power nodes are
wired first and follow the established shape), `shell/Menu/`'s pure
model if node predicates need it, `tests/tst_menu_model.qml` (or a new
`tests/tst_menu_share.qml` mirroring the sibling test files),
`shell/Services/` only if a small presence-check singleton is warranted,
`nix/testvm.nix` (`pkgs.localsend`), `dev/smoke-niri.sh` (`--share`
leg), `docs/USAGE.md`, `docs/SWITCHOVER.md`.

**Produces:**
1. A `SHARE` submenu in the menu tree, present ONLY when `localsend`
   resolves on PATH (one check-resolved presence probe at menu
   open/refresh — the providers' existing check-resolved idiom, never a
   poll):
   - `CLIPBOARD` — shares the newest clipboard entry: text entries are
     written to a mktemp file (`.txt` suffix, omarchy's shape), image
     entries pass their existing content-addressed path directly; then
     `localsend --headless send <path>` spawned detached
     (`Quickshell.execDetached` or the shell's established detach
     idiom — verify which the codebase uses for fire-and-forget).
     Empty clipboard → dim `NOTHING TO SHARE` honest row.
   - `PICK FROM HISTORY` — the clipboard-history list rendered through
     the existing provider machinery, but Enter shares the chosen entry
     (same text/image rules) instead of copying it. Reuse, don't fork:
     read how `clipboardProvider` builds rows and parameterize the
     activation, keeping today's copy route byte-identical.
   - `RECEIVE` — launches the LocalSend GUI detached (transfers are its
     job, not the shell's).
2. Tests: the pure decision logic (entry kind → path-vs-tempfile, node
   presence gating, empty-history row) against fixture entries.
3. testvm gains the real `localsend` package. The `--share` smoke leg:
   copies a fixture string, summons the menu's share route (screenshot —
   rows visible), drives the CLIPBOARD action over the menu IPC, then
   asserts a real `localsend` process appeared with `--headless send`
   and a readable file argument (pgrep + /proc cmdline), and kills it by
   PID. A second assertion path proves the honest state: temporarily
   shadowing PATH so `localsend` is absent must hide the SHARE node
   (menu `debug query` or a second screenshot — whichever gives
   readable evidence).
4. USAGE.md documents the route; SWITCHOVER.md documents the host-side
   prerequisites: `localsend` package + firewall 53317 tcp/udp in the
   owner's nix config.

**Verify:** `just vm-test`; `just vm-lint`; `just vm-smoke --share`,
Read the PNG + the process-argv evidence in the log. Commit
(`feat(menu): …`).

### Task 2: LibrePods section in the bluetooth panel

**Files:** create `shell/Services/LibrePodsService.qml`,
`shell/Airpods/model.js` (pure), `tests/tst_airpods_model.qml`; modify
`shell/Surfaces/Panels/BluetoothPanel.qml`, `docs/USAGE.md`,
`docs/SWITCHOVER.md`.

**Produces:**
1. FIRST: clone `github.com/kavishdevar/librepods` to
   `~/Developer/librepods` (read-reference only) and read the Linux
   daemon's D-Bus surface — bus name, object path, interface(s),
   property/method names, signal shapes, battery units, mode enum
   values. Every wire detail in the QML/JS below comes from that
   source. If the daemon exposes no stable D-Bus interface (or the
   project's Linux daemon turns out to work differently than the
   research summary), STOP and report blocked with what the source
   actually shows — never ship a section speaking a guessed protocol.
2. `Airpods/model.js` (pure): parsers for the daemon's replies
   (battery levels per bud/case, charging flags, mode int ↔ label
   mapping `OFF / ANC / TRANSPARENCY / ADAPTIVE`), unit conversion at
   the boundary if needed, honest nulls for absent buds (single-bud
   use). Tests against fixture strings captured verbatim from the
   daemon source/docs.
3. `LibrePodsService.qml` (Singleton): `available` (bus name has an
   owner — one `busctl --user status`-shaped probe when the bluetooth
   panel opens, refreshed by the monitor below), battery/mode state,
   `setMode(mode)` via the daemon's method call. A monitor Process
   subscribing to the daemon's signals runs ONLY while the bluetooth
   panel is open; panel close kills it (M16 Task 12's rule). All
   Processes are `busctl`/`gdbus` argv — no shell wrappers, no polling
   timers.
4. `BluetoothPanel.qml`: an `AIRPODS` section (uppercase meta header,
   ledger rows) rendered only while `available`: battery rows for
   LEFT / RIGHT / CASE (percent + the panel's existing battery
   rendering idiom; absent bud → row omitted, not `--`), and a
   four-cell mode row (active mode inverted per the ledger selection
   contract, click/Enter/keyboard-cursor sets it through the same nav
   the panel already has). No daemon → the section does not exist; the
   rest of the panel is byte-identical to today.
5. USAGE.md documents the section + its presence condition;
   SWITCHOVER.md documents that the librepods daemon itself is
   owner-side setup (package/service + its BlueZ prerequisites per the
   librepods README) and the shell only consumes its session-bus
   interface.

**Verify:** `just vm-test` (model fixtures); `just vm-lint`;
`just vm-smoke --panel bluetooth` — the VM has no daemon (and no
adapter), so the honest unchanged panel is the expected screenshot;
Read it. Live AirPods behavior is owner-verified post-ship, stated
honestly in the commit. Commit (`feat(bluetooth): …`).

### Task 3: Docs, screenshots, closing sweep

**Files:** `docs/USAGE.md`, `docs/SWITCHOVER.md`, `README.md` +
`docs/screenshots/*` if the share route screenshot is worth the grid;
targeted fixes where the sweep finds drift.

**Produces:** re-run `just vm-test`, `just vm-lint`, `just vm-smoke
--share --panel bluetooth --menu` (menu regression: the share node must
not disturb existing routes); Read the PNGs against DESIGN.md §2/§4;
tree clean, all commits pushed.

**Verify:** the commands above, run and read. Commit (`docs: …`).

---

## Review checkpoint

One adversarial checkpoint after Task 3: re-run the share and bluetooth
smoke legs, hunt guessed-not-verified D-Bus names (diff the QML against
the cloned librepods source yourself), presence-gate leaks (any SHARE
chrome rendered without localsend, any AIRPODS chrome without the
daemon), detached-process leaks (localsend processes surviving the
smoke run), session-bus hygiene (monitor Process lifetime bound to
panel-open), license hygiene (nothing copied from omarchy/LinuxPods),
unpushed commits.
