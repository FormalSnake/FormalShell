# FormalShell M3: Matugen Theme Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development semantics via the Workflow orchestrator — one subagent per task, sequential, verification evidence required, **push after every task commit** (owner follows along on GitHub).

**Goal:** Wallpaper-driven color: `formalshell` sets a wallpaper → matugen runs (user templates merged) → `theme.json` updates → every token in the running shell recolors live → niri window borders follow via a hot-reloaded KDL fragment. Light/dark flip included. Bar visibly recolors in the nested-niri smoke test.

**Architecture:** Pure-JS TDD'd core (config-builder, palette-mapper, KDL renderer) + thin QML service shells around them. `ThemeEngine` (singleton) owns a serialized matugen `Process` queue; `State` (singleton) owns `state.json` via `FileView`+`JsonAdapter`; `Theme` (existing singleton) gains a `FileView` watch on `theme.json` with the existing Flexoki statics as fallback. A `Background` layer surface displays the current wallpaper. All spec sections "Theming" and "Configuration" apply.

**Tech Stack:** matugen (nixpkgs), `Quickshell.Io` (Process/FileView/JsonAdapter), qmltestrunner for JS units.

**Spec:** `docs/superpowers/specs/2026-07-27-formalshell-design.md` (in-repo). Spec wins over plan. The M1–M2 plan's **Global Constraints all still apply** (`docs/superpowers/plans/2026-07-27-m1-m2-skeleton-and-compositor.md`), plus:

- Push to origin/main after every task commit (`git push`; SSH-agent warnings before a successful push are known noise on this host — verify with `git ls-remote origin main` if unsure, never force-push).
- `theme.json` and all engine outputs live under `$XDG_STATE_HOME/formalshell/` (default `~/.local/state/formalshell/`). Writes are atomic (`.tmp` + rename). `settings.json` stays read-only to the shell.
- matugen invocations must be serialized: one at a time, a newer pending request supersedes an older *pending* one (never kill a running process mid-write).

---

### Task 1: State singleton — `state.json`

**Files:**
- Create: `shell/Core/State.qml`
- Modify: `shell/Core/qmldir` (add `singleton State State.qml`)

**Interfaces:**
- Produces: singleton `State` (`import qs.Core`) with:
  - `property string wallpaper` (absolute path, "" if unset)
  - `property string mode` (`"dark"` | `"light"`, default `"dark"`)
  - `function setWallpaper(path: string)`, `function setMode(mode: string)`, `function toggleMode()` — each updates the property AND persists.
  - Persistence: `FileView` + `JsonAdapter` on `<state-dir>/state.json`, loaded at startup, written via `writeAdapter()` on every setter. Resolve the state dir via `Quickshell.statePath("state.json")` if available on the pinned quickshell (check `qs` docs/source — `Quickshell.statePath()` exists per upstream docs; verify) else `Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"` + `/formalshell/`.
  - `signal wallpaperChanged2()`-style extra signals are NOT needed — consumers bind to the properties.

**Steps:**
- [ ] Write State.qml (consult DMS `Common/SessionData.qml` for the FileView+JsonAdapter idiom; port pattern only, keep ours minimal).
- [ ] Verify: `just build` passes; run the built shell briefly against the host niri? NO — use nested smoke; then `qs ipc` not needed yet. Minimum: `nix flake check -L` green.
- [ ] Commit `feat(core): state singleton persisting wallpaper and mode to state.json`; push.

---

### Task 2: Matugen config builder (pure JS, TDD)

**Files:**
- Create: `shell/Theme/matugen.js` (`.pragma library`)
- Create: `tests/tst_matugen_builder.qml`

**Interfaces:**
- Produces:
  - `buildConfig(opts)` → string (TOML for `matugen -c`). `opts = { shellTemplateDir, stateDir, userConfigText (string|null), dropInTexts (list<string>), }`.
  - Merge order (spec-mandated, assert in tests): (1) `[config]` section extracted verbatim from `userConfigText` if present; (2) the shell's own `[templates.formalshell]` block: `input_path = <shellTemplateDir>/theme.json.tmpl`, `output_path = <stateDir>/theme.json.tmp`; (3) the shell's `[templates.formalshell-niri-border]` block: `input_path = <shellTemplateDir>/niri-border.kdl.tmpl`, `output_path = <stateDir>/niri-border.kdl.tmp`; (4) the user's `[templates]` section from `userConfigText` verbatim; (5) each `dropInTexts` entry appended verbatim.
  - `extractSection(text, name)` → string ("" if absent): returns the lines from `[name]`/`[name.` up to the next top-level section — needed because user config.toml mixes `[config]` and `[templates.*]`.

**Steps:**
- [ ] Write failing tests first:

