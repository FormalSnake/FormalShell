# FormalShell M27: capture polish, recording finish and discoverability

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. The spec wins over
> this plan on conflict.

**Origin, owner ask (2026-08-17):** "also port over omarchy's screenshotting
flow. If you screenshot on there it opens in an editor and its handy. Also
add area screen recordings and stuff", then, after investigation showed most
of it already shipped: "do the handoff it doesnt matter" (keep the external
editor rather than building an in-shell one), and all four recording items
selected, webcam overlay included.

Upstream read at `origin/quattro` HEAD `262d6f06` (2026-08-17), MIT.

## What the investigation found, and what it corrected

A read-only agent mapped omarchy's whole capture family
(`bin/omarchy-capture-*`, its Hyprland binds and its menu entries) against
FormalShell's own. **The screenshot flow is already ported, editor
included.** `ScreenshotIpc.qml:429-433` fires a `SCREENSHOT SAVED`
notification carrying an `EDIT` action and a thumbnail, which spawns
`tensaku-edit` on the saved file. That is precisely upstream's design
(`bin/omarchy-capture-screenshot:71-73`), down to the same editor, which is
already packaged here at `nix/tensaku-package.nix` and swappable through the
`screenshot.editor` config key.

Three more things the owner asked about also already exist, and one of them
is better here than upstream:

- **Area recording**: `record start region`, plus the picker's own three REC
  tools (`RegionPicker.qml:84-91`).
- **Screen freeze while picking**: per-output `grim` to a file before the
  surface maps (`RegionPicker.qml:336-355`), so nothing moves under the
  selection. Upstream shells out to `hyprpicker -r -z`, which is a
  Hyprland-ecosystem tool; ours is compositor-neutral and already works on
  both backends.
- **Keyboard window selection while picking**: Tab/Shift-Tab sequential and
  arrows directional (`RegionPicker.qml:457-511`). Upstream cannot do this
  without warping the real cursor through `hyprctl eval` and re-probing
  which rectangle slurp highlights (`omarchy-capture-region:224-270`), an
  elaborate workaround for not drawing its own picker.

**So the owner's symptom was never a missing feature.** `Mod+Shift+S` on
g815 was bound to `screenshot region`, the legacy bare-slurp route with no
toolbar and no recording, rather than `screenshot pick smart default`. Fixed
outside this repo (`~/.config/nix`, commit `c073f948`, live on g815 as
generation 386). That misbinding is the single most important finding here,
and Task 1 exists so the next person cannot repeat it.

## Deliberate scope decisions

- **No in-shell annotation editor.** Offered and declined: "do the handoff
  it doesnt matter". The Tensaku handoff stays exactly as it is.
- **Webcam overlay is included at owner instruction**, over a documented
  portability objection. `RecordingService.qml:41-43` already records why it
  was skipped: pinning a floating window to a screen corner is a compositor
  window rule, and niri's and Hyprland's differ. Task 5 therefore implements
  it per backend behind the existing `CompositorService` abstraction, and
  where a backend cannot place the window the feature reports an honest
  unavailable state rather than spawning an unplaceable mpv window.

## Global constraints, binding on every task

- ASCII/ledger grammar per `docs/DESIGN.md`. Radius 0, 2px borders, no blur,
  no shadows, no gauges. Upstream renders its speed test as floating arc
  gauges; `NetworkPanel.qml:28-31` already records why that chrome was
  rejected here, and the same reasoning binds any new surface.
- Every gap, padding and font size resolves through `Theme.space` /
  `Theme.fontSize`. Raw pixel literals are defects.
- **The smoke rig is load-bearing on this code.** `dev/smoke-niri.sh`'s
  `--capture`, `--screenshot`, `--record` and `--ocr` legs drive
  `RegionPicker.key()` / `setTool()`, `ScreenshotIpc.pick()` /
  `pickerStatus()` and `RecordIpc.status()` verbatim. Changing any of those
  signatures or JSON shapes breaks the gate. Extend them; do not reshape
  them.
- Honest unavailable states, never faked data. A missing webcam, a missing
  ffmpeg filter, a backend that cannot place a window: each renders its own
  honest state.
