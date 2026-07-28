# FormalShell M7: Now playing, lock, screensaver, image picker — Implementation Plan

> **For agentic workers:** Workflow-driven per `docs/superpowers/workflow-template.md`
> — one subagent per task, sequential, verification evidence required, push
> after every task commit (classifier-denied pushes: note and continue). Read
> `CLAUDE.md` and `docs/DESIGN.md` first — both binding. The spec
> (`docs/superpowers/specs/2026-07-27-formalshell-design.md` §Surfaces 5/8/10/11)
> wins over this plan on any conflict.

**Goal:** The shell gains its media, session and idle surfaces: a now-playing
bar cell + panel on MPRIS (with opt-in Apple Music animated covers), a real
lock screen on `WlSessionLock` + PAM with no external binary, an idle-driven
screensaver, and an image/wallpaper picker that feeds ThemeEngine.

## API ground truth (verified against the pinned quickshell 0.3.0, 2026-07-28)

Do not guess these; they were read out of the built package's qmltypes:

| Type | Module | Notes |
| --- | --- | --- |
| `WlSessionLock`, `WlSessionLockSurface` | `Quickshell.Wayland` | `locked`, `secure`, `unlock()`, `surface` component |
| `PamContext`, `PamResult`, `PamError` | `Quickshell.Services.Pam` | the whole auth story — no external binary |
| `IdleMonitor` | `Quickshell.Wayland` (re-exported from `._IdleNotify`) | `enabled`, `isIdle`, `timeout`, `respectInhibitors` |
| `IdleInhibitor` | `Quickshell.Wayland` (from `._IdleInhibitor`) | `enabled`, `window` |
| `ScreencopyView` | `Quickshell.Wayland` (from `._Screencopy`) | `captureSource`, `live`, `hasContent`, `captureFrame()` |
| `BackgroundEffect` | `Quickshell.Wayland` (from `._BackgroundEffect`) | `blurRegion` — compositor-side blur |
| `Mpris`, `MprisPlayer`, `MprisPlaybackState`, `MprisLoopState` | `Quickshell.Services.Mpris` | now playing |

`IdleMonitor` lives in a `_IdleNotify` submodule that the main
`Quickshell.Wayland` qmldir imports, so a plain `import Quickshell.Wayland`
reaches it. Read each type's full qmltypes before use — the table above is
the existence proof, not the complete signature.

## Plan-wide constraints

- **DESIGN.md is binding.** The lock screen and screensaver are the two
  surfaces where DESIGN.md grants an exception: the lock-screen backdrop blur
  is the **only** permitted blur in the entire shell. Everything else stays
  flat, radius 0, ruled cells, uppercase MetaLabel meta rows, inversion for
  selection. The lock screen is "oversized clock (display slot) + single
  bordered input cell"; the picker is a grid of cells sharing rules.
- `Theme.font.display` is the DESIGN.md-reserved display slot for the
  oversized lock clock. If it does not exist yet, add it defaulting to the
  mono family (DESIGN.md §Token additions already specifies this) — do not
  hardcode a font family, ever.
- **Honest unavailable states, never faked.** No fingerprint reader, no
  battery and no Wi-Fi exist in the test VM. A fingerprint prompt must appear
  only when a reader is actually enrolled.
- **Zero network when disabled** is a hard contract for the Apple Music
  service: with the setting off, it must make no requests at all, and that
  must be *proven*, not asserted.
- The shell only reads `settings.json`; runtime-mutable values go to
  `$XDG_STATE_HOME/formalshell/`.
- Nerd Font glyphs are raw multi-byte codepoints — targeted `Edit` operations
  only, codepoints from the font cmap, never from memory.
- Smoke script changes are additive only; `dev/smoke-niri.sh` must stay
  byte-compatible with Linux-host use.
- **Lock-screen safety:** all lock testing happens inside the nested niri
  session in the VM. A lock bug there is harmless. Never run a lock surface
  against anything but the nested session.

---

