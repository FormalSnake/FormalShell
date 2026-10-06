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

- Never build on e1504g. Build both shells' closures on g815 and copy
  them over (`nix copy --to ssh://e1504g`), then run nested.
- In a nested session on e1504g, in power saver: CPU over 60 s idle, over 60 s with the
  spinner, per-frame times through ten panel opens and ten scrim fades,
  RSS after 10 minutes, cold start to first commit.
- The same five numbers for the QML shell under the same nesting.
- QML baseline for the launcher stall: time from `menu toggle` to the
  launcher's first frame, and the longest gap between bar frames while a
  herdr spinner runs across that open. R4 is held to beating both.
- Write the table into this file. If a budget fails, say which and stop
  before R1.

### Results, e1504g, 2026-10-06

Both shells built on g815 against e1504g's own nixpkgs (`55ba7f49`; the
repo's lock links glibc 2.42, the host's mesa needs 2.44, and Qt then finds
no EGL), copied over, and run back to back through `--r0-measure 600`,
nested visibly in the live session. Power profile `performance` for both
runs, not power saver. The nested Hyprland rendered on the iGPU (`Mesa
Intel(R) Graphics (ADL-N)`), at 946x1024 (the host tiled its window).

The host withheld frame events from the nested window for most of both
runs (the rust bar got 39 frame callbacks in ten minutes), so the nested
Hyprland barely presented and every number driven by a frame clock is void:
the spinner, the panel and scrim frames, the launcher stall. Those rows are
not measured.

| | Budget | Rust | QML | Verdict |
|---|---|---|---|---|
| CPU, 60 s idle | 0.0% | 0.00% | 0.32% | pass |
| CPU, 60 s spinner | < 2% | void | void | not measured |
| Frames, ten panel opens | none over 16 ms | void | void | not measured |
| Frames, ten scrim fades | none over 16 ms | void | void | not measured |
| RSS at 600 s | < 120 MB | 16 MB | 279 MB | pass |
| Cold start to first commit | < 300 ms | 160 ms | 1750 ms | pass |
| Launcher first frame | < 50 ms | no launcher yet | void | not measured |
| Bar gap across a launcher open | bar keeps animating | no launcher yet | void | not measured |

For the frame-driven rows, the VM (aarch64, llvmpipe, `--r0-measure 300`)
is the only reading so far: spinner 0.63% (rust) against 11.4% (QML),
worst panel frame 8.8 ms against 83 ms, scrim step 0.04 ms against a 72 ms
launcher frame, launcher first frame 128 ms median and a 144 ms bar gap on
QML.

Raster: the scrim is a `wp_single_pixel_buffer_v1` pixel scaled by
`wp_viewporter` and faded by `wp_alpha_modifier_v1`, so a flat full-output
surface costs no raster on either path. CPU versus GPU for a full-output
surface that is not flat stays open until the frame rows are measured.

Not decided: R1 waits on the four void rows, measured with the nested
window on screen, and on a power-saver run.
