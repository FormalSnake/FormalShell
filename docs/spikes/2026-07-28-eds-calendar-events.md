# Spike: EDS/GOA calendar events from pure QML (M6 Task 5)

**Question:** can FormalShell read GNOME Online Accounts calendar events —
via Evolution Data Server's D-Bus API — from pure QML/JS, with no compiled
companion binary (CLAUDE.md's hard rule)?

**Answer: no, not usefully.** EDS's calendar D-Bus protocol requires a
single, held-open D-Bus connection across a multi-call handshake, which no
CLI tool (`gdbus`, `busctl`, `dbus-send`) can hold — each is a one-shot
process. Quickshell itself ships no generic QML-exposed D-Bus binding to do
it directly either. Driving the real protocol would mean writing and
maintaining a small persistent-connection helper (Python/GJS via `Process`),
which buys nothing over the spec's own documented fallback since GOA-backed
accounts need an interactive OAuth sign-in this headless rig can never
complete or verify anyway. **Implemented path: local `.ics` files from a
configured directory** (khal/vdir-compatible), per the spec's and plan's own
fallback clause.

## What was tried, in order

### 1. Is EDS even reachable over D-Bus without a compiled client?

Built `evolution-data-server` (3.60.2, from the pinned nixpkgs, cached on
cache.nixos.org — no local compile needed) and registered its D-Bus
`.service` files on the test VM's session bus via
`services.dbus.packages = [ pkgs.evolution-data-server ]` (temporary, for
this spike only — see "Cleanup" below). D-Bus activation worked immediately:

```
$ gdbus call --session --dest org.gnome.evolution.dataserver.Sources5 \
    --object-path /org/gnome/evolution/dataserver/SourceManager \
    --method org.freedesktop.DBus.ObjectManager.GetManagedObjects
```

returned a live `ObjectManager` dump of EDS's auto-registered default
sources, including a local `system-calendar` UID (EDS creates
"On This Computer" mail/calendar/tasks sources automatically, no GOA account
needed) — confirming the source registry itself is trivially readable, plain
D-Bus, no C client library required.

### 2. Opening the calendar: the factory handshake

```
$ gdbus introspect --session --dest org.gnome.evolution.dataserver.Calendar8 \
    --object-path /org/gnome/evolution/dataserver/CalendarFactory
```

exposes `OpenCalendar(source_uid) -> (object_path, bus_name)`. Calling it:

```
$ gdbus call --session --dest org.gnome.evolution.dataserver.Calendar8 \
    --object-path /org/gnome/evolution/dataserver/CalendarFactory \
    --method org.gnome.evolution.dataserver.CalendarFactory.OpenCalendar \
    "system-calendar"
('/org/gnome/evolution/dataserver/Subprocess/988/2', 'org.gnome.evolution.dataserver.Calendar8')
```

works — the backend spins up as a subprocess but answers on the *same*
well-known bus name, not a private peer-to-peer socket (better than
expected). The returned object exposes `Open()`, `GetObjectList(query)`
(query is an EDS S-expression; returns raw ICS text synchronously — no
`GetView`/streaming subscription needed for a one-shot read) per the
upstream interface XML (`src/private/org.gnome.evolution.dataserver.Calendar.xml`
in the EDS 3.60.2 source tarball).

### 3. The actual blocker: connection-tied backend lifetime

Introspecting the returned object path from a **second**, freshly-connected
`gdbus` invocation (i.e. what any one-shot CLI call necessarily does) found
nothing:

```
$ gdbus introspect --session --dest org.gnome.evolution.dataserver.Calendar8 \
    --object-path /org/gnome/evolution/dataserver/Subprocess/988/2
node /org/gnome/evolution/dataserver/Subprocess/988/2 {
};
```

Reproduced deterministically, back-to-back with no delay: `OpenCalendar` →
`Open()` on a fresh connection against the returned path:

```
Error: GDBus.Error:org.freedesktop.DBus.Error.UnknownMethod: Object does not exist at path "/org/gnome/evolution/dataserver/Subprocess/1034/2"
```

Reading EDS's own source (`src/libebackend/e-data-factory.c`,
`data_factory_watched_names_add`/`data_factory_name_vanished_cb`) confirms
why: the factory `g_bus_watch_name_on_connection`s the **calling client's**
unique bus name and tears the backend reference down the instant that name
vanishes. A CLI tool's connection closes the moment the process exits —
i.e. immediately after the reply — so the backend is gone before any
*second* invocation could ever reach it. The whole
`OpenCalendar → Open → GetObjectList` sequence has to happen over **one held
connection**, which rules out `gdbus`/`busctl`/`dbus-send` categorically —
each is architecturally a single request-response process, not a session.

### 4. Does Quickshell give QML a generic D-Bus binding instead?

