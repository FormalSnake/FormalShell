# FormalShell M5: Notifications + OSD — Implementation Plan

> **For agentic workers:** Workflow-driven: one subagent per task, sequential, verification evidence required, push after every task commit (classifier-denied pushes: note and continue). Read `CLAUDE.md` and `docs/DESIGN.md` first — binding. M1–M2 plan Global Constraints apply.

**Goal:** A full mako-replacement notification stack (freedesktop server, Omarchy's three-tier popup→pending→past model, strict DND bypass, ledger-cell toasts + summonable history center) and a jitter-free bottom-center OSD driven by new Audio/Brightness services and an `osd` IPC target.

**Architecture:** Pure-JS TDD'd notification state machine (`shell/Notifications/model.js`) wrapped by a QML service owning `Quickshell.Services.Notifications.NotificationServer`. `AudioService` (Pipewire) and `BrightnessService` (brightnessctl) are the first two "system" services; OSD auto-shows on audio changes and via IPC. All visuals are `Components/Cell` ledger cells per DESIGN.md.

**Spec:** in-repo `docs/superpowers/specs/2026-07-27-formalshell-design.md` §Surfaces(6,7). Spec/DESIGN win.

## Plan-wide constraints

- ⚠️ **D-Bus isolation (new hard rule, add to CLAUDE.md in Task 7):** the shell's `NotificationServer` acquires `org.freedesktop.Notifications` on the session bus. The owner's live session bus is owned by DMS — NEVER run the shell's notification stack against the host bus. `dev/smoke-niri.sh` gains a `dbus-run-session` wrapper (Task 4) so every nested run gets a private session bus; `notify-send` fired inside the nested session then talks to OUR server. Verify isolation by checking the host's `busctl --user status org.freedesktop.Notifications` owner PID is unchanged after a smoke run.
- Toasts/center/OSD are Cells sharing hairline rules; critical notifications are full-bleed accent cells with `onAccent` text; app-name + relative timestamp is a MetaLabel meta row; radius 0; no slide/bounce — instant appear, 150ms color transitions, breathing pulse allowed only for an active screen-recording style persistent state (not used yet).
- All timestamps from `Date.now()` at event arrival; relative rendering ("2m ago") recomputed by a 30s timer in the view layer only.

---

### Task 1: AudioService (Pipewire)

**Files:** Create `shell/Services/AudioService.qml`, `shell/Services/qmldir` (`singleton AudioService AudioService.qml`); modify `shell/Ipc/DebugIpc.qml` (extend `dump()` with `audio: {volume, muted, available}` + `_warmAudio` touch).

**Produces:** singleton `AudioService`: `readonly property bool available`, `property real volume` (0..1, read from the default sink), `property bool muted`, `function setVolume(v)`, `function toggleMute()`, `signal changed()` (fired on external volume/mute changes — the OSD trigger). Implementation on `Quickshell.Services.Pipewire`: bind `Pipewire.defaultAudioSink`, track via `PwObjectTracker`; **verify the exact API** (`Pipewire.defaultAudioSink.audio.volume/muted`, tracker requirement) against quickshell source `src/services/pipewire/` and DMS `Services/AudioService.qml` before writing.

**Steps:** implement → verify in nested niri (`--dump`): `audio.available: true`, volume is a sane 0..1 number; `wpctl set-volume` in-session changes the dump value on a second dump → commit `feat(services): pipewire audio service`; push.

---

### Task 2: BrightnessService

**Files:** Create `shell/Services/BrightnessService.qml`; register in `shell/Services/qmldir`; extend `DebugIpc.dump()` (`brightness: {available, percent}`).

**Produces:** singleton `BrightnessService`: `readonly property bool available` (a backlight device exists), `property real percent` (0..100), `function set(percent)`, `function step(delta)` — via `brightnessctl -m` (machine-readable) `Process` calls; refresh on demand + after each set (no polling loop). `brightnessctl` must be on PATH in the nix package wrapper — add it to the package's PATH prefix (modify `nix/package.nix` accordingly; check how the wrapper currently handles PATH, mirror caelestia's `--prefix PATH` pattern).

