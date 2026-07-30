# FormalShell M12: DMS parity gaps + GOA/EDS calendar

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding.

**Origin, owner ask (2026-07-30):** the e1504g swap review named the features
lost moving off DMS: GOA/Google calendar events, the emoji launcher, the
calculator and nix-package-runner launcher surfaces, the GitHub notifier, and
screenshot tooling. Owner verdict: "all of the features you mentioned I'd
lose are essential". For calendar specifically: "I want to use GNOME's online
account system", and a compiled companion CLI is explicitly authorized ("if
we really need a CLI, write one with zig or something"). This plan closes all
six gaps, then refreshes screenshots and docs. The nix-config side (enabling
GOA system services on e1504g, new keybinds) is out of scope here and happens
at rebuild time.

**Owner override of two standing rules, recorded:** the spec's non-goals list
(no screenshot tooling, launcher plugins out of scope) and CLAUDE.md's "no
compiled companion binary" rule are both amended by the owner's 2026-07-30
ask, narrowly: one small in-repo companion CLI for EDS, screenshot tooling as
a thin grim/slurp wrapper, and the four launcher/bar features above. Task 1
writes these amendments into the spec so the "spec wins" rule stays coherent.

**Already established, do not re-derive** (from
`docs/spikes/2026-07-28-eds-calendar-events.md`, all confirmed against a real
EDS 3.60.2 on the VM's session bus):

- EDS source discovery is plain D-Bus: `org.freedesktop.DBus.ObjectManager.GetManagedObjects`
  on `org.gnome.evolution.dataserver.Sources5` at
  `/org/gnome/evolution/dataserver/SourceManager`. GOA-backed calendars
  appear here exactly like local ones.
- Opening a calendar is `OpenCalendar(uid)` on
  `org.gnome.evolution.dataserver.Calendar8` at
  `/org/gnome/evolution/dataserver/CalendarFactory`, then `Open()` and
  `GetObjectList(sexp)` on the returned object path, same well-known bus
  name. `GetObjectList` returns **raw ICS text synchronously**. No view or
  subscription API is needed for a one-shot read.
- The only blocker was connection lifetime: the factory watches the calling
  client's unique bus name and tears the backend down when it vanishes. The
  whole handshake therefore has to run over **one held connection**. That is
  trivially satisfied by one short-lived process doing all calls on one
  connection before exiting. It categorically cannot be done by chaining
  `gdbus`/`busctl` invocations, and Quickshell exposes no generic QML D-Bus
  type. Hence the CLI.
- `shell/Calendar/ics.js` already parses concatenated VCALENDAR/VEVENT text
  (16 tests). The CLI's stdout can feed the exact same parser.

## Constraints

- `CLAUDE.md` hard rules bind except where the owner override above narrows
  them. `docs/DESIGN.md` is the design authority for every new surface: cells
  not cards, radius 0, monospace, Nerd Font glyphs, uppercase meta labels,
  honest empty states (`NO AUTH`, `NO GH`, `NO ACCOUNTS`, never invented
  data).
- The companion CLI is the ONLY compiled artifact. Zig is the owner's stated
  preference; sd-bus (libsystemd) is the D-Bus layer, not glib/libecal. If
  Zig's C interop with sd-bus fights back, time-box it: after roughly 45
  minutes of fighting the toolchain rather than the problem, fall back to
  plain C with the same sd-bus design, and record the decision in the commit
  message. The CLI must stay small (a few hundred lines): no daemon mode, no
  caching, no RRULE logic in the binary.
- Existing behaviour may not change: every current smoke mode must still
  pass. Smoke script changes are additive only.
- Menu additions follow the existing provider/route architecture
  (`shell/Menu/providers.js`, the `clipboard` route is the worked example,
  summoned via `menu summon <route>`). No second architecture.
- Every task ends with its verification commands actually run, their output
  read (screenshots Read as images, not assumed), and a conventional-style
  commit (`feat(scope): ...`, lowercase imperative, no co-author trailers,
  no commit descriptions).
- The VM rig is the verification loop (`just vm-test`, `just vm-smoke
  [flags]`, `just vm-lint`; see CLAUDE.md's macOS verification loop section).
  The VM is already running; `dev/vm.sh status` to confirm, `dev/vm.sh
  start` if not. Tasks run strictly sequentially in this one working tree,
  committing before the next task starts.
- ⚠️ Files containing Nerd Font glyphs or emoji data: targeted `Edit`
  operations only, never wholesale rewrites.

---

### Task 1: Spec addendum + README status fix

**Files:** modify `docs/superpowers/specs/2026-07-27-formalshell-design.md`,
`README.md`.

**Produces:**
1. A dated addendum section in the spec (do not rewrite history in place)
   recording the owner's 2026-07-30 override: EDS/GOA calendar events enter
   v1.5 scope via one small companion CLI (amending both the non-goals list
   and the pure-QML hard rule, narrowly); screenshot tooling (grim/slurp
   wrapper behind a `screenshot` IPC target) enters scope; menu providers
   calculator/emoji/nix-run and a `github` bar widget enter scope. Each with
   one sentence of rationale pointing at this plan.
2. README's stale "Status" line updated (M1 through M11 complete, M12 in
   progress, pointer to this plan).

**Verify:** `just test` still green (nothing functional changed), README
renders sanely (`head -40 README.md` read).

### Task 2: `formalshell-eds` companion CLI + nix packaging

**Files:** create `tools/eds/` (Zig sources + `build.zig`, or C + a tiny
Makefile if the fallback triggers); create `nix/eds-package.nix`; modify
`flake.nix` (new package output `formalshell-eds`), `nix/package.nix` (add
the CLI to the wrapper's PATH prefix so `Process` finds it),
`nix/testvm.nix` (add `evolution-data-server` + its
`services.dbus.packages` registration, restoring what the spike removed).

**Produces:**
1. `formalshell-eds sources`: JSON array of calendar sources
   (`{uid, displayName, backend}`) from the SourceManager ObjectManager dump.
   Filter to sources that actually have a Calendar extension.
2. `formalshell-eds events [--days N] [--source UID ...]`: for each source
   (default: all calendar sources), one held connection running
   `OpenCalendar -> Open -> GetObjectList` with an `(occur-in-time-range? ...)`
   sexp covering today minus 1 through today plus N (default 45) days, and
   prints the concatenated raw ICS to stdout. Nonzero exit and a stderr line
   when the bus or EDS is unreachable; empty output with exit 0 when there
   are simply no events. Never invents data.
3. `formalshell-eds seed <summary> <isoDate>`: rig-only helper that
   `CreateObjects` a single timed VEVENT into `system-calendar`, used by the
   smoke rig to make the EDS path testable headlessly (a real backend write,
   not a mock). Document in `--help` that it exists for the test rig.
4. Built as `packages.<system>.formalshell-eds`, linked into the shell
   wrapper's PATH.

**Verify:** in the VM (`dev/vm.sh run`): `formalshell-eds sources` lists
`system-calendar`; `seed` then `events` round-trips the seeded event as
parseable ICS (pipe through `rg SUMMARY`); a second `events` run confirms
repeatability. `just vm-build` green. Commit.

### Task 3: CalendarEventsService EDS backend

**Files:** modify `shell/Services/CalendarEventsService.qml`,
`shell/Core/Config.qml` (document new key), `dev/smoke-niri.sh` (extend
`--panel calendar`), `tests/` sibling if service logic is extracted into a
testable js lib.

**Produces:**
1. The service gains an EDS path: run `formalshell-eds events` via `Process`
   on the same refresh cadence the ics path already uses (icsDir change /
   5 minutes / panel open), parse stdout through the existing
   `Calendar/ics.js`, and merge with icsDir events (both sources can
   coexist; dedupe by UID).
2. `calendar.eds` settings key (bool, default `true`): the service probes by
   running the CLI once; unreachable EDS degrades silently to ics-only, the
   honest state, no error cell, one console.warn.
3. `--panel calendar` smoke leg additionally seeds EDS via
   `formalshell-eds seed "EDS FIXTURE EVENT" <today>` and the screenshot must
   show BOTH the existing ics fixture event and the EDS one under TODAY.

**Verify:** `just vm-test` green; `just vm-smoke --panel calendar` PNG Read
and both fixture events visible. Commit.

### Task 4: RRULE expansion subset in ics.js

**Files:** modify `shell/Calendar/ics.js`, `tests/tst_calendar_ics.qml`.

**Produces:** bounded expansion of recurring VEVENTs into instances within a
query window: FREQ=DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, COUNT, UNTIL, and
BYDAY for weekly rules. Unsupported parts (BYSETPOS, BYMONTHDAY lists,
EXDATE handling beyond simple date matches if not already present) leave the
anchoring event as a single occurrence, documented in the file header. TDD:
new tests first, covering each FREQ, INTERVAL>1, COUNT and UNTIL bounds, a
weekly BYDAY=MO,WE, and the fallback for an unsupported rule.

**Verify:** `just vm-test` green with the new tests counted. Commit.

### Task 5: Menu calculator provider

**Files:** modify `shell/Menu/providers.js` (or wherever the provider
registry actually lives, read it first), create the parser as a `.pragma
library` js file with tests.

**Produces:**
1. A safe recursive-descent expression parser (no `eval`, no `Function`):
   + - * / % ^ parentheses, unary minus, decimal and underscore-free numbers.
2. Root-menu integration: when the query parses as an expression, the first
   row is `= <result>` (accent meta label `CALC`), Enter copies the result
   via `wl-copy` and closes the menu. Also a `calc` route for a dedicated
   surface, same pattern as `clipboard`.
3. Parse errors are silent (no row), never a crash row.

**Verify:** parser tests green in `just vm-test`; `just vm-smoke --menu`
still passes; an added smoke assertion drives `menu debug query "2+2*3"` and
checks the ranked result contains `8`. Commit.

### Task 6: Menu emoji provider

**Files:** create `shell/Menu/emoji.json` (vendored, generated), create
`dev/gen-emoji.sh`, modify `shell/Menu/providers.js`.

**Produces:**
1. `dev/gen-emoji.sh`: generates `emoji.json` (`[{ch, name, group}]`) from
   Unicode's published `emoji-test.txt` (fully-qualified entries only),
   header comment records source URL + Unicode version + license note. Run
   it once and vendor the output; the shell never generates at runtime.
2. An `emoji` route (`menu summon emoji`): fuzzy search over names, row
   renders the char + uppercase name, Enter copies the char via `wl-copy`
   and closes. The clipboard service then captures it, same as DMS's flow.
3. Root-level trigger `:e <query>` narrowing to emoji results, matching the
   DMS muscle memory the owner already has.

**Verify:** `just vm-test` green (data file loads, search returns a known
mapping such as "thumbs up"); smoke assertion via `menu debug query ":e
thumbs"` returns the 👍 row; `--menu` mode still passes. ⚠️ `emoji.json` is
multi-byte dense: never Edit it by hand, always regenerate. Commit.

### Task 7: Menu nix package runner provider

**Files:** modify `shell/Menu/providers.js`, `dev/smoke-niri.sh` (PATH shim).

**Produces:**
1. A `nix` route plus `:nix <query>` root trigger: debounced
   `nix search nixpkgs <query> --json` via `Process` (500ms debounce, one
   in-flight search, stale results dropped), rows show attr name + version +
   dimmed description, Enter spawns the package in a terminal:
   `ghostty -e sh -c 'nix run nixpkgs#<attr>; read'` when a query row is
   picked. `nix` missing from PATH renders the honest single dim `NO NIX`
   row.
2. Smoke: a PATH-shimmed `nix` fixture script (echoing a canned
   `--json` result) so the rig verifies plumbing hermetically, same pattern
   as `dev/sni-stub.py`. Real `nix search` behaviour is host-trial territory.

**Verify:** `just vm-smoke --menu` extended assertion: `menu debug query
":nix hello"` against the shim returns the canned attr row. `just vm-test`
green. Commit.

### Task 8: `github` bar widget

**Files:** create `shell/Surfaces/Bar/widgets/GithubWidget.qml`, modify
`shell/Bar/layout.js` (register the widget name), `shell/Surfaces/Bar/Bar.qml`
(builtin registry entry), `dev/smoke-niri.sh` (gh shim + a `--bar-layout`
region entry or dedicated assertion).

**Produces:**
1. A `github` builtin (opt-in via `bar.layout`, NOT in the default
   arrangement: the no-config fallback must stay byte-identical): polls
   `gh api` every `github.intervalMs` (default 300000) for open PRs authored
   by the user and issues assigned, renders a glyph + `N/M` meta cell.
   Click spawns `xdg-open https://github.com/notifications`.
2. Honest states: `gh` absent from PATH -> hidden entirely (the Battery
   `shown` pattern, read CLAUDE.md's Loader-visibility warning and Bar.qml's
   header comment before wiring); `gh` present but unauthenticated -> dim
   `NO AUTH` cell.
3. Smoke: gh PATH shim returning canned JSON; `--bar-layout` gains the
   widget in its custom layout so the existing screenshot proves it renders.

**Verify:** `just vm-smoke --bar-layout` PNG Read shows the github cell with
the canned counts; default-layout modes unchanged (`just vm-smoke` plain PNG
shows no github cell). `just vm-test` green. Commit.

### Task 9: `screenshot` IPC target

**Files:** create `shell/Ipc/ScreenshotIpc.qml`, modify `shell.qml` (or
wherever IPC targets register, mirror an existing one), `nix/package.nix`
(add `grim` and `slurp` to the wrapper PATH), `dev/smoke-niri.sh`
(`--screenshot` mode), `shell/Core/Config.qml` (document
`screenshot.directory`, default `~/Pictures/Screenshots`).

**Produces:**
1. `screenshot full` and `screenshot region`: grim (with slurp geometry for
   region) writing `<dir>/screenshot-<timestamp>.png` AND copying to the
   clipboard via `wl-copy`, replying with the file path. Failure (slurp
   cancelled, grim error) replies with an error string, never a silent
   no-op.
2. A fired notification via the shell's own NotificationService on success
   (summary + path), so there is visible feedback without any bar surface.
3. Smoke `--screenshot`: calls `screenshot full` in the nested session,
   asserts the reply path exists and is a valid PNG (`magick identify` or
   `file`), and that `wl-paste --list-types` shows an image type.

**Verify:** `just vm-smoke --screenshot` passes with output read; existing
modes unaffected. `just vm-test` green. Commit.

### Task 10: Docs + screenshots sweep

**Files:** modify `README.md`, `docs/USAGE.md`, `docs/SWITCHOVER.md`;
recapture affected `docs/screenshots/*.png` via the smoke rig.

**Produces:**
1. USAGE: new sections for the calendar EDS backend (including the
   `formalshell-eds` CLI contract and GOA setup pointer), calc/emoji/nix
   menu routes and triggers, the github widget config, the screenshot IPC
   target with example niri binds.
2. SWITCHOVER: gaps table updated: EDS/GOA and RRULE rows closed (VM-only
   evidence, GOA OAuth path explicitly still needs the real-host trial),
   new rows for the five new surfaces with their evidence links.
3. README feature list updated; screenshots recaptured for menu (with the
   new routes visible where the existing capture flow shows them) and
   calendar panel (now with the EDS fixture event). Only recapture
   screenshots whose surface actually changed.

**Verify:** every named doc section exists (`rg` the headings), recaptured
PNGs Read and visually sane, `just vm-test` + `just vm-smoke` green at HEAD.
Commit.
