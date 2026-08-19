# M38 — everything in the launcher, and multi-GPU

**Date:** 2026-08-19
**Status:** approved, pre-implementation
**Spec:** `docs/superpowers/specs/2026-07-27-formalshell-design.md` (spec wins on conflict)

## Why

Two owner asks, one milestone.

1. **The launcher is the front door.** Every feature of the shell must be
   reachable from the menu. The audit says 15 of 15 panels, the console, plain
   screenshots, manual screensaver, plugins and the notification actions have
   no launcher path at all — they are bar-cell or keybind only. A feature that
   only exists behind a bar cell disappears the moment the cell is opt-out.
2. **A launcher route may host a whole app, not a row list.** Raycast's model:
   the launcher is a window manager for small views. The system monitor is the
   first one — a bar cell for people who want it there, a compact panel behind
   that cell, and the FULL monitor inside the launcher for people who don't.
3. **Multi-GPU.** The shell has no GPU awareness at all today. The owner's own
   g815 is an Intel + NVIDIA hybrid laptop whose external HDMI is wired to the
   dGPU; nothing in the shell can say so, and nothing can launch an app on the
   dGPU.

## Scope

In: launcher app-view seam, launcher reachability sweep, system monitor
(service + pure parsers + bar cell + compact panel + full launcher view), GPU
service (enumeration, per-vendor metrics, connector mapping), launch-on-dGPU,
hybrid-mode switching where `supergfxctl` exists, display-panel output-to-card
annotation, smoke legs, docs.

Out: per-process GPU accounting, GPU fan/power control, a settings UI for any
of it, replacing `Usage` (that is AI token usage and keeps its name).

## Locked design decisions

### D1 — app views are a registry, not a special case

`_isPickerRoute` (`shell/Surfaces/Menu/Menu.qml:375`) and `_isSplitRoute`
(`:533`) are both hardcoded route-id booleans. A third one would be a third
special case, and the owner asked for a *class* of thing. So:

- `shell/Menu/appviews.js` — pure module, single source of truth:
  `VIEWS = { monitor: "views/MonitorView.qml" }`, `viewFor(routeId)` returns
  the relative path or `""`, `isAppView(routeId)` is `viewFor() !== ""`.
- `Menu.qml` grows ONE `Loader` sibling to `rowsView`/`gridView`, same
  anchors/width/height, `source: Qt.resolvedUrl(_appViewSource)`.
- `rowsView` gains `&& !root._isAppView` on `visible` and on the `model`
  ternary, exactly as it already does for `_isPickerRoute`.
- Chrome is free: breadcrumb (`:730`), Escape/`_pop()` (`:1628`), search focus
  and the `menu` IPC all key off `currentNodeId`/`_mode`, not off the view.
- The view MAY declare `property string query`; when it does, Menu.qml binds
  the live search text into it. `MonitorView` does not, so its search field is
  inert by design. This is the seam a future filterable app view needs, and it
  costs one `if (item && item.query !== undefined)`.
- Arrow keys and Enter are no-ops while `_isAppView` (guard in `_activateRow`
  and the key handler), because there is no row cursor to move.
- Width: new token `popupWidthMenuApp: 900` in `shell/Theme/tokens.js`
  alongside `popupWidthMenuSplit`, plus its row in DESIGN.md §1.3. Never a
  literal in Menu.qml.

Adding the second app view later is then one line of `appviews.js` plus one
QML file under `shell/Surfaces/Menu/views/`.

### D2 — one collector, pure parsers

`/proc` and `/sys` reading is done by ONE `sh -c` collector snippet emitting a
sectioned `@stat/@mem/@load/@uptime/@net/@temp/@disk/@drm/@nvidia/@gfx/@end`
blob, run once per poll tick. Not N `FileView`s:

- procfs defeats `FileView`'s change watching, so every file would need manual
  `reload()` anyway;
- `/sys/class/drm/card*` and `/sys/class/hwmon/*` need globbing, which QML has
  no primitive for;
- one blob means ONE pure parse function, testable against bytes captured from
  real hardware (below) instead of a mock filesystem.

The collector script text is a `const` in `shell/Monitor/collect.js` so it is
reviewable, diffable and unit-testable, never an inline string in QML.

Parsers live in `shell/Monitor/sysinfo.js` and `shell/Monitor/gpu.js` — pure,
no Quickshell imports, tested head-on by `qmltestrunner`, following the
`shell/Usage/usage.js` and `shell/Display/outputs.js` precedent (parsing lives
beside its feature, services stay thin).

