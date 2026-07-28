# FormalShell M9: Polish sweep + e1504g trial + switchover gate

> **For agentic workers:** Workflow-driven per `docs/superpowers/workflow-template.md`.
> Read `CLAUDE.md` and `docs/DESIGN.md` first, both binding. This is the last
> milestone of the v1 build order.

**Goal:** Close the two loose ends M8b's review flagged, sweep motion and
tokens to one consistent system, then prove FormalShell on real hardware and
hand the owner a switchover decision backed by evidence rather than opinion.

**Spec build order item 9:** *"Polish pass (animation/token sweep), e1504g
daily-drive trial, switchover gate for the g815."*

## What M8b left open (both confirmed by its final review)

1. `Panel.qml` applies `panelPadding` on top and left only, so every panel and
   menu card renders an 18px gutter on two sides against a 2px rule on the
   other two. Visible in `panels-niri.png`, `calendar-niri.png`,
   `media-niri.png`, `menu-niri.png`. It reads as misaligned.
2. Legacy `Theme.font.*` is still used alongside the new rem-root
   `Theme.fontSize.*` (for example `Screensaver.qml:195`). Two sizing systems
   coexist, so a font-scale change only moves half the shell.

## Plan-wide constraints

- **Visual and structural polish only.** The owner's M8b scope pin still
  holds: features and functionality are correct, matugen support is
  load-bearing, nothing gets removed or narrowed for aesthetics. Report
  conflicts rather than resolving them.
- `CLAUDE.md` hard rules bind: radius 0, no blur outside the lock backdrop, no
  shadows, monospace via the fontconfig alias, Nerd Font glyphs only.
- Regression gate every task: `just test` green, `just vm-smoke --wallpaper`
  still recolours, and the smoke modes covering touched surfaces still pass.
- ⚠️ Quickshell percentage properties are 0..1, not 0..100. Shipped twice.
- ⚠️ A bare `State` identifier collides with QtQuick's `State`; import
  `qs.Core as Core`.
- ⚠️ Never reintroduce `ScreencopyView`, never hardcode `WAYLAND_DISPLAY`
  before launching a compositor, never hardcode a font family.
- ⚠️ Files carrying Nerd Font glyphs or block characters: targeted `Edit`
  only, verify bytes afterwards.

---

### Task 1: Card padding symmetry + token migration

**Files:** modify `shell/Components/Panel.qml`, `shell/Surfaces/Menu/Menu.qml`,
and every file still referencing `Theme.font.*`.

