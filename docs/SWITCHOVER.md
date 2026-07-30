# FormalShell v1 — switchover readiness report

Written at commit `4aad1d6` (HEAD of `main`), after M9 tasks 1-4 (design
retrofit, motion sweep, the e1504g real-hardware sweep, and its fixes) and
`just test` = 259 passed / 0 failed. This is Task 5 of
`docs/superpowers/plans/2026-07-28-m9-polish-and-switchover.md`: an honest
readiness assessment, not a go/no-go decision — the decision is the owner's.

**Both Linux hosts were offline at the time this report was first written.**
e1504g was powered off after its sweep completed; g815 was unavailable.
**Update, 2026-07-29:** g815 came back online and was re-swept at HEAD
`52e2db0` — 17 of `dev/smoke-niri.sh`'s 18 modes PASS outright; the 18th,
`--lock`, PASSes on render (locked/error/unlocked screens, symmetric insets,
the `lock`/`isLocked` IPC round trip) but reports `SMOKE_FAIL: lock isLocked
did not flip back to false` on its real-PAM leg, because g815 has no
`formalshell-lock` PAM service — the exact environment block this report
already documents in the parity table below and in §2's known gaps, not a
code defect. The sweep otherwise confirms the `ca56dfc` padding fix holds on
real hardware and closes two of the three previously fix-unconfirmed gaps
(audio panel, Bluetooth panel) plus the OSD auto-show reactivity fix.
Details:
`docs/superpowers/plans/2026-07-29-g815-head-resweep.md`, screenshots in
`artifacts/g815-head/` (gitignored; the 12 published `docs/screenshots/*.png`
were recaptured from this sweep the same day). The table below cites this
sweep alongside the original e1504g evidence wherever it applies.

**Update, 2026-07-29 (M10):** the SNI tray, indicators slot, and
settings-driven bar layout with custom `command`/`qml` modules — §2's
largest concrete feature gap against DMS — are built, per
`docs/superpowers/plans/2026-07-29-m10-bar-completeness-and-readme.md`.
All three are VM-only verified so far (mac VM rig, `dev/smoke-niri.sh
--tray`/`--notify`/`--bar-layout`); g815 has not been re-swept since. Task
5 of that plan, capturing screenshots of the new surfaces, found a real
regression the prior M10 tasks' own verification had missed: the imperative
"mirror the loaded widget's `visible` onto its Loader" mechanism Bar.qml's
settings-driven rewrite introduced (to drop a hidden widget's slot instead
of leaving it dead) silently detached that *same* widget's own `visible`
binding from ever updating again the instant anything outside its Loader
read it — so the tray, the indicators, and even the pre-existing (M6/M7)
now-playing cell never actually appeared once their condition turned true
after the bar had already rendered, despite every `qs ipc` status query
reporting the correct underlying state throughout. Fixed at `bd20ef6`: each
affected widget now exposes a `shown` property computed the same way its
`visible` binding already was, and Bar.qml reads `.shown` (falling back to
`true` for every widget that has none, since those never hide) instead of
ever reading `.visible` across the Loader boundary. See §2 and the parity
table below for the closed gap and its verification evidence.

**Update, 2026-07-30 (M12):** the six DMS-parity gaps the owner ruled
essential in the e1504g swap review are closed, per
`docs/superpowers/plans/2026-07-30-m12-dms-parity-and-eds.md`: EDS/GNOME
Online Accounts calendar events (via the `formalshell-eds` companion CLI —
the one compiled binary in the shell, an owner-authorized spec amendment —
plus RRULE expansion in `Calendar/ics.js`), menu calculator/emoji/
nix-runner routes, an opt-in `github` bar widget, and a `screenshot` IPC
target. All are VM-only verified (mac VM rig; both Linux hosts were offline
for the whole milestone); the GOA OAuth path specifically — a real
Google/Nextcloud account authenticated through GNOME Online Accounts
feeding EDS — has never run anywhere, since the VM's evidence is EDS's
local `system-calendar` only. See §2's resolved bullets and the seven new
parity-table rows.

## 1. Parity table

