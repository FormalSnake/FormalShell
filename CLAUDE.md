# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Standing orders

- Plans are created autonomously — no user approval gate before writing one.
- Implementation, mapping, testing, and docs all run through subagent
  workflows (one subagent per plan task, sequential, verification evidence
  required before commit — see `docs/superpowers/plans/`).
- The approved design lives at `docs/superpowers/specs/`. Plans live at
  `docs/superpowers/plans/`. **The spec wins over any plan on conflict.**
- Since 2026-08-25 the approved design is
  `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md` (Omarchy
  behaviour, shadcn chrome, wallpaper palette, keyboard everywhere, Hyprland
  only). The 2026-07-27 spec still holds for architecture, IPC and config;
  the 08-25 spec wins where the two disagree.
- Since 2026-09-18 `docs/superpowers/specs/2026-09-18-theme-boundary.md`
  decides what a theme owns (styling, bar position, motion) and what is
  global (layout, behaviour, spacing, casing, palette source). It wins
  over both specs above.
- Since 2026-10-06 `docs/superpowers/specs/2026-10-06-rust-rewrite.md`
  replaces the Quickshell runtime with a Rust binary under `crates/`. It
  wins over the "pure QML/JS" hard rule; `shell/` stays the shipped shell
  until milestone R9 cuts over.

## Verification loop

- `just build`: `nix build .#formalshell`. **`git add` first**, flakes only
  see git-tracked files, so an unstaged file is invisible to the build.
- `just test`: headless `qmltestrunner` over `tests/` (`QT_QPA_PLATFORM=offscreen`).
- `just lint`: `nix flake check -L` (qml-tests + qmllint).
- `just smoke` / `dev/smoke.sh <flags>`: the runtime loop. Builds the shell,
  brings up an isolated Hyprland session under `dbus-run-session`, drives
  the legs the flags asked for, screenshots, tears it down. **Read the PNGs
  rather than assuming they look right.**
- `just vm-smoke <flags>`: the same script inside the mac VM, screenshots
  pulled back to the mac (the mac rig section below).
- `just vm-greeter` / `dev/smoke-greeter.sh`: not a flag on the rig. greetd's
  `default_session` is a standing system service, so this drives the
  already-running greeter session (restart greetd, screenshot pre-auth, a
  wrong password then the real one over `wtype`) and pulls
  `artifacts/greeter/`. It fails unless the session log shows a real
  `pam_authenticate: AUTH_ERR` on the wrong attempt.
- `dev/parity.sh <flags>`: runs one leg combination through `just vm-smoke`
  from this worktree and from a sibling worktree at `origin/main`
  (`../FormalShell-main`), then `compare -metric AE`s every frame pair into
  `artifacts/parity/diff/`. The one acceptance test for a theme table
  migration: a non-zero diff outside the bar clock, a caret or a toast
  timestamp is a defect, never a pixel to wave off.
- `dev/native-check.sh [--no-build] [release...]`: the Arch and Debian/Ubuntu
  packages built for arm64 in a container on the mac, copied into the VM
  and run through `--native` one release at a time (trixie, forky,
  resolute, arch by default), frames and logs under
  `artifacts/native/<release>/`.

How a run works:

- Session mode is decided by the machine, never by a flag: a real host nests
  Hyprland in the running session, and the VM, whose pixman sway parent
  advertises no `zwp_linux_dmabuf_v1` and hands out no render node, runs it
  on the `vkms` software KMS card instead (`nix/testvm.nix`).
- Flags combine into one session: `leg_<n>_order` sets the order, timings are
  max-merged so a combination outlives its slowest half, and a leg that
  cannot share the session takes the run over (`--screensaver-gif`).
- Legs sharing a surface wait on the owner's marker (`picker_done_path`), and
  a leg covering the whole output starts at its own `<leg>_t0`, past any
  desktop sampler, which is why `--wallpaper` pushes `--menu` and `--lock`
  back and leaves a matugen-recoloured desktop behind them.
- Every run prints `SMOKE_OK <path>` for its own frame and `SMOKE_<NAME>
  <path>` for each named artifact; `dev/vm.sh smoke` scps all of them plus
  the run's stdout JSON into `./artifacts/` on the mac.
- Each VM holds one checkout and `dev/vm.sh sync` rsyncs over it with
  `--delete`, so every VM command from a worktree goes through
  `dev/vm-lock.sh just vm-smoke <flags>`. There are two VM slots (`FS_VM_SLOT`,
  default 0): the lock takes whichever slot is free, waits when both are busy,
  boots that slot's VM if it is down and exports `FS_VM_SLOT` to the command.
  Slot 0 is ssh 2222 and state in `dev/.testvm`, slot 1 is 2223 and
  `dev/.testvm/slot1`; each VM is 8 GB and 6 cores, so no third slot.
- matugen's source colour is pinned to its own rank 0 rather than left to
  `--prefer`, which is a bad proxy for what colour a wallpaper is;
  `shell/Theme/ThemeEngine.qml`'s header carries the why. Force the source
  the same way if you run matugen by hand while debugging.

Every leg is one file, `dev/smoke.d/<name>.sh`, whose header carries the
detail; `dev/smoke.d/README.md` is the file contract. What each proves:

- `airplay.sh` `--airplay`: AirplayService against a PATH-shimmed `uxplay`
  (the real one decodes into a GL texture this rig's software KMS card has
  no path for), which prints uxplay's own connect log line and writes the
  `-md`/`-ca`/`-dacp` files at its own startup, standing in for a client
  already connected. `airplay status` and the media panel's `airplay`
  source (MediaService's `_airplayRows`) read the metadata and cover art
  back; a drive-script trigger then tells the shim to clear the files and
  print the disconnect line, and both go back to idle in the frame and
  over IPC.
- `app_grid.sh` `--app-grid`: `menu.appGrid` drawing the launcher's app
  results as icons over their names, read off the probe entry's own colour
  covering a 64px cell rather than a row's glyph, with real arrow keys
  moving the cursor one cell across and a column count down, a real Enter
  launching through the row path, apps and a ranked route sharing the card,
  and the key deleted underneath the running shell putting the grid back
  under every theme, `--pantheon` included.
  Then typing on real keys: `cursorId` agreeing with the view's own
  `viewCursor` after a re-rank and a Backspace, a query no app matches
  keeping the grid with no rows in it, Escape clearing the query and
  leaving the launcher open, and a held Backspace climbing one level.
- `bar_adaptive.sh` `--bar-adaptive`: the wingpanel band reading its own
  paint off the wallpaper under it, four wallpapers in one session (a flat
  bright field, a flat dark one, a half-and-half field, and the dark one
  under a fullscreen window), each read twice: the paint and the three
  numbers `bar paint` reports, and the fill the band actually drew, off a
  patch of the frame above the cells. Pins `theme.preset` and
  `fullscreen.hideChrome` itself.
- `bar_layout.sh` `--bar-layout`: user `bar.modules` and a reordered layout
  resolved from settings.json alone, every `CommandModule` failure path in
  the one frame.
- `bar_position.sh` `--bar-position <edge>`: the strip on a bottom, left or
  right edge, read off the compositor's own layer geometry, with a chevron
  collapsing and expanding along it and a panel hanging off its inner edge.
  Ridden by a leg that photographs its own frames (`--join`,
  `--menu-emerge`, `--panel-morph`) it pins the edge alone: the layout, the
  chevron and the panel are then the rider's business.
- `bar_room.sh` `--bar-room`: a strip crowded past its own length, `bar
  room` reporting a hidden cell in the right region and a now-playing
  budget under 220, the frame read for a whole cell at the region's own
  inner edge, never a cut one, and every drawn cell rect `bar room`
  reports clear of every other.
- `bar_title.sh` `--bar-title`: a window title far longer than the strip
  in a crowded bar, read off `bar room`: the title drawn at exactly the
  budget its region has with the marquee running, no cell hidden, and no
  two cell rects intersecting, cut by a clip or past the strip's ends,
  settled and in 24 samples taken while focus switches to a short title
  and back. A real mpv plays a long-titled track throughout: both labels
  keep a non-zero budget, the track at least its minimum or an even share
  and the title no more than the track while the track is short, and the
  centre's middle within 2px of the strip's where the cells let it be.
  Then settings.json rewritten to the title cell alone, the title
  stopping at its own ceiling with the marquee running. Rides `--bar-position <edge>`, which pins the edge in this
  leg's own `bar` key.
- `caffeinate.sh` `--caffeinate`: `caffeinate.onStartup` starting the
  session caffeinated with its `formalshell:caffeinate` layer surface
  mapped, the real ext-idle-notify monitor staying non-idle three screensaver
  timeouts in, and after `caffeinate disable` the surface gone and the same
  timeout firing the screensaver on its own.
- `capture.sh` `--capture`: the shell's own region picker (smart pick, tab
  cycling, commit) measured against the compositor's output, the toolbar's
  record commit, and the cancel path.
