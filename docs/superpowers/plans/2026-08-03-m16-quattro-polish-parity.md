# FormalShell M16: quattro polish parity — density unification, motion consistency, laptop feature gaps

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. M15
> (`2026-08-03-m15-live-feedback-density-and-audio.md`) landed immediately
> before this plan; its task notes are context for every file touched here.

**Origin, owner ask (2026-08-03):** "Make sure we match the same level of
features and polish omarchy quattro has, but not bloated for my laptop's
use case. In my design language animations are subtle, smooth, and
tasteful. We use ASCII and nerd fonts, to match the terminal TUI aesthetic.
Make sure font sizes and densities are consistent too." Follow-up
(same day): "tailscale, speed-test, multi monitor and DDC is good for us
too" — those four move from the skip list into Tasks 5/7/8/9.

**Research already done (2026-08-03), do not re-derive.** Omarchy clone
freshly pulled to `12af188` (23 commits past M14's `fa95901`; 9 touch the
shell UI — IPC-completeness pass `f54edbe`, battery-percent toggle,
in-place bar config patching, Setup>Network menu, cross-monitor dismiss).
Full audits of both trees were run this session; findings below carry
file:line pointers.

*FormalShell density/typography audit:*

- Every `font.pixelSize` in `shell/` resolves through `Theme.fontSize.*` —
  zero raw literals. Two unregistered scale steps exist
  (`shell/Components/AuthPrompt.qml:114` `displayLarge * 4`,
  `shell/Surfaces/Screensaver/Screensaver.qml:249` `body * 2.4`) — both
  token-derived and rescale correctly; leave them, do not add scale steps.
- Two parallel spacing systems are live: legacy **fixed**
  `Theme.spacing = {xs:2, sm:4, md:8, lg:16}` (`shell/Core/Theme.qml:53`,
  never scales) vs scaling `Theme.space` (`Theme.qml:35`,
  `tokens.js` `SPACING_BASE`). Usage tally: `spacing.xs` ×30, `.sm` ×23,
  `.md` ×15, `.lg` ×0. Value-preserving map: `xs→space.xxs` (2),
  `sm→space.sm` (4), `md→space.lg` (8).
- `shell/Components/Cell.qml:44-45,81-84` — the shared row/cell primitive
  under every bar cell, panel row, menu row, and notification card — pads
  with the legacy fixed scale, so row density does not track
  `fontBaseSize` while the text inside does.
- **Visible density bug:** `shell/Surfaces/Bar/Bar.qml:264` left region
  inter-widget spacing is `Theme.spacing.md` (8 fixed) while center/right
  (`Bar.qml:291,314`) use `Theme.space.sm` (4 scaling). DESIGN.md §3 says
  bar cells are separated by "sm-ish gaps" — unify all three regions on
  `Theme.space.sm`.
- **Visible density bug:** the flat slider/track idiom is `height: 6` at
  `AudioPanel.qml:277,371,451`, `CalendarPanel.qml:463`,
  `MediaPanel.qml:94`, `PowerPanel.qml:106`, `UsagePanel.qml:315` — but
  `shell/Surfaces/Osd/Osd.qml:273` uses `height: 4` for the identical
  idiom its own comment claims mirrors the others.
- `shell/Theme/tokens.js:39-43` declares nine semantic tokens
  (`controlGap`…`labelGap`) that nothing consumes. They stay declared
  (DESIGN.md §1.3 documents the vocabulary); wiring them is out of scope
  because it would change rendered output.
- Letter-spacing is ad hoc: `MetaLabel.qml:13-14` is the canonical
  uppercase+`letterSpacing:1` meta row, but `Center.qml:171-172,194-195`
  (DND / CLEAR ALL cells) reimplement the combination on plain `Text`,
  and `AuthPrompt.qml:123` uses a third value (`2`) for the date label.
- `CalendarPanel.qml:375` hardcodes `spacing: 2` (should be
  `Theme.space.xxs`).

*FormalShell motion audit:*

- All durations/easings already flow through `Theme.motion` tokens
  (`tokens.js:63-71`) — zero hardcoded literals. Strength, keep it that way.
