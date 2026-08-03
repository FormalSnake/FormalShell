# FormalShell M15: live-trial feedback — weather cell, notification density, audio mixer

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. M14
> (`2026-08-01-m14-quattro-behavior-parity.md`) landed immediately before
> this plan and is live on the e1504g; its task notes are context for every
> file touched here.

**Origin, owner ask (2026-08-03, live daily-drive):** "the weather widget
says WEATHER but clicking on it does show weather"; "notifications panel
needs to look like omarchy too and the info density is sometimes
ugly/unusable, eg GH notifs"; "the audio panel looks confusing, make it
like omarchy too with app level volume and stuff". (A fourth item —
win+space should close the open menu — was a dotfiles keybind calling
`menu summon ""` instead of M13's `menu toggle` verb; fixed out-of-band in
the owner's nix config, no shell change needed.)

**Research already done (2026-08-03, omarchy clone at fa95901), do not
re-derive:**

- Omarchy weather (`shell/plugins/panels/weather/BarWidget.qml:49-83`,
  `Panel.qml:441-448,494-833`, `Model.js:126-135,262-278`): the bar cell is
  a condition glyph only (`iconForCode` maps open-meteo weather codes to
  Nerd Font glyphs), hidden until the first fetch lands; the panel refetches
  on a 15-minute default timer (`refreshMinutes`), hero row = big glyph +
  temp + FEELS/WIND/HUMID stats, then a 3-day forecast row.
- Omarchy notifications (`shell/plugins/notifications/NotificationCard.qml`,
  `Service.qml`, `NotificationLogic.js`): NO notification-center surface
  exists there (history replays as toasts) — FormalShell's center stays,
  it adopts omarchy's *density language*, not a nonexistent layout. That
  language: summary `maximumLineCount: 2`, body `maximumLineCount: 3`,
  body rendered as `Text.StyledText` with `\n` converted to `<br/>`
  (StyledText ignores raw newlines — `NotificationCard.qml:47,154-186`);
  fixed card width; icon slot 40×40 showing the real notification
  image/app icon, hidden entirely when neither resolves (no broken-image
  box); single-line toasts shrink vertical padding (7 vs 10);
  `sanitizeBody` (`NotificationLogic.js:8-15`) strips `<img>` tags always
  and, for Chromium-derived senders (Chrome/Brave/Vivaldi/Edge/Opera,
  matched on app name/icon), strips the leading URL-as-link or bare-URL
  prefix those browsers prepend — **this is the exact "GH notifs are
  ugly" cause: GitHub web notifications arrive via the browser with a URL
  line glued to the front of the body**; replace-by-id de-dup honoring
  freedesktop `replaces_id` (`Service.qml:215-220`) so updating
  notifications never pile up; durations low 5s / normal 8s / max 30s,
  critical sticky, hover pauses the expiry countdown (`Service.qml:100-121,
  851`).
- Omarchy audio (`shell/plugins/panels/audio/Panel.qml`, `Model.js`):
  section order OUTPUT → INPUT → app streams; INPUT and the streams
  section vanish entirely (header included) when empty; device rows are
  click-to-set-default (`Pipewire.preferredDefaultAudioSink = node`,
  active row = the one whose id equals `Pipewire.defaultAudioSink.id`,
  drawn filled/bold); labels via nickname → description → name with
  friendly-label cleanup; volume steps are 5% everywhere (slider drag,
  wheel tick, keyboard h/l), percent shown as separate text tracking the
  drag live; master output/input clamp to 1.0 but **per-app streams allow
  overdrive to 1.5**; per-stream mute is a direct `node.audio.muted`
  write. Stream enumeration (`Panel.qml:45-67`, `Model.js:1-9`): filter
  `Pipewire.nodes.values` on `isStream` + playback-shaped `node.type`
  (`Stream/Output/Audio`/`AudioOutStream`/`Output`) **without reading
  `node.properties` at filter time** — properties are invalid pre-bind and
  reading them during stream churn destabilized quickshell's Pipewire
  service in omarchy's history; only read `properties` behind
  `node.ready`, via a tracker. App label chain:
  `properties["application.name"]` → `node.description` →
  `properties["media.name"]` → `node.name`. Keyboard model: one cursor
  over sections (output slider / device rows / input / stream rows),
  arrows move, h/l adjust 5%, m mutes, Enter activates (=set default on a
  device row, toggle mute on a stream row).
- FormalShell current state (read 2026-08-03): `WeatherWidget.qml` is a
  static glyph + "WEATHER" MetaLabel by design (its header comment: the
  fetch lives in WeatherPanel and only runs while open);
  `NotificationCard.qml` clamps summary to 1 line/body to 2, renders body
  as plain text (raw `<a href…>` markup and newlines show literally), and
  `_relTime` renders minutes forever ("600m ago");
  `Center.qml` has DND + PENDING/EARLIER but no CLEAR ALL;
  `AudioPanel.qml` lists only hardware nodes (`!isStream`), has no
  default-device selection, no app streams.