- `capture_edit.sh` `--capture-edit`: the SAVED notification's EDIT action
  reaching a real editor with the capture's own path on argv.
- `center.sh` `--center`: the notification centre listing the pending tier,
  with the toast stack suppressed for as long as it is open, content-tall on
  a short history and capped and scrolling on thirty rows, then one open at
  a tenth speed over a band down the trailing edge, for the card coming out
  of the line there.
- `chevron.sh` `--chevron`: a right-region chevron holding the five cells
  before it off the strip entirely, and `bar chevron expand` opening them in
  the second bar under it, the two frames asserted to differ. Under
  `--pantheon` it also sets a flat bright wallpaper first, so the band goes
  to dark ink, and reads a patch inside the card for a dark plate carrying
  light words: the second bar keeps its own ink whatever the band wears.
- `chevron_quiet.sh` `--chevron-quiet`: the same second bar OPENING, read
  off a stamped burst of frames: the card is never narrower than the width
  it settles on, and nothing inside it moves once its own entrance is over.
- `clipboard.sh` `--clipboard`: the ledger's capture order and in-process row
  activation, with the image entry's preview and a copied-markup row's own
  angle brackets in the frame, and a `text/uri-list` copy of one jpeg (how a
  GTK4 app copies an image) landing as a png image row.
- `clipssh.sh` `--clipssh`: the clipssh route's send, its bar indicator and
  its copied/failed toasts, against a shimmed binary.
- `clipssh_image.sh` `--clipssh-image`: the two sends that resolve a host out
  of `clipssh.alias` rather than off a row, `clipssh.autoSendImages` and
  Shift+Enter on a history image row, each checked against the sha256 of
  what the clipboard actually held when the shimmed binary read it.
- `config_reload.sh` `--config-reload`: a settings.json whose symlink is
  retargeted (what home-manager does on every activation, the one write a
  file watch cannot see) still reaching a running shell, read off the bar's
  own edge moving right to left.
- `console.sh` `--console`: the quake console parking on a special workspace
  and coming back with the same window id.
- `deform.sh` `--deform`: a burst through one open showing the card past its
  own resting box on at least one frame (the spatial curve's overshoot and
  the velocity deform on top of it) and back on it exactly three clocks
  later, the springs unwound.
- `device_routes.sh` `--device-routes`: the launcher's Wi-Fi, Bluetooth, Audio
  and Radio Stations routes over real keys and IPC, read off `menu status`
  (its `ids` and `checked` lists) and each service's own status. The Wi-Fi
  row on the two hostapd radios opens the masked password step, a wrong
  password comes back as "Wrong password" on the row and Enter asks again,
  the real one connects and ticks the row, Shift+Enter forgets it, and
  neither password reaches `menu-selection.txt` or the shell log. A null
  sink of the leg's own becomes the default over Enter, read back with
  `pactl`, the tick moving with it. Bluetooth is the honest no-adapter row
  while `panel open bluetooth` still opens the panel. A favourite served by
  the leg's own looping ffmpeg listener plays and ticks, Shift+Enter
  removes it, and `:r` leaves its searching row (a failed search passes).
  A root query reaches the saved network, the sink and the favourite, and
  never a nearby network or a search result. Refuses `--wifi` and `--radio`
  in the same run.
- `display.sh` `--display`: `display scale|mirror|enable` reaching the
  running compositor as `hyprctl eval 'hl.monitor{...}'` calls, each read
  back off `hyprctl monitors all -j`: the rig's output at scale 1.5, then a
  headless second output created for the purpose mirroring it, unmirrored,
  disabled and enabled again, removed before the panel frame is taken.
- `dump.sh` `--dump`: the `debug` target's whole state dump, saved as the
  run's JSON sidecar and read by other legs for what the shell resolved.
- `earbuds.sh` `--earbuds`: the earbuds panel against PATH-shimmed
  `nothingctl` and `openscq30` answering with fixtures read out of
  `tests/tst_earbuds_*.qml`, and a staged librepods status.json, in five
  phases: the B175 alone (wrapped listening mode and EQ rows, custom bands
  in signed dB), the Soundcore pair alone, both with the device choice
  heading the panel, the AirPods, and a device nothingctl refuses. `earbuds
  set` over IPC reaches nothingctl's stdin as exactly `anc transparency`
  and `eq-custom 5 0 -2` and openscq30 as one `--set
  ambientSoundMode=NoiseCanceling`; the refused device's `watch` prints the
  `unsupported-model` line and exits 3, and 12s later it was started once
  and no device is listed. The VM has no Bluetooth controller, so the leg
  exports `FORMALSHELL_SMOKE_BLUETOOTH`, a device list that replaces the
  adapter's (`Earbuds/model.js` `bluetoothDevices`), with the Soundcore
  pair connected.
 the launcher's emoji route by search and by order:
  `:e sob` reaching 😭 through CLDR's keywords (its Unicode name has no
  "sob" in it), and one copy through the row's own Enter path putting that
  emoji at the head of its own rank and no higher, with no settings key
  written.
- `flexoki.sh` `--flexoki`: a wallpaper under a `flexoki/` directory, and
  the rewrite reaching a user template, its `post_hook`, and the shell's own
  GTK and Qt palettes: Flexoki green and yellow, which no Material scheme
  seeded on Flexoki blue can produce.