### D3 — the GPU model

A GPU record is derived from `/sys/class/drm/cardN/device`:

| field | source | note |
| --- | --- | --- |
| `card` | dir name | `card0`, opaque string, never parsed for an index |
| `driver` | `driver` symlink basename | `nvidia`, `i915`, `amdgpu`, `xe` |
| `vendorId`/`deviceId` | `vendor`, `device` | `0x10de` etc. |
| `pci` | `device` symlink basename | `0000:02:00.0`, used for `DRI_PRIME` |
| `bootVga` | `boot_vga` | `1` = the integrated/primary one |
| `label` | `label` | ACPI label, `Onboard - Video` on Intel, empty on NVIDIA |
| `name` | nvidia-smi, else vendor name + device id | see below |
| `outputs` | `cardN-*` connector dirs | with `connected`/`disconnected` |

Metrics are per-driver and deliberately uneven, because the kernel is:

- **amdgpu**: `gpu_busy_percent`, `mem_info_vram_used/total`, hwmon
  `temp1_input`/`power1_average`/`fan1_input`. Full row.
- **nvidia**: nothing usable in sysfs. `nvidia-smi --query-gpu=...
  --format=csv,noheader,nounits` when it is on PATH; `[N/A]` is a real value
  it emits (fan speed on laptop GPUs) and must parse to "unavailable", not 0.
- **i915/xe**: no unprivileged utilisation counter exists. The row renders the
  card, its outputs and `NO METRICS` — never a fabricated percentage. This is
  the honest-unavailable rule, not a gap to paper over.

Names: `nvidia-smi` gives the marketing name for NVIDIA. For everything else
use the ACPI `label` when non-empty, else `"<vendor> <deviceId>"` from a small
vendor-id table (`0x8086` Intel, `0x1002`/`0x1022` AMD, `0x10de` NVIDIA,
`0x1af4` virtio). No `lspci` — it is absent on both NixOS hosts, and no
`pci.ids` file is guaranteed.

### D4 — launch on dGPU

