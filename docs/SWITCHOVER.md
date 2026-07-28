# FormalShell v1 — switchover readiness report

Written at commit `4aad1d6` (HEAD of `main`), after M9 tasks 1-4 (design
retrofit, motion sweep, the e1504g real-hardware sweep, and its fixes) and
`just test` = 259 passed / 0 failed. This is Task 5 of
`docs/superpowers/plans/2026-07-28-m9-polish-and-switchover.md`: an honest
readiness assessment, not a go/no-go decision — the decision is the owner's.

**Both Linux hosts are now offline.** e1504g was powered off after its
sweep completed; g815 is unavailable. Nothing below could be re-verified on
real hardware during this task; where a fix landed after the last real
hardware could see it, that is stated plainly rather than implied fixed.

## 1. Parity table

Evidence sources: the e1504g sweep at commit `1300b02`
(`docs/superpowers/plans/2026-07-28-m9-e1504g-trial.md`, screenshots in
`artifacts/e1504g/`), an older g815 sweep at commit `707f8e3`
(`artifacts/g815/`, **M6-era — predates M7, M8, and M8b entirely**, so it
speaks only to pre-visual-retrofit rendering and is cited only where the
e1504g sweep didn't cover the same ground), and the mac VM rig (`just
vm-smoke`, this task's own runs, all at HEAD `4aad1d6`). All real-hardware
evidence is niri-backend only — neither sweep ever ran `dev/smoke-hyprland.sh`
on real hardware.

| Surface | Status | Evidence |
| --- | --- | --- |
| Bar | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/plain.png` — real BAT/Wi-Fi/Bluetooth cells the VM cannot produce |
| Menu | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/menu.png` |
| Panel: audio | Hardware-verified, with a caveat | e1504g @ 1300b02 found the percentage-lost-behind-elision defect (`artifacts/e1504g/panel-audio.png`); fixed at `4aad1d6`. The fix itself is **VM-only re-verified** (this task, `artifacts/smoke-20260728-230744.png`) — e1504g went offline before a re-sweep could confirm it against a real long device name |
| Panel: network | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/panel-network.png` — real SSID, correct 79% signal (the 0..1-scaling bug stayed fixed) |
| Panel: bluetooth | Hardware-verified, fix unconfirmed visually | e1504g @ 1300b02 found the adapter-state title-case defect (`artifacts/e1504g/panel-bluetooth.png`); fixed at `4aad1d6` (grep-confirmed: the only remaining `.toString(` call under `shell/Surfaces/Panels/` without `.toUpperCase()`). Cannot be re-screenshotted anywhere: the VM has no Bluetooth adapter at all (`artifacts/smoke-20260728-230805.png` shows the honest `NO ADAPTER` state), and e1504g is offline |
| Panel: power | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/panel-power.png` — `FULLY CHARGED` uppercase, real `power-profiles-daemon` values |
| Panel: calendar | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/panel-calendar.png` — real month grid, local-.ics fixture event |
| Panel: weather | **Unverified** | Never included in either real-hardware sweep (neither e1504g's 18-mode run nor the older g815 run drove `--panel weather`); only ad hoc dev-loop crops exist in `artifacts/` (`weather-crop*.png`), not a hardware or a repeatable VM smoke run |
| Notifications | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/notify.png`, `notify-center.png` |
| OSD | Hardware-verified, with a defect found+fixed | e1504g @ 1300b02 found the auto-show reactivity defect (`osd-volume.png` never updated on an external `wpctl set-volume`); manual volume/brightness legs passed (`osd-manual.png`, `osd-brightness.png`). Fixed at `4aad1d6` (wrong signal name, `onVolumeChanged` vs `onVolumesChanged`). Fix is **VM-only re-verified** (this task, `artifacts/smoke-20260728-230920.png`, real bar+OSD flip to 30% off a real `wpctl` call) — not re-confirmed against a real PipeWire graph |
| Clipboard | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/clipboard.png` |
| Now playing (media) | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/media.png` + `panel-media.png` — real MPRIS via mpv into the hardware sink |
| Lock screen | Partially hardware-verified | e1504g @ 1300b02 proved render, the `lock`/`isLocked` IPC round trip, and fail-closed behavior (`lock-locked.png`, `lock-error.png`, `lock-unlocked.png`) — but **environment-blocked** on the actual PAM success/failure paths, since e1504g had no `formalshell-lock` PAM service (that's exactly what switchover installs). Those two paths remain **VM-only verified** (`docs/screenshots/lock-niri.png`, the VM has `nixosModules.formalshell`'s PAM service) |
| Screensaver | Hardware-verified | e1504g @ 1300b02, `screensaver-auto.png`, `screensaver-manual.png` — real `IdleMonitor` + live-media guard |
| Picker | Hardware-verified | e1504g @ 1300b02, `picker-grid.png`, `picker-select.png` — real matugen recolor on choose |
| Greeter | **VM-only** | Never run against real greetd on either host (neither has switched to `nixosModules.formalshell-greeter`). Verified via `just vm-greeter` / `dev/smoke-greeter.sh`: real PAM auth round trip in the VM, `artifacts/greeter/greeter-pre-auth.png`, `greeter-wrong-pw.png`, `greeter-post-auth.png` |
| Theming (matugen) | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/wallpaper.png` — real matugen run recoloring bar/workspace accents from a wallpaper on real hardware |

Everything marked hardware-verified above is the **niri** backend only. The
Hyprland backend has never run on either Linux host — it exists only as
`dev/smoke-hyprland.sh` against a nested Hyprland session in the VM, and per
`CLAUDE.md` that nested session is flakier than niri's even there.

## 2. Known gaps and rough edges

- **Calendar events are local `.ics` only, not GNOME Online Accounts/EDS.**
  `docs/spikes/2026-07-28-eds-calendar-events.md` spiked reading Evolution
  Data Server's D-Bus calendar API directly and concluded it isn't feasible
  without a compiled client (EDS ties its calendar-view D-Bus object to the
  lifetime of the specific connection that opened it, which a stateless
  `Process`-based `gdbus` call can't hold open) — recorded as a post-v1 item,
  `evolution-data-server` removed from the VM again rather than left
  half-working. `Calendar/ics.js` reads a khal/vdir-style directory instead.
- **No RRULE expansion.** `Calendar/ics.js` (per `docs/ARCHITECTURE.md`)
  reads single `VEVENT`s only — a recurring event's `RRULE` field is not
  expanded into instances. A user with recurring calendar entries will see
  the first occurrence only.
- **Hyprland backend is flaky in the sandboxed dev loop** and has never run
  on real hardware at all (see the parity table note above). Both niri and
  Hyprland implement the same formal `CompositorBackend` contract, but only
  niri has any real-world mileage.
- **The greeter has no session or user picker.** Verified directly against
  greetd's own wire protocol (`create_session`/`post_auth_message_response`/
  `start_session`, no enumeration call anywhere in it) — this is a protocol
  limit, not a FormalShell gap. The session launched on successful login is
  a fixed `greeter.sessionCommand` set in Nix config, and the username is
  free-text entry.
- **`--lock`'s real-PAM-success/failure path is environment-blocked, not
  proven, on real hardware** (see parity table) — it only runs where
  `nixosModules.formalshell`'s `security.pam.services.formalshell-lock` PAM
  service exists, which today is only the VM. Switchover is exactly what
  installs that service on a real host, so this is expected to resolve
  itself the moment a host switches over — but it is not yet evidence, it's
  an expectation.
- **`--panel weather` has never been screenshotted on real hardware or in a
  repeatable VM smoke run** — see the parity table. The static `WEATHER` bar
  label (confirmed by reading `WeatherWidget.qml`: it always shows the
  literal text as an entry point, like `Clock.qml`'s `TIME`) is by design,
  but the panel's actual open-meteo forecast rendering has no sweep evidence
  behind it at all.
- **Two of the three real-hardware defects found (audio panel, Bluetooth
  panel) are fixed by code and grep-confirmed but not visually
  re-confirmed** — one because the VM has no long enough device name to
  retrigger the original elision bug's exact failure mode, the other
  because the VM has no Bluetooth adapter to render a state string on at
  all. Real hardware is what will actually prove these.
- **The core finding, stated plainly: four real-hardware defects have now
  been found by hardware sweeps that the VM structurally could not surface**
  (Wi-Fi 0..1-as-0..100 scaling, UPower title-case, the OSD auto-show signal
  bug, the audio-panel elision bug — the Bluetooth title-case bug is a fifth
  in the same class). All were found in populated-state paths (real device
  names, real signal values, real audio graphs) that the VM's minimal
  single-node fixtures never exercise. This is evidence, not speculation,
  that more of the same class of bug likely remains in code paths the VM
  cannot populate — most plausibly anywhere else a real string or numeric
  reading from hardware gets formatted for display.
- **Everything else in the parity table that reads "hardware-verified"**
  was rendered under real Mesa/Intel graphics on e1504g; everything marked
  VM-only or unverified has, at most, only ever been rendered under
  software `llvmpipe` (the VM's nested-compositor GPU path) — a genuine
  hardware GPU rendering path has not touched those surfaces yet.

## 3. The exact install path

FormalShell installs as a whole system: one home-manager module for the
shell, two NixOS modules for the system-side pieces home-manager can't
reach (a PAM service, geoclue2, greetd). The full wiring — every sub-option,
a minimal working `flake.nix`, and the exact `services.formalshell`/
`services.formalshell-greeter`/`programs.formalshell` option shapes — is
documented in this repo's `README.md` under **Install**; it is not
duplicated here to avoid the two copies drifting.

Concretely, for the owner's own `~/.config/nix` (which already wires
DankMaterialShell the same way, as a flake input with its own
`homeModules.dank-material-shell`):

1. Add `formalshell` as a flake input (`github:FormalSnake/FormalShell`).
2. Import `formalshell.nixosModules.formalshell` and
   `formalshell.nixosModules.formalshell-greeter` at the host level for the
   machine being switched (`systems/e1504g` or `systems/g815`), turning on
   `services.formalshell.enable` and configuring `services.formalshell-greeter`.
3. Import `formalshell.homeModules.formalshell` in that host's home-manager
   config and set `programs.formalshell.enable = true`, in place of (or
   alongside, for an A/B period) the current `dank-material-shell` import.
4. Run the one command that activates it: `sudo nixos-rebuild switch
   --flake ~/.config/nix#<host>` (`e1504g` or `g815`).

This report does **not** run that command and does **not** touch
`~/.config/nix` — steps 1-3 are edits to a repo this task was explicitly
told not to modify. Step 4 is the gate; crossing it is the owner's call,
informed by the parity table above (most importantly: the lock screen's
real-PAM path and the greeter have no real-hardware evidence at all yet,
only VM evidence — switchover is itself the first real test of both).

## 4. What "parity with DMS" would still require

There's no feature checklist gap against DMS today — the spec's non-goals
section already draws that line deliberately (no plugin system, no settings
GUI, no dock, no polkit agent, no screenshot/recording tooling, no sway/river
backends — DMS has some of these, FormalShell scopes them out of v1 on
purpose, not by oversight). A defined bar for the g815 switchover instead
means:

1. **Every row in the parity table above reading VM-only or unverified
   moves to hardware-verified** on at least one real host: the greeter, the
   lock screen's real-PAM paths, the weather panel, and the Hyprland
   backend in whatever form it's expected to be used.
2. **The two fixed-but-unconfirmed defects (audio panel, Bluetooth panel)
   get a real re-sweep** on hardware with a long device name and a real
   Bluetooth adapter, closing the loop the e1504g sweep couldn't.
3. **A daily-drive trial on e1504g itself**, per the spec's own build-order
   gate (`docs/superpowers/specs/2026-07-27-formalshell-design.md`: "e1504g
   daily-drive trial → switchover gate for the g815") — this report is the
   readiness assessment for switching e1504g over, not a substitute for
   actually living on it day to day before g815 follows.
4. **No new real-hardware defect class for one full sweep cycle** — the
   fact that four defects have been found across two sweeps so far, all in
   previously-unexercised populated-state paths, means the bar for
   "parity" includes running out of that specific well, not just clearing
   the four already found.
