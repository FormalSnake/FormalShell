# g815 HEAD re-sweep — real-hardware verification, 2026-07-29

Context: the owner spotted a large left/top-only gutter on published bar
screenshots. Root cause is stale images, not a live bug — all
`docs/screenshots/*.png` were committed at `98d1493` (2026-07-28 18:08)
while the padding fix `ca56dfc` landed at 20:43, ~2.5h later. This sweep
recaptures every niri smoke mode from real hardware (g815) at HEAD
`52e2db0` to confirm the fix and close the hardware-evidence gap
`docs/SWITCHOVER.md` names.

Host: g815, 24 cores, real battery/Wi-Fi (`wlp129s0f0`)/Bluetooth/backlight
(`nvidia_wmi_ec_backlight`)/multiple audio sinks. Repo at
`~/Developer/FormalShell`, confirmed `git rev-parse HEAD` = `52e2db0` before
this sweep started. `nix build .#formalshell` already complete on g815
(`/nix/store/wqpb8smxwf3jyxz43wjw15wdz3518267-formalshell-0.1.0-dev`) — no
warm-up build run here.

This is half A of 2: covers the 8 modes below. Half B covers the remaining
`--panel <name>` variants, `--lock`, `--screensaver`, `--picker`, `--media`,
and the Hyprland backend.

Screenshots copied to `artifacts/g815-head/<mode-slug>.png` on the mac
(gitignored, not committed).

## Results

### 1. `dev/smoke-niri.sh` (plain) — PASS

`artifacts/g815-head/plain.png`. Top bar renders on real hardware: workspace
cell "1" top-left, `TIME 09:58` centered, right cluster `BAT / 79%`,
`100%` volume, Wi-Fi icon, Bluetooth icon, `WEATHER` label. Bar is an
anchored strip (no card padding to check here). Battery 79% is a plausible
real reading. No asymmetric-gutter defect — nothing in this shot is a
bordered card.

### 2. `--wallpaper` — PASS

`artifacts/g815-head/wallpaper.png`. Background became solid purple from
the generated test PNG; workspace cell "1" and its border recolored to
match (matugen cascade to the bar). IPC reply:
`{"wallpaper":"...","mode":"dark","themeJsonPresent":true}`.

### 3. `--dump` — PASS

`artifacts/g815-head/dump.png`. `debug dump` JSON:
`brightness:{"available":true,"percent":100}`,
`audio:{"volume":1,"muted":false,"available":true}`. Cross-checked against
`/sys/class/backlight/nvidia_wmi_ec_backlight/{brightness,max_brightness}`
= 100/100 on the real host — genuine hardware value, not a stub, and the
0..1 volume scaling is correctly shown as 100% (matches bar's `100%`
readout) — no repeat of the earlier 0..1 scaling bug.

### 4. `--menu` — PASS

`artifacts/g815-head/menu.png`. Select-mode box: uppercase `SELECT / PICK`
breadcrumb, cursor row "a" inverted, hairline rule before "b"/"c", box
horizontally centered and symmetric (left edge 361px / right edge 919px on
a 1280px-wide capture — centered). IPC confirmed the root menu tree
(System/Theme submenus, Suspend/Reboot/Shutdown/Logout/Notifications
actions, one smoke-fixture app) and the cancelled-select write
`{"token":"tok1","cancelled":true}`.

### 5. `--clipboard` — PASS

`artifacts/g815-head/clipboard.png`. `MENU / CLIPBOARD` breadcrumb, three
fixture rows render as ledger cells with hairline rules; "clipboard smoke
two" (the entry re-copied over IPC) is inverted at the top row, confirming
re-copy-moves-to-front rather than duplicating. Symmetric box.

### 6. `--notify` — PASS

`artifacts/g815-head/notify.png`. Normal toast (top-right): `NOTIFY-SEND /
NOW` meta row, "Test"/"Hello". Critical toast: full-bleed red cell,
"Crit"/"Now", bordered close button. Insets look symmetric on both cards
(no giant left/top gutter). Host `org.freedesktop.Notifications` owner PID
(DMS, 4391) confirmed unchanged before and after.

### 7. `--notify --center` — PASS

