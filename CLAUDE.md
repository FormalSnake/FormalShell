# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Standing orders

- Plans are created autonomously — no user approval gate before writing one.
- Implementation, mapping, testing, and docs all run through subagent
  workflows (one subagent per plan task, sequential, verification evidence
  required before commit — see `docs/superpowers/plans/`).
- The approved design lives at `docs/superpowers/specs/`. Plans live at
  `docs/superpowers/plans/`. **The spec wins over any plan on conflict.**

## Verification loop

- `just build` — `nix build .#formalshell`. **`git add` first**: flakes only
  see git-tracked files, so an unstaged file is invisible to the build.
- `just test` — headless `qmltestrunner` over `tests/` (`QT_QPA_PLATFORM=offscreen`).
- `just lint` — `nix flake check -L` (qml-tests + qmllint).
- `just smoke` — builds the shell, launches it inside an isolated **nested**
  niri session, screenshots that session, tears it down, and prints the PNG
  path. This is THE visual verification loop for any bar/surface change —
  **Read the PNG, don't assume it looks right.**
- `dev/smoke-hyprland.sh` — the same loop for the second backend (nested
  Hyprland, `hyprctl`/exec-once instead of niri's `spawn-at-startup`). Nested
  Hyprland is flakier than nested niri in a sandboxed dev environment; if it
  won't screenshot, fall back to verifying the backend via qmllint plus the
  `debug` IPC dump (`qs ipc call debug dump`) rather than skipping
  verification.

## Hard rules

- **Design language**: every UI surface follows `docs/DESIGN.md` (mek.gallery-derived
  ruled-ledger grid: shared hairline rules, cells not cards, inversion for
  selection, accent as full-bleed cells, uppercase meta labels, radius 0).
  Read it before building or restyling any surface.
- Pure QML/JS. No compiled companion binary. No Node/npm/bun anywhere.
- Compositor window/workspace ids are **opaque strings** end to end. Never
  parse, compare numerically, or assume stability. The one exception is the
  IPC wire boundary in each backend, where niri/Hyprland actions convert the
  string back with `Number(id)` (niri) or use the id verbatim (Hyprland hex
  addresses) — that conversion happens nowhere else.
- The shell only ever **reads** `~/.config/formalshell/settings.json`; it
  never writes it. Runtime-mutable state goes to
  `$XDG_STATE_HOME/formalshell/state.json`.
- Brutalist defaults, non-negotiable: corner radius `0`, no blur, no
  shadows, border width `2`, font = fontconfig `monospace` alias (never a
  hardcoded family name), icons = Nerd Font glyphs (no SVG icon sets).
- License MIT. Every file substantially ported from DankMaterialShell keeps
  a `// Portions from DankMaterialShell (MIT, Copyright 2025 Avenge Media LLC)`
  header line.
- ⚠️ Nerd Font glyphs are raw multi-byte codepoints; whole-file rewrites can
  corrupt them (Omarchy's `AGENTS.md` documents this). Use targeted `Edit`
  operations on files containing glyphs; never rewrite such files wholesale.
- Commits: conventional style, lowercase imperative subject
  (`feat(compositor): …`), no Co-Authored-By lines, no commit descriptions.
- Every task ends with its verification commands actually run and their
  output read. No claiming green without evidence.

## Reference repos

- `github.com/basecamp/omarchy` (branch `quattro`) — architecture/UX
  reference (single-process shell, unified surfaces, IPC contract patterns).
  Read, don't copy — treat as read-reference only; check its license before
  ever porting code from it.
- `github.com/AvengeMedia/DankMaterialShell` (MIT) — niri/Hyprland backend
  prior art and matugen orchestration patterns. MIT, so code can be ported
  directly, but every substantially-ported file needs the attribution
  header above.
- QuickShell source/docs (`git.outfoxxed.me/quickshell/quickshell`, pinned
  flake input) — ground truth for toolkit APIs (`Quickshell.Io.Socket`,
  `IpcHandler`, `Quickshell.Hyprland`, `Singleton`, …). When a QML/JS API's
  behavior is uncertain, read the C++ source or run the built `qs` binary
  rather than guessing.