- Same-idiom inconsistency: hover-revealed FORGET cells fade 100ms
  (`BluetoothPanel.qml:326-335`, `NetworkPanel.qml:465-474`) but four
  sibling opacity state-swaps snap: `AudioPanel.qml:255` (stream mute
  dim), `MediaPanel.qml:128,174` (transport disabled dim),
  `CalendarPanel.qml:393` (event dot).
- `Screensaver.qml:207` is a bare `visible:` binding — no enter fade.
  DESIGN.md §3 sanctions the *exit* being instant; the entrance is not
  covered and currently pops.
- `LockSurface.qml` has no animations at all — leave it; a security
  surface snapping shut/open is deliberate. DESIGN.md §4 gains one line
  naming lock enter/exit and screensaver exit as sanctioned-instant.
- Menu card re-centers on every keystroke: `Menu.qml:349` tracks live
  `rowsView.contentHeight`, `:790` re-derives `top` from
  `implicitHeight`. Omarchy freezes card top on first keystroke/submenu
  move so resizes grow downward (`~/Developer/omarchy/shell/plugins/menu/Menu.qml:1010-1020`).
- Bar cells whose text length changes (`ActiveWindow.qml`,
  `NowPlaying.qml`) resize instantly, shoving neighbors. Omarchy animates
  the label width 180ms (`~/Developer/omarchy/shell/plugins/bar/widgets/ActiveWindow.qml:20-22`);
  ours stays inside the band at `Theme.motion.standard`.
- `Background.qml:19-23` is a single `Image` — wallpaper set is a
  full-screen hard cut. Omarchy runs a 420ms InOutCubic slanted-wipe
  (`Background.qml:161-176` there); we do a plain crossfade, not the wipe.

*Laptop-relevant feature gaps (omarchy has, we lack):*