- `frame.sh` `--frame`: pins `frame.thickness` in the settings fixture so the
  bar's window grows to the output and paints the frame round it, and reads
  that box and the four exclusion zones off the compositor's own layer list.
  Under `--pantheon` it proves the other half: a table whose `habits.frame`
  is false reads the same key as 0, so the bar stays a strip, no edge
  reserves anything and `debug dump`'s `frame` block reports the 10 that was
  asked for beside the ring that was not drawn.
- `fullscreen.sh` `--fullscreen`: the fullscreen chrome auto-hide, read off
  the compositor's own layer list: bar, frame zones and hot corners gone
  while the fixture window is fullscreen and back to their starting counts
  after, with `hyprctl clients` confirming a window really was fullscreen.
- `gallery.sh` `--gallery`: the dev gallery sheet, every shared component
  drawn against the live theme. `PowerFlow` is drawn from `Power/flow.js`'s
  fixed g815 snapshot (labelled a sample), the only populated view of it on
  a rig with no battery; `--panel power` proves the honest "No power
  sources" state.
- `gpu.sh` `--gpu`: both cards of a hybrid laptop this rig is not, and the
  four PRIME offload variables reaching a launched child.
- `grid_relaunch.sh` `--grid-relaunch`: the root grid after launches that
  re-rank it and desktop entry rescans while it is closed and open, read
  off `menu status`'s `cells`: eight ids, none twice, the launched app
  first.
- `headset_card.sh` `--headset-card`: the headset connect card, which only
  the Rust shell has (it needs `FS_IMPL=rust`). `FORMALSHELL_SMOKE_BLUETOOTH`
  is exported as `@<file>`, a JSON device list the shell reads again on every
  change (the rig has no controller), so a device connects and disconnects
  by the leg rewriting that file. A device connected at startup raising no
  card; a headphone connecting raising one with its BlueZ battery ring, held
  past four seconds by a real pointer parked on it and dismissed by the pointer leaving (Escape needs on-demand focus, which Hyprland gives on a click);
  the same device off and on inside a second raising none; AirPods off the
  staged librepods status file raising left, right and case rings, the
  pointer leaving dismissing them; and do-not-disturb raising none. Counted
  off the shell log's `headset card mapped` and `unmapped` lines, with the
  frames read by eye.
- `hdr.sh` `--hdr`: HDR on the rig's EDID-less vkms output, so the honest
  unavailable path: `hdr status` unsupported with a reason, `enable`,
  `toggle` and `setOutput` refusing with their error strings and leaving
  state.json alone, the Display panel frame carrying the dim "HDR
  unavailable" line, and `hdr rule <output>` (the rule an enable would
  send, unsent) restating the mode, position, scale, transform and vrr
  `hyprctl monitors all -j` reports. The real toggle is g815's to confirm.
- `hotcorner.sh` `--hotcorner`: both hot corner surfaces mapped on the right
  layer, which is all a rig with no synthetic pointer can observe.
- `hotcorner_relock.sh` `--hotcorner-relock`: locks from the corner, unlocks
  by typing, proves the corner stays quiet while the pointer sits in it and
  fires again only after a leave plus the 400ms cooldown. Then the same on
  the screensaver corner: dismissed with the cursor parked in it, quiet for
  3s after the overlay unmaps, firing again after a leave.
- `instance.sh` `--instance`: a second daemon taking the lock, exactly one
  survivor, and the survivor being the new pid.
