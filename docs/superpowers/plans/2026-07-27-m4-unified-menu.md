# FormalShell M4: Unified Menu — Implementation Plan

> **For agentic workers:** Workflow-driven: one subagent per task, sequential, verification evidence required, push after every task commit. Read `CLAUDE.md` and **`docs/DESIGN.md`** (binding for every visual in this plan) before starting any task. M1–M2 plan Global Constraints still apply.

**Goal:** Omarchy-style unified menu as a ruled-ledger surface: one hierarchical JSONC tree that is app launcher + system menu + power menu (with the owner's configurable custom power buttons) + a generic `select`/`input` dmenu-replacement — fuzzy-searchable, fully keyboard-driven, every route summonable by IPC for direct compositor keybinds (`super+ñ` → clipboard later), themed by the live matugen tokens.

**Architecture:** Pure-JS TDD'd core (JSONC parse/merge/tree, tiered fuzzy scorer) + QML surface. New `Config` singleton (read-only watched `settings.json`) supplies user overrides + custom power buttons. New ledger primitives in `Components/` (Cell, meta-label, list keyboard nav) become the shared building blocks for every later surface (panels, notifications). Menu window is a keyboard-exclusive top-layer surface on the focused screen.

**Spec:** `docs/superpowers/specs/2026-07-27-formalshell-design.md` §Surfaces(3) + `docs/DESIGN.md` §Concrete translations (Menu). Spec/DESIGN win over plan.

## Plan-wide constraints

- Every visual follows DESIGN.md: cells sharing hairline rules, cursor row = fg/bg inversion, accent as full-bleed cells only, uppercase meta labels (`Theme.font.caption`), spacing `sm`/`md`, radius 0, no new animation beyond 120–200ms color transitions.
- Menu data: default tree shipped at `shell/Menu/default-menu.jsonc`; user file `~/.config/formalshell/menu.jsonc` merged **per-key over** the default (user wins; a user entry with `"hidden": true` removes a default entry).
- All shell-condition strings (`when`, `checked`) execute via `Quickshell.Io.Process` with `["sh", "-c", cond]`, batched at menu-open, never per-keystroke.
- Push after every commit (verify with `git ls-remote` on odd output; never force-push). If a push is denied by the permission classifier, note it in the report and continue — the orchestrator pushes for you afterwards.

---

### Task 1: Ledger token additions

**Files:** Modify `shell/Core/Theme.qml`, `shell/Theme/palette.js`, `shell/Theme/templates/theme.json.tmpl`, `tests/tst_palette.qml`.

**Produces (exact names):**
- `Theme.color.rule` — divider color: from theme.json `rule` key (new tmpl line: matugen `{{colors.outline.default.hex}}`); fallback = Flexoki `#403E3C`.
- `Theme.color.onAccent` — text on accent cells: tmpl `{{colors.on_primary.default.hex}}`; fallback `#FFFCF0`.
- `Theme.font.display` — family string, defaults to `Theme.font.family` (user-overridable later; just the slot now).
- `Theme.inverted()` → `{ bg: <foreground>, fg: <background> }`.
- `Theme.label` convention: meta rows use `font.pixelSize: Theme.font.caption`, `font.capitalization: Font.AllUppercase`, `font.letterSpacing: 1`, color `foregroundDim` — encode as a reusable component in Task 4 (not here; here only tokens).
- `palette.js`: `validate` now requires `rule` and `onAccent` too; `fallback()` gains both. Update tests first (red), then implement (green). theme.json consumers must stay backward-tolerant: `Theme` falls back per-key (missing `rule` in an old theme.json → Flexoki value), not whole-file.

**Steps:** red tests → implement → `just test` green → `just lint` green → commit `feat(theme): ledger tokens — rule, onAccent, display slot, inversion helper`; push.

---

### Task 2: Config singleton (settings.json, read-only)

**Files:** Create `shell/Core/Config.qml`; modify `shell/Core/qmldir` (`singleton Config Config.qml`).

**Produces:**
- Singleton `Config` watching `~/.config/formalshell/settings.json` (FileView `watchChanges: true` + the M3-proven bounded retry for not-yet-existing files; `Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"`). **Never writes.**
- `readonly property var settings` — parsed object, `{}` on absence/parse error (log a warning with the parse error, keep last good value on re-parse failure).
- `function get(path, fallback)` — dotted-path lookup: `Config.get("menu.customPowerButtons", [])`.
- Documented v1 keys (README later): `menu.customPowerButtons: [{ label, icon, command, confirm? }]`, `bar.position` (reserved), `theme.fontDisplay` (reserved).

**Steps:** implement → verify: `just build`; in-tree quick check via a temporary qmltestrunner-compatible pure-JS extraction is NOT required (FileView is env-dependent) — instead verify live in nested niri: `dev/smoke-niri.sh --dump`-style run with an isolated-HOME settings.json fixture containing a marker key, extend `debug dump` to include `configLoaded: Config.settings` marker presence. Commit `feat(core): read-only watched settings.json config singleton`; push.

---

### Task 3: Menu model core (pure JS, TDD)

**Files:** Create `shell/Menu/model.js`, `tests/tst_menu_model.qml`.

**Produces (`.pragma library`):**
- `parseJsonc(text)` → object. Strips `//` line comments (not inside strings) and trailing commas, then `JSON.parse`. Throw on hard syntax errors.
- `buildTree(defaultObj, userObj)` → `{ rootIds: [id], nodes: { id: Node } }` where `Node = { id, parentId|null, label, icon (string, may be ""), title, aliases: [..], kind: "action"|"link"|"submenu"|"provider", action?, target?, provider?, when?, checked?, confirm?: bool, childIds: [..] }`.
  - Keys are dotted ids implying hierarchy (`system.power.reboot` under `system.power` under `system`); parents auto-created as submenus if not declared.
  - Kind inference (Omarchy semantics): `action` key → action; `target` → link; `provider` → provider; else submenu.
  - User merge: per-id, user keys override default keys; `hidden: true` drops the node (and its subtree).
- `visibleChildren(nodes, id, condResults)` → `[Node]` — filters `when`-guarded nodes by `condResults[id] === true` (undefined → visible), **self-pruning**: a submenu/link with zero visible children is itself invisible, recursively.
- Test cases (write first, all red): dotted-id hierarchy with auto-parents; kind inference for all four kinds; user override of a default label; `hidden` removing a subtree; self-pruning cascade (a `when`-hidden leaf empties its parent chain); jsonc comment + trailing-comma stripping; comment-like text inside a string preserved.

**Steps:** red → implement → green (`just test`) → commit `feat(menu): jsonc tree model with per-key user merge and self-pruning (tdd)`; push.

---

### Task 4: Search scorer (pure JS, TDD) + ledger primitives

**Files:** Create `shell/Menu/search.js`, `tests/tst_menu_search.qml`, `shell/Components/Cell.qml`, `shell/Components/MetaLabel.qml`, `shell/Components/qmldir`.

**Produces:**
- `search.js`: `score(node, query, depth, declIndex)` → int (0 = no match) with Omarchy's tiers: exact label (1000, +100 root bonus) > label starts-with (800) > label contains (600) > alias/id-slug match (400) > word-boundary match in title/description (200); ties break by shallower depth then declaration order; `kind === "app"` rows rank one tier below equally-scored menu rows (implement as a flat −50). `rank(nodes, query, condResults)` → sorted `[Node]` capped at 40.
- `Cell.qml`: THE ledger cell — `property bool selected` (inversion via `Theme.inverted()`), `property bool accent` (full-bleed accent + `onAccent` text), hover state via `Theme.control("hover")`, shared-rule layout contract: cell draws only its **bottom and right** rule (`Theme.color.rule`, `Theme.borderWidth`); the container draws the top/left outer rule — this is how adjacent cells share one border. Content via default property.
- `MetaLabel.qml`: the uppercase caption label per DESIGN.md (Task 1's conventions).
- Scorer tests first (red→green): each tier ordering, root bonus, depth tiebreak, app demotion, cap.

**Steps:** red → implement → green → `just build` → commit `feat(menu): tiered fuzzy scorer (tdd) + ledger cell primitives`; push.

---

### Task 5: Menu surface

**Files:** Create `shell/Surfaces/Menu/Menu.qml`, `shell/Surfaces/Menu/MenuRow.qml`; modify `shell/shell.qml` (instantiate one Menu, not per-screen — it opens on the focused screen at summon time).

**Produces:**
- A centered top-layer window (`WlrLayershell.layer: Top`, `keyboardFocus: Exclusive` while open, width ~560px logical, max-height 60% of screen, on `CompositorService.focusedOutputName`'s screen — fall back to first screen), visually per DESIGN.md: outer rule border, column of cells; top cell = search input (mono text, blinking block cursor fine); below = rows from `search.rank()` when query non-empty else `visibleChildren()` of the current node; title/breadcrumb as a MetaLabel meta row (`MENU / SYSTEM / POWER` style).
- `MenuRow.qml` = `Cell` with icon glyph + label + (for submenus) a `▸`-style mono indicator; `checked` condition true → `✓` suffix cell text.
- Keyboard: up/down move cursor (wraps), enter activates, esc closes (or pops one level if inside a submenu), backspace on empty query pops level, typing filters live (search across the WHOLE tree, not just current level — Omarchy semantics). Mouse: hover moves cursor, click activates.
- Activation: `action` → `CompositorService.spawn(["sh","-c",action])` + close; `submenu`/`link` → descend (link jumps to target node); `provider` → descend into provider-populated children (Task 6); `confirm: true` actions require a second enter — the row label swaps to `CONFIRM <label>?` in an accent cell until cursor moves.
- `when`/`checked` conditions batched: on open (and on level descend), run each visible node's condition via one Process per condition (bounded: only current level + search results), results cached per menu-open session in a JS object passed to `visibleChildren`/`rank`.
- Open/close API on the component: `function open(route)`, `function close()`, `property bool isOpen`. Route = node id or alias; unknown route → open at root.

**Steps:** implement → verify visually: add `--menu` mode to `dev/smoke-niri.sh` (summon via IPC after Task 7? IPC not built yet — for this task use a temporary `Component.onCompleted` env-gated auto-open: `FORMALSHELL_SMOKE_OPEN_MENU=1` env → open at root; keep it, it's harmless and useful) → screenshot: menu grid visible over wallpaper, cells share single rules, cursor row inverted. Read the PNG. Commit `feat(menu): ledger menu surface with keyboard nav and confirm gates`; push.

---

### Task 6: Providers + default tree + power submenu

**Files:** Create `shell/Menu/providers.js`, `shell/Menu/default-menu.jsonc`; modify `shell/Surfaces/Menu/Menu.qml` (provider wiring).

**Produces:**
- `providers.js`: `appsProvider()` → nodes from `DesktopEntries.applications` (Quickshell built-in; verify exact API — `DesktopEntries.applications.values` list of DesktopEntry with `name`, `icon`, `execute()`): id `apps.<desktop-id>`, kind `"app"` (the scorer's demoted kind), activation via `entry.execute()` (NOT sh -c — respects .desktop semantics).
- `default-menu.jsonc` (root order): `apps` (provider), `system` submenu — `system.lock` (action: `qs ipc call lock lock` — placeholder until M7, `when: "false"` hides it for now), `system.suspend` (`systemctl suspend`), `system.reboot` (`systemctl reboot`, `confirm: true`), `system.shutdown` (`systemctl poweroff`, `confirm: true`), `system.logout` (compositor-aware later; v1 `niri msg action quit --skip-confirmation` with `when` guarding on niri) — **plus custom power buttons from `Config.get("menu.customPowerButtons", [])` appended as `system.custom.N` action nodes at tree-build time** (label/icon/command/confirm from the entry; the owner's Windows-reboot shortcut is the canonical case). `theme` submenu — `theme.mode-toggle` (action: internal, see below), `theme.wallpaper` (reserved, `when: "false"`).
- Internal actions: support `"action": "@ipc:theme.toggleMode"`-style internal dispatch (prefix `@ipc:` → call the in-process function directly instead of spawning; map `theme.toggleMode` → `Core.State.toggleMode()`); document the convention in the file header comment.
- Wire into Menu.qml: provider descend calls `providers.appsProvider()`; tree rebuild on `Config.settings` change.

**Steps:** implement → nested-niri smoke with `--menu`: screenshot shows apps listed (nested session has .desktop entries from the isolated env — seed one fixture .desktop file in the smoke script's isolated XDG_DATA_HOME so the list is deterministic) and typing filters (drive via a second summon? keyboard injection is not scriptable here — visual check of the open menu + a `menu` debug dump of ranked results for a query via a `function query(q): string` debug hook on the `debug` IPC target) → commit `feat(menu): apps provider, default tree, config-driven custom power buttons`; push.

---

### Task 7: Menu IPC + select/input modes

**Files:** Create `shell/Ipc/MenuIpc.qml`; modify `shell/shell.qml`, `shell/Surfaces/Menu/Menu.qml`.

**Produces:**
- `IpcHandler { target: "menu" }`: `toggle(route: string): string`, `summon(route: string): string` (always opens), `close(): string`, `refresh(): string` (re-read default+user jsonc + config), `ping(): string`.
- Select/input modes (the dmenu replacement): `select(prompt: string, optionsJson: string): string` — opens the same surface in select mode listing the JSON array of option strings; the chosen option is written to `<state-dir>/menu-selection.txt` (atomic) and `select` requests are correlated by a caller-passed token: `select(prompt, optionsJson, token)` writes `{token, value}` JSON — callers poll/read the file. `input(prompt: string, token: string): string` — freeform text cell instead of options. (qs ipc calls are synchronous request/response but can't block on UI; the file+token contract sidesteps that — document it in the handler's comment and README later. A future `qs ipc wait` listener can replace polling.)
- Escape in select/input mode writes `{token, cancelled: true}`.

**Steps:** implement → verify in nested niri: `--menu` mode now uses `qs ipc … call menu summon ""` instead of the env auto-open (keep the env hook too); test `menu select` end-to-end in-session: spawn `qs ipc call menu select "Pick" '["a","b","c"]' tok1`, screenshot shows the select list, then (no keyboard injection available) verify cancel path by calling `menu close` and reading the `{cancelled:true}` file. Commit `feat(menu): ipc summon/toggle routes and select-input dmenu modes`; push.

---

### Task 8: Docs + screenshots

**Files:** Modify `README.md`, `docs/ARCHITECTURE.md`, `CLAUDE.md`; add `docs/screenshots/menu-niri.png`.

**Steps:**
- Capture `docs/screenshots/menu-niri.png` from the `--menu` smoke (menu open over the recolored wallpaper — Read it: ledger cells, inverted cursor row, uppercase breadcrumb).
- README: "Menu" section — the tree model, `~/.config/formalshell/menu.jsonc` per-key merge with `hidden`, custom power buttons example (the owner's real case:
  `{"label": "Windows", "icon": "󰖳", "command": "systemctl reboot --boot-loader-entry=auto-windows", "confirm": true}`),
  direct-summon keybind example for niri (`Mod+Ntilde { spawn "formalshell-ipc" "menu" "summon" "clipboard"; }` — express with the actual `qs ipc` CLI form the smoke scripts use), select/input scripting contract.
- ARCHITECTURE: menu data flow (jsonc → model → cond batch → rank → cells) + the Cell shared-rule contract (bottom/right rules only).
- CLAUDE.md: add `--menu` smoke mode to the verification loop.
- Verify every documented path/command; commit `docs(menu): menu usage, custom power buttons, refreshed screenshots`; push.

---

## Self-review notes (applied)

- DESIGN.md compliance is enforced structurally: all rows/cells go through `Components/Cell.qml` (Task 4), so the review checkpoint greps for `Rectangle`-with-border outside Components/ as drift evidence.
- Custom power buttons come from Config (Task 2) at tree-build (Task 6) — satisfying the spec's "first-class, not a workaround" requirement and the owner's Windows-reboot case verbatim.
- Clipboard/emoji providers are M6 by the spec build order; the menu only needs routes to exist for them later — no stubs shipped now.
- Keyboard-injection limits in nested sessions are acknowledged: interaction coverage comes from the model/scorer unit tests + visual open-state screenshots + IPC-driven mode switches, not fake claims.
