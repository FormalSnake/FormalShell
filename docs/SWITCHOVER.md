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

**Update, 2026-07-30 (M13):** the e1504g daily-drive trial started, and its
first hours of feedback are fixed, per
`docs/superpowers/plans/2026-07-30-m13-trial-feedback-fixes.md`: workspaces
sort by the backend's `idx` and hide empty non-active ones; tray cells
vertically center, left/middle click activate/secondary-activate, right
click (or left click on an `ItemIsMenu` item) opens the item's DBusMenu as
a native popup; the github widget opens a PR/issue list panel instead of
xdg-open; calendar days are clickable with a `calendar select` IPC verb;
the menu gains a root `WALLPAPER` node (opens the picker grid), an
arity-proof no-argument `menu toggle` verb (the win+space keybind
regression), and quieted absent-`menu.jsonc` warnings; picking an emoji
auto-types it via `wtype` on top of the copy; `screenshot region` gets a
themed slurp overlay, a `screenshot.timeoutSeconds` watchdog (the host's
invisible hour-stuck slurp), and a `cancel` verb; and a motion pass adds
90-140ms opacity+translate transitions across menu/panels/OSD/toasts
behind `Theme.motion` tokens and a `motion.enabled` settings switch
(DESIGN.md §4 rewritten). All VM-only verified (mac VM rig; e1504g is
mid-trial and per the plan's own constraint was never touched). Host-trial
territory, recorded here rather than faked: slurp's visual overlay under a
real drag (no synthetic pointer exists in the rig), real applications'
tray DBusMenus opening on click (the rig asserts the Activate path against
its SNI stub; menu-open would wedge a headless run), and `wtype` really
typing into a refocused window (the rig asserts the spawn via an
argv-logging shim; the nested session has no focused client to receive
it).

**Update, 2026-07-30 (M13b):** round two of the e1504g trial feedback is
fixed, per `docs/superpowers/plans/2026-07-30-m13b-trial-feedback-round-two.md`:
launcher rows render real display names and the desktop entry's icon-theme
icon as an image (the "apps list shows app IDs" symptom was the raw icon
*name* — conventionally equal to the id — rendering as literal text in the
glyph slot); a `bell` widget joins the default bar layout (pending count,
left click toggles the center, right click flips DND — the DND glyph moves
there from the indicators slot); `theme mode toggle` works with no
wallpaper set (mode-matched Flexoki fallback written through the same
theme.json pipeline matugen uses); the nix runner shows honest
`SEARCHING`/`NO RESULTS`/`SEARCH FAILED`/`NO NIX` states and fires a
`NIX RUN` toast on Enter; and the screensaver cycles effects indefinitely
after a `screensaver.holdSeconds` hold instead of freezing on first
convergence. All VM-only verified (mac VM rig; e1504g is mid-trial and
untouched). Host-trial territory, recorded rather than faked: a real
host's icon theme resolving real apps' icons (the rig proves one honestly
installed hicolor fixture icon plus the no-icon fallback), real
`nix search` timing against cold evaluation caches (the rig's nix is a
canned shim; the `SEARCHING` row exists precisely for that
tens-of-seconds first run), and the wall-clock feel of screensaver
cycling overnight (the rig shortens `holdSeconds` and watches the
`cycles` counter, not hours of runtime).

**Update, 2026-08-03 (M15):** a third round of e1504g trial feedback is
fixed, per
`docs/superpowers/plans/2026-08-03-m15-live-feedback-density-and-audio.md`:
the weather bar cell shows a live day/night condition glyph and rounded
temperature instead of the static `WEATHER` label, sourced from a poll now
owned by the panel (same pattern `GithubPanel` established) so the widget
just flips it on; notification cards adopt Omarchy's density language —
2-line summary / 3-line body clamps rendered as `Text.StyledText`, a
40×40 icon slot, and a `sanitizeBody` step that strips the leading
URL-as-link prefix Chromium-derived senders (Chrome/Brave/Vivaldi/Edge/
Opera) glue to the front of the body — the exact cause of GitHub web
notifications reading as an unreadable wall of link markup; toast
durations follow Omarchy's low/normal/cap bands with hover-pause, and the
center gains a `CLEAR ALL` cell; and the audio panel is rewritten as an
Omarchy-style mixer (`OUTPUT`/`INPUT` master sliders plus click-to-default
device rows, an `APPS` section listing real playback streams with 0..1.5
overdrive tracks) with a combined keyboard cursor and wheel-on-track/cell
volume everywhere. All VM-only verified (mac VM rig; e1504g is mid-trial
and untouched). The weather panel in particular moves out of this report's
**Unverified** row for the first time — see the parity table and §2's
resolved bullet below.

**Update, 2026-08-18 (M29):** AirPods gets a dedicated panel and bar cell,
retiring the M17 `AIRPODS NOISE` row that used to sit at the bottom of
`BluetoothPanel`, per
`docs/superpowers/plans/2026-08-18-m29-device-panels.md`. The backend
changes too: the old integration probed the stock librepods Qt app's
write-only `/tmp/app_server` socket and could only send four commands,
never read anything back. `AirpodsPanel` now binds `AirpodsService`, which
watches the `omarchy-pods` project's extended `librepods` daemon (a
different, unrelated GPL-3.0 project — `daemon/` subtree, built and run
out-of-repo) for its own `status.json`, so battery per bud/case, the active
listening mode, Conversation Awareness, One-Bud ANC, and ear detection are
all real read-back state, not set-only writes. Switchover means replacing
the stock librepods tray app with this daemon (`librepods --headless`) as
the running service — see the host-prerequisite bullet in §2. DualSense
also gets a bar cell and panel (`DualsenseService`, read-only sysfs against
`hid-playstation`), replacing the old `custom:dualsense` command module.
Both are VM-only verified (mac VM rig, `dev/smoke-niri.sh --panel
airpods`/`--panel dualsense` — the parity table rows below); neither has
ever run against real hardware.

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
| Bar: workspaces order + hide-empty | VM-only | M13 (3c7d6fd): cells sort by the backend's per-output `idx` ordinal and a workspace renders only when occupied or active/focused (`shell/Bar/workspaces.js`, unit-covered in `tests/tst_workspaces_model.qml` over fake workspace+window models). Every plain VM smoke screenshot shows the nested session's occupied/focused workspaces only; the shaping host context — nine persistent named niri workspaces, which DMS hid when empty — is exactly what the e1504g trial itself verifies |
| Bar: SNI tray | VM-only | mac VM rig, 2026-08-14, `dev/smoke-niri.sh --tray`, `docs/screenshots/tray-niri.png` (recaptured for M24) — six real `dev/sni-stub.py` StatusNotifierItems each render as their own cell, with no visible limit and no drawer. M23's per-item pinned/drawer/hidden buckets and the older 4-item "+N" overflow chevron are both gone: bounding a long strip is the bar chevron's job now (row below). The `--tray` drive still calls `tray activate` and asserts the stub's `--activate-file` recorded a real `Activate(x, y)` over the session bus; DBusMenu *open* on a real click renders a platform QMenu no headless run can dismiss, so that leg — and any real application's menu contents — is host-trial territory. Not yet re-swept on a real host |
| Bar: chevron (collapse boundary) | VM-only | mac VM rig, 2026-08-14, `dev/smoke-niri.sh --chevron`, `docs/screenshots/chevron-collapsed-niri.png` / `chevron-expanded-niri.png` — `chevron` placed mid-right-region collapses the five entries before it (M25: the governed side runs inward, away from the region's anchored edge); `bar chevron status` asserted in both states and the two screenshots differ by exactly those cells plus the glyph direction, with the chevron and the three cells outboard of it at the same x in both, which is the anchoring claim itself. The reveal animates (`Theme.motion.standard`), and the run's shots sit three seconds past the expand so each is the end state rather than a frame inside it. The cell's own click is untested here (no synthetic pointer); `bar chevron expand` stands in for it, so a real pointer click is host-trial territory |
| Bar: indicators slot | VM-only | mac VM rig @ bd20ef6, `dev/smoke-niri.sh --notify`: the DND bell-off glyph appeared after `notifications setDnd true` over IPC. M13b (55e1ba4) moved DND display to the bell widget (row below), leaving this slot idle-inhibit only; idle-inhibit shares the same reactivity fix but has no dedicated smoke screenshot yet; not yet re-swept on a real host. M22 (afa4e34) gave the slot four cells, loudest first: a live screen recording, a pending reminder, stay-awake, night light. Only the reminder cell has ever rendered here (`--reminder`, `reminder-pending.png`); night light has only ever rendered as absent in this VM (see the night-light row below) and the recording cell has never rendered anywhere at all, since `--record` cannot start wf-recorder in this rig (see the recording row below) |
| Bar: notification bell | VM-only | M13b (55e1ba4): `bell` joins the default right region (the one owner-requested default-layout change; every no-config smoke screenshot now shows the cell). `dev/smoke-niri.sh --notify` flips DND over IPC and screenshots the bell-off swap (`docs/screenshots/indicators-niri.png`, recaptured 2026-07-30 — the bell cell crossed out with three toast cards up); `--center` asserts `notifications status` (new verb) through pending:3 → centerOpen:true → pending:0 across a showHistory toggle, the same center.open()/close() the cell's own left click calls. A real pointer click on the cell is host-trial territory (no synthetic pointer exists in the rig) |
| Notifications: card density + sanitize | VM-only | M15 (3052df0), `dev/smoke-niri.sh --notify --center` with a dense Chromium-shaped fixture (app name `Google Chrome`, a `github.com` link prefix glued to a long PR-title line plus five more body lines): `docs/screenshots/indicators-niri.png` (recaptured, toast stack) and the new `docs/screenshots/notifications-center-niri.png` (center open) both show the leading URL-as-link prefix stripped, the 2-line summary / 3-line body clamp with an ellipsis, and the `CLEAR ALL` cell beside `DND`. Hover-pause on a popup's countdown and the sender's own `expire_timeout` hint honoring the low/normal/cap duration bands have no dedicated screenshot (nothing visual distinguishes a paused timer from a running one) — proven instead by `NotificationService.qml`'s hover-pause logic and its own timer math, unit-adjacent to the model tests |
| Bar: settings-driven layout + custom modules | VM-only | mac VM rig @ bd20ef6, `dev/smoke-niri.sh --bar-layout` — a reordered left region led by six `bar.modules` entries: one happy-path `command` module (`CMD 42`), four exercising each of `CommandModule.qml`'s failure paths (all render the honest `MODULE ERROR` cell), and one `qml` module (`QML OK`); every other smoke mode's own screenshot, carrying no `bar` config, keeps proving the no-config fallback renders today's exact default arrangement; not yet re-swept on a real host. `docs/screenshots/bar-layout-niri.png` was recaptured 2026-07-30 with the M12 `github` cell heading the region, which pushes the `qml` module past the visible clip at the VM's 1276px width — its rendering stays proven by the bd20ef6 capture and `tests/tst_bar_layout.qml` |
| Bar: github widget + panel | VM-only | mac VM rig @ 8dfbe55, `dev/smoke-niri.sh --bar-layout` with a PATH-shimmed `gh` returning canned counts — `docs/screenshots/bar-layout-niri.png` (recaptured 2026-07-30) shows the octicon + `3/2` cell leading the custom left region; every default-layout mode's screenshot keeps proving the widget is absent without opt-in. M13 (fb65ee2) replaced the cell's xdg-open jump with a GithubPanel (two ledger sections, title + dimmed repo rows, row click opens the URL): `dev/smoke-niri.sh --panel github` drives `panel open github` against the extended gh shim and screenshots both sections' canned rows. Real `gh` auth states (`NO AUTH`, live counts) and real row-click xdg-open remain host-trial territory |
| Bar: usage widget + panel | VM-only | M14 (a3c0b4f), same opt-in-not-default idiom as the github widget above: `usage` is absent from `bar.layout`'s default region (every non-`--panel usage` smoke screenshot keeps proving that), and `dev/smoke-niri.sh --panel usage` drives `panel open usage` headlessly. The VM has neither `~/.claude` credentials nor a `codex` binary, so its own screenshot shows the honest `CLAUDE`/`NO AUTH` + `CODEX`/`NO CODEX` states rather than live percentages — real Anthropic OAuth usage and a real `codex app-server` JSON-RPC round trip are host-trial territory |
| Menu | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/menu.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/menu.png` (`docs/screenshots/menu-niri.png`) |
| Menu: app names + icons | VM-only | M13b (b838b8e), `dev/smoke-niri.sh --menu` — two fixture `.desktop` entries in the isolated HOME, one with a 48x48 icon honestly installed into the hicolor tree, one whose icon no theme here resolves: `debug query` asserts both rows carry display-name labels (`Iconic Test App`, `Formal Test App`, never raw ids) with `iconSource` set only for the resolvable one, and `docs/screenshots/menu-apps-niri.png` (2026-07-30) shows the icon rendered as a real image beside the no-icon fallback row. The e1504g trial's own icon theme resolving real apps (firefox, mpv, …) is exactly what the host must confirm |
| Panel: audio | Hardware-verified, fix now visually confirmed | e1504g @ 1300b02 found the percentage-lost-behind-elision defect (`artifacts/e1504g/panel-audio.png`); fixed at `4aad1d6`. **Closed:** the g815 HEAD sweep @ 52e2db0 re-screenshotted it against real long device names (`GB206 High Definition Audio Controll.`, `800 Series Chipset Family Audio Cont.`) at plausible non-1% percentages — `artifacts/g815-head/panel-audio.png` (`docs/screenshots/panels-niri.png`) — that per-device-slider layout is now superseded on VM by the row below; not yet re-swept on real hardware |
| Panel: audio: omarchy mixer rewrite | VM-only | M15 (06b5781), `dev/smoke-niri.sh --media --panel audio` with a real `mpv` MPRIS stream playing into the null sink — `docs/screenshots/audio-panel-niri.png` shows `OUTPUT`'s master slider + `Virtual Sink` device row (selected row inverted) and an `APPS` section with the live `mpv` stream at a 100% overdrive fill past the 1.0 hairline notch on its 0..1.5 track; `INPUT` is correctly absent (no input hardware in the VM). Real hardware has never seen this layout — the g815/e1504g `panel-audio.png` captures above predate the rewrite and show the old per-device-slider-only layout |
| Panel: network | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/panel-network.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/panel-network.png` — real SSID `kaiiserni` at 62% (the 0..1-scaling bug stayed fixed on a second real host) |
| Panel: bluetooth | Hardware-verified, fix now visually confirmed | e1504g @ 1300b02 found the adapter-state title-case defect (`artifacts/e1504g/panel-bluetooth.png`); fixed at `4aad1d6`. **Closed:** the g815 HEAD sweep @ 52e2db0 re-screenshotted it against a real adapter and three real paired devices (`MX Master 3S M`, `CMF Headphone Pro`, `AirPods Pro`), status correctly uppercase `ENABLED` — `artifacts/g815-head/panel-bluetooth.png` |
| Bar + panel: AirPods | VM-only | M29, `dev/smoke-niri.sh --panel airpods` — a schema-true fixture `status.json` (Pro 3, ANC mode, both buds in ear, CA on, one-bud off, lid open) staged into the isolated HOME plus a real `python3` `AF_UNIX` listener standing in for the daemon's control socket. `artifacts/airpods-panel.png` (`docs/screenshots/airpods-niri.png`) shows the bar cell's worst-bud `%` and the panel's per-bud `BATTERY` tracks, `LISTENING MODE` with the `ANC` row selected and no `Off` row (Pro 3 dropped it), `CA` `ON` in accent, `EAR DETECTION`. `qs ipc call airpods noise transparency` is asserted against the stub's own recorder file (`noise:transparency`, exactly), then the fixture is rewritten in place to `noise_mode:2` and `artifacts/airpods-live.png` proves the `FileView` watch re-rendered live (the two frames differ, the same dead-binding guard the chevron leg uses). Retires M17's `AIRPODS NOISE` row and its `/tmp/app_server` write-only probe entirely — see the M29 update above. **Never run against a real `librepods --headless` daemon or real AirPods** — that is exactly what switchover proves. |
| Bar + panel: DualSense | VM-only, honest-unavailable path proven | M29, `dev/smoke-niri.sh --panel dualsense` — the VM has no `hid-playstation` device, so the honest `NO CONTROLLER` card (with its dim `READ ONLY` title-band tag) is the correct, deterministic screenshot, and the bar cell self-hides with no controller present. **Never run against real sysfs nodes:** a real battery percent/status, a real lightbar swatch, and real player-LED dots are all real-host-trial territory — g815 already runs the owner's `dualsense-sync` host units this panel's read path depends on, so it is the natural first real target |
| Panel: power | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/panel-power.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/panel-power.png` — real battery 79%, uppercase `PENDING CHARGE`, correct active-profile highlight |
| Panel: power: brightness (backlight + DDC), low-battery warnings, static battery stats | VM-only | M16 Task 5, `dev/smoke-niri.sh --panel power` — the VM (no battery, no backlight device, no DDC monitors) renders the fully honest fallback: `AC POWER` cell, no `DISPLAY` header, a single dim `NO BACKLIGHT` row. `Power/model.js`'s `warnEvent()` hysteresis (crossings, re-arm-on-charge, charge interruptions, boot-below-threshold) is unit-covered in `tests/tst_power_model.qml`, not screenshot-provable on hardware without draining a real battery to 5-10%. **Never run against real hardware:** a real internal backlight driving `BrightnessService.set()`/`step()`, and DDC control of an actual external monitor via `ddcutil`, are both real-host-trial territory — see §2's i2c-permissions gap below |
| Panel: calendar | Hardware-verified (ics path) | e1504g @ 1300b02, `artifacts/e1504g/panel-calendar.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/panel-calendar.png` — real month grid, local-.ics fixture event. `docs/screenshots/calendar-niri.png` was recaptured 2026-07-30 (M13) from the mac VM: tomorrow's cell inverted with its EDS fixture event under the `JUL 31` dated header, today's cell keeping its accent fill |
| Calendar: EDS/GOA events | VM-only | mac VM rig @ 57efc97, `dev/smoke-niri.sh --panel calendar` — the rig seeds one real VEVENT over `formalshell-eds seed` into EDS's `system-calendar` on the run's private session bus, the service reads it back through `formalshell-eds events`, and the run's screenshot showed both the ics and the EDS fixture events under `TODAY` (the published `docs/screenshots/calendar-niri.png` has since been recaptured with M13's selected-day state, tomorrow's EDS fixture under its dated header — same rig, same backends). The GOA OAuth path (a real online account feeding EDS) has never run anywhere — the VM has no GOA account, so that leg is real-host-trial territory |
| Calendar: day selection | VM-only | M13 (2b23b4c), `dev/smoke-niri.sh --panel calendar` — the drive seeds a second EDS VEVENT dated tomorrow, calls `calendar select <tomorrow>` after the open, asserts `calendar status` reports tomorrow selected, and the screenshot (`docs/screenshots/calendar-niri.png`, recaptured 2026-07-30) shows tomorrow's cell inverted with its fixture event under the dated meta header while today keeps its accent marker |
| Calendar: RRULE expansion | VM-only | `tests/tst_calendar_ics.qml` @ aa3c61a — bounded expansion of FREQ=DAILY/WEEKLY/MONTHLY/YEARLY with INTERVAL/COUNT/UNTIL/weekly-BYDAY/EXDATE, unsupported rules falling back to a single occurrence. Pure-JS logic, so the headless tests are the whole evidence; there is nothing to screenshot |
| Menu: calculator | VM-only | mac VM rig @ 61da420, `dev/smoke-niri.sh --menu` — `debug query "2+2*3"` returns the `= 8` CALC row as the first ranked result (the run's `calc-query.json` artifact); parser edge cases in `tests/tst_menu_calc.qml` |
| Menu: emoji | VM-only | mac VM rig @ 913d9a3, `dev/smoke-niri.sh --menu` — `debug query ":e thumbs"` returns the 👍 THUMBS UP row from the vendored `emoji.json` (the run's `emoji-query.json` artifact); dataset load + search in `tests/tst_menu_emoji.qml` |
| Menu: nix runner | VM-only | mac VM rig @ 76757d5, `dev/smoke-niri.sh --menu` — two-pass `debug query ":nix hello"` against the PATH-shimmed `nix` returns the canned `hello` attr row after the 500ms debounce (the run's `nix-query.json` artifact). M13b (5bea2ed) added the honest states, each asserted by the extended drive against a query-dispatching shim: `SEARCHING` while the shim blocks on a gate flag file, `NO RESULTS` on a clean `{}`, `SEARCH FAILED` on a nonzero exit, plus a screenshotted `NIX RUN` toast (`nix-toast.png`) on row activation with a `notifications status` popup-count assert. Real `nix search` timing (the tens-of-seconds cold-cache first run the `SEARCHING` row exists for) and the `ghostty` spawn stay host-trial territory |
| Menu: share (LocalSend) | VM-only | M17 Task 1, `dev/smoke-niri.sh --share` — the presence gate resolves for real against the VM's `pkgs.localsend` closure (`docs/screenshots/share-menu-niri.png` — CLIPBOARD/PICK FROM HISTORY/RECEIVE rows). A second phase hands off to a PATH-shadowed second instance (the same takeover protocol `--instance` mode proves) whose own presence check genuinely cannot find `localsend_app`, and the SHARE node disappears from the tree entirely, screenshotted with the plain root menu and no SHARE row at all. LocalSend's own CLI has no headless auto-send mode (verified against upstream's `LoadSelectionFromArgsAction`) — a share still ends with LocalSend's GUI open, which is real-host-trial territory, along with a genuine cross-device transfer over LAN. **M17 Task 3's own menu-regression check** ran `dev/smoke-niri.sh --share --panel bluetooth --menu` for the first time — all three legs sharing one nested session — and it failed twice on unrelated grounds before passing clean: `share-drive.sh`'s own `menu activate 0` (aimed at the CLIPBOARD row) was landing on `--menu`'s still-open `select()` overlay instead, picking list index 0 and leaving `menu-selection.txt` with a real `{token,value}` pick instead of the close-to-cancel `{"cancelled":true}` `--menu`'s own assertion expects; and separately, `share_mode`'s own primary-instance launch line dropped `--menu`'s `nix`/`wtype` PATH shims entirely, sending `menu_finish_script`'s nix-search legs at the VM's real `nix` and hanging the released-search assertion on `SEARCHING` forever. Both were smoke-harness scheduling/PATH bugs, not shell defects: `share-drive.sh` now waits on a completion marker `--menu`'s own finish script touches as its last action before it touches the menu route at all, and the primary-instance launch line carries the shim PATH prefix through regardless of which mode owns it. Confirmed the fix didn't regress `--share` alone (still SMOKE_OK end to end). **CORRECTED 2026-08-04:** the original CLIPBOARD mechanism above (`localsend_app -t <text>`) was a no-op on real LocalSend — `LoadSelectionFromArgsAction` drops every dash-prefixed arg before its existence check ever runs, so `-t` and the text after it were both silently discarded and the launched GUI opened with nothing selected; the smoke assertion only checked that `-t <text>` reached argv, which was true but proved nothing about LocalSend actually using it. Fixed to omarchy's own shape: a text entry is written to a mktemp `.txt` file first, then shared by that file's path exactly like an image entry. Re-verified for real: `dev/vm.sh smoke --share` launched `/run/current-system/sw/bin/localsend_app /tmp/tmp.21xW6rS7av.txt`, and the temp file's own on-disk contents (read back by PID, not assumed) were the exact fixture text `share smoke fixture` — proof the text now reaches LocalSend through a real path its arg parser accepts, not a flag it silently drops. `just vm-test` (592/592 passing, including the 12 corrected `MenuShare` cases) and `just vm-lint` (`all checks passed!`) also re-ran clean |
| Screenshot IPC | VM-only | mac VM rig @ fd56a5f, `dev/smoke-niri.sh --screenshot` — `screenshot full`'s replied path exists as a valid PNG and `wl-paste --list-types` offers `image/png` in-session. M13 (d2d55a5) added the region watchdog and cancel: the extended drive starts `screenshot region`, round-trips `status` through `capturing:true`, calls `cancel`, and confirms cancelled-not-stuck state plus a still-working `full` afterward in the same session. The themed slurp overlay under a real drag stays host-trial — no synthetic pointer exists in the rig |
| Bar + panel: weather | VM-only | Never included in any real-hardware sweep (neither e1504g's 18-mode run, the older g815 run, nor the 2026-07-29 g815 HEAD resweep drove `--panel weather`) — still real-host-trial territory. **Closed the "never a repeatable smoke run" half:** M15 (e789de0) replaced the bar cell's static `WEATHER` label with a live day/night condition glyph + rounded temperature (poll now owned by `WeatherPanel`, same pattern as `GithubPanel`, so the widget just flips `pollEnabled`), and `dev/smoke-niri.sh --panel weather`'s location-override fixture makes the run reproducible: `docs/screenshots/weather-niri.png` shows the bar cell's live `☁ 16°` cell next to a real open-meteo fetch in the panel (`OVERCAST 16°` hero row, a 5-day forecast ledger). Before the first fetch, or with no location fix, both the cell and this same fixture-less run show the honest dim static glyph instead of a fake reading (confirmed on a separate `just vm-smoke` run taken before the async fetch resolves) |
| Notifications | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/notify.png`, `notify-center.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/notify.png`, `notify-center.png` (`docs/screenshots/notifications-niri.png`) |
| OSD | Hardware-verified, fix now confirmed on real PipeWire | e1504g @ 1300b02 found the auto-show reactivity defect (`osd-volume.png` never updated on an external `wpctl set-volume`); manual volume/brightness legs passed (`osd-manual.png`, `osd-brightness.png`). Fixed at `4aad1d6` (wrong signal name, `onVolumeChanged` vs `onVolumesChanged`). **Closed:** the g815 HEAD sweep @ 52e2db0 fired a real `wpctl set-volume @DEFAULT_AUDIO_SINK@ 30%` against a real PipeWire graph and the OSD auto-showed correctly — `artifacts/g815-head/osd-auto.png` (`docs/screenshots/osd-niri.png`), brightness leg cross-checked against the real `nvidia_wmi_ec_backlight` (100/100) |
| Clipboard | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/clipboard.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/clipboard.png` (`docs/screenshots/clipboard-niri.png`) |
| Now playing (media) | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/media.png` + `panel-media.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/media.png` (`docs/screenshots/media-niri.png`), `panel-media.png` (honest `NO PLAYER` empty state when no MPRIS player is running) — real MPRIS via mpv into the hardware sink |
| Lock screen | Partially hardware-verified | e1504g @ 1300b02 and the g815 HEAD sweep @ 52e2db0 (`artifacts/g815-head/lock-locked.png` = `docs/screenshots/lock-niri.png`, `lock-error.png`, `lock-unlocked.png`) both prove render, the `lock`/`isLocked` IPC round trip, and fail-closed behavior — but **environment-blocked** on the actual PAM success/failure paths on both real hosts, since neither had a `formalshell-lock` PAM service (that's exactly what switchover installs). Those two paths remain **VM-only verified** (the mac VM rig has `nixosModules.formalshell`'s PAM service) |
| Screensaver | Hardware-verified | e1504g @ 1300b02, `screensaver-auto.png`, `screensaver-manual.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/screensaver-auto.png` (`docs/screenshots/screensaver-niri.png`) — real `IdleMonitor` + live-media guard, confirmed on a second host |
| Picker | Hardware-verified | e1504g @ 1300b02, `picker-grid.png`, `picker-select.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/picker-grid.png` (`docs/screenshots/picker-niri.png`), `picker-selection.png` — real matugen recolor on choose |
| Greeter | **VM-only** | Never run against real greetd on either Linux host (neither has switched to `nixosModules.formalshell-greeter`), and this is intentionally out of scope for `dev/smoke-niri.sh`-style hardware sweeps. Verified via `just vm-greeter` / `dev/smoke-greeter.sh` on the mac VM rig, re-run 2026-07-29 at the same HEAD: real PAM auth round trip, `artifacts/greeter/greeter-pre-auth.png` (`docs/screenshots/greeter-niri.png`), `greeter-wrong-pw.png`, `greeter-post-auth.png` |
| Theming (matugen) | Hardware-verified | e1504g @ 1300b02, `artifacts/e1504g/wallpaper.png`; g815 HEAD sweep @ 52e2db0, `artifacts/g815-head/wallpaper.png` — real matugen run recoloring bar/workspace accents from a wallpaper, confirmed on a second real host |
| Theming: no-wallpaper mode toggle | VM-only | M13b (bf993e3), `dev/smoke-niri.sh --theme-toggle` — with wallpaper kept `""`, `theme mode toggle` flips `theme status` to `mode:"light"` and back, and the paired screenshots (`docs/screenshots/theme-dark-niri.png` / `theme-light-niri.png`, 2026-07-30, same session seconds apart) show the whole shell recoloring between the Flexoki dark and light fallbacks with no matugen involved; a following `--wallpaper` run proves the matugen path unchanged |
| Screensaver: continuous cycling | VM-only | M13b (f336f98), `dev/smoke-niri.sh --screensaver` extended — `holdSeconds` shortened via the settings fixture, then past convergence + hold the run asserts `screensaver frameInfo`'s new `cycles` counter incremented and the reported effect changed with no IPC nudge (reroll logic unit-covered in `tests/tst_screensaver_effect.qml`: random never repeats the immediately previous effect, a pinned name rerolls a fresh seed); `--screensaver-gif` still records single deterministic effects, cycling suspended while `frame(n)` pins the surface. Overnight wall-clock feel on a real idle host is trial territory |
| Polkit agent | VM-only | M16 Task 4, `dev/smoke-niri.sh --polkit` — a real `pkexec true` request routes to `PolkitService.qml`'s registered `PolkitAgent`: `polkit-active.png` shows the centered `AUTHENTICATION REQUIRED` card, `polkit-error.png` shows the urgent-italic `WRONG PASSWORD` retry state after a real `wtype`d wrong password, and the run asserts the backgrounded `pkexec`'s own exit code is 0 once the VM's real test password resolves the same `AuthFlow`. Needed `security.polkit.enablePkexecWrapper = true` in `nix/testvm.nix`: on this pinned nixpkgs rev, `security.polkit.enable` alone no longer installs the setuid `pkexec` wrapper (a recent hardening split) — reproduced directly (`pkexec must be setuid root`, exit 127) before adding it. Never run on real hardware — see §2's one-agent-per-session gap below |
| Tailscale widget + panel | VM-only, honest-unavailable path proven | M16 Task 8, `dev/smoke-niri.sh --panel tailscale` — the VM carries no `tailscale`/`tailscaled` binary at all, so `TailscalePanel.qml`'s poll exits 127 and the screenshot shows the dim `NO TAILSCALE` cell, the correct deterministic result. `Tailscale/model.js`'s `parseStatus()`/`selfIp()` (running/stopped/needs-login/no-daemon fixtures, peer sort, honest nulls) are unit-covered in `tests/tst_tailscale_model.qml`. **Never run against a real tailscaled:** the STATUS toggle's real `tailscale up`/`down` round trip, a real `NEEDS LOGIN` state, real peer rows, and the `NOT OPERATOR` permission-denied path are all real-host-trial territory — see §2's tailscale-operator gap below |
| Night light | VM-only, honest-failure path proven | M16 Task 6, `dev/smoke-niri.sh --nightlight` — `nightlight enable` drives a real `wlsunset` process and `nightlight status` is polled to a settled state. Every VM run so far lands on the honest failure branch: this VM's nested niri (winit backend) does not advertise `wlr-gamma-control-unstable-v1` at all — confirmed independently outside the shell (`wlsunset` alone against the same nested session prints `compositor doesn't support wlr-gamma-control-unstable-v1` and exits within milliseconds of connecting, before any signal is even sent) — so `active:false` with `lastError` populated is the correct, deterministic result here, not flakiness. `nightlight-active.png` shows the bar with the indicator slot correctly empty (idle-inhibit and night-light both false, so the whole `Indicators.qml` row hides, per its own "never an empty box" contract). The `md-lightbulb_night` glyph (U+F1A4C, verified against the pinned cmap) and the `active:true` bar state have never rendered anywhere — real hardware with a compositor that implements gamma control (or a nested backend that does) is what switchover needs to prove the glyph itself |

| Capture: region picker (`screenshot pick`) | VM-only | M22 (afa4e34, arity fix 9c40127), `dev/smoke-niri.sh --capture` against a session holding one real tiled foot window: `pick smart` opens the shell's own Overlay-layer picker (not slurp), `pickerStatus` reports the named-window / drawable-rectangle split niri forces, `key tab` moves the cursor and a second dump proves it moved, a third dump records the exact rectangle about to be captured so the resulting PNG's real pixel dimensions are checked against `niri msg -j outputs` rather than merely existing, and a following `pick region` dismissed with `key escape` proves the cancel path leaves no surface and no file behind (`capture-picker.png` shows the frozen screen, the scrim, the selection border and the named-window card). The toolbar (2026-08-12) is verified in the same leg: `key 4` selects the REC SCREEN cell through the same `setTool()` a click on it calls, `pickerStatus` proves the switch took (`"mode":"fullscreen","action":"record","tool":3`) and preselected the focused output rather than leaving the commit cell with nothing to act on, and `capture-toolbar-record.png` shows both group labels, all six cells with the current one inverted, the ink commit cell reading RECORD, the selection border swapped to `urgent` and the legend following the action. `capture-picker.png` is the same surface in its shot state. Two halves stay untested: a real pointer drag and real key delivery into an Exclusive-focus surface (the rig has no synthetic pointer, so `screenshot key` stands in, the same split `tray expand` and `picker choose` already use), and the whole Hyprland affordance, since window rectangles exist only there and no Hyprland run has ever happened on real hardware |
| Capture: OCR and color pick (`capture`) | VM-only, pipeline proven, selection not | M22 (afa4e34), `dev/smoke-niri.sh --ocr` against a real foot window carrying known text on a known `#3fae2a` background. `capture text` starts a real `slurp -d` and `capture color` slurp's single-point mode instead (asserted by pgrep, since the two verbs differ only in the flags they hand slurp), both cancel clean with no slurp left behind, and the clipboard still holds the rig's own sentinel, which proves a cancelled capture copied nothing rather than merely reporting that it didn't. `textAt`/`colorAt` then run the identical pipelines from a supplied geometry, and that is what proves grim to tesseract to wl-copy, and grim to od to hex to wl-copy, end to end. The selection itself is host-trial: both bare verbs block on a real slurp drag, and slurp cannot be shimmed off the shell's PATH the way `nix`/`gh` can (`nix/package.nix` installs it with `--prefix`, which outranks anything the rig prepends). OCR accuracy is reported, never asserted: tesseract reads the bar's own text off a real capture reliably, but the fixture terminal's 28px dark-on-green body is not reliably recognized under llvmpipe |
| Recording (`record`) | **Unverified, environment-blocked** | M22 (afa4e34) ships `Services/RecordingService.qml` and a `dev/smoke-niri.sh --record` leg that cannot pass in this rig, for a reason outside the shell: nested niri under llvmpipe advertises `zwp_linux_dmabuf_v1` at version 3 (`failed building default dmabuf feedback, falling back to v3`) and wf-recorder 0.6.0 binds version 4 unconditionally, so the registry bind is rejected before any recording key matters. Nothing about screen recording has therefore run anywhere: not the wf-recorder child, not the desktop or desktop+mic audio mixing, not the two-pass GIF transcode, and not the bar's recording cell, which exists only while a recording is live. This needs a real GPU, which makes it the largest single thing switchover would be the first to test. The capture picker's own record path (`RecordingService.startAt`, 2026-08-12) is blocked at exactly the same line and no earlier: `dev/smoke-niri.sh --capture` drives the toolbar's REC SCREEN cell to a committed rectangle, the picker unmaps itself, and a wf-recorder child is spawned carrying this run's resolved output name on its argv — which is what its own stderr then names before the dmabuf bind kills it. So the handoff is verified and the recorder is not; the leg reports that as `SMOKE_CAPTURE_RECORD_BLOCKED` with the stderr quoted, and fails outright if `lastError` is empty (nothing launched) or names anything other than the known dmabuf block |
| Reminders (`reminder`) | VM-only | M22 (afa4e34), `dev/smoke-niri.sh --reminder`: one real 12s countdown, long enough for the pending state to be screenshotted on the bar (`reminder-pending.png`), dumped through `reminder status`, and read back out of the real `state.json`, which is where a reminder survives a shell restart. DND is switched on before the reminder is ever set, so the toast that lands after the deadline (`reminder-fired.png`) can only have reached the popup tier through `Notifications/model.js`'s urgency-2 bypass: the bypass proven rather than read off the source. Afterwards `reminder status` is back to 0 and `state.json` no longer carries the entry |
| Menu: toggle hub | VM-only | M22 (afa4e34), `dev/smoke-niri.sh --toggles`: `debug query` carries each row's resolved `checked`, so the checkmark is readable from outside the process, and `menu status` is byte-identical before and after a toggle, which is what "the hub stays open" means here. The DND row is what proves a checkmark flipping false to true inside the open hub, cross-checked against `notifications status`. The night-light row is the cross-check that a checkmark tracks the service rather than the request: on this VM both stay honestly false, because wlsunset cannot hold a session with no gamma control (see the night-light row below) |
| Menu: keybinds route | VM-only | M22 (afa4e34), `dev/smoke-niri.sh --keybinds`: a real `config.kdl` written into the isolated `XDG_CONFIG_HOME`, with the nested session deliberately launched from a different config path so the documented lookup chain is what has to resolve rather than an override. The fixture is a real config, not a bare binds block (a preceding sibling block with nested braces, a quoted argument holding `//` and braces, a hotkey-overlay-title property, a line comment, a slashdash-disabled bind), and the assertions are exact: five live rows, the disabled bind absent, each fixture chord carrying its own action, and none of the route's four honest end-state rows. The Hyprland leg (`hyprctl binds -j`) has no equivalent run anywhere |
| Plugins | VM-only, `bar` kind only | M22 (afa4e34), `dev/smoke-niri.sh --plugins`: a real drop-in directory (`manifest.json` plus an `entry.qml` that itself imports `qs.Core` and reads `Theme`) under the isolated config home, read back through the `plugins` target. No `bar` key is written for this leg on purpose, since the manifest's own `region` is what places the cell, so dropping the directory in is the whole install. `plugins status` reporting one loaded bar plugin with no errors and no warnings is the only place a plugin's entry QML failing to load is visible from outside the process, because plugin QML lives outside this repo and qmllint never sees it. The `panel`, `overlay` and `service` kinds are covered at the manifest level only (`tests/tst_plugin_manifest.qml`) and have never been loaded from a real directory in a running session |
| Bar: opt-in microphone, keyboard layout, system update | VM-only | M22 (afa4e34), all three absent from the default layout, which every other smoke screenshot keeps proving. `--mic` points `bar.layout` at the `microphone` builtin and the honest `NO MIC` label is the passing result: this VM has a pipewire null sink and no capture device, so a glyph here would mean the widget invented one, and the live and muted states need real capture hardware. `--systemupdate` points `systemUpdate.flakeDir` at this repo, so the panel parses a real `flake.lock` and probes the real upstream refs behind its real inputs; no count is asserted, since that would be asserting the state of GitHub rather than of the panel. `keyboardLayout` has no smoke flag at all: the nested session carries one layout, so `Compositor/keyboard.js` is unit-covered (`tests/tst_keyboard_layout.qml`) and the widget has never rendered a real layout switch |
| Menu: launch-or-focus on app rows | VM-only, unit tests only | M22 (afa4e34): activating an app row whose window is already open raises it instead of spawning a second copy, and repeat activation cycles that app's windows. `Compositor/appmatch.js` (`startupClass` then entry id, first tier wins, no fuzzy tier) is unit-covered in `tests/tst_app_match.qml`; no smoke leg drives it, because the nested session has no second instance of a real desktop entry to raise. This is the behavior change a daily driver meets first, on every launcher use |
| Notifications: repeat collapse | VM-only, unit tests only | M22 (afa4e34): identical notifications (same app name, same summary; body deliberately out of the key) collapse into one card carrying a repeat count, and `MAX_POPUPS` caps groups rather than raw entries so five repeats cannot evict four unrelated toasts. `tests/tst_notifications_model.qml` covers the grouping; no smoke leg fires a repeat, so the collapsed card has never been screenshotted. The case it exists for is a chat app firing one summary per message, which is a real-host phenomenon |

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
- **Resolved 2026-08-03 (M15): `--panel weather` now has a repeatable VM
  smoke run.** The static `WEATHER` bar label — an owner-reported dead end
  ("clicking on it does show weather") — is gone; the cell now renders a
  live day/night condition glyph + rounded temperature once the panel's own
  poll has data (see the parity table's `Bar + panel: weather` row,
  `docs/screenshots/weather-niri.png`). **Still open:** real hardware has
  never driven `--panel weather` at all, so genuine geoclue location
  resolution and real Berlin-shaped-or-otherwise forecast data remain
  real-host-trial territory.
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
- **DDC brightness control needs `i2c-dev` loaded and i2c group access —
  `ddcutil` fails silently (honestly) without either.** `BrightnessService`'s
  DDC path (M16 Task 5) shells out to `ddcutil detect --brief`/`getvcp`/
  `setvcp`, which need the kernel's `i2c-dev` module loaded
  (`hardware.i2c.enable = true;` in NixOS, or `modprobe i2c-dev`) and the
  invoking user in the `i2c` group (or an equivalent udev rule granting
  `/dev/i2c-*` access) — without both, `ddcutil detect` finds nothing and
  the panel's `DISPLAY` section just shows the backlight-only rows it
  already shows in the VM, no error surfaced anywhere. Neither Linux host's
  i2c/DDC state has been checked yet; this is what switchover needs to
  confirm before external-monitor brightness can work at all. Until
  2026-08-11 there was a second and simpler reason it could not work:
  `ddcutil` was not on the shell's own PATH (next bullet), so a plain
  home-manager install never reached the i2c question in the first place.
- **Resolved 2026-08-11 (M22): the shell's own wrapper was missing four
  runtime CLIs.** `nix/package.nix` did not put `matugen`,
  `qrencode`, `cava` or `ddcutil` on the wrapped `qs`'s PATH. They resolved
  in the smoke rig only because `nix/testvm.nix` lists them in
  `environment.systemPackages`, and on a real host only if something else
  installed them, so a plain `programs.formalshell.enable` install had no
  theming, no Wi-Fi QR share, no visualizer and no external-monitor
  brightness while every smoke run passed. All four are prefixed onto the
  wrapper now, along with `wf-recorder`, `tesseract`, `ffmpeg-headless` and
  `git` for the capture suite. Worth knowing why no sweep caught it: a host
  already running DMS carries matugen for DMS's own theming, so the
  hardware-verified theming rows above were leaning on the host's system
  packages, not on anything this repo installs. Daemon-paired CLIs (`nmcli`,
  `bluetoothctl`) stay off the wrapper on purpose, since they have to match
  the NetworkManager and bluez the system is actually running.
- **Polkit agent needs a host's existing agent dropped first — only one can
  register per session.** M16 Task 4's `PolkitService.qml` never fights
  over the D-Bus registration: if another agent already owns it,
  `isRegistered` stays false, one line is logged, and `PolkitDialog.qml`
  simply never has a flow to show. **The e1504g runs
  `polkit-kde-authentication-agent-1` today (verified 2026-08-03)** —
  switchover means dropping that package/service from the host's own nix
  config, or FormalShell's agent never actually takes over privilege
  prompts there. g815's own agent situation is unconfirmed. VM-only
  verified either way (parity table) — real GUI privilege prompts (a real
  `pkexec`-using app, not the smoke rig's own `true`) have never reached
  this agent on real hardware.
- **The menu's `SHARE` route needs `localsend_app` on the host's own PATH,
  and its firewall ports open for peer discovery/transfer to actually
  work.** `default-menu.jsonc`'s `share` node gates on a live `command -v
  localsend_app` check (nixpkgs' `pkgs.localsend` installs a binary named
  `localsend_app`, not the bare `localsend` omarchy's own Arch packaging
  assumes — verified against the built package, not guessed), so nothing
  renders at all without it — but the binary alone still can't see or reach
  peers on the LAN without inbound 53317/tcp and 53317/udp allowed
  (omarchy's own `firewall.sh` opens the same two ports). Neither Linux
  host has `localsend` installed or those ports opened yet; switchover
  means adding the package and the firewall rule to the owner's own nix
  config (outside this repo). Also worth knowing going in: LocalSend has no
  true headless auto-send CLI — only a bare file path that exists on disk
  pre-populates the GUI's send selection (verified against upstream's own
  arg parser, `LoadSelectionFromArgsAction`: dash-prefixed args like `-t`
  are silently skipped and never reach a message), so a text share writes
  a mktemp `.txt` file first and a share still ends with LocalSend's window
  open, waiting for a device to be picked. Read-only proof that the
  presence gate works and that the process launches against a real file
  carrying the fixture text is VM-only (parity table) — a real
  cross-device transfer over LAN has never run anywhere.
- **Resolved 2026-08-18 (M29): the AirPods panel now reads real battery and
  mode state, not just set-only writes — but needs a different daemon
  installed than before.** `AirpodsPanel`/`AirpodsService` replace the old
  `LibrePodsService` probe of the stock librepods Qt app's `/tmp/app_server`
  socket with the `omarchy-pods` project's extended `librepods` daemon
  (`daemon/` subtree, GPL-3.0, built and run out-of-repo), which writes its
  whole state to `$XDG_STATE_HOME/librepods/status.json` and exposes a
  control socket at `$XDG_RUNTIME_DIR/librepods.sock`. **Switchover means
  running that daemon as `librepods --headless` in place of the stock app**
  — the owner's e1504g and g815 both currently run the stock app, so this
  is new host setup, not a drop-in continuation. VM-only verified so far
  (parity table); the daemon has never run on either Linux host.
- **DualSense needs `hid-playstation` bound and the owner's own
  `dualsense-sync` udev LED rule for lightbar/player-LED readability.**
  `DualsenseService` globs `/sys/class/power_supply/ps-controller-battery-*`
  and `/sys/class/leds/input*:rgb:indicator` — both node names key off an
  input index that drifts per reconnect, which is why the probe globs
  rather than pinning a path. The shell only ever reads these nodes; the
  owner's existing host units own writing the lightbar and player LEDs.
  VM-only verified (the VM has no DualSense at all, so the honest `NO
  CONTROLLER` card is the parity-table evidence); real sysfs reads are
  real-host-trial territory.
- **Tailscale up/down needs the invoking user set as operator first —
  otherwise the daemon refuses the toggle.** `TailscalePanel.qml`'s STATUS
  action cell shells out to `tailscale up`/`down` unprivileged; the real
  1.98.8 binary's own API layer rejects that from a non-root, non-operator
  user (`Access denied: …`, confirmed by a `strings` dump of the pinned nix
  store closure, not guessed), and the panel renders that honestly as
  `NOT OPERATOR` rather than pretending the toggle worked. Switchover means
  running `sudo tailscale set --operator=$USER` once per host before the
  toggle can ever succeed from this shell — read-only status polling needs
  no such grant. Neither Linux host's operator state has been checked yet.
- **Screen recording is the one shipped surface with no evidence of any
  kind.** The rig cannot reach it: nested niri under llvmpipe advertises
  `zwp_linux_dmabuf_v1` at version 3 and wf-recorder 0.6.0 binds version 4
  unconditionally, so the bind is rejected before a recording starts. That
  is an environment limit rather than a defect, and it has no software
  workaround inside this repo, so the wf-recorder child, both audio modes,
  the GIF transcode and the bar's recording cell all reach a real host
  unproven (parity table). Switchover is the first test of every one of
  them.
- **Window-mode capture looks different on niri than on Hyprland, and that
  is permanent for now.** niri reports a pixel box only for floating
  windows (`Tile::ipc_layout_template` hardcodes
  `tile_pos_in_workspace_view: None`, niri v26.04 `src/layout/tile.rs:869`),
  so a tiled window has no rectangle for the picker to highlight. Selecting
  a window works on both backends; on niri the candidates are named in a
  ledger card instead of outlined on screen, and the capture goes through
  niri's own `ScreenshotWindow` action, which crops server-side. The
  branch is on `rect === null`, never on a compositor name, so a niri that
  starts reporting tiled geometry gets the Hyprland affordance for free.
  Both Linux hosts run niri, so the named-card path is the one switchover
  actually gets.
- **A user `menu.jsonc` keyed on the old toggle ids goes inert silently.**
  M22 moved the toggle rows into their own subtree: `theme` and
  `theme.mode-toggle` are now `toggles` and `toggles.dark-mode`, and
  `system.stay-awake` is now `toggles.stay-awake`. `Model.buildTree()`
  merges a user file over the default tree by dotted id, so an override
  naming an id that no longer exists is not an error, it simply matches
  nothing: the customization disappears and the default row renders instead.
  Neither Linux host is known to carry a `~/.config/formalshell/menu.jsonc`
  today, but anyone who wrote one before 2026-08-11 has to rename those
  three ids by hand.

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
it 2026-07-29, see §2's resolved bullet and item 1 below.**

**The non-goals list quoted above has since been overtaken on three of its
six entries**, so it is no longer a shortcut for "what FormalShell does not
do": the polkit agent shipped in M16, screenshot tooling in M12 and the rest
of the capture suite (region picker, OCR, color pick, screen recording) in
M22, and the plugin system in M22. Only the settings GUI, the dock and the
sway/river backends are still genuinely out of scope. Each addition widens
the switchover surface: every one of their parity rows reads VM-only, and
recording's reads worse.

A defined bar for the g815 switchover means:

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
   the screenshot target. M22 adds ten more: the region picker, the OCR and
   color-pick verbs, reminders, the toggle hub, the keybinds route,
   plugins, the three opt-in bar widgets, launch-or-focus, notification
   repeat collapse, and screen recording, which starts one step further
   back than the rest since it has no VM evidence at all.
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