```qml
import QtQuick
import QtTest
import "../shell/Theme/matugen.js" as M

TestCase {
    name: "MatugenBuilder"
    function test_merge_order() {
        var cfg = M.buildConfig({
            shellTemplateDir: "/shell/tpl", stateDir: "/state",
            userConfigText: "[config]\nreload_apps = true\n[templates.ghostty]\ninput_path = 'x'\n",
            dropInTexts: ["[templates.extra]\ninput_path = 'y'\n"]
        });
        var iCfg = cfg.indexOf("reload_apps");
        var iShell = cfg.indexOf("[templates.formalshell]");
        var iUser = cfg.indexOf("[templates.ghostty]");
        var iDrop = cfg.indexOf("[templates.extra]");
        verify(iCfg >= 0 && iCfg < iShell < iUser < iDrop === false ? (iCfg < iShell && iShell < iUser && iUser < iDrop) : (iCfg < iShell && iShell < iUser && iUser < iDrop));
        verify(cfg.indexOf("/state/theme.json.tmp") >= 0);
    }
    function test_no_user_config() {
        var cfg = M.buildConfig({ shellTemplateDir: "/t", stateDir: "/s", userConfigText: null, dropInTexts: [] });
        verify(cfg.indexOf("[templates.formalshell]") >= 0);
        verify(cfg.indexOf("[config]") === -1);
    }
    function test_extract_section() {
        var t = "[config]\na = 1\n[templates.x]\nb = 2\n";
        compare(M.extractSection(t, "config").indexOf("a = 1") >= 0, true);
        compare(M.extractSection(t, "templates").indexOf("b = 2") >= 0, true);
        compare(M.extractSection("", "config"), "");
    }
}
```

(Fix the sloppy comparison chain in test_merge_order when writing it for real — assert `iCfg < iShell && iShell < iUser && iUser < iDrop` plainly.)
- [ ] Run `just test` → fails (module missing). Implement. Run → green.
- [ ] Commit `feat(theme): matugen config builder with spec merge order (tdd)`; push.

---

### Task 3: Palette mapper + shipped matugen templates (TDD)

**Files:**
- Create: `shell/Theme/palette.js` (`.pragma library`)
- Create: `shell/Theme/templates/theme.json.tmpl`
- Create: `shell/Theme/templates/niri-border.kdl.tmpl`
- Create: `tests/tst_palette.qml`

**Interfaces:**
- Produces:
  - `theme.json` schema (written by matugen, read by Theme.qml): `{ "mode": "dark", "background": "#…", "backgroundAlt": "#…", "foreground": "#…", "foregroundDim": "#…", "accent": "#…", "urgent": "#…" }`.
  - `theme.json.tmpl` maps matugen M3 roles → schema: background=`{{colors.surface.default.hex}}`, backgroundAlt=`{{colors.surface_container.default.hex}}`, foreground=`{{colors.on_surface.default.hex}}`, foregroundDim=`{{colors.outline.default.hex}}`, accent=`{{colors.primary.default.hex}}`, urgent=`{{colors.error.default.hex}}`, mode=`{{mode}}` — **verify each placeholder against `matugen` docs/`matugen --help` and DMS's `matugen/templates/dank.json` before trusting; adjust to what matugen actually substitutes** (e.g. `{{mode}}` may not exist — if not, ThemeEngine passes mode out-of-band and the tmpl omits it).
  - `niri-border.kdl.tmpl`: a niri `layout { focus-ring { active-color "…" } border { active-color "…" inactive-color "…" } }` fragment using accent/foregroundDim placeholders — exact KDL node names verified against the owner's existing `~/.cache/dank/niri-border.kdl` (readable on this host) and niri wiki.
  - `palette.js`: `validate(themeObj)` → `{ ok: bool, missing: [string] }` (all six color keys present, `#`-hex format); `fallback()` → the static Flexoki object matching Theme.qml's current values (single source: Theme.qml will import THIS).
- **Steps:** failing tests for `validate`/`fallback` (valid obj passes; missing key reported; bad hex reported; fallback returns 6 valid colors + mode) → implement → green → commit `feat(theme): palette schema, validation, and shipped matugen templates (tdd)`; push.

---

### Task 4: ThemeEngine service — serialized matugen runs

**Files:**
- Create: `shell/Theme/ThemeEngine.qml`
- Create: `shell/Theme/qmldir` (`singleton ThemeEngine ThemeEngine.qml`)

**Interfaces:**
- Consumes: `State` (wallpaper/mode), `matugen.js`, `palette.js`.
- Produces: singleton `ThemeEngine` with `function retheme()` — reads `State.wallpaper`/`State.mode`, builds the merged config (reading `~/.config/matugen/config.toml` and `~/.config/formalshell/matugen.d/*.toml` via `FileView`/`Process` reads), writes it to `<state-dir>/matugen-merged.toml`, then runs `matugen image <wallpaper> -m <mode> -c <merged>` via `Quickshell.Io.Process`. On success: atomically rename `theme.json.tmp` → `theme.json` and `niri-border.kdl.tmp` → `niri-border.kdl` (a tiny `sh -c 'mv …'` process), then call `CompositorService.applyThemeFragment()`. Queue semantics: `running` flag + `pending` bool — a `retheme()` during a run sets pending; run end with pending → immediately rerun. Auto-trigger: `Connections` on `State.wallpaper`/`State.mode` changes. No wallpaper set → skip matugen, write `palette.fallback()` as theme.json so the pipeline stays uniform.
- **Verify matugen CLI form first** (`nix develop -c matugen --help`; `matugen image --help`): exact subcommand/flags, and whether `-t <scheme-type>` default is acceptable (use default scheme; scheme-type setting is a later option).
- **Steps:** implement → verify by hand-driving in nested niri (`--dump`-style: `qs ipc call theme retheme` comes in Task 6; for now, run the engine once at startup via `Component.onCompleted` if theme.json absent) → `just smoke` still passes → commit `feat(theme): serialized matugen engine writing theme.json atomically`; push.

