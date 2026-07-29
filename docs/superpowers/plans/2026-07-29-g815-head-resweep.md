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

## Summary

All 8 modes: PASS. No padding/gutter defects found on real hardware in any
of the 8 shots — the `ca56dfc` fix holds. Populated-state values (battery
79%, volume 100%→30% after the OSD leg, brightness 100/100) are all
plausible and hardware-cross-checked; no repeat of the title-case or 0..1
scaling defect classes. One disclosed side effect: real system volume left
at 30% (see `--osd` above), restore blocked by permission classifier.

