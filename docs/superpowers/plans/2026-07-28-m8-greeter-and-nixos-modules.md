# FormalShell M8: Greeter + NixOS modules — Implementation Plan

> **For agentic workers:** Workflow-driven per `docs/superpowers/workflow-template.md`
> — one subagent per task, sequential, verification evidence required, push
> after every task commit (classifier-denied pushes: note and continue). Read
> `CLAUDE.md` and `docs/DESIGN.md` first — both binding. The spec
> (`docs/superpowers/specs/2026-07-27-formalshell-design.md` §Surfaces 9, §Nix)
> wins over this plan on any conflict.

**Goal:** FormalShell becomes installable as a complete system, not just a
user shell: a greeter entry point on greetd that looks like the lock screen,
plus the two NixOS modules the spec calls for — including the system-side
prerequisites M6 and M7 quietly created but could not declare.

**Why the modules are in scope here, not deferred:** M6's `LocationService`
needs `services.geoclue2` with an agent, and M7's lock screen needs a
`security.pam.services.<name>` entry. Neither can be done from home-manager;
both are currently only satisfied by hand-edits in `nix/testvm.nix`, which
means a real installation of FormalShell today has a broken lock screen and a
geoclue that never answers. `nixosModules.formalshell` is where that debt gets
paid.

## Spec-mandated flake outputs after this milestone

| Output | Status before M8 | After |
| --- | --- | --- |
| `packages.<system>.formalshell` | exists | unchanged |
| `packages.<system>.formalshell-greeter` | **missing** | Task 1 |
| `homeModules.formalshell` | exists | Task 3 may extend |
| `nixosModules.formalshell` | **missing** | Task 3 |
| `nixosModules.formalshell-greeter` | **missing** | Task 4 |
| `devShells.default`, `checks.<system>.qmllint` | exist | unchanged |

## Plan-wide constraints

- **DESIGN.md is binding.** The greeter is the lock screen's twin: oversized
  clock in `Theme.font.display`, one bordered ledger input cell, uppercase
  meta labels, radius 0, flat. It shares `Core/` and `Theme/` with the main
  shell — if you find yourself duplicating a Theme token or a Cell, stop and
  share instead.
- **Never break the running shell to build the greeter.** `shell.qml` and
  `greeter.qml` are separate entry points over shared code; a change to
  `Core/` must keep `just test` and the existing smoke modes green.
- The greeter runs as the `greeter` user before any user session exists. It
  cannot read `$XDG_STATE_HOME/formalshell/state.json` of a real user and must
  not try — theme comes from a system-readable path or falls back to the
  Flexoki defaults. State that choice explicitly in the docs.
- **Honest unavailable states, never faked.** If the greeter cannot enumerate
  sessions or users on the test system, it shows that honestly.
- Nerd Font glyphs: targeted `Edit` operations only, codepoints from the font
  cmap.
- Smoke script changes are additive only. `dev/smoke-niri.sh` must stay
  byte-compatible with Linux-host use — the g815 is back online and runs it
  unchanged, so this is a live requirement.
- ⚠️ Quickshell percentage/fraction-shaped properties are 0..1, not 0..100
  (see `CLAUDE.md`) — this has already caused two shipped bugs.

---

### Task 1: `greeter.qml` entry point + `formalshell-greeter` package

**Files:** create `greeter/greeter.qml`, `greeter/qmldir` (if the layout needs
it), `nix/greeter-package.nix`; modify `flake.nix`.

**Produces:**
- A `greeter.qml` entry point on `Quickshell.Services.Greetd` — **verify the
  module's real API against the built quickshell's qmltypes and C++ source
  before writing** (`Quickshell.Services.Greetd` is confirmed present but its
  signatures have never been used in this project). It renders the lock
  screen's visual language: oversized clock, date subline, one bordered input
  cell, an uppercase error meta row on failed auth.
- Session and user selection **only if greetd actually exposes them**; if the
  service does not enumerate sessions, render the configured default and say
  so in the docs rather than inventing a picker.
- `packages.<system>.formalshell-greeter`: the same `makeWrapper` pattern as
  the main package but pointing at the greeter entry point. Read
  `nix/package.nix` and factor shared logic rather than copy-pasting a second
  divergent wrapper.

**Steps:** implement → `git add -A && nix build .#packages.aarch64-linux.formalshell-greeter`
→ confirm the wrapper script contains the right `-p` path and QML import
paths → `just test` + `just vm-lint` green → commit
`feat(greeter): greetd entry point and formalshell-greeter package`; push.

---

### Task 2: Greeter renders and authenticates in the VM

**Files:** modify `nix/testvm.nix`, `dev/smoke-greeter.sh` (new — a sibling of
the existing smoke scripts, not a flag on `smoke-niri.sh`, since it drives a
different session model), `justfile`.