---

### Task 5: Dynamic Theme singleton + Background surface

**Files:**
- Modify: `shell/Core/Theme.qml` (FileView watch on `theme.json`; colors become `property` driven by parsed file, falling back to `palette.fallback()` on absence/invalid per `palette.validate`)
- Create: `shell/Surfaces/Background/Background.qml` (per-screen `PanelWindow` on the **background** layer — `WlrLayershell.layer: WlrLayer.Background` via the panel's `aboveWindows: false`/layer property; verify the exact QuickShell property for background layer against Omarchy's background plugin or DMS's wallpaper surface — showing `State.wallpaper` as an `Image`, `fillMode: PreserveAspectCrop`, plain `Theme.color.background` fill when no wallpaper)
- Modify: `shell/shell.qml` (instantiate Background variants)

**Interfaces:**
- Produces: `Theme.color.*` now LIVE — all existing consumers (Bar, widgets) recolor automatically on theme.json change (they already bind). No consumer changes allowed — if a consumer needs touching, that's a defect in its original binding.

**Steps:** implement → `just build` + `just test` green → nested-niri visual check (`just smoke`): background layer shows (solid color, no wallpaper set yet), bar still renders → commit `feat(theme): live theme.json-driven tokens + background wallpaper layer`; push.

---

### Task 6: Theme/wallpaper IPC + niri fragment application

**Files:**
- Create: `shell/Ipc/ThemeIpc.qml` (`IpcHandler` target `theme`: `function retheme(): string`, `function mode(m: string): string` ("dark"/"light"/"toggle"), `function status(): string` → JSON of `{ wallpaper, mode, themeJsonPresent }`)
- Create: `shell/Ipc/WallpaperIpc.qml` (`IpcHandler` target `wallpaper`: `function set(path: string): string` (absolute-path check → `State.setWallpaper`), `function get(): string`)
- Modify: `shell/shell.qml` (instantiate), `shell/Compositor/niri/NiriBackend.qml` (implement `applyThemeFragment()`: send `{ Action: { LoadConfigFile: {} } }`? — **verify**: reloading the *current* config picks up the `include`d fragment; check niri-ipc Action enum for the no-path form (`LoadConfigFile { path: Option }` — pass null/omit) against niri source; HyprlandBackend keeps the no-op)

**Interfaces:**
- Produces: the user-facing contract: `formalshell` (or `qs -p … ipc call`) `wallpaper set /path/img.jpg` → full pipeline fires; `theme mode toggle` → relight. Documented niri user step: add `include "~/.local/state/formalshell/niri-border.kdl"` to niri config (create the file empty at engine startup if absent so the include never errors).

**Steps:** implement → end-to-end verify in nested niri: extend `dev/smoke-niri.sh` with a `--wallpaper <path>` mode that (a) generates a solid-color test PNG via ImageMagick or `nix run nixpkgs#imagemagick -- convert -size 640x480 xc:'#7a3fb0' /tmp/wp.png` inside the script, (b) calls `qs ipc … wallpaper set` in-session, (c) waits, screenshots. Read the PNG: background shows the purple wallpaaper, bar recolored away from Flexoki defaults. Assert `theme status` JSON too → commit `feat(theme): wallpaper/theme ipc and niri border fragment hot-reload`; push.

---

### Task 7: Review checkpoint artifacts — docs + screenshot refresh

**Files:**
- Modify: `README.md` (theming section: how colors flow, the niri `include` line, wallpaper IPC usage; refresh `docs/screenshots/bar-niri.png` from a `--wallpaper` smoke run so the README shows the matugen-recolored bar — owner's standing rule: README screenshots track the isolated test env)
- Modify: `docs/ARCHITECTURE.md` (ThemeEngine data-flow diagram: State → matugen(queue) → theme.json/niri-border.kdl → FileView → tokens / LoadConfigFile)
- Modify: `CLAUDE.md` (verification loop gains `just smoke --wallpaper`-equivalent and `matugen` notes)

**Steps:** write → verify every named path/command exists → commit `docs(theme): theming architecture, usage, refreshed screenshots`; push.

---

## Self-review notes (applied)

- Spec coverage M3 only: engine, merge order, serialization, live tokens, fallback statics, niri border sync, state split, background display. Static-scheme pinning (flexoki-pin equivalent) and the picker UI are M7 by the spec's build order — excluded here deliberately.
- Consumers must NOT change in Task 5 — that constraint is the proof M1's token design was right.
- Every externally-owned syntax (matugen placeholders/CLI, niri KDL node names, LoadConfigFile no-path form, background-layer property) is marked verify-first with a concrete source to check.