**Steps:** implement → `--dump` in nested niri shows `brightness.available` true-or-false honestly (the nested session sees the host's real /sys backlight — read-only `get` is fine; do NOT call `set` in tests on the host device, assert only the read path) → commit `feat(services): brightnessctl-backed brightness service`; push.

---

### Task 3: Notification state machine (pure JS, TDD)

**Files:** Create `shell/Notifications/model.js`, `tests/tst_notifications_model.qml`.

**Produces (`.pragma library`, pure functions, state in/state out):**
- `initialState()` → `{ popups: [], pending: [], past: [], dnd: false, nextExpiry: null }`. Entry shape: `{ id, appName, appIcon, summary, body, urgency (0|1|2), actions: [{key,label}], image: string|"", arrivedAt, seenAt|null, expiresAt }`.
- `add(state, notif, now, opts)` → state. Behavior: DND on and NOT `bypassesDnd(notif)` → straight to `pending`; else into `popups` with `expiresAt = now + (urgency===2 ? 0 (sticky) : opts.timeoutMs default 6000)`; popups capped at 4 — overflow pushes oldest to `pending`.
- `bypassesDnd(notif)` — Omarchy's narrow rule: `urgency === 2 && notif.senderIsNotifySend === true` (the server layer sets that flag from the sender's app info; chat apps abusing critical do NOT bypass).
- `expire(state, now)` → moves timed-out popups to `pending` (unseen). `dismissPopup(state, id)` → popup removed to `past` (seen, `seenAt: now`). `markAllSeen(state, now)` → pending drained to `past`. `prunePast(state, now)` → drops past entries older than 15 min. `dismissOne(state, id)`, `dismissAll(state)`, `clearPending(state)`, `setDnd(state, on)`, `invokeTarget(state)` → the most recent popup-or-pending entry (for invokeLast).
- Tests first (red): DND routing + bypass rule both ways; popup cap overflow; expiry to pending; dismiss to past; 15-min prune; markAllSeen; invokeTarget ordering; purity (input state unmutated).

**Steps:** red → implement → green (`just test`) → commit `feat(notifications): three-tier state machine with strict dnd bypass (tdd)`; push.

---

### Task 4: Notification server + toast surface + isolated-bus smoke

**Files:** Create `shell/Notifications/NotificationService.qml` (singleton, register in `shell/Services/qmldir` or a new `shell/Notifications/qmldir` — match existing conventions), `shell/Surfaces/Notifications/Toasts.qml`, `shell/Surfaces/Notifications/NotificationCard.qml`; modify `shell/shell.qml`; modify `dev/smoke-niri.sh` (dbus-run-session wrapper + `--notify` mode).

**Produces:**
- `NotificationService`: owns `NotificationServer` (enable `actionsSupported`, `bodySupported`, `imageSupported`, `persistenceSupported`, `keepOnReload` — verify property names in quickshell source `src/services/notifications/`), maps incoming `Notification` objects into model entries (detect notify-send: the server exposes the sender's `appName`/desktop-entry — Omarchy checks the literal app name `notify-send`; mirror DMS/Omarchy's actual detection, read their source), drives `model.js` via a 1s expiry timer + 60s prune timer, exposes the model tiers as `popups/pending/past` list properties + all verbs (`dismissPopup`, `invokeAction(id, key)` → `notification.actions[..].invoke()`, `focusSender(id)` → `CompositorService.focusWindow` by matching appId, fallback no-op).
- `Toasts.qml`: top-right column (below the bar, `Theme.spacing.md` from edges — bar is top-anchored, so anchor below it; a bottom bar setting is reserved, ignore), stacked `NotificationCard` cells sharing rules; card = meta row (APP NAME / 2M AGO) + summary (body elided 2 lines); urgency 2 → accent cell; click body → default action if present else `focusSender`; click X cell → dismiss; action buttons as inline cells in a bottom row of the card.
- Smoke: wrap the nested compositor launch in `dbus-run-session --` (both smoke scripts); `--notify` mode fires `notify-send -u normal "Test" "Hello"` + `notify-send -u critical "Crit" "Now"` in-session, waits, screenshots; asserts host `org.freedesktop.Notifications` owner unchanged (busctl before/after).

**Steps:** implement → `--notify` smoke: Read PNG (two toasts, critical one accent-filled) + host-bus assertion → `just test`/`lint` regression → commit `feat(notifications): freedesktop server, ledger toasts, isolated-bus smoke`; push.

---

### Task 5: Notification center + `notifications` IPC