1. Fix the padding asymmetry so panel and menu cards read as deliberately
   inset on all four sides, without reintroducing the doubled border that
   `b044c8e` fixed (content's own bottom/right `Cell` rule must not draw a
   second line parallel to the frame's). Read that commit before touching it.
2. Migrate every remaining `Theme.font.*` call site to the reactive
   `Theme.fontSize.*` rem-root tokens, then make the absence checkable:
   `rg 'Theme\.font\.' shell/ greeter/` must return nothing except the family
   accessor, if one legitimately remains. State the exact command and its
   output in your evidence.

**Steps:** before screenshots, implement, after screenshots, Read both →
`just test`, `just vm-smoke --menu`, `--panel calendar`, `--panel media`,
`--wallpaper` → commit `fix(panels,theme): symmetric card padding and a single font scale`; push.

---

### Task 2: Motion sweep

**Files:** modify `shell/Core/Theme.qml` and any surface with an ad hoc
duration or easing.

DESIGN.md's motion rule is instant or near-instant colour transitions
(120–200ms), with the breathing pulse the only "alive" idiom, and nothing
sliding, bouncing or zooming. Audit every animation in the shell against it:
collect durations and easings into named theme tokens, remove anything that
moves geometry, and keep the screensaver's continuous effect and the charging
pulse as the two documented carve-outs.

**Produces:** a small set of motion tokens on `Theme`, every call site using
them, and a grep-checkable absence of raw numeric durations in surfaces.

**Steps:** implement → `just test` → smoke the surfaces with the most motion
(`--notify`, `--osd`, `--menu`, `--panel audio`) and Read the PNGs to confirm
nothing regressed visually → commit `fix(theme): collect motion into tokens and drop geometry animations`; push.

---

### Task 3: e1504g real-hardware verification sweep

**Files:** none in the shell. This task produces evidence.

The e1504g is ONLINE and is the spec's designated trial host. It has what the
VM cannot: a real battery (`BAT0`/`AC0`), a real backlight (`intel_backlight`),
real Wi-Fi, real Bluetooth and a real GPU. Its store already contains a built
quickshell from an earlier run.

**You are authorised to ssh to e1504g for this task ONLY**, with:
`ssh -o BatchMode=yes -o IdentityAgent=none -i ~/.ssh/id_ed25519 e1504g bash -s <<'EOF' ... EOF`
(its login shell is fish, so always drive it through `bash -s`).

**Permitted there:** `git -C ~/Developer/FormalShell pull`, `nix build`,
running `dev/smoke-niri.sh` with any flags, and copying artifacts back.
**Forbidden there, no exceptions:** `nixos-rebuild`, `home-manager switch`,
any change to the owner's nix config repo, changing or killing their live niri
session, running the shell or ThemeEngine outside the nested smoke session,
and any write outside `~/Developer/FormalShell` and `~/fs-*`.

The smoke script is safe on a live host by design: it nests its own niri, runs
under an isolated `HOME`/`XDG_*` so ThemeEngine cannot re-fire the owner's own
matugen post-hooks, wraps everything in `dbus-run-session`, and asserts the
host's `org.freedesktop.Notifications` owner PID is unchanged before and after.
`--wallpaper` is therefore safe now; the isolated `HOME` is precisely the fix
for the 2026-07-27 incident.

Note the machine has 7GB RAM with roughly 1GB free, so cap build parallelism
(`nix build --cores 4`) and do not run builds concurrently with the sweep.

**Run every mode** and pull each artifact back to `artifacts/e1504g/` on the
mac: plain, `--dump`, `--wallpaper`, `--menu`, `--notify`, `--notify --center`,
`--osd`, `--clipboard`, `--media`, `--lock`, `--screensaver`, `--picker`, and
`--panel` for audio, network, bluetooth, power, calendar and media.

**Read every PNG on the mac** and compare against the VM equivalents. The
populated states are the whole point: a real battery percentage in the bar and
power panel, a real backlight percentage in the OSD and `--dump`, a populated
Wi-Fi list with real signal strength (the 0..1 scaling fix must show a
plausible percentage, not 1%), real Bluetooth devices. Any surface that looks
right in the VM but wrong here is a finding.

**Steps:** sweep → Read every PNG → commit the artifacts index or findings as
`docs/superpowers/plans/2026-07-28-m9-e1504g-trial.md` with what passed, what
differed from the VM, and any defect found; push.

---

### Task 4: Fix whatever task 3 found

**Files:** whatever the findings implicate.

Real hardware has already produced two defects the VM structurally could not
(the Wi-Fi 0..1 scale error and the title-case UPower state). Expect more. Fix
each, re-verify on e1504g, and record it.

If task 3 found nothing, say so plainly and skip with evidence rather than
inventing work.

**Steps:** fix → re-run the affected modes on e1504g → Read the PNGs → commit
`fix: <what real hardware exposed>`; push.

---

### Task 5: Switchover readiness report + install path

**Files:** create `docs/SWITCHOVER.md`; modify `README.md`.

**Produces:** an honest readiness assessment the owner can act on:
1. **Parity table** against the spec's surface list: every surface, whether it
   is verified on real hardware, in the VM only, or unverified, with the
   evidence for each.
2. **Known gaps and rough edges**, stated plainly. Anything that only ever ran
   under llvmpipe, anything with no real backend on either host, anything
   deferred (EDS calendar events, RRULE expansion, the Hyprland backend's
   flakiness).
3. **The exact install path** for daily-driving it: the `nixosModules.formalshell`
   and `formalshell-greeter` wiring, the home-manager module, and the one
   command the owner runs. Do NOT run it, and do not modify the owner's nix
   config repo. This is the gate; the decision is the owner's.
4. **What "parity with DMS" would still require**, so the g815 switchover has
   a defined bar rather than a feeling.

**Steps:** write it against real evidence, verify every documented command that
is safe to run → commit `docs(switchover): readiness report and install path`; push.

---

## Then

v1 build order is complete. The daily-drive decision and the g815 switchover
are the owner's calls, made against Task 5's report.