**Produces:** a real greetd instance inside the test VM whose session command
launches a nested headless compositor running the greeter, screenshotted and
driven to a successful authentication with the VM's throwaway `test` password
(the same credential M7's `--lock` mode uses).

This is the task most likely to fight back. Verify-first: read how greetd
expects to be configured, what `GREETD_SOCK` the greeter needs, and how the
existing `dev/smoke-niri.sh` nests a compositor — then compose the two. If a
full greetd round trip proves impossible headlessly after 3 genuinely
distinct approaches, fall back to launching `greeter.qml` against a **real
greetd socket** with the session command stubbed, prove the auth exchange
over that socket, and record precisely what was and was not exercised. Do not
downgrade to "it renders" and call that done.

**Steps:** implement → `just vm-greeter` → **Read the PNGs**: the greeter
showing its clock and input cell, and the post-authentication state → paste
the greetd log lines proving the auth exchange happened → commit
`feat(greeter): greetd smoke rig with real authentication`; push.

---

### Task 3: `nixosModules.formalshell`

**Files:** create `nix/nixos-module.nix`; modify `flake.nix`, `nix/testvm.nix`.

**Produces:** the system-side prerequisites module the spec names, covering
everything the shell needs that home-manager cannot provide:
- `services.geoclue2.enable` **plus its agent**, for M6's `LocationService`
  default source (the spec calls this out specifically).
- `security.pam.services.<name>` for M7's lock screen, with the service name
  matching what `Lock.qml` actually passes to `PamContext` — read the source,
  do not assume.
- Any other system-side dependency the shell has accumulated (audit
  `nix/testvm.nix` for hand-added services that exist only to make the shell
  work: NetworkManager, bluez, upower, power-profiles-daemon, pipewire — decide
  for each whether it is a genuine FormalShell prerequisite or merely part of
  the test rig, and justify the split in the module's comments).
- Options in the established nix-darwin/home-manager style
  (`enable`, `package`), with sane defaults.

Then **make `nix/testvm.nix` consume the module** instead of duplicating those
service declarations by hand — that is the proof the module actually works,
and it keeps the rig honest about what a real install requires.

**Steps:** implement → `just vm-down && just vm-up` with the VM now importing
the module → re-run `just vm-smoke --lock` and `just vm-smoke --panel network`
to prove PAM and the system services still work through the module → commit
`feat(nix): nixosModules.formalshell with geoclue and pam prerequisites`; push.

---

### Task 4: `nixosModules.formalshell-greeter`

**Files:** create `nix/nixos-greeter-module.nix`; modify `flake.nix`,
`nix/testvm.nix`.

**Produces:** the greetd wiring module — `services.greetd.enable`, its
`settings.default_session` pointing at the greeter package, the compositor it
runs under, and the `greeter` user's environment. Options for the session
command a successful login should launch, so the module is usable by someone
who is not the owner.

The test VM then enables this module and Task 2's smoke rig runs against the
**module-configured** greetd rather than a hand-rolled one — same proof
strategy as Task 3.

**Steps:** implement → `just vm-down && just vm-up` → `just vm-greeter` green
against the module-driven greetd, PNGs Read again → confirm the normal
`--lock` and plain smoke modes still pass (the VM must not have become a
greeter-only box) → commit
`feat(nix): nixosModules.formalshell-greeter wiring greetd`; push.

---

### Task 5: Docs + screenshots

**Files:** modify `README.md`, `docs/ARCHITECTURE.md`, `CLAUDE.md`; add
`docs/screenshots/greeter-niri.png`.

**Steps:**
- Screenshot pulled from the VM and **Read before publishing**.
- README: a real **installation** section — the two NixOS modules, the
  home-manager module, what each provides, and a minimal working
  `flake.nix` snippet for someone adopting FormalShell. State plainly that the
  lock screen needs the NixOS module (or an equivalent hand-written PAM
  service) and that geoclue needs its agent.
- ARCHITECTURE: the greeter entry point alongside `shell.qml`, what they
  share, and the greetd flow.
- CLAUDE.md: the `just vm-greeter` verification loop entry.
- Verify every documented command by running it. Commit
  `docs(greeter): greeter, nixos modules, and installation`; push.

---

## Then

**M9** — the polish pass: the ledger retrofit of the M1–M3 surfaces (bar,
workspaces, active window) that predate `docs/DESIGN.md`, an animation/token
sweep, then the e1504g daily-drive trial and the g815 switchover gate.

**M9's last two items cannot be closed from the macbook.** The retrofit and
the sweep can. The trial and the gate are judgment calls on hardware the owner
uses daily — e1504g is currently offline, and the g815 is back but is the
switchover *target*, not the trial host. Plan M9 to deliver everything up to
that boundary and hand the gate over explicitly.