## Constraints

- Same as M14: CLAUDE.md binds (host safety, D-Bus isolation, honest
  states, 0..1 fractions, glyphs from the pinned cmap via fonttools ttx,
  targeted Edits on glyph-bearing files), DESIGN.md is the authority,
  verification ONLY on the VM rig (`just vm-test` / `vm-lint` /
  `vm-smoke`), one conventional commit per task, pushed, tree clean.
- DESIGN.md's flat-fill slider idiom wins over omarchy's pill-and-knob:
  volume tracks stay full-width flat `accent` blocks, radius 0, no thumb.
  Apply omarchy's *behavior* (5% steps, wheel, overdrive, click-to-default)
  inside FormalShell's chrome, exactly like M14 did for wifi.
- The notification center is a FormalShell surface (omarchy has none);
  restyle its rows with the density rules but do not remove the
  PENDING/EARLIER split, DND cell, or ledger inversion — DESIGN.md §3
  still governs the layout.

---

### Task 1: Pure model groundwork (notification sanitize/time/dedup, weather glyphs, audio labels)

**Files:** modify `shell/Notifications/model.js`,
`tests/tst_notifications_model.qml`, `shell/Weather/openmeteo.js`,
`tests/tst_openmeteo.qml`; create `shell/Audio/model.js`,
`tests/tst_audio_model.qml`.