- **Polkit agent** — omarchy registers a native agent
  (`shell/plugins/polkit/PolkitAgent.qml` there, read it for flow
  handling; error shake NOT ported — our error idiom is the lock
  screen's urgent border + italic message). Pinned quickshell ships it:
  `src/services/polkit/qml.hpp` (`PolkitAgent` QML element: `path`,
  `isRegistered`, `isActive`, `flow`; conversation outcome signals on the
  `AuthFlow` — read `flow.hpp` for the respond/cancel API), built ON by
  default (`default.nix:52` `withPolkit ? true` →
  `SERVICE_POLKIT`). Without an agent, GUI privilege prompts have
  nowhere to land on the daily-driven host.
- **Low-battery warnings** — omarchy's `omarchy.battery` service warns;
  we render a percent and nothing else. UPower fractions are 0..1
  (CLAUDE.md hard rule).
- **Brightness has no mouse surface** — `shell/Services/BrightnessService.qml`
  already exists (brightnessctl-backed `set()`/`step()`/`refresh()`,
  honest `available`), consumed only by the OSD's IPC route. Omarchy has
  a Monitor panel slider. DDC/external monitors NOT ported (laptop).
- **Night light** — omarchy has a nightlight service + bar indicator. We
  have nothing. wlsunset-as-Process, opt-in.
- **Bluetooth has no IPC target** — omarchy just exposed every UI-only
  toggle over IPC (`f54edbe`: `toggleBluetooth`, `toggleNetwork`…). Our
  `network` target has `wifi(enabled)`; bluetooth power is mouse-only.
- **Multi-monitor dismiss** — our `shell/Components/Panel.qml:16-21`
  backdrop (transparent full-screen `PanelWindow` on the panel's own
  output) has exactly the limitation omarchy fixed in `3cb3861`: the
  compositor hit-tests pointer input per-output, so a click on another
  monitor never reaches the backdrop. Omarchy's fix
  (`shell/Ui/KeyboardPanel.qml:343-375` there): while open, spawn a
  transparent, input-transparent-to-keyboard twin `PanelWindow` per
  *other* screen whose only job is close-on-press. `Menu.qml` and
  `Center.qml` carry the same single-output backdrop.
- **DDC external-monitor brightness** — omarchy's shell always calls one
  script with the focused monitor name; the script picks kernel
  backlight vs ddcutil, caching the I²C bus per monitor and a 60s
  "unavailable" verdict (`bin/omarchy-brightness-display-ddc:1-40`
  there — read the whole script for the cache/getvcp/setvcp shape).
  Our `BrightnessService` is backlight-only.
- **Tailscale** — omarchy panel (`shell/plugins/panels/tailscale/`
  there): status, up/down switch, machine list, copy IP/name, IPC
  `up`/`down`/`toggleTailscale`/`refresh`/`status`. Backend is the
  `tailscale` CLI (JSON status). Connecting-state breathing pulse maps
  to our existing 900ms pulse idiom, NOT their spinner.
- **Speed test** — omarchy's measurement lives in
  `bin/omarchy-network-speedtest` (read it): pick the active iface via
  `ip route get 1.1.1.1`, run parallel `curl` transfers (8 streams, 3
  URLs) against Cloudflare speed endpoints, and compute live Mbps from
  `/sys/class/net/<iface>/statistics/rx_bytes|tx_bytes` deltas — the
  panel state props are `network/Panel.qml:104-111` there. The 270°-arc
  gauge overlay (`SpeedTestPanel.qml`) is NOT our chrome; the feature is
  reimplemented as flat ledger rows.

*Deliberately NOT ported (bloat or design-language violations — do not
re-propose in future audits):* bar drag-and-drop reordering, move-bar-edge
gesture, bar transparency toggle, bar tooltips, hero status phrase
rotation (2.8s ambient subtitle cycler — its *content* ports as static
rows in Task 5, the motion does not), media marquee scroll (continuously
auto-scrolling now-playing ticker — we elide; continuous ambient motion
violates DESIGN.md §4's flat-and-still doctrine), tray 600ms drawer
slide, the speed-test arc-gauge chrome (feature ports flat in Task 9),
wifi QR overlay, DNS provider picker, Dropbox panel, system-update
widget (Arch-specific), keyboard-layout and microphone widgets (revisit
only on owner request), reminders overlay, omarchy's 420ms slanted
wallpaper wipe (we crossfade instead), polkit failure shake.

## Constraints

- Same as M14/M15: CLAUDE.md binds (host-session safety, D-Bus isolation,
  honest unavailable states, 0..1 fractions, opaque window ids, glyphs
  verified from the pinned nerd-fonts cmap via fonttools ttx — never
  memory, targeted Edits on glyph-bearing files), DESIGN.md is the
  authority, verification ONLY on the VM rig (`just vm-test` /
  `vm-lint` / `vm-smoke *FLAGS`), one conventional commit per task,
  pushed, tree clean at the end.
- **Value-preserving migration:** Task 1's spacing unification must not
  change rendered pixel output at default scale except the two named
  fixes (bar left gap 8→4, OSD track 4→6). Everything else is
  same-value token swaps.
- **Motion stays in the band:** every new animation uses existing
  `Theme.motion` tokens (100/130ms, OutCubic). The single exception is
  the wallpaper reveal (Task 3): a new `Theme.motion.reveal` (400ms,
  InOutQuad) that DESIGN.md §4 names as the third documented carve-out
  beside the pulse and the screensaver; `motion.enabled: false` zeroes it
  like everything else.
- New IPC surfaces (`--polkit` rig, `nightlight` target, `bluetooth`
  target) are spec addendums in the `panel`-target tradition: documented
  in USAGE.md, unknown args return error strings, never silent no-ops.
- Secrets discipline (polkit): the typed password goes to the AuthFlow
  respond call only — never logged, never in `debug` dumps, never in
  state.json.

---

### Task 1: Density unification — one spacing system, one track thickness, tokened letter-spacing

**Files:** modify `shell/Theme/tokens.js`, `shell/Core/Theme.qml`,
`shell/Components/Cell.qml`, `shell/Components/MetaLabel.qml`,
`shell/Components/AuthPrompt.qml`, `shell/Surfaces/Bar/Bar.qml`,
`shell/Surfaces/Osd/Osd.qml`, `shell/Surfaces/Notifications/Center.qml`,
`shell/Surfaces/Panels/CalendarPanel.qml`, plus every file
`rg -l 'Theme\.spacing\.'` surfaces across `shell/` and `greeter/`
(~68 sites); extend the existing token/palette test file (or add
`tests/tst_tokens.qml` mirroring `tst_palette.qml`'s shape).

**Produces:**
1. `tokens.js`: semantic spacing set gains `trackThickness` (6);
   a new `letterSpacing` token group `{meta: 1, wide: 2}` exposed via
   `Theme` (both scale with `spacingScale`/`fontScale` respectively —
   pick the root that keeps today's rendered values at default scale).
2. Every `Theme.spacing.*` use migrated value-preserving
   (`xs→space.xxs`, `sm→space.sm`, `md→space.lg`; `.lg` verified
   unused), then the legacy `Theme.spacing` object deleted from
   `Theme.qml`. `Cell.qml`'s padding now scales with the shell.
3. Bar: all three regions space widgets with `Theme.space.sm`
   (left region tightens 8→4 — the one intended visual change).
4. OSD track height becomes `Theme.space.trackThickness`, as do the six
   panel track sites (7 sites total, all reading one token; OSD is the
   one whose rendered value changes, 4→6).
5. `MetaLabel` reads `Theme.letterSpacing.meta`; `Center.qml`'s DND and
   CLEAR ALL cells read the same token (still body-size action cells —
   only the tracking value is shared); `AuthPrompt.qml:123` reads
   `Theme.letterSpacing.wide`. `CalendarPanel.qml:375` → `Theme.space.xxs`.
6. Token tests: `trackThickness`/`letterSpacing` present and scaling,
   legacy `spacing` gone (a `Theme.spacing === undefined`-shaped
   assertion so it can't silently return).
7. Glyph-bearing files (bar widgets, panels, Center) touched ONLY with
   targeted Edits — never whole-file rewrites (CLAUDE.md glyph rule).

**Verify:** `just vm-test`; `just vm-lint`; `just vm-smoke` (default) +
`just vm-smoke --osd` — Read the PNGs: left bar region gap now matches
center/right, OSD track fattened to 6, everything else visually
unchanged. Commit (`refactor(theme): …` or `fix(theme): …`).

### Task 2: Motion consistency — missing fades, screensaver entrance, bar width smoothing, menu freeze

**Files:** modify `shell/Surfaces/Panels/AudioPanel.qml`,
`shell/Surfaces/Panels/MediaPanel.qml`,
`shell/Surfaces/Panels/CalendarPanel.qml`,
`shell/Surfaces/Screensaver/Screensaver.qml`,
`shell/Surfaces/Bar/widgets/ActiveWindow.qml`,
`shell/Surfaces/Bar/widgets/NowPlaying.qml`,
`shell/Surfaces/Menu/Menu.qml`, `docs/DESIGN.md` (§4 amendment),
`dev/smoke-niri.sh` (`--menu` leg extension).

**Produces:**
1. `Behavior on opacity` at `Theme.motion.fast`/`motion.easing` on the
   four instant state-swaps (mute dim, two transport dims, event dot) —
   same shape as the FORGET cells.
2. Screensaver **enter** fades at `Theme.motion.standard` (opacity only,
   no slide — full-screen surface); exit stays instant per DESIGN.md §3.
   Must not disturb the `--screensaver-gif` frame-stepping rig
   (frame stepping drives banner content, not surface opacity — verify).
3. `ActiveWindow` and `NowPlaying` cells animate width changes at
   `Theme.motion.standard` so text-length changes stop shoving
   neighbors. If a width Behavior fights elision/binding loops after a
   real attempt, drop that item and record why in the commit — never
   ship a jittering bar.
4. Menu card freeze: on first filter keystroke or submenu move, the
   card's top edge pins (stops re-centering; height changes grow/shrink
   downward only), releasing on close/summon — omarchy's behavior
   reimplemented against `Menu.qml:349,780,790`'s geometry.
5. DESIGN.md §4: one line naming lock enter/exit + screensaver exit as
   sanctioned-instant surfaces.
6. `--menu` smoke leg: after `summon`, `wtype` a filter string, take a
   second screenshot, and assert (Read both PNGs) the card's top edge
   did not move while the row count changed.

**Verify:** `just vm-test`; `just vm-smoke --menu --screensaver --media
--panel audio` — Read the PNGs. Commit (`feat(motion): …`).

### Task 3: Wallpaper crossfade

**Files:** modify `shell/Surfaces/Background/Background.qml`,
`shell/Theme/tokens.js` (+ its test), `shell/Core/Theme.qml`,
`docs/DESIGN.md` (§4 carve-out), `docs/USAGE.md` (motion section).

**Produces:**
1. `Theme.motion.reveal` (400ms, InOutQuad), zeroed by
   `motion.enabled: false` exactly like fast/standard.
2. `Background.qml` double-buffers: the previous wallpaper stays painted
   while the incoming `Image` fades from 0 over `motion.reveal`; hard
   cut (today's behavior) when motion is disabled or on first paint.
   Plain crossfade — NOT omarchy's slanted wipe. No blur, no zoom.
3. DESIGN.md §4 names the wallpaper reveal the third motion carve-out;
   USAGE.md documents the token.

**Verify:** `just vm-test` (token test covers reveal zeroing);
`just vm-lint`; `just vm-smoke --wallpaper` — end-state PNG identical to
today's contract (recolored bar, new wallpaper fully opaque). Commit
(`feat(background): …`).

### Task 4: Polkit agent

**Files:** create `shell/Services/PolkitService.qml`,
`shell/Surfaces/Polkit/PolkitDialog.qml`; modify `shell/shell.qml`,
`nix/testvm.nix`, `dev/smoke-niri.sh` (new `--polkit` leg),
`docs/USAGE.md`, `docs/SWITCHOVER.md`.

**Produces:**
1. `PolkitService.qml`: a `PolkitAgent` (verify the QML module URI and
   the `AuthFlow` respond/cancel API against the pinned quickshell
   source — `src/services/polkit/qml.hpp`, `flow.hpp` — before writing a
   line). `settings.json` gate `polkit.enabled` (default **true**);
   `isRegistered: false` (another agent owns the session) logs one
   honest line and renders nothing — never fight over registration.
2. `PolkitDialog.qml`: one centered card in the shell's chrome —
   uppercase `AUTHENTICATION REQUIRED` meta header, the action message,
   the requesting identity as a dim meta row, and the `AuthPrompt` field
   idiom (masked `●` input, `CHECKING…` during auth, `WRONG PASSWORD` in
   urgent italic on retry, Escape cancels). Radius 0, border 2,
   monospace — no shake.
3. testvm: `security.polkit.enable` + a `pkexec`-runnable fixture; the
   `--polkit` smoke leg runs `pkexec true` in-session, screenshots the
   dialog, `wtype`s a wrong password (error state screenshot), then the
   VM's real test password, and asserts the pkexec exit code is 0. If
   agent registration genuinely cannot attach to the nested session's
   polkit subject after real attempts, report blocked honestly with the
   polkitd/journal evidence — never fake the flow.
4. USAGE.md + SWITCHOVER.md document the agent, the setting, and the
   one-agent-per-session caveat.

**Verify:** `just vm-test`; `just vm-lint`; `just vm-smoke --polkit` —
Read all three PNGs. Commit (`feat(polkit): …`).

### Task 5: Power — brightness (backlight + DDC), low-battery warnings, critical battery cell, static battery stats

**Files:** create `shell/Power/model.js`, `tests/tst_power_model.qml`;
modify `shell/Services/BrightnessService.qml`,
`shell/Surfaces/Panels/PowerPanel.qml`,
`shell/Surfaces/Bar/widgets/Battery.qml`,
`shell/Notifications/NotificationService.qml`, `docs/USAGE.md`,
`docs/SWITCHOVER.md` (i2c permissions note).

**Produces:**
1. `Power/model.js` (pure): `warnEvent(prevPct, pct, charging, fired)`
   hysteresis — warn once crossing `battery.warnPercent` (default 10)
   discharging, critical once at `battery.criticalPercent` (default 5),
   re-arm on charge; percentages are 0..1 fractions at the UPower
   boundary, converted exactly once. Tests cover crossings, re-arm,
   charge interruptions, and boot-below-threshold.
2. `NotificationService` gains a local-inject path (investigate the
   reducer's ingest shape first; reuse it honestly — a local entry is
   marked so `debug` dumps show its origin). Low battery → normal
   toast; critical → `critical` urgency (sticky, DND-bypassing like
   notify-send criticals).
3. `Battery.qml`: cell goes full-bleed `urgent` (DESIGN.md §2.4) at/below
   the critical threshold while discharging.
4. The hero-rotation *content* ports statically: `BATTERY` section gains
   dim meta rows for time-to-full/time-to-empty and charge rate where
   the UPower device reports them (verify `timeToFull`/`timeToEmpty`/
   `energyRate` against the pinned quickshell UPower source before
   binding; render nothing when a value is 0/absent — honest states,
   no rotation, no timer).
5. `BrightnessService` grows a device list: the existing backlight
   device plus one entry per DDC-capable external monitor (ddcutil
   `detect --brief` with the omarchy script's I²C-bus + unavailable
   caching design reimplemented in QML/JS; `getvcp`/`setvcp 10` for
   read/write; detection runs on panel open, never on a poll loop —
   ddcutil is slow and touching it constantly is how you hang a bar).
   `ddcutil` missing from PATH or no DDC displays → the backlight-only
   behavior of today, honest.
6. `PowerPanel` gains a `DISPLAY` section: one `BRIGHTNESS` row per
   device (backlight labeled `INTERNAL`, DDC rows by monitor connector)
   — flat accent track (`Theme.space.trackThickness`), percent text,
   wheel/`h`/`l` at 5% steps, `refresh()` on panel open; honest dim
   `NO BACKLIGHT` single row when nothing is controllable (the VM's
   expected state).
7. SWITCHOVER.md: DDC needs `i2c-dev` + i2c group membership (or a udev
   rule) on the host — documented, not assumed.

**Verify:** `just vm-test`; `just vm-smoke --panel power` — VM shows
`AC POWER` + `NO BACKLIGHT` honestly; Read the PNG. Threshold behavior
rides on the model tests, DDC on the owner's dock post-switchover —
both stated honestly in the commit. Commit (`feat(power): …`).

### Task 6: Night light (opt-in)

**Files:** create `shell/Services/NightLightService.qml`,
`shell/Ipc/NightLightIpc.qml`; modify `shell/shell.qml`,
`shell/Surfaces/Bar/widgets/Indicators.qml`, `nix/testvm.nix` (wlsunset
package), `dev/smoke-niri.sh` (`--nightlight` leg), `docs/USAGE.md`.

**Produces:**
1. `NightLightService`: manages a `wlsunset` Process (`-t` from
   `nightlight.temp`, default 4000; fixed-temp mode, not schedule),
   `active` tracks process liveness, exit-with-error surfaces
   `lastError` honestly. `nightlight.startOn` (default **false** —
   opt-in, non-bloat). `wlsunset` missing from PATH → honest
   `NO WLSUNSET` state over IPC, never a silent no-op.
2. `nightlight` IPC target: `toggle`/`enable`/`disable`/`status`
   (compact JSON: active, temp, lastError).
3. `Indicators.qml` gains a night-light glyph (codepoint verified from
   the pinned cmap via fonttools ttx) shown while active — joining
   idle-inhibit in the transient strip.
4. `--nightlight` smoke leg: `nightlight enable`, poll `status` to
   `active:true`, screenshot the indicator, `disable`, confirm
   `active:false`. If nested niri lacks the gamma-control protocol and
   wlsunset exits, the leg asserts the honest failure surface instead
   (`active:false` + `lastError` populated) and says so in the log —
   both outcomes are real evidence; silent skip is not.

**Verify:** `just vm-test`; `just vm-lint`; `just vm-smoke --nightlight`,
Read the PNG/JSON. Commit (`feat(nightlight): …`).

### Task 7: Multi-monitor dismiss twins

**Files:** create `shell/Components/DismissTwins.qml`; modify
`shell/Components/Panel.qml`, `shell/Surfaces/Menu/Menu.qml`,
`shell/Surfaces/Notifications/Center.qml`, `docs/USAGE.md`.

**Produces:**
1. `DismissTwins.qml`: a `Variants { model: <other screens> }` of
   transparent, `exclusionMode`-neutral, keyboard-none `PanelWindow`s
   whose single press handler invokes a `dismissed()` callback —
   omarchy's `KeyboardPanel` twin pattern reimplemented (the
   compositor hit-tests pointer input per output; the existing
   same-output backdrop cannot see clicks elsewhere). Instantiated only
   while the owning surface is open (`model: open ? … : []` so closed
   surfaces cost zero windows).
2. `Panel.qml` (covers all nine panels + the picker), `Menu.qml`, and
   `Center.qml` each mount the twins next to their existing backdrop;
   clicking any other monitor closes the surface exactly like clicking
   the local backdrop. Escape/IPC close paths unchanged.
3. USAGE.md: one line under the panel behavior section.

**Verify:** `just vm-test`; `just vm-lint`; `just vm-smoke --panel audio
--menu` still green (single-output VM renders zero twins — the
regression check is that nothing changed; Read the PNGs). Multi-output
behavior is owner-verified on the docked host post-switchover, stated
honestly in the commit. Commit (`feat(panels): …`).

### Task 8: Tailscale widget + panel

**Files:** create `shell/Surfaces/Panels/TailscalePanel.qml`,
`shell/Surfaces/Bar/widgets/TailscaleWidget.qml`,
`shell/Tailscale/model.js`, `tests/tst_tailscale_model.qml`; modify
`shell/Bar/layout.js` (BUILTIN_WIDGETS gains `tailscale`, NOT in
DEFAULT_LAYOUT — opt-in like `github`/`usage`),
`shell/Surfaces/Bar/Bar.qml`, `shell/shell.qml`,
`shell/Ipc/PanelIpc.qml` (registry gains `tailscale`),
`nix/testvm.nix` (only if a headless assertion needs the CLI present),
`dev/smoke-niri.sh` (`--panel tailscale` evidence), `docs/USAGE.md`,
`docs/SWITCHOVER.md`.

**Produces:**
1. `Tailscale/model.js` (pure): `parseStatus(json)` over
   `tailscale status --json` output (`BackendState`, `Self` name/IPs,
   peer list → `{name, online, ip, os}` sorted online-first then
   alphabetical), `selfIp(status)`, honest `null`s for missing fields.
   Tests against realistic fixture JSON (running, stopped, needs-login,
   no-daemon) — fixture shapes read from the omarchy panel's own
   parsing, verified against the real CLI's documented output.
2. `TailscalePanel.qml` (GithubPanel poll-in-panel pattern: poll while
   widget present or panel open, open re-polls): `STATUS` section — the
   connected/stopped state as an action cell (click/Enter toggles via
   `tailscale up`/`down` Process; `NEEDS LOGIN`/`NO TAILSCALE` honest
   dim states when auth or the CLI is missing), self hostname + IP row
   (click copies IP via the existing wl-copy idiom); `MACHINES` section
   — one ledger row per peer (name, dim IP, online state as the
   breathing 900ms pulse ONLY while `up` is actively connecting,
   otherwise static), click copies that peer's IP. Keyboard nav via
   `Panel.keyPressed` (M14 pattern).
3. `TailscaleWidget.qml` (GithubWidget shape): glyph verified from the
   pinned cmap; hidden until first successful status read (`shown`
   pattern); dim when stopped, normal when up; click toggles the panel.
4. `tailscale up`/`down` from an unprivileged shell requires operator
   mode — SWITCHOVER.md documents `tailscale set --operator=$USER` as
   the host-side prerequisite, and the panel renders the resulting
   permission error honestly (`NOT OPERATOR` dim state) instead of
   pretending the toggle worked.

**Verify:** `just vm-test` (model fixtures); `just vm-lint`;
`just vm-smoke --panel tailscale` — the VM has no tailscaled, so the
honest `NO TAILSCALE` state is the expected screenshot; Read the PNG.
Live toggle is owner-verified post-switchover, stated honestly. Commit
(`feat(tailscale): …`).

### Task 9: Network speed test — flat ledger rows, no gauges

**Files:** create `shell/Network/speedtest.js`,
`tests/tst_speedtest.qml`; modify
`shell/Surfaces/Panels/NetworkPanel.qml`, `shell/Ipc/NetworkIpc.qml`,
`dev/smoke-niri.sh` (`--speedtest` leg), `docs/USAGE.md`.

**Produces:**
1. `speedtest.js` (pure): `mbps(bytesDelta, msDelta)`,
   `formatMbps(v)` (omarchy's format: one decimal under 10, whole
   numbers above), and the sample-window reducer that turns a series of
   `(timestamp, rx_bytes)` readings into a live rate + final result.
   Tests cover the math, counter resets, and zero-duration guards.
2. `NetworkPanel` gains a `SPEED TEST` section: a `RUN` action cell;
   while running, `DOWNLOAD` then `UPLOAD` ledger rows — flat accent
   fill track (fill = current/expected-max, capped honestly), live
   Mbps text, dim phase meta (`MEASURING DOWN…`). Measurement is the
   omarchy technique reimplemented in-shell (never a port of their
   script): resolve the active iface via `ip route get 1.1.1.1`
   (Process), read `/sys/class/net/<iface>/statistics/rx_bytes`/
   `tx_bytes` on a sampling timer, drive parallel `curl` transfers
   against Cloudflare's speed endpoints (download `__down`, upload
   `__up`) for a bounded duration, kill the curls by PID on
   stop/close. `curl` missing or no active iface → dim `NO NETWORK`/
   `NO CURL` honest states. Results persist in the section until the
   panel closes; no state.json writes.
3. `network speedtest` IPC verb: starts a run headlessly, `network
   speedstatus` (or a field in the existing `status`) reports
   `{running, phase, downMbps, upMbps}` — headless rig + keybind path.
4. `--speedtest` smoke leg: inside the VM (which has real NAT network),
   drive `network speedtest`, poll status until both numbers land (or
   a bounded timeout reports the honest failure), screenshot the panel
   with the section visible. The VM's virtio NIC gives real if slow
   numbers — either outcome (numbers or honest `TIMED OUT`) is real
   evidence; assert the section renders it.

**Verify:** `just vm-test`; `just vm-lint`; `just vm-smoke --speedtest`,
Read the PNG + status JSON. Commit (`feat(network): …`).

### Task 10: Bluetooth IPC, docs, screenshots, final sweep

**Files:** create `shell/Ipc/BluetoothIpc.qml`; modify `shell/shell.qml`,
`docs/USAGE.md`, `docs/SWITCHOVER.md`, `README.md` +
`docs/screenshots/*` as touched; targeted QML fixes where the sweep
finds drift.

**Produces:**
1. `bluetooth` IPC target (omarchy `f54edbe` parity): `toggle`/`power
   (on|off)`/`status` (adapter present/enabled/connected count JSON) —
   keybind-reachable radio control; honest `NO ADAPTER` error string.
2. USAGE.md: every new setting (`polkit.enabled`, `battery.warnPercent`/
   `criticalPercent`, `nightlight.temp`/`startOn`), IPC table rows
   (`nightlight`, `bluetooth`, the new `network` verbs, `panel open
   tailscale`), motion-token additions. SWITCHOVER.md gains the
   polkit-agent, night-light, DDC/i2c, and tailscale-operator notes.
3. Full smoke matrix re-run; Read every PNG against DESIGN.md §2's six
   checks and §4's motion rules; fix confirmed drift in bounded
   per-surface commits. README screenshots recaptured for surfaces whose
   look changed (bar default run, OSD, power panel).
4. Final `just vm-test` + `just vm-lint` + default `just vm-smoke`
   green; tree clean; every commit pushed.

**Verify:** the commands above, run and read. Commit(s) (`feat(ipc): …`,
`docs: …`).

---

## Review checkpoints

Three: after Task 4 (polkit is this plan's riskiest infrastructure — a
reviewer re-runs `--polkit`, reads the PNGs for fake evidence, and greps
for password leakage into logs/dumps), after Task 8 (density/motion
regressions against the value-preserving constraint, the DDC/tailscale
Process hygiene — no poll loops against slow CLIs, PIDs killed, honest
states), and after Task 10 (full sweep: design drift, motion-band
violations, host-safety leaks, contract drift on the new IPC targets,
unpushed commits).
