# R0: Rust spike

Goal: prove or kill the stack in `specs/2026-10-06-rust-rewrite.md` before
any port starts. Output is numbers from e1504g, not a usable shell.

Facts this plan rests on (checked 2026-10-06):

- QML baseline on e1504g: 556 MB RSS, ~30% of one core idle with a herdr
  spinner live, 22% on `QSGRenderThread`.
- `smithay-client-toolkit` 0.21.1, `vello_cpu` 0.3.0, `parley` 0.11.1,
  `taffy` 0.14.0, `calloop` 0.14.5 are current on crates.io.
- `dev/smoke.sh` already nests Hyprland on a real host, so e1504g can run
  the spike in a nested session without touching the live one.

## Task 1: workspace and flake build

- `crates/Cargo.toml` workspace with one binary crate `formalshell-rs`.
- Flake output `packages.<system>.formalshell-rs` via `rustPlatform`,
  building for aarch64-linux (VM) and x86_64-linux (e1504g).
- Verify: `nix build .#packages.aarch64-linux.formalshell-rs` from the mac.

## Task 2: a strip that never redraws at rest

- One layer surface on the top edge, height and colours from the
  `metamorphosis` table, exclusive zone set.
- Retained scene with per-node damage, `vello_cpu` into double-buffered
  shm, `damage_buffer` per dirty rect, frame callbacks only while
  something animates.
- A clock cell (minute updates on a timer aligned to the minute) and the
  workspace pills from `.socket2.sock` events.
- Verify: a run under `dev/smoke.sh FS_IMPL=rust` in the VM, frame read
  by eye against a QML frame of the same layout.

## Task 3: the spinner and one panel

- The herdr badge spinning on the real pulse duration, damaging only its
  own rect.
- One cell opening one panel through the joined shape on the QML spring
  constants, pantheon's blurred cast drawn with `vello_cpu` (or reported
  missing).
- A full-output 0.5 black scrim fading in, CPU raster.

## Task 4: measure on e1504g

- In a nested session on e1504g: CPU over 60 s idle, over 60 s with the
  spinner, per-frame times through ten panel opens and ten scrim fades,
  RSS after 10 minutes, cold start to first commit.
- The same five numbers for the QML shell under the same nesting.
- Write the table into this file. If a budget fails, say which and stop
  before R1.