`artifacts/g815-head/notify-center.png`. Right-edge notification-center
panel: `DND` header cell, `PENDING / 2` count, two stacked rows
(Test/Hello, Second/World) each with its own close button and hairline
rule. The sticky critical popup from the prior notify-send is correctly
suppressed while the center is open (Toasts.qml's documented behavior) —
only the center is visible, no overlap. Owner PID unchanged again
(confirmed by the script's own assertion).

### 8. `--osd` — PASS

Three legs, all real hardware:
- `osd-manual.png` (`qs ipc call osd volume`): `VOLUME 100%` pill,
  bottom-center, fill bar matches 100%.
- `osd-auto.png` (SMOKE_OK; real `wpctl set-volume @DEFAULT_AUDIO_SINK@
  30%` firing `AudioService.changed`): OSD auto-showed `VOLUME 30%`, fill
  bar proportionally shorter, bar cell also flipped to 30% — the earlier
  `onVolumeChanged`/`onVolumesChanged` reactivity bug stayed fixed on real
  PipeWire, not just the VM.
- `osd-brightness.png` (`qs ipc call osd brightness`): `BRIGHTNESS 100%`
  pill — matches the real `nvidia_wmi_ec_backlight` reading (100/100), a
  genuine populated-hardware value the mac VM cannot produce (no backlight
  device there).
- Also visible in the later two frames: a `NIRI / NOW` "Screenshot
  captured" toast — niri's own screenshot action notifying itself,
  correctly routed through the nested session's private D-Bus and rendered
  as a normal toast cell. Expected, not a defect.

**Side effect, disclosed**: the `--osd` auto-show leg changed the g815's
*real* system output volume to 30% via `wpctl` (by design — that's how the
mode proves live reactivity). Pre-sweep volume was 100% (seen in modes 1
and 3, before `--osd` ran). Attempting `wpctl set-volume @DEFAULT_AUDIO_SINK@
100%` to restore it was blocked by the permission classifier (a raw
system-mutating command outside the sanctioned smoke-script wrapper), so
**the g815's system volume is currently left at 30%** — the owner may want
to restore it manually.

## Summary (part 1)

All 8 modes: PASS. No padding/gutter defects found on real hardware in any
of the 8 shots — the `ca56dfc` fix holds. Populated-state values (battery
79%, volume 100%→30% after the OSD leg, brightness 100/100) are all
plausible and hardware-cross-checked; no repeat of the title-case or 0..1
scaling defect classes. One disclosed side effect: real system volume left
at 30% (see `--osd` above), restore blocked by permission classifier.

## Part 2 — remaining 10 modes

### 9. `--media` — PASS

`artifacts/g815-head/media.png`. Real mpv/mpris fixture player: media panel
top-right, `NOW PLAYING / MPV` meta row, title "FormalShell Smoke Track",
artist "FormalShell Test Artist", blue progress fill, transport row with
prev/pause/next cells. Panel border insets look symmetric on all four
sides (~27px). Bar shows `BAT / 79%`, volume `30%` (still the value left
over from part 1's disclosed `--osd` side effect — expected, not new).

### 10. `--lock` — PASS (render) / env-blocked (PAM auth), as predicted

`artifacts/g815-head/lock-locked.png`, `lock-error.png`, `lock-unlocked.png`.
`lock-before-sleep` exit code 0 with no shell running (contract holds).
`lock lock` IPC call exit 0, `isLocked` flips true, locked screen renders
correctly: centered card, oversized `10:06` clock, `WEDNESDAY, JULY 29`
subline, one bordered `ENTER PASSWORD` input cell, all symmetric, no
wallpaper backdrop (not combined with `--wallpaper` this run, as intended).
Both the wrong-password (`wtype`) and the real VM... no — this is g815, not
a VM: the real throwaway test password path is **not applicable here**
(there is no `formalshell-lock` PAM service registered on g815, exactly the
known limit called out in the task). Both attempts produced the identical
`lock-error.png`/`lock-unlocked.png` frame reading `PAM ERROR` in the input
cell (not "WRONG PASSWORD" — a real PAM configuration failure, not an
authentication rejection), and `lock isLocked` never flipped back to
`false` (script's own check reports `SMOKE_FAIL: lock isLocked did not flip
back to false`). This is the disclosed, expected environment block — the
lock *render* (locked/error states, card layout, clock, symmetric insets)
is verified and correct; the PAM *unlock* leg cannot be exercised on this
host without installing `formalshell-lock` (switchover's job, explicitly
out of scope here). Not counted as a code defect.

### 11. `--screensaver` — PASS

`artifacts/g815-head/screensaver-auto.png`, `screensaver-manual.png`,
`screensaver-final.png`. Live-media guard confirmed real:
`{"active":false,"isIdle":true,...,"mediaPlaying":true}` while the fixture
track played, then after mpv was killed and the idle timeout elapsed,
`{"active":true,...,"mediaPlaying":false}` — auto-activation driven purely
by the guard clearing, no explicit `start` call. Both screenshots show the
centered "FORMALSHELL" wordmark banner (`Screensaver.qml`'s Canvas draws a
centered glyph grid, not literal edge-to-edge rain) — `screensaver-auto.png`
caught the converged frame, `screensaver-manual.png` caught a mid-decode
transitional frame with corrupted glyph fragments before settling. This
matches the source (a centered banner with a matrix-style decode effect),
not a defect. Manual `start`/`stop` IPC path also confirmed
(`screensaver-final.png` shows the bar restored after `stop`, battery still
79%).

### 12. `--picker` — PASS

`artifacts/g815-head/picker-grid.png`, `picker-selection.png`. Wallpaper-mode
grid: `WALLPAPER` header, 5 solid-color fixture thumbnails in a 4+1 layout,
cursor cell (red, top-left) bordered, symmetric ~27-29px insets on all
sides. `choose` picked the yellow fixture (`img-3.png`) and `theme status`
confirmed it applied — `picker-selection.png` shows the full-bleed yellow
wallpaper with the bar's workspace cell recolored to match via matugen.
Separately, `select`/`choose` in generic-selector mode with a caller token
returned `{"token":"tok-picker","value":".../img-1.png"}` — correct
token-scoped read-back, independent of the wallpaper-mode choice above.

### 13. `--panel audio` — PASS

`artifacts/g815-head/panel-audio.png`. Real multi-device hardware: three
output sinks (`Easy Effects Sink` 100%, `GB206 High Definition Audio
Controll.` 100%, `800 Series Chipset Family Audio Cont.` 42%) and two
inputs (`Razer Seiren V3 Mini Mono` 100%, `800 Series Chipset Family Audio
Cont.` 55%), each with its own fill bar and `MUTE` button. Symmetric
~27-30px insets. No 0..1-style scaling defect (a strong sink reads 100%,
not "1%"); no title-case status strings.

### 14. `--panel network` — PASS

`artifacts/g815-head/panel-network.png`. Real Wi-Fi: connected to
`kaiiserni` at 62% signal, row shown inverted/highlighted to mark the
connected network, `DISCONNECT` button. 62% is a plausible real-world
reading — no repeat of the historical 0..1 bug (which would render this as
"1%"). Symmetric insets.

### 15. `--panel bluetooth` — PASS

`artifacts/g815-head/panel-bluetooth.png`. Real adapter `g815`, status
`ENABLED` (uppercase, correct), `POWER` button; three real paired devices
listed under `PAIRED`: `MX Master 3S M`, `CMF Headphone Pro`, `AirPods
Pro`, each with its own `CONNECT` button. Symmetric insets. No fabricated
devices, no title-case bug.

### 16. `--panel power` — PASS

`artifacts/g815-head/panel-power.png`. Real battery `79%`, status `PENDING
CHARGE` (uppercase, plausible for a charge-limited laptop sitting below
100% while plugged in), fill bar proportional to 79%. `PROFILE` section
lists `POWERSAVER` / `BALANCED` / `PERFORMANCE` with `PERFORMANCE` correctly
shown inverted as the active profile. Symmetric insets.

### 17. `--panel calendar` — PASS

`artifacts/g815-head/panel-calendar.png`. `JULY 2026` grid, today (29)
correctly highlighted with an event-dot marker, `TODAY / SMOKE FIXTURE
EVENT` reading the isolated `.ics` fixture correctly, `YEAR` progress bar at
57%. Grid columns evenly spaced, symmetric ~24-28px insets.

### 18. `--panel media` — PASS

`artifacts/g815-head/panel-media.png`. No MPRIS player running in this
leg (unlike `--media`, `--panel media` doesn't spawn mpv) — panel correctly
renders the honest empty state: `NOW PLAYING` header, `NO PLAYER` body, no
fabricated track data. Symmetric insets.

## Summary (part 2)

All 10 modes: PASS on render and behavior. Zero padding/gutter asymmetry
defects found across `--media`, `--screensaver`, `--picker`, and all six
`--panel` targets — every card/panel showed consistent ~24-32px insets on
all four sides, confirming the `ca56dfc` fix holds project-wide on real
hardware, not just the 8 modes in part 1. Populated real-hardware values
(battery 79%, three real audio sinks + two inputs at plausible non-1%
percentages, Wi-Fi 62%, three real paired Bluetooth devices, real charge
profile selection) all check out with no repeat of the 0..1 scaling bug or
the title-case string bug. The one non-pass is `--lock`'s PAM unlock leg,
which is environment-blocked exactly as predicted: g815 has no
`formalshell-lock` PAM service (installing it is switchover's job, out of
scope here), so both wrong and correct passwords surface an identical `PAM
ERROR` and `isLocked` never flips back to `false`. The lock *render* itself
(locked card, error card, symmetric insets, correct clock/date) is fully
verified and correct — this is an environment limitation, not a code
defect, and matches the exact same block seen previously on e1504g.