Checked the pinned quickshell source (`src/dbus/`: `bus.cpp`, `properties.cpp`,
`objectmanager.cpp`) — a real C++ D-Bus helper layer exists, but it's
internal plumbing consumed only by hand-written, interface-specific C++
modules (`src/network/nm/*` for NetworkManager, `src/dbus/dbusmenu/*` for
the DBusMenu protocol). Only `dbusmenu.hpp` registers a `QML_ELEMENT`; there
is no generic `DBusInterface`/`DBusProxy` QML type a `.qml` file could
import to make an arbitrary method call, let alone hold a connection open
across several. Confirmed by grep, not assumption
(`grep -rn "QML_ELEMENT\|QML_SINGLETON" src/dbus`).

## Decision

Driving the real EDS protocol from this shell would require a small helper
process holding one persistent D-Bus connection through the whole
open→query sequence (a short Python/`dasbus`, GJS, or similar script
launched via `Process` and kept running) — not a *compiled* binary
(CLAUDE.md's specific ban), but a comparable maintenance and dependency
burden, and one that would still only ever reach the local "On This
Computer" EDS calendar in this test rig: exercising an actual GOA-backed
account needs an interactive OAuth sign-in that a headless VM can never
complete or verify, so the payoff for that extra machinery is close to
zero. Recorded as a **post-v1 item**: EDS/GOA calendar events are feasible
in principle (the D-Bus protocol itself is plain, documented, and
synchronous once a connection is held) but not worth building against until
there's a real interactive desktop session to test the GOA path on.

**Implemented instead:** local `.ics` files from a configured directory —
the spec's and plan's own documented fallback, khal/vdir-compatible (a flat
folder of one-or-more-VEVENT `.ics` files).

## What shipped

- `shell/Calendar/ics.js` (`.pragma library`, TDD'd — `tests/tst_calendar_ics.qml`,
  16 tests): RFC 5545 line unfolding, VEVENT extraction across any number of
  concatenated `VCALENDAR`s, UID/SUMMARY/DTSTART/DTEND, all-day vs timed vs
  UTC values, SUMMARY unescaping, `eventsOnDate(events, date)`. No RRULE
  expansion — a recurring event's anchoring VEVENT is read as a single
  occurrence, a deliberate v1 scope cut, not an oversight.
- `shell/Services/CalendarEventsService.qml`: reads `calendar.icsDir` from
  `settings.json` (unset → zero events, the honest empty state every other
  panel backend in the test VM already follows); when set, refreshes via a
  `cat "$dir"/*.ics` `Process` (mirrors `ThemeEngine`'s own drop-in-directory
  read) on an `icsDir` change and every 5 minutes thereafter — no
  folder-watch model, Quickshell has no directory-listing QML type and a
  periodic re-read is enough for data that changes on the timescale of
  "someone edited a calendar file."
- `shell/Surfaces/Panels/CalendarPanel.qml`: an accent dot under any
  in-month day with ≥1 event (reserved layout space always present so rows
  stay uniform height whether or not a day has the dot — no jagged grid),
  plus a `TODAY` ledger section listing today's events by summary, or a
  single dim `NO EVENTS` row when there are none.

## Bug found and fixed during verification

`CalendarEventsService.refresh()` originally gated its `Process` call on the
derived `available` property (`icsDir !== ""`) rather than `icsDir` itself.
Called from `onIcsDirChanged` (needed because `Config`'s `settings.json`
load is async — `icsDir` is still `""` at `Component.onCompleted`), reading
`available` inside that same handler returned a **stale `false`** even
though `icsDir` itself had already updated to the real path — confirmed with
temporary `console.warn` tracing in a manual isolated-HOME run
(`icsDir=/tmp/.../calendar available=false` logged in the same line).
Whichever property the *other* property's binding depends on isn't
guaranteed to have re-evaluated yet inside a signal handler for the
triggering change. Fixed by checking `icsDir` directly in `refresh()`
instead of going through `available`.

## Cleanup

`evolution-data-server` and the `services.dbus.packages` registration used
for steps 1–3 above were added to `nix/testvm.nix` for this spike and
**removed again** once the decision was made — no dependency on a backend
this shell doesn't use ships in the tree.

## Verification

- `just test` — 140/140 (16 new `ics.js` tests + all pre-existing).
- `dev/vm.sh run 'nix flake check -L'` — clean (only pre-existing
  `ThemeEngine.qml`/`CompositorService.qml` warnings, unrelated to this
  change).
- `just vm-smoke --panel calendar` — screenshot shows JULY 2026, today (28)
  inverted with the accent dot under it, `TODAY` listing `SMOKE FIXTURE
  EVENT` (the smoke script's own `.ics` fixture, dated at run time so it
  never goes stale), `YEAR 57%`.
- Manually re-verified the zero-events path with `calendar.icsDir` absent
  from `settings.json`: `NO EVENTS`, no dots, no crash — the panel keeps
  working with zero events configured, per the plan's requirement.