`DesktopEntry.execute()` cannot carry an environment (upstream docs: "Run the
application. Currently ignores runInTerminal and field codes"), so the offload
path builds its own argv in `shell/Monitor/gpu.js`:

```
offloadArgv(execString, target, tools) -> ["nvidia-offload", "sh", "-c", "<exec>"]
```

- NVIDIA target: `nvidia-offload` if on PATH (NixOS), else `prime-run` (Arch),
  else `env __NV_PRIME_RENDER_OFFLOAD=1 __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
  __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only`. The four
  variables are the exact set NixOS's own `nvidia-offload` wrapper exports,
  read off g815 on 2026-08-19.
- Non-NVIDIA target: `env DRI_PRIME=pci-0000_02_00_0` (Mesa's PCI-slot form,
  taken from the card record — never the positional `DRI_PRIME=1`, which is
  ambiguous on a three-GPU box).
- Field codes (`%f %F %u %U %i %c %k %d %D %n %N %v %m`) are stripped from the
  Exec string first; nothing in the repo does this today, so it is new pure
  code with its own tests.
- `runInTerminal` entries are launched through `Config.get("console.command")`
  when set, else spawned bare with a warning — a terminal app asking for the
  dGPU is rare enough not to earn more.

### D5 — evidence, given the rig has no GPU

`/sys/class/drm` in the mac VM contains `version` and nothing else: no cards.
That is not a problem to route around, it is the honest-unavailable path and
the default `--monitor` smoke leg proves it (`NO GPU` cell, monitor still
showing real CPU/MEM from the VM's own `/proc`).

The parse-to-render path is proven separately by a PATH-shimmed `nvidia-smi`
and a shimmed collector, both speaking bytes captured from real hardware —
the same line `--panel github`'s `gh` shim and `--clipssh`'s `clipssh` shim
already draw. What needs proving is the shell's path, not that a VM has a
GPU. Inventing `/sys` entries inside the rig stays forbidden.

## Real-hardware fixtures (captured 2026-08-19)

Captured with the D2 collector over ssh. These exact bytes go into
`tests/fixtures/` and back the parser tests.

**g815 — hybrid Intel + NVIDIA (`gpu-hybrid.txt`)**

```
@drm
card|card0|nvidia|0x10de|0x2d58|0|0000:02:00.0|
conn|card0|DP-3|disconnected
conn|card0|eDP-2|disconnected
conn|card0|HDMI-A-1|connected
card|card1|i915|0x8086|0x7d67|1|0000:00:02.0|Onboard - Video
conn|card1|DP-1|disconnected
conn|card1|DP-2|disconnected
conn|card1|eDP-1|connected
@nvidia
0, NVIDIA GeForce RTX 5070 Laptop GPU, 16, 50, 78, 8151, 12.17, [N/A]
@gfx
```

Note what this fixture pins: the dGPU is `card0` but `boot_vga=0`, the iGPU is
`card1` with `boot_vga=1` — card numbering does NOT imply primacy. The
external HDMI hangs off the dGPU while the internal panel hangs off the iGPU.
`fan.speed` is `[N/A]`. `supergfxctl` is absent, so `@gfx` is empty.

**e1504g — single Intel (`gpu-single.txt`)**

```
@drm
card|card1|i915|0x8086|0x46d0|1|0000:00:02.0|Onboard - Video
conn|card1|eDP-1|connected
conn|card1|HDMI-A-1|disconnected
@nvidia
@gfx
```

Note: the only card is `card1`, not `card0`. Any code indexing by number is
wrong on this machine.

**mac VM — no GPU (`gpu-none.txt`)**: `@drm` section empty.

**amdgpu (`gpu-amd.txt`)**: no AMD hardware is reachable from this rig, so
this fixture is hand-written to the documented sysfs contract
(`gpu_busy_percent`, `mem_info_vram_used/total`, hwmon `temp1_input`) and
labelled as such in the test. It exercises the parser only; no smoke leg
claims AMD hardware.

CPU/memory/temperature fixtures come from the same capture (24-core g815
`/proc/stat`, its `coretemp` hwmon set with `Core N` labels, `nvme` and
`acpitz` zones, `iwlwifi` with an empty label).

## Tasks

One subagent per task. Every task ends with its verification commands actually
run and their output read; no task reports green without pasted evidence.
Tasks in the same **wave** own disjoint file sets and may run in parallel;
waves are strictly sequential.

### Wave 1

**Task 1 — `shell/Monitor/sysinfo.js` + tests**
Owns: `shell/Monitor/sysinfo.js`, `shell/Monitor/collect.js`,
`tests/tst_monitor_sysinfo.qml`, `tests/fixtures/monitor-g815.txt`,
`tests/fixtures/monitor-vm.txt`.
Do: the collector script constant (D2) and pure parsers — `splitSections`,
`parseStat` (returns per-cpu jiffy records; a separate `cpuDelta(prev, next)`
returns aggregate + per-core busy fractions in **0..1**, matching the repo's
fraction convention), `parseMem` (total/available/free/swap in bytes, plus a
`usedFraction`), `parseLoad`, `parseUptime`, `parseNet` (per-interface rx/tx
bytes; `netDelta` gives bytes/sec, `lo` excluded), `parseTemps` (hwmon rows,
empty label falls back to the chip name, millidegrees to degrees), `parseDisk`
(df rows to `{mount, size, used, fraction}`).
Rules: a missing section returns an empty result, never throws. Fractions are
0..1 everywhere. First tick has no previous sample, so every delta function
must return `null` rather than a fake 0.
Verify: `just vm-test`.

**Task 2 — `shell/Monitor/gpu.js` + tests**
Owns: `shell/Monitor/gpu.js`, `tests/tst_monitor_gpu.qml`,
`tests/fixtures/gpu-hybrid.txt`, `gpu-single.txt`, `gpu-none.txt`,
`gpu-amd.txt`.
Do: `parseCards` (the `@drm` section to the D3 record shape, `conn|` rows
folded into `outputs`), `parseNvidia` (the CSV, `[N/A]` to `null`), `mergeGpu`
(nvidia rows matched to `nvidia`-driver cards by enumeration order),
`vendorName`, `displayName`, `metricsFor` (returns `{available:false}` for
i915/xe rather than zeros), `outputCard(connectorName, cards)`,
`offloadArgv` + `stripFieldCodes` (D4), `parseGfxMode` (supergfxctl `-g`
output; absent/empty means unsupported, never "integrated").
Rules: card ids are opaque strings end to end (CLAUDE.md); `card0` is not
index 0 and the e1504g fixture is the test that proves it. `boot_vga` decides
which card is integrated, never the number.
Verify: `just vm-test`, with the e1504g and hybrid fixtures both asserted.

**Task 3 — launcher reachability sweep**
Owns: `shell/Menu/default-menu.jsonc`, `shell/Menu/providers.js` (tray
provider only), `tests/tst_menu_reachability.qml`, `docs/USAGE.md` (menu
section only).
Do: add a launcher route for every gap the audit found —
- `panels.*` submenu with one row per name in the `PanelIpc` registry
  (appmenu, audio, calendar, network, bluetooth, airpods, dualsense, power,
  weather, media, github, usage, tailscale, systemupdate, display), each
  spawning `qs ipc -p <selfPath> call panel open <name>`, exactly the
  `capture.*` pattern;
- `system.console` (`console toggle`), `capture.screenshot`/`capture.region`
  (`screenshot full`/`region`), `system.screensaver` (`screensaver start`),
  `system.plugins` (`plugins list`, `plugins reload`),
  `notifications.clear`/`markAllSeen`/`dismissAll`, `theme.retheme` and
  explicit `theme mode dark|light`;
- a `tray` provider fn enumerating `SystemTray.items` to rows that call
  `tray activate <id>` (the one entry needing new provider plumbing).
- `system.lock` stays `"when": "false"`. It is deliberately disabled and
  flipping it is the owner's call, not this task's. Leave a one-line comment
  saying so.
Then the guard that keeps the philosophy true: `tst_menu_reachability.qml`
asserts every name in the panel registry list has a menu node whose action
mentions it, and fails when a panel is added without a route.
Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --menu` and read the
PNG.

### Wave 2

**Task 4 — `SystemMonitorService` + `GpuService`**
Owns: `shell/Services/SystemMonitorService.qml`,
`shell/Services/GpuService.qml`, `shell/Services/qmldir`.
Do: two singletons over the Task 1/2 modules. One `Process` running the
collector per tick; `subscribe()`/`unsubscribe()` refcounting so nothing polls
while every consumer is closed (the bar cell subscribes while visible, the
panel and the app view while open); interval from
`Config.get("monitor.intervalMs", 2000)`, floored at 500. `available` booleans
per section, derived from the parse, never a separate enum.
`GpuService.enumerate()` runs once at startup and on explicit refresh; metrics
poll only while subscribed. `nvidia-smi` absent is a normal state.
Verify: `just vm-build`, `just vm-lint`, plus `qs ipc call debug dump` in the
rig showing the services alive.

**Task 5 — `MonitorIpc`**
Owns: `shell/Ipc/MonitorIpc.qml`, `shell/shell.qml` (IPC registration only).
Do: `monitor status` (JSON: cpu, mem, load, temps, net, disk, availability
flags), `monitor gpu` (JSON: the card records with metrics and outputs),
`monitor launch <desktopId> [card]` (D4 offload, `card` defaults to the first
non-`boot_vga` card, error string when there is none), `monitor mode
[integrated|hybrid]` (supergfxctl; a clear "unsupported" reply when it is
absent). Unknown args return an error string, never a silent no-op.
Verify: `just vm-lint`, then in the rig `qs ipc call monitor status` and
`monitor gpu` dumped to JSON and read.

### Wave 3

**Task 6 — bar cell + compact panel**
Owns: `shell/Surfaces/Bar/widgets/MonitorWidget.qml`,
`shell/Surfaces/Panels/MonitorPanel.qml`, `shell/Bar/layout.js`,
`shell/Surfaces/Bar/Bar.qml`, `shell/shell.qml` (panel wiring),
`shell/Ipc/PanelIpc.qml` (header comment), `tests/tst_bar_layout.qml`.
Do: `monitor` as an **opt-in** builtin — added to `BUILTIN_WIDGETS`, absent
from `DEFAULT_LAYOUT`, with the opt-in comment extended and the
`test_monitor_is_an_optin_builtin_absent_from_defaults` case following M36's
`display` precedent verbatim. The cell shows CPU% and MEM% (and GPU% when a
card reports one), label-off like its siblings. The panel is the COMPACT view:
CPU, MEM, the GPU summary rows, and a final row that closes the panel and
summons the launcher's full monitor route.
Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --panel monitor`, read
the PNG.

**Task 7 — the app-view seam + `MonitorView`**
Owns: `shell/Menu/appviews.js`, `shell/Surfaces/Menu/Menu.qml`,
`shell/Surfaces/Menu/views/MonitorView.qml`, `shell/Theme/tokens.js`,
`docs/DESIGN.md` (§1.3 width table row), `tests/tst_menu_appviews.qml`,
`shell/Menu/default-menu.jsonc` (the `monitor` route entry only).
Do: D1 exactly. `MonitorView` is the FULL monitor in ledger grammar — CPU with
per-core bars, MEM, SWAP, LOAD, UPTIME, TEMPS, NET rates, DISK, then a GPU
section: one block per card with name, driver, PCI address, its connectors
(and which are connected), and either live metrics or `NO METRICS`. `NO GPU`
when the machine has none. Every visual token from DESIGN.md — `Cell`,
`MetaLabel` uppercase with `colon: true`, `DitherFill` bars, rule width 2,
radius 0, no invented spacing.
Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --monitor`, read the
PNG — the launcher must show the full view with the VM's real CPU/MEM and an
honest `NO GPU`.

### Wave 4

**Task 8 — launch on dGPU**
Owns: `shell/Menu/providers.js` (apps rows + a `gpu` provider),
`shell/Surfaces/Menu/Menu.qml` (activation only),
`shell/Menu/default-menu.jsonc` (`gpu.*` entries),
`tests/tst_menu_gpu.qml`.
Do: a `gpu` route listing the machine's cards (name, driver, integrated/
discrete, outputs) with, under it, `gpu.launch` — the app list again, where
activation goes through `monitor launch <id> <card>` instead of
`_entry.execute()`. Plus Shift+Enter on any ordinary app row as the
accelerator for the same thing, targeting the default discrete card. On a
single-GPU machine the whole `gpu.launch` route hides (`when`-style gating on
the card count) rather than offering a no-op.
Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --gpu` (Task 10's leg).

**Task 9 — outputs know their card**
Owns: `shell/Surfaces/Panels/DisplayPanel.qml`, `shell/Display/outputs.js`,
`tests/tst_display_outputs.qml`.
Do: annotate each output row with the card driving it, matching the
compositor's output name (`eDP-1`, `HDMI-A-1`) against the connector names in
the GPU records. No match renders no annotation, never a guess. On g815's
fixture this is the difference between "HDMI-A-1" and "HDMI-A-1 · dGPU".
Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --panel display`, read
the PNG.

### Wave 5

**Task 10 — smoke legs**
Owns: `dev/smoke-niri.sh`, `dev/vm.sh` (artifact pulls), `justfile` if needed.
Do: `--monitor` (bar cell led into `bar.layout.right`, panel opened, launcher
monitor route summoned; three screenshots plus `monitor status` and `monitor
gpu` JSON dumps; asserts the no-GPU honest state) and `--gpu` (a PATH-shimmed
`nvidia-smi` emitting the g815 bytes verbatim and a shimmed collector emitting
`gpu-hybrid.txt`, so the same run renders a two-card machine; then `monitor
launch` against a fixture desktop entry whose Exec writes its own environment
to a file, read back to prove the four `__NV_*`/`__GLX_*`/`__VK_*` variables
actually reached the child). Both legs carry `SMOKE_*` marker lines so
`dev/vm.sh` pulls their artifacts back to the mac.
Verify: `just vm-smoke --monitor` and `just vm-smoke --gpu`, every artifact
read on the mac.

**Task 11 — docs**
Owns: `docs/USAGE.md`, `docs/DESIGN.md`, `CLAUDE.md`, `README.md`.
Do: document the monitor (cell, panel, launcher route), the app-view registry
as the way to add the next one, the GPU story including what is honestly
unavailable per driver, the new IPC target, and the two new smoke flags in
CLAUDE.md's verification-loop list. Match the existing prose density; no
marketing.
Verify: `just vm-lint`; re-read the CLAUDE.md flag list for accuracy against
what Task 10 actually built.

## Verification matrix

| Claim | Proven by |
| --- | --- |
| Parsers handle real hardware | Task 1/2 tests over bytes captured from g815 and e1504g |
| Card numbering is not index | e1504g fixture (`card1` alone) asserted in Task 2 |
| `[N/A]` is not zero | g815 nvidia fixture asserted in Task 2 |
| Every panel is in the launcher | `tst_menu_reachability.qml` (Task 3), fails on the next unrouted panel |
| App view renders in the launcher | `--monitor` screenshot (Task 10) |
| Honest no-GPU state | same run, `NO GPU` cell plus real CPU/MEM beside it |
| Two-card rendering | `--gpu` run under the shimmed collector |
| Offload env reaches the child | `--gpu` env-dump file read back |
| Bar cell stays opt-in | `tst_bar_layout.qml` (Task 6) |

## Out of scope, deliberately

- `system.lock` stays disabled in the menu; flipping it is the owner's call.
- No settings UI for `monitor.*`; `settings.json` keys only, read-only as ever.
- No AMD smoke leg — no AMD hardware is reachable, and faking one is banned.
- No per-process GPU accounting.