**Produces:**
1. `Notifications/model.js`: `sanitizeBody(body, appName, appIcon)` —
   strip `<img …>` always; when the sender is Chromium-derived (port
   omarchy's app-name/icon match list), strip the leading
   `<a …>URL</a>` or bare-URL prefix; expose `styledBody()` that
   HTML-escapes nothing further but converts `\n` → `<br/>` for
   StyledText. `relTime(nowMs, arrivedAtMs)` → `now`, `Nm ago`, `Nh ago`,
   `Nd ago`. Replace-by-id: ingest honors `replaces_id`-style identity
   (investigate what the reducer already keys on — quickshell's
   Notification objects expose the server-side id; if replacement already
   works, prove it with a test instead of re-implementing).
2. `Weather/openmeteo.js`: `glyphForCode(code, isDay)` mapping open-meteo
   weather codes to Nerd Font weather glyphs (codepoints verified from
   the pinned cmap via fonttools ttx — the M14 precedent), with an
   explicit fallback glyph for unknown codes.
3. `shell/Audio/model.js` (pure): `isPlaybackStream(node-shaped object)`
   using only pre-bind-safe fields (`isStream`, `isSink`, `type` string
   match per the research header), `streamLabel(props, description,
   name)` fallback chain, `clampStream(v)` (0..1.5) vs `clampDevice(v)`
   (0..1).
4. Tests for all of it: the chromium URL-prefix strip against a realistic
   GitHub-notification body fixture, `<img>` strip, newline conversion,
   rel-time unit boundaries, weather-code map totality (every documented
   open-meteo code group resolves, unknown → fallback), stream filtering
   never touching a `properties` field, label chain, clamps.

**Verify:** `just vm-test` green. Commit (`feat(model): …`).

### Task 2: Notification surfaces — density + omarchy card language

**Files:** modify `shell/Surfaces/Notifications/NotificationCard.qml`,
`Toasts.qml`, `Center.qml`, `shell/Notifications/NotificationService.qml`
(only if durations/pause need service-side state), `dev/smoke-niri.sh`
(`--notify`/`--center` fixtures), `docs/USAGE.md`.

**Produces:**
1. `NotificationCard`: summary 2 lines max (bold, body-size), body via
   `styledBody()` at `bodySmall`, `Text.StyledText`, 3 lines max,
   `sanitizeBody` applied at the model boundary so Center rows and toasts
   both benefit; meta row uses `relTime` (h/d units). Icon slot: the
   notification's own image, else the sender's themed app icon (same
   check-resolved `Quickshell.iconPath` path as M14's ActiveWindow — read
   the quickshell Notification C++ API for the image/appIcon properties
   rather than guessing), hidden entirely when neither resolves; DESIGN.md
   gains the one-line amendment naming notification cards the third
   sanctioned image surface (they carry sender-supplied imagery by
   nature). Single-line entries (no body) drop to the tighter vertical
   padding.
2. `Toasts`: durations low 5s / normal 8s / cap 30s, honoring a sender's
   `expireTimeout` within the band; critical stays sticky; hovering a
   toast pauses its expiry (omarchy's `!card.hovered` gate — check what
   the service's timer structure needs). Fixed toast width stays.
3. `Center`: `CLEAR ALL` action cell beside DND (clears pending + past
   through existing service verbs; hover-inverts like every row), rows
   pick up the same card changes automatically.
4. Smoke fixtures: `--notify` and `--center` legs add one dense
   chromium-shaped notification (`notify-send -a "Google Chrome"` with a
   leading `<a href="https://github.com/...">github.com</a>` body prefix,
   a long PR-title line, and 6+ lines of body) — screenshots must show
   the URL prefix gone, 3-line clamp, readable meta row. Existing
   assertions stay additive.

**Verify:** `just vm-test`; `just vm-smoke --notify --center`, Read the
PNGs (clamps + stripped prefix visible). Commit (`feat(notifications): …`).

### Task 3: Weather — live bar cell

**Files:** modify `shell/Surfaces/Bar/widgets/WeatherWidget.qml`,
`shell/Surfaces/Panels/WeatherPanel.qml`, `docs/USAGE.md`.

**Produces:**
1. WeatherPanel adopts the GithubPanel poll-ownership pattern: poll timer
   (`weather.intervalMs`, default 900000) runs while `pollEnabled` (set by
   the widget's presence in bar.layout) or the panel is open; opening
   refreshes. Current-conditions state (temp, code, isDay) becomes panel
   properties the widget binds.
2. WeatherWidget renders `glyphForCode` + rounded temp (`14°` — unit per
   the existing panel's convention) once data exists; before the first
   fetch, or with no location, it keeps a dim static weather glyph
   (clickable, honest) — never the dead "WEATHER" label, never a fake
   value. The VM has no location fix, so the dim-glyph state IS the
   expected smoke rendering.
3. USAGE.md documents the new settings key and the widget's states.

**Verify:** `just vm-test`; `just vm-smoke --panel weather` — cell shows
the dim honest glyph in the VM, panel unchanged-or-better; Read the PNG.
Commit (`feat(weather): …`).

### Task 4: Audio panel — omarchy mixer behavior

**Files:** modify `shell/Surfaces/Panels/AudioPanel.qml`,
`shell/Surfaces/Bar/widgets/AudioWidget.qml` (wheel-on-cell volume, only
if absent), `dev/smoke-niri.sh`, `docs/USAGE.md`.

**Produces:**
1. Sections: `OUTPUT` — master slider row for the default sink (flat
   accent track, % text, MUTE cell) then one row per sink, click/Enter
   sets `Pipewire.preferredDefaultAudioSink`, the current default row
   inverted per the ledger idiom; `INPUT` — same for sources, section
   (header included) omitted when no sources exist; `APPS` — one row per
   playback stream (`Audio/model.js.isPlaybackStream` over
   `Pipewire.nodes.values`, `PwObjectTracker`-bound, labels via
   `streamLabel` read only behind `node.ready`): label, flat track with
   0..1.5 overdrive (a hairline marker at the 1.0 point so overdrive
   reads as deliberate), % text, MUTE cell; section omitted entirely when
   no streams.
2. Interaction parity: 5% steps for wheel-on-track and keyboard h/l;
   keyboard cursor over rows via `Panel.keyPressed` (M14 wifi pattern),
   `m` toggles mute on the cursor row, Enter activates (default-switch on
   device rows, mute-toggle on stream rows). Percent text tracks drags
   live.
3. Smoke: a combined `--media --panel audio` run gains an assertion +
   screenshot — mpv's real stream must appear under `APPS` (the fixture
   track is already playing into the null sink; label per the fallback
   chain), volume write via a new tiny `audio` IPC status/set verb ONLY if
   headless assertion needs it (prefer reading the panel state through the
   existing `debug`/screenshot evidence; add IPC only on real need).

**Verify:** `just vm-test`; `just vm-smoke --media --panel audio`, Read
the PNG (APPS section with the mpv row, master + device rows). Commit
(`feat(audio): …`).

### Task 5: Docs, screenshots, sweep

**Files:** `docs/USAGE.md`, `docs/SWITCHOVER.md` if states changed,
`README.md`/`docs/screenshots/*` recaptured for notifications, audio,
weather bar.

**Produces:** recaptured screenshots for every surface this plan touched;
full `just vm-test` + `just vm-lint` (with the M14-documented
`substitute = false` workaround if the VM daemon crash recurs) + smoke
matrix over the touched flags; tree clean, all commits pushed.

**Verify:** commands above, outputs read. Commit (`docs: …`).

---

## Review checkpoint

One adversarial checkpoint after Task 5: re-run `just vm-test` and
`just vm-smoke --notify --center --media --panel audio`, Read the PNGs,
hunt density regressions (clamp counts, StyledText injection — a body
containing literal `<script>`/broken tags must render harmlessly as
StyledText), pre-bind `properties` reads on stream nodes (the omarchy
destabilization note), 0..1-vs-percent bugs, design drift, unpushed
commits.