Evidence sources: the e1504g sweep at commit `1300b02`
(`docs/superpowers/plans/2026-07-28-m9-e1504g-trial.md`, screenshots in
`artifacts/e1504g/`), the g815 HEAD sweep at commit `52e2db0`
(`docs/superpowers/plans/2026-07-29-g815-head-resweep.md`, screenshots in
`artifacts/g815-head/`), an older g815 sweep at commit `707f8e3`
(`artifacts/g815/`, **M6-era — predates M7, M8, and M8b entirely**, so it
speaks only to pre-visual-retrofit rendering and is cited only where neither
newer sweep covered the same ground), and the mac VM rig (`just vm-smoke`,
this task's own runs, all at HEAD `4aad1d6`). All real-hardware evidence is
niri-backend only — no sweep has ever run `dev/smoke-hyprland.sh` on real
hardware.

| Surface | Status | Evidence |
| --- | --- | --- |
| Bar | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/plain.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/plain.png` (`docs/screenshots/bar-niri.png`) — real BAT/Wi-Fi/Bluetooth cells the VM cannot produce, and confirms the `ca56dfc` padding fix (symmetric insets, no left/top-only gutter) on real hardware |
| Bar: SNI tray | VM-only | mac VM rig @ bd20ef6, `dev/smoke-niri.sh --tray`, `docs/screenshots/tray-niri.png` — six real `dev/sni-stub.py` StatusNotifierItems collapse to three pinned cells plus a "+3" overflow drawer, which expands to "−3" over the same `tray expand` IPC call the overflow cell's own click takes; not yet re-swept on a real host |
| Bar: indicators slot | VM-only | mac VM rig @ bd20ef6, `dev/smoke-niri.sh --notify`, `docs/screenshots/indicators-niri.png` — the DND bell-off glyph appears after `notifications setDnd true` over IPC; idle-inhibit shares the same widget and reactivity fix but has no dedicated smoke screenshot yet; not yet re-swept on a real host |
| Bar: settings-driven layout + custom modules | VM-only | mac VM rig @ bd20ef6, `dev/smoke-niri.sh --bar-layout` — a reordered left region led by six `bar.modules` entries: one happy-path `command` module (`CMD 42`), four exercising each of `CommandModule.qml`'s failure paths (all render the honest `MODULE ERROR` cell), and one `qml` module (`QML OK`); every other smoke mode's own screenshot, carrying no `bar` config, keeps proving the no-config fallback renders today's exact default arrangement; not yet re-swept on a real host. `docs/screenshots/bar-layout-niri.png` was recaptured 2026-07-30 with the M12 `github` cell heading the region, which pushes the `qml` module past the visible clip at the VM's 1276px width — its rendering stays proven by the bd20ef6 capture and `tests/tst_bar_layout.qml` |
| Bar: github widget | VM-only | mac VM rig @ 8dfbe55, `dev/smoke-niri.sh --bar-layout` with a PATH-shimmed `gh` returning canned counts — `docs/screenshots/bar-layout-niri.png` (recaptured 2026-07-30) shows the octicon + `3/2` cell leading the custom left region; every default-layout mode's screenshot keeps proving the widget is absent without opt-in. Real `gh` auth states (`NO AUTH`, live counts) are host-trial territory |
| Menu | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/menu.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/menu.png` (`docs/screenshots/menu-niri.png`) |
| Panel: audio | Hardware-verified, fix now visually confirmed | e1504g @ 1300b02 found the percentage-lost-behind-elision defect (`artifacts/e1504g/panel-audio.png`); fixed at `4aad1d6`. **Closed:** the g815 HEAD sweep @ 52e2db0 re-screenshotted it against real long device names (`GB206 High Definition Audio Controll.`, `800 Series Chipset Family Audio Cont.`) at plausible non-1% percentages — `artifacts/g815-head/panel-audio.png` (`docs/screenshots/panels-niri.png`) |
| Panel: network | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/panel-network.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/panel-network.png` — real SSID `kaiiserni` at 62% (the 0..1-scaling bug stayed fixed on a second real host) |
| Panel: bluetooth | Hardware-verified, fix now visually confirmed | e1504g @ 1300b02 found the adapter-state title-case defect (`artifacts/e1504g/panel-bluetooth.png`); fixed at `4aad1d6`. **Closed:** the g815 HEAD sweep @ 52e2db0 re-screenshotted it against a real adapter and three real paired devices (`MX Master 3S M`, `CMF Headphone Pro`, `AirPods Pro`), status correctly uppercase `ENABLED` — `artifacts/g815-head/panel-bluetooth.png` |
| Panel: power | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/panel-power.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/panel-power.png` — real battery 79%, uppercase `PENDING CHARGE`, correct active-profile highlight |
| Panel: calendar | Hardware-verified (ics path) | e1504g @ 1300b02, `artifacts/e1504g/panel-calendar.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/panel-calendar.png` — real month grid, local-.ics fixture event. `docs/screenshots/calendar-niri.png` was recaptured 2026-07-30 from the mac VM to show the M12 EDS backend alongside it (both fixture events under `TODAY`) |
| Calendar: EDS/GOA events | VM-only | mac VM rig @ 57efc97, `dev/smoke-niri.sh --panel calendar` — the rig seeds one real VEVENT over `formalshell-eds seed` into EDS's `system-calendar` on the run's private session bus, the service reads it back through `formalshell-eds events`, and the screenshot shows both the ics and the EDS fixture events under `TODAY` (`docs/screenshots/calendar-niri.png`, recaptured 2026-07-30). The GOA OAuth path (a real online account feeding EDS) has never run anywhere — the VM has no GOA account, so that leg is real-host-trial territory |
| Calendar: RRULE expansion | VM-only | `tests/tst_calendar_ics.qml` @ aa3c61a — bounded expansion of FREQ=DAILY/WEEKLY/MONTHLY/YEARLY with INTERVAL/COUNT/UNTIL/weekly-BYDAY/EXDATE, unsupported rules falling back to a single occurrence. Pure-JS logic, so the headless tests are the whole evidence; there is nothing to screenshot |
| Menu: calculator | VM-only | mac VM rig @ 61da420, `dev/smoke-niri.sh --menu` — `debug query "2+2*3"` returns the `= 8` CALC row as the first ranked result (the run's `calc-query.json` artifact); parser edge cases in `tests/tst_menu_calc.qml` |
| Menu: emoji | VM-only | mac VM rig @ 913d9a3, `dev/smoke-niri.sh --menu` — `debug query ":e thumbs"` returns the 👍 THUMBS UP row from the vendored `emoji.json` (the run's `emoji-query.json` artifact); dataset load + search in `tests/tst_menu_emoji.qml` |
| Menu: nix runner | VM-only | mac VM rig @ 76757d5, `dev/smoke-niri.sh --menu` — two-pass `debug query ":nix hello"` against the PATH-shimmed `nix` returns the canned `hello` attr row after the 500ms debounce (the run's `nix-query.json` artifact). Real `nix search`/`ghostty` spawn behaviour is host-trial territory |
| Screenshot IPC | VM-only | mac VM rig @ fd56a5f, `dev/smoke-niri.sh --screenshot` — `screenshot full`'s replied path exists as a valid PNG and `wl-paste --list-types` offers `image/png` in-session; `region`'s slurp leg needs a human dragging a rectangle, so it has no headless evidence |
| Panel: weather | **Unverified** | Never included in any real-hardware sweep (neither e1504g's 18-mode run, the older g815 run, nor the 2026-07-29 g815 HEAD resweep drove `--panel weather`); only ad hoc dev-loop crops exist in `artifacts/` (`weather-crop*.png`), not a hardware or a repeatable VM smoke run |
| Notifications | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/notify.png`, `notify-center.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/notify.png`, `notify-center.png` (`docs/screenshots/notifications-niri.png`) |
| OSD | Hardware-verified, fix now confirmed on real PipeWire | e1504g @ 1300b02 found the auto-show reactivity defect (`osd-volume.png` never updated on an external `wpctl set-volume`); manual volume/brightness legs passed (`osd-manual.png`, `osd-brightness.png`). Fixed at `4aad1d6` (wrong signal name, `onVolumeChanged` vs `onVolumesChanged`). **Closed:** the g815 HEAD sweep @ 52e2db0 fired a real `wpctl set-volume @DEFAULT_AUDIO_SINK@ 30%` against a real PipeWire graph and the OSD auto-showed correctly — `artifacts/g815-head/osd-auto.png` (`docs/screenshots/osd-niri.png`), brightness leg cross-checked against the real `nvidia_wmi_ec_backlight` (100/100) |
| Clipboard | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/clipboard.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/clipboard.png` (`docs/screenshots/clipboard-niri.png`) |
| Now playing (media) | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/media.png` + `panel-media.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/media.png` (`docs/screenshots/media-niri.png`), `panel-media.png` (honest `NO PLAYER` empty state when no MPRIS player is running) — real MPRIS via mpv into the hardware sink |
| Lock screen | Partially hardware-verified | e1504g @ 1300b02 and the g815 HEAD sweep @ 52e2db0 (`artifacts/g815-head/lock-locked.png` = `docs/screenshots/lock-niri.png`, `lock-error.png`, `lock-unlocked.png`) both prove render, the `lock`/`isLocked` IPC round trip, and fail-closed behavior — but **environment-blocked** on the actual PAM success/failure paths on both real hosts, since neither had a `formalshell-lock` PAM service (that's exactly what switchover installs). Those two paths remain **VM-only verified** (the mac VM rig has `nixosModules.formalshell`'s PAM service) |
| Screensaver | Hardware-verified | e1504g @ 1300b02, `screensaver-auto.png`, `screensaver-manual.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/screensaver-auto.png` (`docs/screenshots/screensaver-niri.png`) — real `IdleMonitor` + live-media guard, confirmed on a second host |
| Picker | Hardware-verified | e1504g @ 1300b02, `picker-grid.png`, `picker-select.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/picker-grid.png` (`docs/screenshots/picker-niri.png`), `picker-selection.png` — real matugen recolor on choose |
| Greeter | **VM-only** | Never run against real greetd on either Linux host (neither has switched to `nixosModules.formalshell-greeter`), and this is intentionally out of scope for `dev/smoke-niri.sh`-style hardware sweeps. Verified via `just vm-greeter` / `dev/smoke-greeter.sh` on the mac VM rig, re-run 2026-07-29 at the same HEAD: real PAM auth round trip, `artifacts/greeter/greeter-pre-auth.png` (`docs/screenshots/greeter-niri.png`), `greeter-wrong-pw.png`, `greeter-post-auth.png` |
| Theming (matugen) | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/wallpaper.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/wallpaper.png` — real matugen run recoloring bar/workspace accents from a wallpaper, confirmed on a second real host |

Everything marked hardware-verified above is the **niri** backend only. The
Hyprland backend has never run on either Linux host — it exists only as
`dev/smoke-hyprland.sh` against a nested Hyprland session in the VM, and per
`CLAUDE.md` that nested session is flakier than niri's even there.

## 2. Known gaps and rough edges

- **Resolved 2026-07-30 (M12): calendar events now read EDS/GNOME Online
  Accounts, not just local `.ics`.** The spike's blocker (EDS ties its
  calendar objects to the lifetime of the one connection that opened them,
  which no stateless `gdbus` chain can hold) is closed by the
  `formalshell-eds` companion CLI — one process, one held sd-bus
  connection, raw ICS on stdout into the same parser — under an explicit
  owner override of the no-compiled-binary rule (spec addendum,
  2026-07-30). VM-only verified: the smoke rig seeds and reads back a real
  VEVENT through EDS's `system-calendar` (parity table). **The GOA OAuth
  path — a real online account authenticated through GNOME Online Accounts
  feeding EDS — has still never run anywhere** and is exactly what the
  real-host trial must prove.
- **Resolved 2026-07-30 (M12): RRULE expansion.** `Calendar/ics.js` now
  expands recurring `VEVENT`s into instances within the query window
  (FREQ=DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, COUNT, UNTIL, weekly BYDAY,
  simple EXDATE — `tests/tst_calendar_ics.qml`). Rules outside that subset
  (BYSETPOS, BYMONTHDAY, ordinal BYDAY, …) still fall back to a single
  occurrence at DTSTART, documented in the file header — honest
  under-expansion, not a silent guess.
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
- **Resolved 2026-07-29:** the audio-panel and Bluetooth-panel fixes were
  visually unconfirmed as of this report's original writing (VM couldn't
  reproduce a long device name or a Bluetooth adapter at all). The g815 HEAD
  resweep closed both — real long device names and three real paired
  Bluetooth devices, both rendering correctly (`artifacts/g815-head/panel-audio.png`,
  `panel-bluetooth.png`; see parity table). No defect class from the original
  five is still visually unconfirmed.
- **The core finding, stated plainly: five real-hardware defects were found
  by hardware sweeps that the VM structurally could not surface**
  (Wi-Fi 0..1-as-0..100 scaling, UPower title-case, the OSD auto-show signal
  bug, the audio-panel elision bug, the Bluetooth title-case bug). All were
  found in populated-state paths (real device names, real signal values,
  real audio graphs) that the VM's minimal single-node fixtures never
  exercise, and all five are now fixed and visually reconfirmed on real
  hardware. This remains evidence that more of the same class of bug could
  turn up in code paths the VM cannot populate — most plausibly anywhere
  else a real string or numeric reading from hardware gets formatted for
  display — but the 2026-07-29 g815 HEAD resweep (18 modes, both halves A
  and B) found zero new defects of any kind, including zero padding/gutter
  asymmetry anywhere, so this specific well has now run dry for one full
  sweep cycle.
- **Everything else in the parity table that reads "hardware-verified"**
  was rendered under real Mesa/Intel graphics on e1504g or on g815's real
  GPU (2026-07-29 resweep); everything marked VM-only or unverified has, at
  most, only ever been rendered under software `llvmpipe` (the VM's
  nested-compositor GPU path) — a genuine hardware GPU rendering path has
  not touched those surfaces yet.
- **Resolved 2026-07-29 (M10):** this report's largest concrete feature gap
  against DMS — no SNI tray, no indicators slot, no settings-driven bar
  layout, and no custom `command`/`qml` bar-widget modules, all four in
  spec §Surfaces-1's v1 scope — is closed. `Bar.qml` now resolves
  left/center/right from `bar.layout`/`bar.modules` in `settings.json`
  (`shell/Bar/layout.js`), `Quickshell.Services.SystemTray` backs a grouped
  overflow drawer (`Tray.qml`), and DND/idle-inhibit surface as glyphs
  (`Indicators.qml`) — see the parity table's three new Bar rows. All three
  are VM-only verified so far, not yet re-swept on a real host.

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

**Correction:** an earlier version of this section claimed there was no
feature checklist gap against DMS today, citing the spec's non-goals list
(no plugin system, no settings GUI, no dock, no polkit agent, no
screenshot/recording tooling, no sway/river backends). That claim was false.
The non-goals list is real, but it doesn't cover everything the spec puts
in v1 scope: §Surfaces-1 requires an SNI tray, an indicators slot (DND,
idle-inhibit, recording…), and settings-driven bar layout with custom
`command`/`qml` widget modules, and none of the three exist —
`Bar.qml`'s widget list is hardcoded, `Config.qml` marks `bar.position`
reserved with no widget-layout or custom-module keys implemented, and there
is no tray code anywhere in `shell/` (`rg -il
'systemtray|statusnotifier' shell/` matches nothing; `git log -S SystemTray
-- shell/` is empty). **This in turn is now itself historical — M10 closed
it 2026-07-29, see §2's resolved bullet and item 1 below.** A defined bar
for the g815 switchover means:

1. ~~The tray, indicators slot, and settings-driven bar layout/custom
   modules get built~~ — **done 2026-07-29 (M10)**: all three exist and are
   VM-verified (see §2 and the parity table's three new Bar rows); they
   join item 2 below for the still-outstanding real-hardware sweep.
2. **Every row in the parity table above reading VM-only or unverified
   moves to hardware-verified** on at least one real host: the greeter, the
   lock screen's real-PAM paths, the weather panel, the Hyprland backend in
   whatever form it's expected to be used, the tray, indicators slot, and
   settings-driven bar layout M10 added, and now M12's six rows — EDS/GOA
   calendar events (including the never-run GOA OAuth leg), RRULE
   expansion, the calculator/emoji/nix menu routes, the github widget, and
   the screenshot target.
3. ~~The two fixed-but-unconfirmed defects (audio panel, Bluetooth panel)
   get a real re-sweep~~ — **done 2026-07-29**: the g815 HEAD resweep hit a
   real long device name and a real Bluetooth adapter, closing the loop the
   e1504g sweep couldn't (see parity table).
4. **A daily-drive trial on e1504g itself**, per the spec's own build-order
   gate (`docs/superpowers/specs/2026-07-27-formalshell-design.md`: "e1504g
   daily-drive trial → switchover gate for the g815") — this report is the
   readiness assessment for switching e1504g over, not a substitute for
   actually living on it day to day before g815 follows.
5. **No new real-hardware defect class for one full sweep cycle** — the
   fact that four defects have been found across two sweeps so far, all in
   previously-unexercised populated-state paths, means the bar for
   "parity" includes running out of that specific well, not just clearing
   the four already found.