**Files:** Create `shell/Surfaces/Notifications/Center.qml`, `shell/Ipc/NotificationsIpc.qml`; modify `shell/shell.qml`.

**Produces:**
- `Center.qml`: summonable right-anchored top-layer column (width 420, full height minus bar, keyboard `OnDemand`), ledger sections with MetaLabel headers `PENDING / n` and `EARLIER / n`: pending entries first (unseen), then past; opening the center calls `markAllSeen` on close; per-row dismiss; `DND` toggle as the top cell (selected state = accent when on); empty state = single dim cell `NO NOTIFICATIONS`.
- `NotificationsIpc.qml` target `notifications`: `dndState(): string`, `toggleDnd(): string`, `setDnd(on: bool): string`, `showHistory(): string` (toggle center), `clear(): string` (dismissAll+clearPending), `clearPending(): string`, `markAllSeen(): string`, `dismissAll(): string`, `invokeLast(): string`.
- Menu route: add `system.notifications` node to `default-menu.jsonc` (action `@ipc:notifications.showHistory` — extend the internal-dispatch map in Menu.qml accordingly).

**Steps:** implement → smoke `--notify --center` (send 3 notifications, one critical, summon center via IPC, screenshot: sections, accent critical row, DND cell) → commit `feat(notifications): summonable ledger history center with dnd`; push.

---

### Task 6: OSD

**Files:** Create `shell/Surfaces/Osd/Osd.qml`, `shell/Ipc/OsdIpc.qml`; modify `shell/shell.qml`.

**Produces:**
- One bottom-centered top-layer card (no keyboard focus), hidden by default, shown 1.6s after last trigger. THREE fixed-width columns per DESIGN/M-plan: icon cell (width = widest glyph at `Theme.font.title`), label cell (`VOLUME`/`BRIGHTNESS`/`MUTED` MetaLabel), value cell (width sized to `100%`): value shown BOTH as mono percentage text and a flat accent fill bar (a Cell whose accent fill width = fraction — no thumbs, no rounding). Media variant (`osd show media …`) gets a wider label column (track title elided) — layout constants per surface, never per-event (that's the no-jitter contract: widths computed from constants at theme change only).
- Triggers: `Connections` on `AudioService.changed` → volume/mute OSD. `OsdIpc.qml` target `osd`: `volume(): string`, `brightness(): string` (refreshes BrightnessService then shows), `media(text: string): string`, `close(): string`, `state(): string`. Keybind story documented: brightness keys run `brightnessctl set 5%+ && qs … ipc call osd brightness`.

**Steps:** implement → smoke `--osd` mode (in-session: `qs ipc call osd volume` then screenshot — card visible bottom-center with the three columns; then `wpctl set-volume @DEFAULT_AUDIO_SINK@ 30%` and confirm auto-show on a second screenshot) → commit `feat(osd): jitter-free bottom-center osd with audio auto-trigger`; push.

---

### Task 7: Docs + screenshots + hard-rule update

**Files:** Modify `README.md`, `docs/ARCHITECTURE.md`, `CLAUDE.md`; add `docs/screenshots/notifications-niri.png`, `docs/screenshots/osd-niri.png`.

**Steps:**
- Screenshots from the `--notify --center` and `--osd` smokes (Read them first).
- README: Notifications section (three-tier model, DND bypass rule stated honestly, IPC verbs, center summon keybind example) + OSD section (triggers, brightness-keybind pattern).
- ARCHITECTURE: notification data flow (server → model.js reducer → tiers → surfaces) + OSD trigger graph.
- CLAUDE.md: add the **D-Bus isolation hard rule** (session-bus name acquisition never against the host bus; smoke scripts wrap `dbus-run-session`; host-owner assertion pattern) + new smoke modes in the verification loop.
- Verify every documented command; commit `docs(notifications): notification stack, osd, dbus isolation rule, screenshots`; push.

---

## Self-review notes (applied)

- OSD depends on services, not the reverse — AudioService/BrightnessService land first and are independently dump-verified.
- The DND bypass is deliberately narrow (Omarchy's rule) and encoded in ONE pure function with tests on both sides — the review checkpoint greps that no other code path adds popups while DND is on.
- Center/toasts share `NotificationCard` where possible; both are Cells — design-drift grep stays valid.
- Host-bus safety is verified per smoke run (busctl owner assertion), not assumed.