- `iphone.sh` `--iphone`: IphoneService and the notification filter against
  PATH-shimmed `omarchy-iphone-bridge`/`omarchy-iphone-ams`, both a
  `tail -F` over a JSONL fixture the drive script paces in real time.
  Connected state and device name; a normal arrival's toast carrying the
  iPhone source mark, its positive action reaching the bridge shim's own
  call record; a silent arrival under `focus: respect` landing in the
  centre's pending tier with no toast, and under `hide` (retargeted
  mid-run by rewriting settings.json in place) not reaching the centre at
  all while the phone's own recent list still keeps it; the
  `com.apple.MobileSMS`/`Messages` dedupe rule collapsing a phone message
  and the same one over a real `notify-send -a Messages` to one card in
  both arrival orders, the local one surviving; and the panel populated,
  Recent and Now playing off the ams shim's own line. The ams shim's first
  run fails its subscribe (error line, then a non-zero exit) the way a phone
  not yet GATT-ready does: `iphone status` shows the error, worded as the
  LE link being down rather than the GDBus string, with no media, ams is
  started again on its backoff, and the second run's now playing lands
  with the error cleared. Then a status line for a phone BlueZ holds a bond
  for with its LE link down (a phone that forgot this laptop): not
  connected and bonded, ams not started again, the panel offering "Pair
  again", and `iphone pair` reaching the bridge shim with `--forget
  <address>`, the bond cleared and a pairing code landing in the panel.
- `join.sh` `--join`: the join itself mid-flight under `debug motionScale`,
  four opens sampled frame by frame: a panel against the far end of the
  line, the chevron's second bar, a panel clicked out of a cell inside that
  second bar, and one hanging off the line's own start. Asserts the line's
  row painted once, the walled run-out to the screen's edge, a bud held
  inside its owner's span and bordered on both sides while it widens. It
  rides `--bar-position <edge>` and `--frame`, which put the same four cases
  on a vertical hairline or against a ring's line; every probe is cut for the
  top bar, so those runs print each claim as skipped and are read by eye.
- `keybinds.sh` `--keybinds`: the launcher's binds route rendering rows off
  Hyprland's own expanded bind table.
- `lights.sh` `--lights`: LightsService against PATH-shimmed `asusctl` and
  `busctl` standing in for asusd's Aura object: the startup repaint off the
  palette under the default wallpaper source, effect and speed, a custom
  colour switching the source, the toggle off and back to its level, an
  unknown effect refused, and the launcher's effect level with its tick,
  each read off `lights status` and the shim's own argv log.
- `lock.sh` `--lock`: the lock round trip over real PAM, wrong password to
  unlocked, typed by a real virtual-keyboard client, with a staged `~/.face`
  found in the locked frame as the avatar over the clock.
- `localsend.sh` `--localsend`: a real loopback transfer, a second
  independent `localsend-cli send` process against the shell's own real
  receiver child. The file lands byte-identical (sha256) in the fixture
  directory and one RECEIVED toast follows, raised by `recv`'s own `Recv
  file` log line; three files something else writes into that directory
  (a `cp`, a `.part` name, a late `cp`) raise none. The reverse direction (the
  shell's own `send` IPC route against a second real `recv`) can't run
  here: 0w0mewo/localsend-cli hardcodes the receive port to 53317 with no
  flag to move it, so a second `recv` on the same host only collides with
  the first; `--share`'s own `localsend send`/`peers` IPC round trip is
  what this rig can still honestly prove of that half.
- `lock_media.sh` `--lock-media`: a real MPRIS player looping a fixture
  track while the session locks over a flat white wallpaper, the now-playing
  block under the field photographed with its cover, real Tab, Right and
  Return through the password field's own key filter pausing the player
  (`media status`), and the clock's ink flipping from dark to light when a
  flat dark wallpaper replaces the white one under the same lock, read off
  `lock status`'s per-output report and off the frame inside the clock's
  own rect. The real password typed last still unlocks.
- `lyrics.sh` `--lyrics`: three tracks (two cached, one a sibling `.lrc` of
  the shape a line-synced provider really returns), the lit set on a duet and
  background overlap, quality and estimated timing, the estimated wipe read
  off pixels, a real wheel notch taking follow over and a track change
  re-arming it, the none track's panel narrower, the card's centre held on
  its own bar cell's centre through a lyrics arrival, the lit line broken
  inside a chunk wider than the pane, a card resting on the screen's far
  padding keeping its far edge there through a track change, lyrics
  synced before the panel ever opens with the first open landing on the
  split width, a close and reopen with no track change between putting
  `follow` back, two consecutive line changes photographed off mpv's own
  seeks (one into a line that fits a row, one into the line that wraps),
  the pane never emptying out mid-change and the lit row on one place across
  the tail of both bursts, the wipe crossing a wrapped line's row break in
  reading order with the rows under it untouched (two frames off a paused
  player), the rows the pane draws counted against the rows its own height
  holds, the instrumental note over a gap a track with no end stamps leaves
  and empty again once the song is past it, and the same two words held for
  10s and for 3s each wiping to the fraction of the row its own span is
  through. Then the player moved onto a pw-loopback sink declaring 250ms of
  latency, a bluez5 sink's shape, and the lit line held back by exactly
  that, read off `media lyrics` and three paused frames around one line's
  start.
- `lyrics_blur.sh` `--lyrics-blur`: one real MPRIS player, `media.lyricsBlur`'s
  default true against a settings retarget to false, a crop over a far
  unlit row read by edge energy and lower with the blur on, the active
  line never blurred.
- `media.sh` `--media`: the media panel read off a real MPRIS player, both
  marquee states, shuffle/loop/volume set over IPC and read back out of mpv,
  and the players switcher.
- `media_progress.sh` `--media-progress`: the media panel opened once and
  held through playback, a pause and resume, a seek, a track change and a
  player switch, with and without synced lyrics, the drawn progress fill
  measured off the frame against the position `media status` reports at
  every sample.
- `menu.sh` `--menu`: the launcher at root laid out as its sections in
  order (a staged app's grid under Applications, then the Suggestions and
  Commands rows), its fuzzy ranking against the live tree, and the select
  round trip, with every status read's
  `cursorId` checked against the row the live view holds its current item
  on (`viewCursor`). Then real arrow keys on a two-row grid of twelve
  staged apps: one Down from a fresh open scrolls nothing, and four Downs
  into the rows under the grid and four Ups back each leave the cursor's
  item whole inside the viewport (`viewCursor.top`/`bottom`).
- `menu_budget.sh` `--menu-budget`: the rust spec's launcher budget off the
  shell's own commit log, the bar's badge spinning throughout five `menu
  toggle` opens: toggle to the launcher's first commit under 50 ms, the
  shell's own hold on any bar frame under 16 ms (each gap split into the
  compositor's callback wait and the shell's turn), no gap between bar
  commits over 33 ms where the compositor kept 60 Hz, and no launcher
  commit in five seconds open at rest. Rust only; QML prints it as skipped.
- `menu_actions.sh` `--menu-actions`: the launcher's in-process `@ipc:`
  actions reached through its own rows: the toggle hub's Do Not Disturb,
  Caffeinate and Overnight rows each flipping their service with the hub
  left open and the rows ticked, Set Reminder's input step setting a
  reminder typed on real keys, and Clear Reminders dropping it.
- `menu_emerge.sh` `--menu-emerge`: the launcher budding off the top line,
  sampled frame by frame under `debug motionScale`: card fill under the line
  with nothing at its resting floor, the bar's own band undimmed while it is
  still attached, a plain bordered card over a dimmed band at rest, and the
  open-to-rest time printed before any of it is asserted. Which row that
  line is on comes out of a `debug dump`, so the same probes hold on a frame
  ring's top band; a top edge carrying neither prints them as skipped.
- `menu_morph.sh` `--menu-morph`: the card opened on the root at a tenth
  speed, then re-levelled onto the clipboard's split route, its left edge read
  off one header row per frame: the root and the rest frames on the
  `popupWidthMenu` and `popupWidthMenuSplit` edges, a frame between them.
- `menu_rows.sh` `--menu-rows`: the toggle hub filtered at a tenth speed, a
  frame of the rows' band that matches neither settled list: rows that kept
  their place slide, new ones fade in, gone ones fade out.
- `mic.sh` `--mic`: the opt-in mic cell rendering its honest no-device state
  on a machine with no capture device.
- `mirror.sh` `--mirror`: the launcher's camera mirror against two v4l2loopback
  nodes (built by `nix/testvm.nix`, loaded by the leg) fed by real ffmpeg
  writers, a colour pattern on video10 and a GREY one on video11 standing in
  for an IR sensor, alternating a dim frame and a near-black one the way an
  emitter lights every other frame. The view opened with no `/dev/video*` at all (No camera,
  no node held), then reopened on the colour camera with non-flat coloured
  pixels in the feed box and only that node held open by the shell, a real
  Tab stepping to the grey camera (grey pixels, the other node released),
  `mirror previous`/`next` over IPC, and the launcher closed with the shell
  holding no video node, all read off `/proc/<pid>/fd`. On the IR camera
  `mirror status` reports `irFilter`, and ten frames grabbed in a burst
  never show the dark frame and show the dim one levelled up: mean and
  spread each at least 1.3 times the raw frame's, measured on the
  `picture` rect against both frames rendered by ffmpeg to PNG.
- `monitor.sh` `--monitor`: the monitor bar cell, its panel and the
  launcher's monitor view, against this machine's own `/proc` and `/sys`.
- `native.sh` `--native <pkgdir>`: the packages in `<pkgdir>` installed
  with apt or pacman in a rootless podman image of their release, and the
  shell they install run from it against the session over its Wayland
  socket and Hyprland instance directory, on its own private bus: a
  connected hyprland backend in the dump, the bar, `menu toggle` opening
  the launcher, and a wrong then the real password through the package's
  own `formalshell-lock` PAM file.
- `nix_run.sh` `--nix-run`: a menu.jsonc row carrying `@ipc:nix.run:hello`
  run through `menu activate`, read off `hyprctl clients` and `pgrep`: a
  `formalshell-console.run` window running `nix run nixpkgs#hello; read`,
  and no quake console spawned by it.
- `nightlight.sh` `--nightlight`: the wlsunset-backed night light on and off,
  honest about a session that cannot gamma-control.
- `notify.sh` `--notify`: the toast stack collapsed and expanded, critical
  holding the front slot over a newer normal, the icon resolution order over
  three cards, and the layer surface the same size either way.
- `notify_close.sh` `--notify-close`: one sticky critical notification closed
  by a real pointer parked on its close button and a real click, `notifications
  status` counting one popup parked and none after. Rides `--pantheon` for
  the bubble, whose button only exists while the card's hover holds.