### Task 1: MPRIS now-playing service + bar cell + panel

**Files:** create `shell/Services/MediaService.qml`,
`shell/Surfaces/Panels/MediaPanel.qml`,
`shell/Surfaces/Bar/widgets/NowPlaying.qml`; modify `shell/Services/qmldir`,
`shell/Surfaces/Bar/Bar.qml`, `shell/shell.qml`, `shell/Ipc/` (a `media`
target per the spec's IPC list), `nix/testvm.nix`, `dev/smoke-niri.sh`.

**Produces:**
- `MediaService.qml` on `Quickshell.Services.Mpris`: the active player
  (preferring an actually-playing one), `title`/`artist`/`album`/`artUrl`,
  `isPlaying`, `canGoNext`/`canGoPrevious`, position, and verbs
  `playPause()`, `next()`, `previous()`, `seek(fraction)`. Honest
  `available: false` when no player exists.
- `MediaPanel.qml` extending `Components/Panel.qml` (mirror AudioPanel /
  NetworkPanel exactly): album art cell, a meta row (`NOW PLAYING / <app>`),
  title + artist rows, a flat accent-fill progress cell (no thumb), and
  transport controls as inverted-on-hover cells.
- `NowPlaying.qml` bar cell: elided title, panel-open accent dot, hidden
  entirely when no player is present (not a "nothing playing" lie).
- `media` IPC target: `playPause()`, `next()`, `previous()`, `status()`.
- **VM enablement:** add an MPRIS player that actually works headlessly —
  `mpv` with `mpvScripts.mpris` playing a generated silent audio file into the
  existing pipewire null sink is the intended path. Add a `--media` smoke mode
  that starts it in-session before screenshotting.

**Steps:** implement → `just vm-smoke --media` → Read the PNG: bar cell with a
real track title, panel with meta row, transport cells, flat progress fill →
cross-check over ssh with `playerctl metadata` (or the `media status` IPC) that
the displayed values match the real player → `just test` + `just vm-lint` →
commit `feat(media): mpris now-playing service, bar cell, panel, media ipc`; push.

---

### Task 2: Apple Music animated album art (opt-in, isolated)

**Files:** create `shell/Services/AppleMusicArtService.qml`,
`shell/Media/applemusic.js`, `tests/tst_applemusic.qml`; modify
`shell/Surfaces/Panels/MediaPanel.qml`, `shell/Core/Config.qml`.

**Produces:** a single isolated service, **off by default**, resolving
animated cover art via iTunes Search + the amp-api `editorialVideo` field
(undocumented — the spec says so explicitly, so every failure path falls back
to static art). MP4s cache to `~/.cache/formalshell/applemusic-art/` with
**atomic rename**, **misses cached too** (so a track without animated art is
not re-fetched every play), and a **30-day prune**. The muted looping video
plays only while the track is actually playing.

`applemusic.js` (pure, TDD'd first) owns URL construction, response parsing,
and the cache-key/prune-decision logic, with tests for: a hit, a miss, a
malformed response, an HTTP error, and prune boundary conditions.

**Steps:** red → implement → green → prove the three contracts:
1. **Zero network when disabled** — the setting off, run the shell in the VM
   and show no request was made (e.g. no cache dir created and no outbound
   connection attributable to the service; state exactly how you proved it).
2. **Static-art fallback** — force a failure (bad host or a track with no
   animated art) and screenshot the panel still showing static art.
3. **Cache behavior** — second resolution of the same track hits the cache
   (show the timing or the absence of a second request).
   The live amp-api path is undocumented and may simply not respond from the
   VM; if so, say that plainly — a network failure that falls back correctly
   is a PASS for this task, an unhandled failure is not.
→ commit `feat(media): opt-in apple music animated art with cached fallback`; push.

---

### Task 3: Lock screen (WlSessionLock + PAM)

**Files:** create `shell/Surfaces/Lock/Lock.qml`,
`shell/Surfaces/Lock/LockSurface.qml`, `shell/Ipc/LockIpc.qml`; modify
`shell/Core/Theme.qml` (the `font.display` slot if absent), `shell/shell.qml`,
`nix/testvm.nix`, `dev/smoke-niri.sh`.

**Produces:**
- `Lock.qml` on `WlSessionLock` with a `WlSessionLockSurface` per output:
  blurred current-wallpaper backdrop (`ScreencopyView` for the capture +
  `BackgroundEffect.blurRegion` for the blur — DESIGN.md's single blur
  exception), an oversized clock in `Theme.font.display`, and ONE bordered
  ledger input cell. Failed auth inverts the input cell and shows an
  uppercase error meta row; no shake, no bounce.
- PAM auth via `PamContext` — no external binary. **Verify which PAM service
  name actually exists in the VM** (`/etc/pam.d/`) and use one that works;
  whatever it is, `nix/testvm.nix` must declare it (`security.pam.services.<name>`)
  and Task 7 must document that a real deployment needs the same, since the
  home-manager module alone cannot create a PAM service.
- `lock` IPC target: `lock()`, `isLocked()`, `status()`.
- **VM enablement:** give the `test` user a real password so PAM can succeed —
  a throwaway test-only credential in `nix/testvm.nix`, clearly commented as
  such. Add a `--lock` smoke mode: lock over IPC, screenshot the lock surface,
  then authenticate with the test password and screenshot the unlocked session
  to prove the round trip.

**Steps:** implement → `just vm-smoke --lock` → Read BOTH PNGs (locked:
oversized clock, blurred backdrop, single input cell; unlocked: normal
session) → prove `isLocked()` flips both ways over IPC → commit
`feat(lock): wlsessionlock lock screen with pam auth and blurred backdrop`; push.

---

### Task 4: Lock hardening — idle blanking, resume guard, fingerprint

**Files:** modify `shell/Surfaces/Lock/Lock.qml`,
`shell/Surfaces/Lock/LockSurface.qml`, `shell/Ipc/LockIpc.qml`,
`shell/Core/Config.qml`.

**Produces:**
- Idle blanking of the lock surface after a configured timeout, with the
  **wall-clock resume guard** the spec calls for: a suspend/resume must not
  leave the surface blanked-but-unlocked or wake into a stale timer — compare
  wall-clock time across the gap rather than trusting a monotonic timer.
- Fingerprint as a **parallel** PAM flow when a reader is enrolled: the
  password field stays usable while the fingerprint attempt is pending, and
  either can succeed. No reader exists in the VM, so the honest verification
  is that no fingerprint prompt appears and the password flow is unaffected —
  state that plainly rather than faking a reader.
- Explicit, uppercase failure states: wrong password, PAM error, account
  locked. Never a silent no-op.
- The `lock-before-sleep` contract: whatever command a systemd unit would
  call must keep the **exit-0-always** behaviour the spec requires, so a lock
  failure can never block suspend. Verify by invoking it and checking `$?`.

**Steps:** implement → `just vm-smoke --lock` regression (both PNGs Read
again) → prove the blank timeout and the resume guard by manipulating the
timeout to a few seconds and screenshotting the blanked surface → prove
exit-0-always with a real `$?` check → commit
`feat(lock): idle blanking with resume guard, parallel fingerprint flow`; push.

---

### Task 5: Idle service + screensaver

**Files:** create `shell/Services/IdleService.qml`,
`shell/Surfaces/Screensaver/Screensaver.qml`,
`shell/Screensaver/effect.js`, `tests/tst_screensaver_effect.qml`,
`shell/Ipc/ScreensaverIpc.qml`; modify `shell/shell.qml`,
`shell/Core/Config.qml`, `dev/smoke-niri.sh`.

**Produces:**
- `IdleService.qml` wrapping `IdleMonitor` (`timeout`, `isIdle`,
  `respectInhibitors`) plus the inhibitor state, exposed as one singleton.
- `Screensaver.qml`: a full-screen overlay-layer surface **per monitor**,
  rendering a themed terminal-text-effect animation drawn in QML with the
  shell's mono font and palette — TTE-style rain/decrypt/matrix. **No spawned
  terminal windows.** Any input dismisses it; optionally chains into lock
  after a further timeout.
- `effect.js` (pure, TDD'd first): the animation's state stepping — column
  state, glyph selection from a defined character set, decay — so the visual
  is a deterministic function of a frame counter and is genuinely testable.
  Tests for: step determinism, bounds (no out-of-range column/row), and the
  decay reaching a resting state.
- Never activates while an idle inhibitor holds or (configurably) while media
  is actually playing — wire the latter to `MediaService.isPlaying`.
- `screensaver` IPC target: `start()`, `stop()`, `status()`.

**Steps:** red → implement → green → `just vm-smoke --screensaver` (IPC
`start`, screenshot, `stop`) → Read the PNG: the effect actually rendering in
the mono font and theme palette, full-screen → prove the media guard by
starting the Task-1 mpv player and confirming the idle trigger does not fire →
commit `feat(screensaver): idle service and themed terminal-effect screensaver`; push.

---

### Task 6: Image/wallpaper picker

**Files:** create `shell/Surfaces/Picker/ImagePicker.qml`,
`shell/Ipc/PickerIpc.qml`; modify `shell/shell.qml`, `dev/smoke-niri.sh`.

**Produces:** a grid of image cells sharing hairline rules (grid first —
Omarchy's skewed carousel is explicitly a later flourish), keyboard navigable
with inversion on the cursor cell, scanning a configured wallpaper directory.
Selecting a wallpaper triggers `ThemeEngine` exactly as the existing
`wallpaper set` IPC path does (reuse it — do not duplicate the theming
trigger). Doubles as a generic image-selector: an IPC verb that opens the
picker and returns the chosen path, mirroring the menu's `select` answer-channel
pattern (read how `MenuIpc` does its request/answer handshake and reuse it
rather than inventing a second mechanism).

**Steps:** implement → `just vm-smoke --picker` with a few generated fixture
images → Read the PNG: grid of cells, cursor cell inverted → select one over
IPC and prove both that the answer channel returned its path and that the
wallpaper/theme actually changed (`theme status` JSON, as
`dev/smoke-niri.sh --wallpaper` already does) → commit
`feat(picker): ledger image grid picker feeding themeengine`; push.

---

### Task 7: Docs + screenshots

**Files:** modify `README.md`, `docs/ARCHITECTURE.md`, `CLAUDE.md`; add
`docs/screenshots/lock-niri.png`, `docs/screenshots/media-niri.png`,
`docs/screenshots/screensaver-niri.png`, `docs/screenshots/picker-niri.png`.

**Steps:**
- Screenshots pulled from the VM and **Read before publishing**.
- README: Now playing (MPRIS, the opt-in Apple Music art with its
  undocumented-API caveat stated honestly), Lock (PAM service requirement —
  including that a real deployment must declare `security.pam.services.<name>`
  system-side, which the home-manager module cannot do), Screensaver
  (timeouts, inhibitor and media guards, IPC), Picker.
- ARCHITECTURE: the MPRIS→panel chain, the lock surface/PAM flow, the idle→
  screensaver trigger graph, and the picker's answer-channel handshake.
- CLAUDE.md: the new smoke modes; the lock-testing safety rule (nested
  sessions only); the blur exception being lock-backdrop-only.
- Verify every documented command by running it. Commit
  `docs(media,lock): now playing, lock, screensaver, picker`; push.

---

## Then

**M8** — greeter + `nixosModules.formalshell-greeter` (shares Core/Theme with
the lock screen, so it lands after M7 deliberately). **M9** — polish pass and
the ledger retrofit of the M1–M3 surfaces, then the e1504g daily-drive trial
and the g815 switchover gate. **Note: M9's last two items need a Linux host
back and cannot be closed from the macbook** — the polish and retrofit can,
the trial and the gate cannot.