- The shell never writes `settings.json`. Runtime-mutable state goes to
  `state.json` via `Core.State`, and any file touching that singleton while
  importing QtQuick must `import qs.Core as Core`.
- Verification per task: `just vm-test`, `git add -A && just vm-lint`, then
  the named `just vm-smoke` flag. **Read the returned PNG.**
- Commit per task, conventional lowercase subject, no body, no
  Co-Authored-By, no em dashes. Exclude `CLAUDE*.md`.

---

## Task 1: make the good route the discoverable one

The owner ran the shell for weeks with `Mod+Shift+S` on a route that cannot
record, and nothing in the shell or its docs said so. Three changes, no new
features:

- `docs/USAGE.md`: a short "recommended keybinds" block naming
  `screenshot pick smart default` as the one to bind for the picker, with
  `screenshot full` for Print, and stating plainly that `screenshot region`
  and `screenshot full` are non-interactive legacy routes with no toolbar
  and no recording. Put it next to the existing IPC target list.
- `ScreenshotIpc.qml`: a header comment stating the same division, so the
  next person reading the IPC surface sees which route is the rich one.
- The picker's own key legend (`RegionPicker.qml:884-892`) already lists
  keys. Confirm by screenshot that the six tool cells are legible enough
  that a first-time user can tell shot from record; if the two groups are
  not visually distinguished, add a `MetaLabel` separating SHOT from REC.
  This is the one visual change permitted in this task.

Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --capture`. Read the
PNG.

Commit: `docs(capture): name the picker route as the one to bind`

## Task 2: finish the recording audio honestly

Upstream's `finalize_recording` (`bin/omarchy-capture-screenrecording:253-280`)
fixes a real defect FormalShell has: PipeWire emits a click at the start of
every captured stream. Its pass, worth porting verbatim in intent because it
is pure ffmpeg and compositor-neutral:

- Trim the first 0.1s of video.
- Re-encode only when the first GOP carries discardable warmup packets;
  otherwise stream-copy, which is near-instant.
- When the recording has an audio track: hard-mute the first 400ms, apply a
  50ms fade in, then `loudnorm` to -14 LUFS.

Implement in `RecordingService.qml` as a finalize step after wf-recorder
exits and before the `RECORDING SAVED` notification fires. Constraints:

- The notification must not fire until finalize completes, otherwise the
  user clicks through to a file still being rewritten.
- Finalize failure is non-fatal: the un-finalized recording is still a valid
  file the user just made, so on a non-zero ffmpeg exit keep the original,
  log the reason, and send the normal notification. Losing a recording to a
  post-processing bug is far worse than a click at the start.
- A recording with no audio track skips the audio half entirely rather than
  running loudnorm against silence.
- `recording.finalize` (bool, default true) in `Config.qml` turns the whole
  pass off.

Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --record`. The rig
records real audio through its null sink, so assert on the output: probe the
finalized file with ffprobe and confirm duration shortened and the audio
stream survives. Read the smoke PNG too.

Commit: `fix(recording): trim the warmup click off finished captures`

## Task 3: a preview thumbnail and a play action

Today's `RECORDING SAVED` notification carries a `GIF` action and nothing
else (`RecordingService.qml:472-476`). Upstream attaches a real frame and a
play action, which is what makes the toast useful rather than a receipt.

- Extract one frame with `ffmpeg -vframes 1` into a temp path, attach it as
  the notification's image, and delete it once the toast has loaded it
  (upstream deletes after 2s; match that, and state the reason in the
  comment: the shell only needs it long enough to read).
- Add a `PLAY` action opening the file with the user's configured player.
  Add `recording.player` (default `xdg-open`) to `Config.qml`, following
  exactly the pattern `screenshot.editor` already establishes, so the two
  handoffs are one idiom rather than two.
- Keep the existing `GIF` action.

Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --record`. Read the
PNG and confirm the toast shows a real frame from the recording, not a
placeholder.

Commit: `feat(recording): show a frame and offer to play it`

## Task 4: resolution cap

Upstream's `--resolution=<size>` downscales while recording so a 4K capture
is not a 200MB file. Add `recording.maxHeight` (int, default 0 meaning no
cap) to `Config.qml`, applied as a wf-recorder scale filter when the
captured region's height exceeds it, preserving aspect ratio.

Expose it on the `record` IPC route as an optional trailing argument so a
keybind can request a capped capture without editing config. Unknown or
non-numeric values return an error string, never a silent no-op, matching
the contract the rest of the IPC surface holds.

Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --record`. ffprobe the
output and confirm the stored height matches the cap, and that an uncapped
run is unchanged.