- `notify_emerge.sh` `--notify-emerge`: rides `--pantheon` and needs it; one
  sticky notification arriving at a tenth speed, read as a ladder down the
  card's own centre column: the bubble unfolds off its top edge, so the
  covered rungs are always the shallow ones and at least one frame carries a
  fraction of the card. The row habit's arrival is `--notify`'s frame and
  `--deform`'s burst instead.
- `ocr.sh` `--ocr`: the `capture` target's text and colour verbs against a
  window carrying known text on a known background.
- `overnight.sh` `--overnight`: overnight enabled and disabled over IPC, the
  restore record's full shape in `overnight status` (the rig's honest
  backlight -1, no LEDs, no asusctl), the bar's moon glyph in the frame,
  and state.json's record gone after disable.
- `osd.sh` `--osd`: the pill's own entrance off the bottom line sampled frame
  by frame under `debug motionScale`, ink on the output's very last row early
  and a plain pill a `screenPadding` clear of it at rest, then at full speed a
  manual call, a real `wpctl` change, and a machine with no backlight.
- `panel.sh` `--panel <name>`: one popout opened over the `panel` route, with
  `panel state` agreeing it is the only open one.
- `panel_anchor.sh` `--panel-anchor`: `panel toggle` hanging its card under
  the cell that owns the panel, read off one crop of the box under a
  left-region audio cell, the card in it once and the bare desktop once.
- `panel_at.sh` `--panel-at <n>`: `panel toggleAt <n>` walking the resolved
  right region and stopping on a panel-bearing cell.
- `panel_emerge.sh` `--panel-emerge`: `panel open network` sampled frame by
  frame, the drawer open: a ladder of probes down the card's gutter showing
  its visible height grow out of the bar's inner line to the resting rect,
  and no card pixel inside the bar's own band in any frame.
- `panel_handoff.sh` `--panel-handoff`: `audio` alone in the left region and
  `network` alone in the right, so the two cards rest ~1500px apart, and
  `panel toggle audio` over an open network panel is one card rather than
  two crossing: five mid-flight frames, none carrying a card at both
  resting places, one of them carrying a card between them, and the settled
  frame equal to the audio card's own rest frame over the band under the bar.
- `panel_keys.sh` `--panel-keys`: row-level keyboard navigation inside a
  panel, driven by real keystrokes rather than the IPC shortcuts.
- `panel_morph.sh` `--panel-morph`: a card whose content changes size
  travels to the new one, read off its far edge against the two rests: the
  Wi-Fi list collapsing under a settled card, the same collapse landing two
  seconds into a five-second emerge, and the now-playing card growing from
  NO PLAYER to a real track. The band is cut for a top bar with no frame, so
  a run on another edge drives the same three cases, prints each claim as
  skipped and is read by eye.
- `pantheon.sh` `--pantheon`: pins `theme.preset` to `pantheon` in the
  settings fixture and rides any other leg, so `--pantheon --gallery` is the
  sheet in elementary's material: raised buttons and chips over sunken
  troughs and fields, cards and toasts on a cast under a lit rim.
- `picker.sh` `--picker`: the wallpaper grid, the pick becoming the
  wallpaper, the select token round trip, the Dark/Light variants, and
  ThumbnailService's prerendered cache backing every cell (the cache
  directory's own contents, since a warmed cell and a fallback cell paint
  the same picture).
- `plugins.sh` `--plugins`: a plugin directory dropped into the config home
  placing its own bar cell, no `bar` key involved.
- `polkit.sh` `--polkit`: a real `pkexec` conversation through the shell's
  agent, the prompt, the error state and pkexec's own exit code, with the
  card's own open off the top line sampled at a tenth speed first.
- `processes.sh` `--processes`: the process table's search, the two-press
  TERM, and `monitor restart` re-running the same argv under a new pid.
- `record.sh` `--record`: `record` start to finished GIF through a real
  wf-recorder child, with the bar's recording cell mid-run.
- `r0_measure.sh` `--r0-measure <seconds>`: R0's numbers for whichever
  shell `FS_IMPL` picks, on one timeline: CPU off `/proc/<pid>/stat` over
  60s idle and 60s with a herdr badge spinning, ten panel opens and ten
  scrim fades, the launcher stall (first frame after `menu toggle`, longest
  gap between bar frames), RSS at `<seconds>`, and the launch stamp a cold
  start counts from. Records, never judges: the budgets are read by hand.
  With `FS_RESULT`/`FS_RS_RESULT` naming prebuilt store paths, nothing is
  built on the host it runs on (e1504g).
- `radio.sh` `--radio`: Radio Atlas's mpv tuned with `radio play` to a
  favourite served on loopback, read back as a media source (`media status`
  kind, title and playing, `media players` listing it once, its own Pipewire
  stream not listed again as an app), the media panel's source menu opened
  on real keys and photographed, and the source gone after `radio stop`.
- `radio_atlas.sh` `--radio-atlas`: Radio Atlas opened with `panel open
  radio` over a world cache holding one loopback-served station, Enter on a
  real key playing it and turning the globe to centre it (the globe's box
  differing from the open frame), and after `radio stop` a real click on
  the globe's centre picking it again, read off `radio status`; Escape
  closes it.
- `reminder.sh` `--reminder`: a real countdown firing inside the run and
  bypassing DND into the popup tier.
- `retro.sh` `--retro`: pins `theme.preset` to `retro` in the settings
  fixture and rides any other leg, so `--retro --gallery` is the sheet
  square, mono and dithered.
- `screensaver.sh` `--screensaver`: the live media guard, auto-activation off
  the idle timer alone, and the manual start/stop path.
- `screensaver_gif.sh` `--screensaver-gif`: five ttfx effects recorded frame
  by frame into `docs/media/`, one session each, taking the run over.
- `screenshot.sh` `--screenshot`: the `screenshot` target's region cancel and
  full-screen routes.
- `share.sh` `--share`: the share route present (the copied text reaching
  LocalSend as a real file) and honestly absent with no binary on PATH.
- `showcase.sh` `--showcase`: seeds state.json with a generated wallpaper
  before the shell starts, so the leg it rides photographs a matugen palette
  over a real desktop. The README's screenshots and GIFs are taken under it.
- `shoulders.sh` `--shoulders`: a join published over `debug join`, the gap
  the bar opens in its own line read off the shell's numbers as the card's
  rect plus a `radiusXl` fillet at either end, and the pixel where the line
  stops and the arc starts.
- `sleep.sh` `--sleep`: `sudo systemctl suspend` with the session unlocked,
  the real logind path with only the kernel's freeze stubbed, the lock read
  back after wake: the stub's millisecond stamp has to come after the shell
  let its delay inhibitor go with the surface secure, and the `FormalShell`
  inhibitor shows in `systemd-inhibit --list` before the suspend and again
  after wake.
