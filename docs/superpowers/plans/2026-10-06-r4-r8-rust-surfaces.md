# R4 to R8: the remaining surfaces

Goal: every surface the QML shell has, in Rust, each milestone ending with
its legs passing under `FS_IMPL=rust` and still passing for QML. One plan
for five milestones, because their tasks are independent once R3's panel
host and widget set are in main, and they run as parallel worktrees.

Facts this plan rests on (checked 2026-10-06):

- R2 (the bar) and R3 Task 1 (`ui/` widgets, `surfaces/panel/` host,
  tooltips, gallery) are merged or merging. A surface is built from `ui::w`
  widgets; a panel implements `surfaces::panel::Panel`.
- Pure logic lives in `fs-menu`, `fs-media`, `fs-info`, `fs-chrome`,
  `fs-system`, `fs-devices`, `fs-screensaver`, `fs-theme`; services in
  `fs-notifd`, `fs-mpris`, `fs-tray`, `fs-bluez`, `fs-auth`, `fs-audio`,
  `fs-upower`, `fs-network`.
- The QML surfaces are `shell/Surfaces/{Menu, Notifications, Osd, Lock,
  Polkit, Screensaver, Capture, Switcher, Background, Frame, HotCorners,
  Caffeinate}` and `shell/Surfaces/Panels/{MediaPanel, LyricsPane,
  VisualizerCanvas, AnimatedAlbumArt, WorkspacePreview}`.

## R4: launcher

- R4a, core: the menu surface (drawer emerge off the bar's line, scrim,
  rows, sections, footer, split preview, the cursor model with
  `viewCursor`), the index kept warm per source on the service thread
  (fs-menu providers, each recomputed alone), fuzzy ranking, frecency,
  desktop entry scan on the blocking pool, app grid, every route's
  activation, `menu` IPC. The spec's budget is binding here: Super+Space to
  first launcher frame under 50 ms in power saver, the bar animating
  throughout. Legs: `--menu`, `--menu-emerge`, `--app-grid`,
  `--grid-relaunch`, `--wheel`, `--keybinds`, `--device-routes`.
- R4b, routes with their own views: emoji grid (`--emoji`), clipboard
  history with image rows and clipssh (`--clipboard`, `--clipssh`,
  `--clipssh-image`), share and LocalSend (`--share`, `--localsend`),
  wallpaper picker with the thumbnail cache and the wallpaper crossfade
  and dither (`--picker`, `--wallpaper`), the camera mirror with the IR
  filter (`--mirror`), the monitor view (`--monitor` launcher half),
  nix search, radio search, calc.

## R5: notifications and OSD

- R5a: `fs-notifd` wired as the server (identity "formalshell" unless
  the QML advertises otherwise; match it), the toast stack, the centre with
  its pending tier, DND, focus rules, the iPhone mirror filter and dedupe,
  reminders. Port `Notifications/{icon,geometry,stack}.js` and the 4
  iPhone cases that needed the notification model. Legs: `--notify`,
  `--notify-close`, `--notify-emerge`, `--center`, `--reminder`,
  `--iphone`.
- R5b: the OSD pill (`--osd`), night light (`--nightlight`), overnight
  panel rows, lights (`--lights`), the headset connect card from the spec.

## R6: lock, auth, session

- The lock surface on ext-session-lock (nested sessions only, CLAUDE.md's
  lock-screen safety rule), PAM through `fs-auth` calling `pam-sys2`
  directly so the whole response buffer is zeroized, the avatar, now
  playing on the lock, ink flip, the sleep delay inhibitor, hot corner
  relock with the parked-cursor rule from `fs-chrome`, the polkit agent UI,
  the greeter, the single-instance lock. Legs: `--lock`, `--lock-media`,
  `--sleep`, `--hotcorner`, `--hotcorner-relock`, `--polkit`,
  `--instance`, and `just vm-greeter`.

## R7: media, lyrics, devices

- The media panel (sources menu, progress, marquee, controls, players
  switcher, cover art loaded and decoded off the UI thread, the animated
  album art), the lyrics pane (sync, wipe, blur and glow, latency), the
  visualizer styles in the panel, radio favourites, AirPlay and iPhone
  panels, earbuds panel, and the headset connect card if R5b did not take
  it. Legs: `--media`, `--media-progress`, `--lyrics`, `--lyrics-blur`,
  `--spectrum`, `--visualizer-styles`, `--radio`, `--airplay`,
  `--panel-morph`.

## R8: capture, switcher, the rest

- Capture: region picker, screenshot, record to GIF through wf-recorder,
  OCR and colour, edit (`--capture`, `--capture-edit`, `--screenshot`,
  `--record`, `--ocr`).
- Window thumbnails on ext-image-copy-capture, live only while their card
  is open: the Alt+Tab switcher (`--switcher`, `--switcher-keys`,
  `--switcher-off`) and the Spaces peek preview (`--spaces` preview half).
- Screensaver with ttfx and the built-in engine (`--screensaver`,
  `--screensaver-gif`), the quake console (`--console`), the frame,
  hot corner surfaces, GPU offload (`--gpu`), HDR (`--hdr`), display
  (`--display`), theme legs not yet run, `--showcase`, `--native`.

## Done

Every leg in `dev/smoke.d/` passes under `FS_IMPL=rust`, then R9 (spec)
cuts over.