Commit: `feat(recording): cap capture height on request`

## Task 5: webcam overlay, per backend, honest where it cannot go

Owner-instructed over a portability objection, so it ships with the
objection engineered around rather than ignored.

- Spawn `mpv av://v4l2:<device>` with the low-latency profile, cropped 8:9,
  its own app id, exactly as upstream does
  (`bin/omarchy-capture-screenrecording:86-92`). Auto-detect the first
  device when none is configured.
- Size it as a proportion of the captured region so it occupies the same
  fraction at any resolution (upstream's arithmetic at
  `omarchy-capture-webcam-resize:78-95` is pure maths, port the intent).
  Anchor bottom-right with a margin from `Theme.space`.
- **Placement goes through `CompositorService`**, with a niri implementation
  and a Hyprland implementation behind one method. A backend that cannot
  place the window must report unavailable and NOT spawn mpv: an
  unplaceable webcam window landing in the middle of the recording is worse
  than no webcam.
- Do not start recording until the window has actually mapped and settled,
  or the camera is filmed sliding into place. Upstream polls for the client
  then sleeps 600ms; poll rather than sleep blindly, with a bounded timeout
  that reports honestly on expiry.
- Config: `recording.webcam` (bool, default false), `recording.webcamDevice`
  (default empty meaning auto-detect), `recording.webcamSize`
  (small|medium|large, default medium).

The VM has no webcam. That is fine and is the point of the honest-state
rule: the smoke leg must show the shell reporting no device rather than
inventing one.

Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --record`. Read the
PNG. State plainly in the commit evidence that the overlay itself is
unverified on real hardware in this rig, and that the leg proves the
no-device path only.

Commit: `feat(recording): offer a webcam overlay where the backend can place it`

## Task 6: cover the edit handoff in the rig

The investigation found that **nothing in `dev/smoke-niri.sh` exercises
`ScreenshotIpc.edit()` or the SAVED notification's EDIT action.** The single
most owner-visible part of the capture flow has no test at all, which is how
a misbinding survived for weeks.

Add a `--capture-edit` leg: take a screenshot over IPC, assert the SAVED
notification carries both a thumbnail and an EDIT action, then invoke
`screenshot edit` against a PATH-shimmed editor that records its argv to a
file (the same technique `--clipssh` and `--panel github` already use for
`clipssh` and `gh`). Read the argv back and confirm the editor was handed
the exact saved path.

The shim stands in for Tensaku because what needs proving is the shell's own
path (capture, save, notify, action, spawn, argv), not whether a GTK4 app
renders in a VM.

Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --capture-edit`. Read
the PNG and the recorded argv file.

Commit: `test(capture): drive the editor handoff in the smoke rig`

---

## Review checkpoints

- **After Task 3**: hunt for a notification firing before finalize
  completes, a finalize failure that loses the user's recording, loudnorm
  run against a track with no audio, a temp preview file left behind, and
  any change to the `record`/`screenshot` IPC JSON shapes the rig asserts on.
- **After Task 6**: hunt for the webcam path spawning mpv on a backend that
  cannot place it, a poll with no bounded timeout, ffprobe assertions that
  were claimed but never run, config keys documented in `USAGE.md` but not
  read by `Config.qml` (or the reverse), unpushed commits, and any smoke leg
  that reports green without its artifact existing.

## Follow-ups deliberately left open

- An in-shell annotation editor, explicitly declined this round.
- OCR and colour-pick both already exist; upstream's QR-from-screen
  (`omarchy-capture-qr`, `zbarimg`) does not exist here and is a small,
  obvious addition whenever it is wanted.
- Upstream's `wl-copy --sensitive` on QR output, which keeps a scanned
  secret out of clipboard history. Worth auditing our own clipboard writes
  for the same treatment separately.