- `spaces.sh` `--spaces`: the Spaces cell over windows on two workspaces,
  each listed with its icon under its own chip in `workspaces status`, every
  occupied chip showing its icons and every chip its ordinal, and the chip
  on screen wider than a bare one; a real wheel notch over the cell moving
  focus there and back; `workspaces peek 2` and a real pointer parked on
  that chip both opening its preview with both windows captured live (the
  hover open without taking the keyboard, and staying open while the
  pointer keeps moving over the chip), and the pointer leaving closing it;
  the card and the chip row cropped for reading; a floated window of
  workspace 2 moved mostly past the output's right edge, the miniature
  opening on the output's own region over a wider strip with that window's
  thumbnail at its full size beyond the viewport, a real wheel notch over
  the peeked card scrolling the strip along x and back, and a horizontal
  axis event (a trackpad's sideways swipe) doing the same on the
  hover-opened card without closing it; and herdr badges read off
  shimmed clients
  (`herdr --remote fakehost` answered by an `ssh` shim, a local `herdr`
  answering `working`), agreeing in `debug dump`, `workspaces status` and
  the frame, where the blocked `!` is red and gone once herdr says idle.
- `spectrum.sh` `--spectrum`: the media panel's own spectrum band, a cava
  child owned by `panelWants` alone with no `visualizer` cell anywhere in
  bar.layout, pgrep proving it appears on open and dies on close.
- `speedtest.sh` `--speedtest`: `network speedtest` settling both phases in
  the network panel.
- `switcher.sh` `--switcher`: the Alt+Tab switcher under whatever theme the
  run rides (it pins none), three
  windows of the fixture's own app id on the focused workspace and a fourth
  on workspace 2 that must not be offered (the leg pins
  `switcher.currentWorkspace`, off by default), `switcher next` twice and `prev`
  once over IPC against `switcher state`, the frame read for the fixture icon
  in three captions and for the selection fill travelling from the third
  cell to the second (cell positions off `switcher state`'s `cells`), all
  three thumbnails holding a captured frame while open (one frame each,
  the selected one refreshed five times a second, never `live`) and none
  holding any capture source after the commit, then a commit landing focus on the window
  the card named (`hyprctl activewindow`).
- `switcher_keys.sh` `--switcher-keys`: the same card driven by the
  compositor's own binds and real keys instead of IPC, one `wtype` process
  holding Alt across two taps of Tab and letting go, with the same fourth
  window on workspace 2 held out of the card. Reads the card open on
  the third entry mid-hold, closed with focus moved on the release, and two
  probe binds on the same key beside the shipped one: a plain `bindr` that
  must not fire (Hyprland shadows a held key's release bind once another
  bind consumes a press) and a no-mods `bindrt` that must not fire either
  (the modifier is still held as far as the bind table is concerned). A bare
  Alt tap first, which has to leave the plain probe's marker. Three fast
  taps close it out, each one wtype process with no sleep between the Tab
  and the Alt release, asserting the active window alternates every time
  rather than a commit racing ahead of the next that opened the card, and
  none of them mapping the card (`switcher state`'s `shows` and a polled
  layer list): it shows only 150ms into a hold. Then nine windows and one
  hold: Tab held on a slowed repeat stepping the cursor several entries
  (the Tab binds carry `repeating`), Shift+Tab with Alt still down stepping
  back one and the release landing there, and all nine thumbnails captured.
  Last the scrolling layout, where Hyprland copies no window whose box
  misses its monitor: the cells with no frame are exactly the windows off
  the monitor, drawn with their icon.
- `switcher_off.sh` `--switcher-off`: the same target with
  `switcher.enabled: false` in the settings fixture: all five verbs answering
  the error string and no switcher surface mapped at all.
- `systemupdate.sh` `--systemupdate`: the flake-inputs-behind cell and panel
  reading this repo's own flake through one shared poll.
- `theme_auto.sh` `--theme-auto`: `theme.mode: "auto"` resolving off the
  fixture's own coordinates rather than the 20:00 to 06:00 fallback, the
  sunrise/sunset pair read back out of `theme status` and checked against
  the wall clock it was sampled at, and one toggle snoozing the schedule for
  a cycle: the override reported, carried in state.json, and expiring on a
  boundary.
- `theme_toggle.sh` `--theme-toggle`: `theme mode toggle` both ways, and with
  `--wallpaper` that a toggle re-runs matugen instead of resetting to the
  fallback palette.
- `toggles.sh` `--toggles`: the toggle hub's rows repainting from a `@state:`
  snapshot without the surface moving under them.
- `tooltip.sh` `--tooltip`: rides `--panel <name>`; the tooltip surface
  absent before the pointer parks on a header button and present after.
- `tooltip_travel.sh` `--tooltip-travel`: rides `--panel <name>`; the card
  parked on the header's close button, then the pointer one button left and
  a frame 250ms later showing one card, on the rescan button, with one
  tooltip layer in both dumps: the group's grace window, not a second delay.
- `tray.sh` `--tray`: six real StatusNotifierItem producers on a strip pinned
  to carry them (`tray.maxVisible: -1`), the D-Bus Activate round trip, and
  the shell-owned menu.
- `tray_overflow.sh` `--tray-overflow`: the shipped default, the whole tray
  in its second bar behind the strip's dots toggle with no settings at all,
  read off `tray status`.
- `visualizer.sh` `--visualizer`: the `cava` child owned and killed with
  playback, proven by pgrep rather than by the frame.
- `visualizer_styles.sh` `--visualizer-styles`: pink noise through a real
  MPRIS player so every band actually differs, the media panel's spectrum
  box found by pixel diff rather than a hardcoded rect, every id `visualizer
  styles` reports set over IPC in turn and cropped to `visualizer-style-
  <id>.png`, no crop empty and no two consecutive ones byte-identical. Then
  the player volume forced to 100 and `visualizer status`'s levels read back
  once cava has settled, none of them pegged above 0.9, with both stereo
  channels present and not silent.
- `wallpaper.sh` `--wallpaper`: the matugen recolour on a set wallpaper, the
  crossfade to a second one, and both sides of the opt-in dither key.
- `wifi.sh` `--wifi`: the network panel against two real hostapd radios:
  scan, wrong password, connect, forget, and the enterprise round trip.
- `wheel.sh` `--wheel`: a virtual-pointer scroll moves the picker grid
  (`menu status` `scrollTop`) without moving the cursor, and a wheel over the
  bar's audio cell still steps the volume.
- `workspaces.sh` `--workspaces`: the bar's workspace indicator as one pill
  that travels, read off the bar region alone before, 80ms into, and after a
  workspace switch.

## macOS verification loop (mac e2e rig)

Both Linux hosts (g815, e1504g) are reachable again over ssh, and both were
rebuilt onto HEAD on 2026-08-12 (`nix flake update formalshell` in
`~/.config/nix`, then `sudo nixos-rebuild switch --flake .#<host>`; both have
passwordless sudo, and their `formalshell.service` user unit restarts onto the
new store path as part of the home-manager activation — their nix config
consumes this repo as `github:FormalSnake/FormalShell`, so a change has to be
pushed before a rebuild can pick it up). That makes them the place to confirm
what the VM's llvmpipe/no-desktop-bus environment cannot show — real GPU
rendering, a real session bus owner, real hardware devices — but it does NOT
make them a test target: the host-session-safety and lock-screen rules below
still forbid running the shell, the ThemeEngine or any compositor action
against a live session there. Rebuild them and look; anything that drives a
surface goes through the nested rig.

Sessions themselves run from a macbook, which has no Wayland at all, so that
rig is where verification happens. nix-darwin's `nix.linux-builder.enable` is
unavailable under `determinateNix.enable = true`, so it is hand-rolled as two
layers, both driven from this repo
(`docs/superpowers/plans/2026-07-28-mac-e2e-rig.md` has the full design
rationale):

- **Build layer** — `dev/linux-builder.sh {start|stop|status|register}` boots
  the stock `darwin.linux-builder` VM in the background and registers it in
  `/etc/nix/machines`, giving `nix build .#packages.aarch64-linux.<x>` a real
  remote builder from the mac. Its only job is compiling aarch64-linux
  closures (`formalshell`, quickshell, the testvm image itself); it does not
  run any part of the shell.
- **Runtime layer** — `nixosConfigurations.testvm` (`nix/testvm.nix`,
  `packages.aarch64-darwin.testvm`) is a headless aarch64 NixOS VM booted
  under HVF, pre-staged with `formalshell`/quickshell/hyprland/sway/matugen
  so in-VM builds are near no-ops. Inside it, a systemd **user** service runs
  a headless wlroots parent compositor (sway, `WLR_BACKENDS=headless`,
  `WLR_RENDERER=pixman`) publishing `WAYLAND_DISPLAY` into the systemd user
  environment, the same lookup `dev/smoke.sh` already falls back to on a real
  host. The script then runs **completely unchanged** inside, except that its
  own session-mode pick lands on `vkms` rather than nesting: that pixman
  parent advertises no `zwp_linux_dmabuf_v1` and hands out no render node, so
  Hyprland renders on the software KMS card the kernel's vkms module draws
  (software rendering throughout, Mesa llvmpipe for Hyprland's EGL and pixman
  for the parent, the same concession any CI-grade wlroots testing makes).

`dev/vm.sh` is the driver: `start` (build+boot headless, wait for ssh),
`stop`, `status`, `sync` (rsync the **working tree** — not a commit — into
`~/formalshell` inside the VM), `run <cmd…>` (ssh with cwd at the repo and
the session env exported), `smoke [flags…]` (sync, run `dev/smoke.sh`,
then `scp` the `SMOKE_OK` screenshot plus any dump/status/query JSON
back to `./artifacts/` on the mac; `--screensaver-gif` additionally rsyncs
the VM's `docs/media/screensaver-*.gif` straight into the real repo's
`docs/media/` on the mac, since those are committed output, not scratch
artifacts — otherwise the next `sync`'s `rsync --delete` would just wipe the
VM's copies before anyone could commit them), `shell` (interactive ssh). `justfile`
wraps this as `vm-up`/`vm-down`/`vm-build`/`vm-test`/`vm-lint`/`vm-smoke
*FLAGS`/`vm-greeter` — the mac-side equivalents of
`build`/`test`/`lint`/`smoke`/`dev/smoke-greeter.sh` above (`vm-greeter`
syncs, runs `dev/smoke-greeter.sh` inside, then pulls `artifacts/greeter/`
back with `dev/vm.sh pull` — greetd's `default_session` is a standing system
service already up in the VM, not a fresh nested compositor `vm-smoke`
spins up itself, so it needs no flag of its own).
Screenshots and JSON always land on the **mac** filesystem under
`./artifacts/` (gitignored) — Read-verify them there exactly as you would
`result/`'s output on a Linux host.

The VM has no real desktop bus owner (nothing on the mac plays the role DMS
plays on the Linux hosts), so `busctl --user status
org.freedesktop.Notifications` legitimately answers ENXIO/no-owner every
run; the smoke rig's D-Bus isolation check tolerates that (`|| true` —
a real "no owner" answer, not a connectivity failure) without changing
behavior on hosts where a real owner exists.

## Hard rules

- **Host-session safety**: the owner's live session is NOT a test target.
  Never run the shell, the ThemeEngine, or any compositor action in an
  environment carrying the host's `HYPRLAND_INSTANCE_SIGNATURE`. All runtime
  testing happens inside nested sessions via `dev/smoke-*.sh` (which scrub and
  restore the env). If you must run `qs` ad hoc, unset that variable first or
  export the nested session's own explicitly. Observed failure mode: host
  compositor config reloads firing during isolated testing (2026-07-27).
- **Lock-screen safety**: never run a lock surface (`Lock.qml`'s
  `WlSessionLock`) against anything but a nested test session. All lock
  testing happens inside the nested Hyprland session `dev/smoke.sh` boots and
  tears down; a lock bug there is harmless (the whole nested
  compositor gets killed regardless), but the same bug against a real host
  session would leave it genuinely locked. This is the same nested-only
  contract the general host-session-safety rule above already establishes,
  called out separately here because a stuck lock is a much worse failure
  mode than a stuck bar.
- **D-Bus isolation**: the shell's `NotificationService` acquires
  `org.freedesktop.Notifications` on the session bus via
  `Quickshell.Services.Notifications.NotificationServer`. The owner's live
  session bus is owned by DMS on the Linux hosts — NEVER run the shell's
  notification stack against the host bus, acquiring that name would steal it
  out from under the real desktop. `dev/smoke.sh` wraps the whole nested
  compositor invocation in `dbus-run-session --`, giving every nested run (and
  `notify-send` fired inside it) a private bus; it asserts `busctl --user status
  org.freedesktop.Notifications`'s owner PID on the **host** bus is unchanged
  before and after every run (`|| true`-tolerant of a legitimate "no owner"
  answer, e.g. on the mac VM rig, which has no desktop bus owner at all).
- **Design language**: every UI surface follows `docs/DESIGN.md`: shadcn/ui
  chrome (`card` fill, 1px `border`, `radiusMd` controls and `radiusXl`
  cards, one `ring` for focus, `accent` hover, `primary` for the wallpaper
  colour) on Omarchy quattro's surface set and habits. Read it before
  building or restyling any surface. mek.gallery and the ledger grammar are
  gone (2026-08-25).
- **`panel` IPC target is a spec addendum, not a conflict.** The design
  spec's §IPC target list (`docs/superpowers/specs/2026-07-27-formalshell-design.md`)
  predates per-widget popouts and doesn't name `panel`. The M6 plan added it
  (`panel.open(name)`, `close()`, `toggle(name)`, `state()`) because
  per-widget popouts otherwise have no summon path for compositor keybinds
  and no way to be verified headlessly in the smoke rig — treat it as part
  of the IPC contract going forward, alongside `menu`/`osd`/`notifications`/
  `clipboard`/etc. Unknown panel names return an error string, never a
  silent no-op.
- **Honest unavailable states, never faked data**, as a standing expectation
  for every VM smoke run: a panel/widget with nothing to show from its
  backend renders a single dim cell (`NO ADAPTER`, `NO DEVICES`,
  `NO LOCATION`, an absent battery bar cell, …) rather than a stubbed value
  or an invented device. Enabling a real service in `nix/testvm.nix` so a
  panel has a genuine backend to talk to is the sanctioned way to make a
  screenshot show more — inventing fake `/sys` entries or synthetic devices
  is not. The one exception (owner, 2026-09-28): with the iPhone as the
  active media source, whose audio never reaches this machine, the
  visualizer draws a frame off the track's Deezer bpm
  (`Visualizer/model.js` `beatFrame`, 120 when Deezer has none) instead of
  cava.
- Pure QML/JS. No compiled companion binary. No Node/npm/bun anywhere.
  Third-party CLIs the shell shells out to (matugen, grim, cava, ttfx, …)
  are runtime dependencies wired onto the wrapper's PATH in
  `nix/package.nix`, not companion binaries: nothing here is built from
  source we maintain, and every one of them has an honest fallback or
  unavailable state when it isn't installed.
- **Everything ships in the flake** (owner, 2026-09-28): FormalShell is
  meant to install on any Hyprland system with first-party Nix support.
  Every CLI the shell uses is packaged here (nixpkgs or `nix/*.nix`) and on
  the wrapper's PATH, and every system piece it needs (a daemon, a D-Bus
  policy, a firewall port, avahi) is a `services.formalshell.*` option in
  `nix/nixos-module.nix`. Never tell a user to install something by hand.
  The native Arch and Debian/Ubuntu packages under `packaging/` carry the
  same guarantee through their own dependencies and split packages. A new
  runtime CLI goes into `nix/package.nix`, the PKGBUILD and
  `packaging/debian/control` together.
- **ttfx is a spec addendum, not a conflict.** Spec §10 says the
  screensaver renders "TTE-style rain/decrypt/matrix drawn in QML with the
  shell's mono font and palette — no spawned terminal windows". The
  screensaver now runs `ttfx` (`nix/ttfx-package.nix`) as a frame source and
  parses its ANSI stream, still drawing every glyph itself on its own
  Canvas in the shell's own mono font, with no terminal window anywhere —
  what moved out of QML is the frame math, and with it the palette, since
  each ttfx effect carries its own gradient (owner's call: match omarchy
  exactly, 2026-08-11). `shell/Screensaver/effect.js` stays as the engine
  for an install with no ttfx on PATH, so the pure-QML/JS guarantee above
  still holds with nothing installed alongside the shell. `screensaver
  frameInfo` reports which engine is live.
- Compositor window/workspace ids are **opaque strings** end to end. Never
  parse, compare numerically, or assume stability. Hyprland's window ids are
  hex addresses and reach its dispatchers verbatim, as an `address:0x…`
  selector built at the backend's own wire boundary and nowhere else.
- The shell only ever **reads** `~/.config/formalshell/settings.json`; it
  never writes it. Runtime-mutable state goes to
  `$XDG_STATE_HOME/formalshell/state.json`.
- Chrome defaults (2026-08-25): every number below is the `metamorphosis`
  table (`shell/Theme/themes/metamorphosis.js`), read through `Theme.box()`;
  see `docs/DESIGN.md` §1 "Themes" for the schema. Radius `Theme.radius` (10, `theme.radius`
  in settings.json), 1px `border`, no shadow, no gradient, no blur drawn by
  the shell (Hyprland blurs behind the translucent bar/panel/launcher cards
  via layerrules; `theme.surfaceOpacity`, default 0.85), dither only behind
  `wallpaper.dither`/`lock.dither` (both default false), fonts = the
  fontconfig `sans-serif` alias for words and `monospace` for values (Geist
  Sans/Mono by intent, never a hardcoded family), icons by name
  through `Components/Icon.qml` with the set picked by `theme.icons`
  (`lucide` default, `nerd`; no raw glyphs in surface files, no SVG icon
  assets). Nothing in the shell blurs or shadows
  anything: a modal surface sits over a plain 0.5 black scrim that only
  darkens the desktop (the modal namespaces take `ignore_alpha = 0.6`, so
  the scrim falls under the compositor's blur and the card over it stays
  above), every other surface sits over the desktop with its border doing
  the work. The lyrics pane is the one exception (owner, 2026-09-17, M56
  spec P12): depth of field on every line but the lit ones, behind
  `media.lyricsBlur`, and a glow on the chunk being sung. Motion is
  `docs/DESIGN.md` §1 "Motion": the two clock families
  behind `Anim`/`CAnim`, and the joined shape a card hanging off the bar
  draws instead of a `Card`. Never
  reintroduce a `ScreencopyView`-based capture anywhere (see
  `LockSurface.qml`'s header comment: it crashes the whole shell outright,
  a fail-open on a security-critical surface). Two exceptions (owner,
  2026-09-28 and 2026-09-29): the Spaces preview's per-window thumbnails
  (`Surfaces/Panels/WorkspacePreview.qml`) and the Alt+Tab switcher's
  (`Surfaces/Switcher/Switcher.qml`), both the one shared
  `Components/WindowThumb.qml`, a `ScreencopyView` on each window's toplevel
  handle, live only while that card is open and holding no capture source
  once it has closed. The lock surface and everything else stay banned.
- License MIT. Every file substantially ported from DankMaterialShell keeps
  a `// Portions from DankMaterialShell (MIT, Copyright 2025 Avenge Media LLC)`
  header line.
- ⚠️ Until M45 finishes the sweep, some files still carry raw Nerd Font
  glyphs (multi-byte codepoints that whole-file rewrites corrupt). Use
  targeted `Edit` operations on those files; new icon uses go through
  `Icon { name: ... }` and `shell/Theme/icons.js`, never a raw codepoint.
- Hyprland is the only supported compositor (owner, 2026-08-25). New
  compositor work goes in `shell/Compositor/hyprland/` only;
  `shell/Compositor/BackendBase.qml` stays as the contract every surface is
  written against, so a second backend would be a new file rather than a
  sweep.
- Lua (`hyprland.lua`) is the only Hyprland config format (owner,
  2026-09-29). Runtime changes go through `hyprctl eval` with the `hl.*` API,
  never `hyprctl keyword`, and nothing the shell or the nix module writes is
  hyprlang. The smoke rig boots from a Lua config too.
- ⚠️ Quickshell percentage/fraction-shaped properties are 0..1, not 0..100
  (`UPowerDevice.percentage`, `WifiNetwork.signalStrength` — both confirmed
  from C++ source: `src/network/wifi.hpp:22`, `src/network/nm/network.cpp:260`).
  This has already caused two shipped bugs. Verify any such property against
  its C++ source before rendering it.
- Commits: conventional style, lowercase imperative subject
  (`feat(compositor): …`), no Co-Authored-By lines, no commit descriptions.
- Every task ends with its verification commands actually run and their
  output read. No claiming green without evidence.

## Reference repos

- `github.com/basecamp/omarchy` (branch `quattro`) — architecture/UX
  reference (single-process shell, unified surfaces, IPC contract patterns).
  Read, don't copy — treat as read-reference only; check its license before
  ever porting code from it.
- `github.com/AvengeMedia/DankMaterialShell` (MIT): Hyprland backend
  prior art and matugen orchestration patterns. MIT, so code can be ported
  directly, but every substantially-ported file needs the attribution
  header above.
- QuickShell source/docs (`git.outfoxxed.me/quickshell/quickshell`, pinned
  flake input) — ground truth for toolkit APIs (`Quickshell.Io.Socket`,
  `IpcHandler`, `Quickshell.Hyprland`, `Singleton`, …). When a QML/JS API's
  behavior is uncertain, read the C++ source or run the built `qs` binary
  rather than guessing.
