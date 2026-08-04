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
- **LibrePods** (`github.com/kavishdevar/librepods`) — CORRECTED
  2026-08-04 after reading the actual source (cloned to
  `~/Developer/librepods`; the earlier web-research claim of an
  `org.librepods.Daemon` D-Bus service was FALSE): the Linux app
  exposes **no D-Bus surface at all**, on either branch. The stable Qt
  app registers a `QLocalServer` named `"app_server"` (Unix socket,
  file at `/tmp/app_server`) accepting exactly five **write-only**
  messages: `reopen`, `noise:off`, `noise:anc`, `noise:transparency`,
  `noise:adaptive` (`linux/main.cpp:1092-1103`, mirrored by its own
  `librepods-ctl` CLI). Battery levels and current mode are never
  exported outside the GUI process. The `linux/rust` rewrite branch is
  the same: D-Bus used only as an MPRIS client, no service of its own.
  The owner runs exactly this Qt app on the e1504g (PID 3117, verified
  live) — so the honest integration is **set-only noise control over
  that socket**: no battery rows, no active-mode read-back, no
  invented state. Two unrelated GPL-3.0 projects (EarPort /
  `io.github.anoryth.EarPort1` from librepods-gnome, and LinuxPods /
  `io.github.Explor3Universe.LinuxPods.Manager`) DO ship
  battery-capable daemons — deliberately NOT integrated here: the
  owner doesn't run either, and adopting one is a host-setup decision
  for a future milestone, not something this plan smuggles in.
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

### Task 2: LibrePods noise-control cells in the bluetooth panel (set-only, corrected scope)

**Files:** create `shell/Services/LibrePodsService.qml`; modify
`shell/Surfaces/Panels/BluetoothPanel.qml`, `docs/USAGE.md`,
`docs/SWITCHOVER.md`.

**Produces:**
1. `LibrePodsService.qml` (Singleton): `available` — true while the
   librepods app's control socket exists AND connects (a
   `Quickshell.Io.Socket` to the `QLocalServer` path; verify the exact
   socket path resolution from `linux/main.cpp` — QLocalServer names
   resolve under `$XDG_RUNTIME_DIR` or `/tmp` depending on Qt
   configuration, so read what the app actually creates, and probe by
   connecting, not just stat-ing a maybe-stale file). `setNoise(mode)`
   writes the verbatim message (`noise:off|anc|transparency|adaptive`)
   — the protocol is write-only; the service stores no invented state.
   Probe on bluetooth-panel open only; no poll loops (M16 hidden-work
   rule).
2. `BluetoothPanel.qml`: an `AIRPODS NOISE` row (uppercase meta
   header) rendered only while `available`: four action cells `OFF /
   ANC / TRANSPARENCY / ADAPTIVE`. The protocol has NO read-back, so
   NO cell renders as selected/active — they are plain action cells
   (hover/press states only), and the header carries a dim `SET ONLY`
   meta tag so the absence of an active indicator reads as designed,
   not broken. Joins the panel's existing keyboard-cursor system. No
   socket → the row does not exist; the rest of the panel is
   byte-identical.
3. No pure model file: there is nothing to parse (write-only fixed
   strings). No fake battery, no fake active mode — the moment
   upstream librepods ships a readable interface, a future task can
   grow this honestly.
4. USAGE.md documents the row + its presence condition; SWITCHOVER.md
   notes the prerequisite is simply the librepods Qt app running (the
   owner's existing setup), and records the deliberate non-goals:
   battery/active-mode need a daemon upstream doesn't provide (EarPort
   / LinuxPods exist as GPL alternatives, owner's call, out of scope).

**Verify:** `just vm-lint`; `just vm-test` (no new suite needed;
existing suites must stay green); `just vm-smoke --panel bluetooth` —
the VM has no librepods socket, so the honest unchanged panel is the
expected screenshot; Read it. A socket-fixture leg is sanctioned IF
cheap: a `socat`/python stand-in QLocalServer in the nested session
that records received bytes proves the four cells send the exact
protocol strings — prefer this over shipping unverified writes; if the
rig can't host one honestly, say so in the commit and the owner
verifies live. Commit (`feat(bluetooth): …`).

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
