# FormalShell M1–M2: Walking Skeleton + Compositor Layer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, execution is driven by the Workflow orchestrator: one subagent per task, sequential, verification evidence required before commit.

**Goal:** A nix-packaged QuickShell shell whose themed bar shows live workspaces + active window on both niri and Hyprland, behind a formal `CompositorBackend` contract, with CI (qmllint + JS unit tests) and a scripted nested-niri smoke loop.

**Architecture:** One QuickShell process (`qs -p <tree>`). QML tree in `shell/` (Omarchy quattro's layout, generalized): `Core/` singletons for tokens/config, `Compositor/` facade + per-compositor backends (niri = hand-rolled two-socket JSON IPC; Hyprland = `Quickshell.Hyprland` + `usingLua` dual dispatch), `Surfaces/Bar/` widgets binding only to the facade. Pure-JS logic (niri event reducer) lives in `.js` modules tested headlessly with `qmltestrunner`.

**Tech Stack:** QuickShell v0.3.x (pinned flake input, `nixpkgs.follows`), Qt 6 QML/JS, Nix flake (packages / homeModules / checks / devShell), qmltestrunner (qt6.qtdeclarative) with `QT_QPA_PLATFORM=offscreen`, GitHub Actions.

**Spec:** The approved design lives in the owner's nix repo at `~/.config/nix/docs/superpowers/specs/2026-07-27-formalshell-design.md`. A copy is committed here as `docs/superpowers/specs/2026-07-27-formalshell-design.md` (Task 1). The spec wins over this plan on any conflict.

## Global Constraints

- Pure QML/JS. No compiled companion binary. No Node/npm/bun anywhere.
- `quickshell` is a pinned flake input from `git+https://git.outfoxxed.me/quickshell/quickshell` with `inputs.nixpkgs.follows = "nixpkgs"` (ABI-critical; never drop the follows).
- Brutalist defaults, non-negotiable: corner radius `0`, no blur, no shadows, border width `2`, font = fontconfig `monospace` alias (never a hardcoded family name), icons = Nerd Font glyphs (no SVG icon sets).
- Compositor window/workspace ids are **opaque strings** end to end. Never parse, compare numerically, or assume stability.
- The shell only ever **reads** `~/.config/formalshell/settings.json`; it never writes it. Runtime-mutable state goes to `$XDG_STATE_HOME/formalshell/state.json`.
- License MIT. Every file substantially ported from DankMaterialShell keeps a `// Portions from DankMaterialShell (MIT, Copyright 2025 Avenge Media LLC)` header line.
- Commits: conventional style, lowercase imperative subject (`feat(compositor): …`), no Co-Authored-By lines, no commit descriptions.
- ⚠️ Nerd Font glyphs are raw multi-byte codepoints; whole-file rewrites can corrupt them (Omarchy's AGENTS.md documents this). Use targeted `Edit` operations on files containing glyphs; never rewrite such files wholesale.
- Reference checkouts (read-only, clone shallow when needed): `github.com/basecamp/omarchy` (branch `quattro`) — architecture/UX reference; `github.com/AvengeMedia/DankMaterialShell` (MIT) — niri backend + matugen prior art. Copy ideas freely, port DMS code with attribution, never copy Omarchy code verbatim (check its license first if ever tempted — treat as read-reference only).
- Every task ends with its verification commands actually run and their output read. No claiming green without evidence.

---

### Task 1: Repo base — license, flake, devShell

**Files:**
- Create: `LICENSE` (MIT, `Copyright (c) 2026 Kyan de Sutter`)
- Create: `.gitignore` (`result`, `result-*`, `.direnv/`, `*.qmlc`, `.qmlls.ini`)
- Create: `flake.nix`
- Create: `docs/superpowers/specs/2026-07-27-formalshell-design.md` (copy verbatim from `~/.config/nix/docs/superpowers/specs/2026-07-27-formalshell-design.md`)
- Create: `README.md` (stub: name, one-paragraph description from the spec's "What it is", "pre-alpha, nothing to see yet" note)

**Interfaces:**
- Produces: `inputs.quickshell`, `pkgsFor`/`forAllSystems` helper, `devShells.<system>.default` — later tasks add `packages`, `checks`, `homeModules` to THIS flake structure; do not restructure it.

- [ ] **Step 1: Write flake.nix**

```nix
{
  description = "FormalShell — brutalist QuickShell Wayland desktop shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, quickshell }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f system nixpkgs.legacyPackages.${system});
      qsFor = system: quickshell.packages.${system}.default;
    in
    {
      devShells = forAllSystems (system: pkgs: {
        default = pkgs.mkShell {
          packages = [
            (qsFor system)
            pkgs.qt6.qtdeclarative # qmllint, qmltestrunner, qmlls
            pkgs.matugen
            pkgs.just
          ];
          shellHook = ''
            [ -f .qmlls.ini ] || touch .qmlls.ini
          '';
        };
      });
    };
}
```

- [ ] **Step 2: Verify flake evaluates**

Run: `cd ~/Developer/FormalShell && git add -A && nix flake check 2>&1 | tail -5` and `nix develop -c qs --version`
Expected: check passes (no outputs to build yet); `qs --version` prints a 0.3.x version. First run downloads/builds quickshell — allow time.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: flake skeleton with pinned quickshell input, devshell, MIT license"
```

---

### Task 2: QML tree + package — an empty bar that builds

**Files:**
- Create: `shell/shell.qml`
- Create: `shell/Surfaces/Bar/Bar.qml`
- Create: `nix/package.nix`
- Modify: `flake.nix` (add `packages`)

**Interfaces:**
- Produces: `packages.<system>.{formalshell,default}`; installed binary `formalshell` = `qs -p $out/share/formalshell`. The QML root is `shell/` — all in-tree imports use the `qs.` root prefix (e.g. `import qs.Core`), which QuickShell maps to the config root.

- [ ] **Step 1: Write shell.qml**

```qml
//@ pragma ShellId formalshell
import Quickshell
import QtQuick

ShellRoot {
    Variants {
        model: Quickshell.screens
        Surfaces.Bar.Bar {}  // adjust to the actual working import form
    }
}
```

Note for implementer: verify the exact idiomatic import/instantiation form against DMS's `quickshell/shell.qml` and Omarchy's `shell/shell.qml` (clone both, read only those files). Use whichever form QuickShell actually resolves — the structure (ShellRoot → Variants over `Quickshell.screens` → one Bar per screen with `required property var modelData; screen: modelData`) is the requirement, the import syntax is discoverable.

- [ ] **Step 2: Write Bar.qml (placeholder)**

```qml
import Quickshell
import QtQuick

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: 32
    color: "#100F0F" // Flexoki black placeholder; Task 3 replaces with Theme token

    Text {
        anchors.centerIn: parent
        text: "formalshell"
        color: "#CECDC3"
        font.family: "monospace"
        font.pixelSize: 13
    }
}
```

- [ ] **Step 3: Write nix/package.nix and wire into flake**

```nix
{ lib, stdenvNoCC, makeWrapper, quickshell }:
stdenvNoCC.mkDerivation {
  pname = "formalshell";
  version = "0.1.0-dev";
  src = ../shell;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/formalshell $out/bin
    cp -r . $out/share/formalshell/
    makeWrapper ${lib.getExe' quickshell "qs"} $out/bin/formalshell \
      --add-flags "-p $out/share/formalshell"
    runHook postInstall
  '';
  meta = { mainProgram = "formalshell"; license = lib.licenses.mit; platforms = lib.platforms.linux; };
}
```

In `flake.nix` outputs add:

```nix
packages = forAllSystems (system: pkgs: rec {
  formalshell = pkgs.callPackage ./nix/package.nix { quickshell = qsFor system; };
  default = formalshell;
});
```

- [ ] **Step 4: Verify build**

Run: `git add -A && nix build .#formalshell && ls result/bin/ result/share/formalshell/`
Expected: `result/bin/formalshell` exists; QML tree under `share/formalshell/`. (`git add` first — flakes ignore untracked files.)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shell): minimal bar per screen + nix package wrapping qs -p"
```

---

### Task 3: Theme token singletons (static brutalist defaults)

**Files:**
- Create: `shell/Core/Theme.qml` (singleton)
- Create: `shell/Core/qmldir`
- Modify: `shell/Surfaces/Bar/Bar.qml` (consume tokens, drop hardcoded colors)

**Interfaces:**
- Produces: singleton `Theme` importable as `import qs.Core` with, exactly:
  - `Theme.color`: `{ background, backgroundAlt, foreground, foregroundDim, accent, urgent }` (color values)
  - `Theme.control(state)`: state ∈ `"normal"|"hover"|"focus"|"selected"` → `{ fill, fillAlpha, border, borderWidth, borderAlpha }`
  - `Theme.font`: `{ family (resolves the fontconfig "monospace" alias — literally the string "monospace"), baseSize (13), caption, bodySmall, body, subtitle, title, heading }` (pixel sizes = baseSize × Omarchy multipliers 0.833/0.917/1.0/1.083/1.167/1.333, rounded)
  - `Theme.spacing`: `{ scale (1.0), xs, sm, md, lg }` = scale × (2, 4, 8, 16)
  - `Theme.borderWidth: 2`, `Theme.radius: 0`
- Static default palette = Flexoki dark: background `#100F0F`, backgroundAlt `#1C1B1A`, foreground `#CECDC3`, foregroundDim `#878580`, accent `#4385BE`, urgent `#D14D41`. (Matugen replaces these via `theme.json` in the M3 plan; keep the properties `readonly property color` bindings so a later FileView can drive them.)

- [ ] **Step 1: Write Theme.qml + qmldir**

`shell/Core/qmldir`:
```
singleton Theme Theme.qml
```

`shell/Core/Theme.qml`:
```qml
pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root

    readonly property var color: ({
        background: "#100F0F", backgroundAlt: "#1C1B1A",
        foreground: "#CECDC3", foregroundDim: "#878580",
        accent: "#4385BE", urgent: "#D14D41"
    })

    readonly property int borderWidth: 2
    readonly property int radius: 0

    readonly property var font: ({
        family: "monospace",
        baseSize: 13,
        caption: Math.round(13 * 0.833), bodySmall: Math.round(13 * 0.917),
        body: 13, subtitle: Math.round(13 * 1.083),
        title: Math.round(13 * 1.167), heading: Math.round(13 * 1.333)
    })

    readonly property var spacing: ({ scale: 1.0, xs: 2, sm: 4, md: 8, lg: 16 })

    function control(state) {
        switch (state) {
        case "hover":
        case "focus":    return { fill: color.foreground, fillAlpha: 0.08, border: color.foreground, borderWidth: borderWidth, borderAlpha: 0.35 }
        case "selected": return { fill: color.accent,     fillAlpha: 0.18, border: color.accent,     borderWidth: borderWidth, borderAlpha: 0.9 }
        default:         return { fill: "transparent",    fillAlpha: 0.0,  border: "transparent",    borderWidth: 0,           borderAlpha: 0.0 }
        }
    }
}
```

(`Singleton` root type: verify against DMS `Common/*.qml` — QuickShell provides `Quickshell.Singleton`; if the running QuickShell version expects `QtObject` + `pragma Singleton` instead, match what DMS does on the pinned version.)

- [ ] **Step 2: Rewire Bar.qml to tokens** — replace both hardcoded colors and font values with `Theme.*` references (`import qs.Core`).

- [ ] **Step 3: Verify** — `git add -A && nix build .#formalshell` then `nix develop -c qmllint --help >/dev/null && echo lint-tool-ok`. Build must pass.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(core): theme token singleton with brutalist flexoki defaults"`

---

### Task 4: Dev smoke loop — nested niri + screenshot

**Files:**
- Create: `dev/smoke-niri.sh` (executable)
- Create: `justfile`

**Interfaces:**
- Produces: `just smoke` → builds the shell, launches a **nested** niri window on the host session running the shell, waits, screenshots the nested session to a known path, quits niri, prints the screenshot path. This is THE visual verification loop for every later UI task (agents Read the PNG).

- [ ] **Step 1: Write dev/smoke-niri.sh**

```bash
#!/usr/bin/env bash
# Nested-niri smoke: run the built shell in an isolated niri window,
# screenshot it, tear down. Prints the screenshot path on success.
set -euo pipefail
cd "$(dirname "$0")/.."

git add -A >/dev/null 2>&1 || true   # flakes only see tracked files
nix build .#formalshell
shot_dir=$(mktemp -d)
cfg=$(mktemp -d)/config.kdl
cat > "$cfg" <<EOF
screenshot-path "$shot_dir/smoke.png"
spawn-at-startup "$PWD/result/bin/formalshell"
spawn-at-startup "sh" "-c" "sleep 6 && niri msg action screenshot-screen --write-to-disk && sleep 1 && niri msg action quit --skip-confirmation"
EOF
timeout 30 nix run nixpkgs#niri -- --config "$cfg" || true
if [ -f "$shot_dir/smoke.png" ]; then
  echo "SMOKE_OK $shot_dir/smoke.png"
else
  echo "SMOKE_FAIL: no screenshot produced" >&2; exit 1
fi
```

Implementer notes: `screenshot-path` takes strftime patterns — a literal path is fine. If the host has `niri` on PATH (it does on the g815), prefer host `niri` over `nix run nixpkgs#niri` (faster, version-matched to the daily driver): detect with `command -v niri`. The nested window appears briefly on the owner's live desktop — expected and accepted. If `screenshot-screen` flags differ on the installed niri version, check `niri msg action screenshot-screen --help` and adapt.

- [ ] **Step 2: Write justfile**

```just
default: build
build:
    git add -A && nix build .#formalshell
smoke:
    ./dev/smoke-niri.sh
lint:
    git add -A && nix flake check -L
test:
    nix develop -c env QT_QPA_PLATFORM=offscreen qmltestrunner -input tests
```

- [ ] **Step 3: Verify** — `chmod +x dev/smoke-niri.sh && just smoke`; then Read the printed PNG: it must show the bar (dark strip, "formalshell" centered) at the top of an empty niri session.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(dev): nested-niri smoke script with screenshot verification"`

---

### Task 5: CompositorBackend contract + facade

**Files:**
- Create: `shell/Compositor/CompositorService.qml` (singleton facade)
- Create: `shell/Compositor/qmldir` (`singleton CompositorService CompositorService.qml`)
- Create: `shell/Compositor/BackendBase.qml` (the contract, as a base component)

**Interfaces:**
- Produces (THE stable contract — all of M2 and every later surface depends on these exact names):

```qml
// BackendBase.qml — QtObject base every backend extends
readonly property bool available          // backend detected its compositor and is connected
property var workspaces: []               // [{ id:string, idx:int, name:string, output:string, isActive:bool, isFocused:bool, isUrgent:bool }]
property var windows: []                  // [{ id:string, title:string, appId:string, workspaceId:string, isFocused:bool, isFloating:bool, isUrgent:bool }]
property var outputs: []                  // [{ name:string, x:int, y:int, width:int, height:int, scale:real }]
property string focusedWindowId: ""
property string focusedWorkspaceId: ""
property string focusedOutputName: ""
signal configReloaded(bool failed)
function focusWorkspace(id) {}
function focusWindow(id) {}
function closeWindow(id) {}
function spawn(argv) {}                   // argv: list<string>, no shell interpolation
function powerOffMonitors() {}
function powerOnMonitors() {}
```

- `CompositorService` (singleton) exposes the same properties/methods, delegating to the active backend, plus `readonly property string compositor` (`"niri" | "hyprland" | "unknown"`). Detection: check `Quickshell.env("NIRI_SOCKET")` then `Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")` (env-based is sufficient inside nested test sessions; the `/proc/net/unix` socket-owner walk from DMS `CompositorService.qml:927` is a hardening follow-up recorded as a TODO comment, not built now).
- Extensions object: `readonly property var ext` on CompositorService — `{ overview: { available:bool, isOpen:bool, toggle() } }`, all-defaults-false when the backend lacks it.

- [ ] **Step 1: Write BackendBase.qml + CompositorService.qml** with a null backend (empty lists, available:false) so the shell still builds with no compositor.
- [ ] **Step 2: Verify** — `git add -A && nix build .#formalshell` passes; `just smoke` still shows the bar.
- [ ] **Step 3: Commit** — `git add -A && git commit -m "feat(compositor): backend contract and facade singleton"`

---

### Task 6: Niri event reducer (pure JS) — TDD

**Files:**
- Create: `shell/Compositor/niri/reducer.js`
- Create: `tests/tst_niri_reducer.qml`
- Modify: `flake.nix` (add `checks.<system>.qml-tests`)

**Interfaces:**
- Produces: `.pragma library` JS module with:
  - `initialState()` → `{ workspaces: [], windows: [], outputs: [], focusedWindowId: "", focusedWorkspaceId: "", focusedOutputName: "", raw: { workspaces: {}, windows: {} } }`
  - `reduce(state, event)` → new state (pure function, no mutation of input). `event` is one parsed niri EventStream JSON object (shape: single-key object, e.g. `{ "WorkspacesChanged": { "workspaces": [...] } }`).
  - Normalization: niri `Workspace{id,idx,name,output,is_urgent,is_active,is_focused,active_window_id}` → contract shape with `id: String(id)`, `name: name ?? ""`; niri `Window{id,title,app_id,pid,workspace_id,is_focused,is_floating,is_urgent}` → contract shape with `id: String(id)`, `appId: app_id ?? ""`, `workspaceId: String(workspace_id)`.
- Handles: `WorkspacesChanged`, `WorkspaceActivated` (sets is_active on that ws + clears others on same output; `focused:true` also sets focusedWorkspaceId), `WorkspaceUrgencyChanged`, `WorkspaceActiveWindowChanged` (ignore for v1 state), `WindowsChanged`, `WindowOpenedOrChanged` (upsert), `WindowClosed`, `WindowFocusChanged` (null id → clear focus), `WindowUrgencyChanged`, `OverviewOpenedOrClosed` (→ `state.overviewOpen`), `ConfigLoaded` (→ `state.configLoadFailed`). **Unknown event keys return state unchanged** (niri's forward-compat mandate).

- [ ] **Step 1: Write the failing tests** — `tests/tst_niri_reducer.qml`:

```qml
import QtQuick
import QtTest
import "../shell/Compositor/niri/reducer.js" as R

TestCase {
    name: "NiriReducer"

    function test_hydrate_workspaces() {
        var s = R.reduce(R.initialState(), { WorkspacesChanged: { workspaces: [
            { id: 3, idx: 1, name: null, output: "eDP-1", is_urgent: false, is_active: true, is_focused: true, active_window_id: 7 },
            { id: 9, idx: 2, name: "mail", output: "eDP-1", is_urgent: false, is_active: false, is_focused: false, active_window_id: null }
        ]}});
        compare(s.workspaces.length, 2);
        compare(s.workspaces[0].id, "3");           // opaque string
        compare(s.workspaces[1].name, "mail");
        compare(s.focusedWorkspaceId, "3");
    }

    function test_window_focus_change() {
        var s = R.reduce(R.initialState(), { WindowsChanged: { windows: [
            { id: 7, title: "ghostty", app_id: "com.mitchellh.ghostty", pid: 1, workspace_id: 3, is_focused: true, is_floating: false, is_urgent: false }
        ]}});
        s = R.reduce(s, { WindowFocusChanged: { id: null } });
        compare(s.focusedWindowId, "");
        compare(s.windows[0].isFocused, false);
    }

    function test_window_closed() {
        var s = R.reduce(R.initialState(), { WindowsChanged: { windows: [
            { id: 7, title: "a", app_id: "a", pid: 1, workspace_id: 3, is_focused: false, is_floating: false, is_urgent: false },
            { id: 8, title: "b", app_id: "b", pid: 1, workspace_id: 3, is_focused: false, is_floating: false, is_urgent: false }
        ]}});
        s = R.reduce(s, { WindowClosed: { id: 7 } });
        compare(s.windows.length, 1);
        compare(s.windows[0].id, "8");
    }

    function test_unknown_event_ignored() {
        var s0 = R.initialState();
        var s1 = R.reduce(s0, { SomeFutureEvent: { whatever: 1 } });
        compare(JSON.stringify(s1), JSON.stringify(s0));
    }

    function test_reduce_is_pure() {
        var s0 = R.initialState();
        R.reduce(s0, { WorkspacesChanged: { workspaces: [ { id: 1, idx: 1, name: null, output: "x", is_urgent: false, is_active: true, is_focused: true, active_window_id: null } ] } });
        compare(s0.workspaces.length, 0);
    }
}
```

- [ ] **Step 2: Run to verify failure** — `nix develop -c env QT_QPA_PLATFORM=offscreen qmltestrunner -input tests` → expect import failure / all tests fail (reducer.js missing).
- [ ] **Step 3: Implement reducer.js** (`.pragma library` at top; pure functions; spread/JSON-clone for immutability).
- [ ] **Step 4: Run to verify pass** — same command, all green.
- [ ] **Step 5: Add flake check** — in `flake.nix`:

```nix
checks = forAllSystems (system: pkgs: {
  qml-tests = pkgs.runCommand "formalshell-qml-tests" {
    nativeBuildInputs = [ pkgs.qt6.qtdeclarative ];
  } ''
    cp -r ${./.}/shell shell; cp -r ${./.}/tests tests
    QT_QPA_PLATFORM=offscreen qmltestrunner -input tests
    touch $out
  '';
});
```

Verify `git add -A && nix flake check -L` passes.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(compositor): pure-js niri event reducer with headless qml tests"`

---

### Task 7: NiriBackend — sockets + actions + debug IPC

**Files:**
- Create: `shell/Compositor/niri/NiriBackend.qml`
- Create: `shell/Ipc/DebugIpc.qml`
- Modify: `shell/Compositor/CompositorService.qml` (instantiate NiriBackend when `NIRI_SOCKET` set)
- Modify: `shell/shell.qml` (instantiate the Ipc scope)

**Interfaces:**
- Consumes: `reducer.js` (`initialState`/`reduce`), `BackendBase` contract (Task 5 exact names).
- Produces: a working live backend on niri; `qs ipc` target `debug` with `function dump(): string` returning `JSON.stringify({ compositor, available, workspaces, windows, focusedWindowId, focusedWorkspaceId })` — the scripted-verification hook every later task uses.

- [ ] **Step 1: Write NiriBackend.qml** — two `Quickshell.Io.Socket`s on `Quickshell.env("NIRI_SOCKET")` (niri's EventStream monopolizes its connection — documented two-socket requirement):
  - `eventSocket`: on connect `write('"EventStream"\n')`; `SplitParser` per line → `JSON.parse` → skip the initial `{"Ok":"Handled"}` reply line → `state = Reducer.reduce(state, event)` → copy normalized fields to the contract properties.
  - `requestSocket`: `function request(obj) { write(JSON.stringify(obj) + "\n") }`; actions map exactly: `focusWorkspace(id)` → `{ Action: { FocusWorkspace: { reference: { Id: Number(id) } } } }`; `focusWindow(id)` → `{ Action: { FocusWindow: { id: Number(id) } } }`; `closeWindow(id)` → `{ Action: { CloseWindow: { id: Number(id) } } }`; `spawn(argv)` → `{ Action: { Spawn: { command: argv } } }`; `powerOffMonitors()` → `{ Action: { PowerOffMonitors: {} } }`; `powerOnMonitors()` → `{ Action: { PowerOnMonitors: {} } }`. (The `Number()` at the IPC boundary is the ONLY place string ids convert back; niri's wire format wants integers.)
  - Reconnect with a 2s `Timer` on socket error/close. Unknown events already ignored by the reducer.
  - Reference implementation to consult (MIT, attribute if ported): DMS `quickshell/Services/NiriService.qml` (two-socket pattern) — but implement against OUR reducer, don't port DMS's inline state handling.
- [ ] **Step 2: Write DebugIpc.qml** — `IpcHandler { target: "debug" }` with `dump()` as above.
- [ ] **Step 3: Verify inside nested niri** — extend the smoke flow manually: launch nested niri with the shell, then inside it run `qs -p <tree> ipc call debug dump` — wait: `qs ipc` must target the running instance; from within the nested session env (`spawn-at-startup "sh" "-c" "sleep 4 && qs ipc call debug dump > /tmp/formalshell-dump.json"`). Assert the JSON contains ≥1 workspace and `available: true`. Add this as `dev/smoke-niri.sh --dump` mode (second spawn-at-startup writing the dump before quitting; script cats it).
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(compositor): niri backend over two-socket json ipc with debug dump target"`

---

### Task 8: Bar widgets — Workspaces + ActiveWindow

**Files:**
- Create: `shell/Surfaces/Bar/widgets/Workspaces.qml`
- Create: `shell/Surfaces/Bar/widgets/ActiveWindow.qml`
- Modify: `shell/Surfaces/Bar/Bar.qml` (three-region RowLayout: left = Workspaces, center = empty, right = ActiveWindow for now)

**Interfaces:**
- Consumes: `CompositorService.{workspaces, windows, focusedWindowId, focusedWorkspaceId, focusWorkspace()}`, `Theme` tokens.
- Produces: the widget slot convention later widgets follow: each widget is an `Item` with `implicitWidth`/`implicitHeight`, reads only the facade + Theme, never a backend directly.

- [ ] **Step 1: Workspaces.qml** — `Repeater` over `CompositorService.workspaces` filtered to `modelData.output === bar.screen.name` (fall back to all if names don't match); each cell: mono `Text` showing `name || idx`, wrapped in a `Rectangle` styled via `Theme.control(ws.isFocused ? "selected" : mouseArea.containsMouse ? "hover" : "normal")` — radius 0, 2px border per token. Click → `CompositorService.focusWorkspace(ws.id)`.
- [ ] **Step 2: ActiveWindow.qml** — `Text` bound to the focused window's `title` (elided, max ~40% bar width), `appId` in `foregroundDim` before it.
- [ ] **Step 3: Verify visually** — `just smoke`; Read the PNG: workspace cells visible left (nested niri starts with ≥1 workspace), focused cell bordered in accent. Then `dev/smoke-niri.sh --dump` shows the same state textually.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(bar): workspaces and active-window widgets on the compositor facade"`

---

### Task 9: HyprlandBackend

**Files:**
- Create: `shell/Compositor/hyprland/HyprlandBackend.qml`
- Modify: `shell/Compositor/CompositorService.qml` (detection order: NIRI_SOCKET → HYPRLAND_INSTANCE_SIGNATURE → null backend)
- Create: `dev/smoke-hyprland.sh` (mirror of the niri smoke: nested Hyprland via `nix run nixpkgs#hyprland`, exec-once the shell + a dump + `hyprctl dispatch exit`)

**Interfaces:**
- Consumes: `BackendBase` contract; `Quickshell.Hyprland` module (`Hyprland.workspaces`, `Hyprland.toplevels`, `Hyprland.monitors`, `Hyprland.focusedWorkspace`, `Hyprland.dispatch()`, `Hyprland.usingLua`).
- Produces: same contract surface as NiriBackend — proving the interface generalizes is the point of this task.

- [ ] **Step 1: Write HyprlandBackend.qml** — map `Hyprland.workspaces`/`toplevels` reactive models into the contract shapes (ids via `String(...)`; Hyprland window ids are hex addresses — keep verbatim). Every dispatch branches on `Hyprland.usingLua` (Hyprland ≥0.55 Lua migration, no upstream shim), e.g. `focusWorkspace`: Lua → `Hyprland.dispatch('hl.dsp.focus({workspace="' + name + '"})')`, legacy → `Hyprland.dispatch("workspace " + name)`; `powerOffMonitors`: `hl.dsp.dpms({ action = "disable" })` vs `dpms off`. Cross-check exact call forms against DMS `HyprlandService.qml:537-636` and Caelestia `services/Hypr.qml` (both handle `usingLua`).
- [ ] **Step 2: Verify** — `./dev/smoke-hyprland.sh`: dump JSON shows `compositor: "hyprland"`, `available: true`, ≥1 workspace; screenshot shows the bar. (If nested Hyprland refuses to run in this environment, record the exact failure in the commit message and verify state-mapping via qmllint + a review pass instead — do NOT fake the dump.)
- [ ] **Step 3: Commit** — `git add -A && git commit -m "feat(compositor): hyprland backend with dual dispatch grammar (usingLua)"`

---

### Task 10: qmllint check + GitHub Actions CI

**Files:**
- Modify: `flake.nix` (add `checks.<system>.qmllint`)
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `nix flake check` = qml-tests + qmllint; CI running it on push/PR.

- [ ] **Step 1: qmllint check** — qmllint does NOT auto-discover QML modules under nix (nixpkgs #337502); pass import paths explicitly:

```nix
qmllint = pkgs.runCommand "formalshell-qmllint" {
  nativeBuildInputs = [ pkgs.qt6.qtdeclarative ];
} ''
  cd ${./.}
  qmllint -I ${qsFor system}/lib/qt-6/qml --bare $(find shell -name '*.qml') 2>&1 | tee $out.log
  touch $out
'';
```

Implementer note: the exact QML module path inside the quickshell package must be verified (`ls $(nix build --print-out-paths .#… )`); adjust `-I`. If quickshell-type resolution proves impossible for qmllint, scope the check to syntax level (`--no-unqualified-id` off etc.) rather than deleting it — a syntax-only gate still catches real breakage. Warnings are allowed; errors fail.

- [ ] **Step 2: CI workflow**

```yaml
name: ci
on: { push: { branches: [main] }, pull_request: {} }
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v16
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - run: nix flake check -L
```

- [ ] **Step 3: Verify** — `git add -A && nix flake check -L` green locally; push and confirm the Actions run goes green (`gh run watch`).
- [ ] **Step 4: Commit** — `git add -A && git commit -m "ci: qmllint + qml-tests flake checks on github actions"` (commit before push; push is part of this task).

---

### Task 11: Home-manager module

**Files:**
- Create: `nix/hm-module.nix`
- Modify: `flake.nix` (add `homeModules.{formalshell,default}`)

**Interfaces:**
- Produces: `homeModules.formalshell` with `programs.formalshell.{enable, package, settings, systemd.{enable, target}}` — the consumption surface the owner's nix repo will use.

- [ ] **Step 1: Write nix/hm-module.nix**

```nix
{ config, lib, pkgs, ... }:
let cfg = config.programs.formalshell; in
{
  options.programs.formalshell = {
    enable = lib.mkEnableOption "FormalShell";
    package = lib.mkOption { type = lib.types.package; description = "FormalShell package (from the flake's packages output)."; };
    settings = lib.mkOption {
      type = (pkgs.formats.json {}).type;
      default = {};
      description = "Contents of ~/.config/formalshell/settings.json. FormalShell only reads this file, so home-manager owns it fully.";
    };
    systemd = {
      enable = lib.mkEnableOption "systemd user service" // { default = true; };
      target = lib.mkOption { type = lib.types.str; default = "graphical-session.target"; };
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    xdg.configFile."formalshell/settings.json" = lib.mkIf (cfg.settings != {}) {
      source = (pkgs.formats.json {}).generate "formalshell-settings.json" cfg.settings;
    };
    systemd.user.services.formalshell = lib.mkIf cfg.systemd.enable {
      Unit = { Description = "FormalShell"; PartOf = [ cfg.systemd.target ]; After = [ cfg.systemd.target ]; };
      Service = { ExecStart = lib.getExe cfg.package; Restart = "on-failure"; };
      Install = { WantedBy = [ cfg.systemd.target ]; };
    };
  };
}
```

In flake outputs: `homeModules = { formalshell = ./nix/hm-module.nix; default = ./nix/hm-module.nix; };`

- [ ] **Step 2: Verify** — `git add -A && nix flake check` still green; eval-test the module: `nix eval --impure --expr 'let f = builtins.getFlake (toString ./.); in f.homeModules.formalshell != null'` → `true`.
- [ ] **Step 3: Commit** — `git add -A && git commit -m "feat(nix): home-manager module (enable/package/settings/systemd)"`

---

### Task 12: Docs — README, CLAUDE.md, architecture notes

**Files:**
- Modify: `README.md` (real content)
- Create: `CLAUDE.md`
- Create: `docs/ARCHITECTURE.md`
- Create: `docs/screenshots/bar-niri.png` (+ `bar-hyprland.png` if the nested-Hyprland smoke worked)

**Interfaces:**
- Consumes: everything built in Tasks 1–11 (describe what EXISTS, not the full spec's future).

- [ ] **Step 1: Capture README screenshots** — run `just smoke`, copy the freshest smoke PNG to `docs/screenshots/bar-niri.png` (Read it first: it must actually show the bar); same from `dev/smoke-hyprland.sh` → `bar-hyprland.png` if that smoke works. These are REQUIRED in the README (owner's standing instruction: README always carries current screenshots from the isolated testing env — refresh them whenever a later plan visibly changes the shell).
- [ ] **Step 2: README.md** — what it is (spec's opening paragraph), a `## Screenshots` section embedding `docs/screenshots/*.png` with a caption noting they come from the nested-niri/Hyprland isolated test sessions, status (pre-alpha, M1–M2 done: bar + compositor layer), install (flake input + homeModule snippet from Task 11), dev loop (`nix develop`, `just build/smoke/test/lint`), license, credits (QuickShell; Omarchy quattro as architectural inspiration; DMS MIT for ported service patterns).
- [ ] **Step 3: CLAUDE.md** — must contain, at minimum:
  - Standing orders: plans are created autonomously (no user approval gate); implementation/mapping/testing/docs run through subagent workflows; spec lives at `docs/superpowers/specs/`, plans at `docs/superpowers/plans/`; the spec wins over plans on conflict.
  - Verification loop: `just build` (remember `git add` first — flakes ignore untracked files), `just test` (headless qmltestrunner), `just lint`, `just smoke` (nested niri + screenshot — Read the PNG, don't assume), `dev/smoke-hyprland.sh` for the second backend.
  - Hard rules: pure QML/JS (no compiled companion, no node); opaque string ids; shell never writes settings.json; brutalist token constraints (radius 0, no blur/shadow, monospace alias, Nerd Font glyphs); the Nerd-Font-glyph Edit-corruption warning; MIT attribution header rule for DMS-ported code; commit style (conventional, lowercase, no co-author, no descriptions).
  - Reference repos and what each is for (omarchy quattro = architecture/UX reference — read, don't copy; DMS = MIT, portable with attribution; quickshell source/docs = ground truth for toolkit APIs).
- [ ] **Step 4: docs/ARCHITECTURE.md** — one page: process model, tree layout, the CompositorBackend contract (copy the exact interface block from Task 5), reducer data flow (socket → JSON line → reduce → facade → widgets), how to add a backend.
- [ ] **Step 5: Verify** — proofread against the actual tree (`fd . shell -t f`); every path and command mentioned must exist and run; confirm the README image links resolve (`ls docs/screenshots/`).
- [ ] **Step 6: Commit + push** — `git add -A && git commit -m "docs: readme with testing-env screenshots, claude.md, architecture notes" && git push -u origin main`

---

## Self-review notes (already applied)

- Spec coverage for M1–M2 only by design: theming engine (M3), menu (M4), notifications/OSD (M5), clipboard/panels (M6), media/lock/screensaver (M7), greeter (M8), polish (M9) are LATER plans — this plan must not grow into them. The Theme singleton here is deliberately the static-fallback subset the M3 engine will drive.
- Type consistency: contract names (`focusedWindowId`, `focusWorkspace(id)`, shapes) are defined once in Task 5 and referenced verbatim in Tasks 6–9; reducer state field names match the contract's.
- Known uncertainty is flagged inline where it exists (Singleton root type, qmllint import path, screenshot flag names, nested-Hyprland viability) with a discovery step, not a guess.
