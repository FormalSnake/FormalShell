# Architecture

## Process model

FormalShell is a single QuickShell process, launched as:

```
qs -p <store-path>/share/formalshell
```

(the nix package wraps this as the `formalshell` binary, `nix/package.nix`;
the home-manager module runs it as a `systemd --user` service bound to
`graphical-session.target`, `nix/hm-module.nix`). There is no compiled
companion binary and nothing runs under Node/npm/bun: all logic is QML/JS.

The third-party CLIs the shell shells out to are not companion binaries, they
are runtime dependencies wired onto that wrapper's PATH in `nix/package.nix`:
`brightnessctl`, `wl-clipboard`, `curl`, `grim`, `slurp`, `matugen`,
`qrencode`, `cava`, `ddcutil`, `ttfx`, `wf-recorder`, `tesseract`,
`ffmpeg-headless`, `git` and `formalshell-eds` are prefixed, `wtype` and
`tensaku` suffixed so an environment copy can shadow them. Anything missing
from that list only resolves when the host happens to install it separately,
which has already gone wrong once: `matugen`, `qrencode`, `cava` and
`ddcutil` were absent until 2026-08-11 and worked only because
`nix/testvm.nix` lists them in `environment.systemPackages`, so
theming, the Wi-Fi QR share, the visualizer and external-monitor brightness
were all broken in a plain home-manager install while every smoke run passed.
Daemon-paired CLIs (`nmcli`, `bluetoothctl`) stay off the list on purpose:
they have to match the NetworkManager and bluez the system is running, and
their callers already guard with `command -v`.

A second, separate entry point (`greeter/greeter.qml`, wrapped as the
`formalshell-greeter` binary, `nix/greeter-package.nix`) runs before any
user session exists, launched by greetd as its `default_session` instead of
by a user's systemd. `nix/greeter-package.nix` copies `shell/` verbatim and
layers `greeter.qml` on top of it, so `import qs.Core`/`qs.Components`
resolve to the one real `Core`/`Components` tree, never a second copy, but
it is a genuinely different process: `Quickshell.Services.Greetd` instead of
compositor sockets or `Quickshell.Services.Pam`, no `WlSessionLock` (greetd
already isolates the greeter into its own disposable compositor with no
other client ever attached, so there's nothing for a lock primitive to
exclude), and no `Core.State` reference at all (the `greeter` system
account's `$HOME` has no real `state.json` to read, and must not get one
written to it, see the file's own header comment).

`shell/shell.qml` is the entry point (`//@ pragma ShellId formalshell`). It
instantiates a `Variants` over `Quickshell.screens`, spawning one `Bar`, one
`Background`, and one `Toasts` popup stack per connected output; a single
non-per-screen `Menu`, `Center` (notification history), `Osd`, and one
instance each of the seven `Panels/*.qml` popouts including `MediaPanel`
(they open/show on the focused screen at summon/trigger time rather than
living on every output); one `Lock` (its `WlSessionLock` manages its own
per-output surfaces internally, no `Variants` loop needed here) and one
`Screensaver` (which *does* need its own `Variants` over
`Quickshell.screens`, since a plain overlay layer has no such auto-multi-
output primitive); one `RegionPicker`; a `Variants` over
`PluginService.surfacePlugins` spawning one host per `panel`/`overlay`
plugin; and the `Ipc` handlers (debug/theme/wallpaper/menu/notifications/
osd/panel/calendar/clipboard/network/bluetooth/media/tray/lock/screensaver/
picker/screenshot/capture/record/reminder/nightlight/gallery/plugins).

## Tree layout

```
shell/
  shell.qml                  ShellRoot; Variants over Quickshell.screens -> Bar/Background per screen
  Core/
    State.qml                 singleton: state.json (wallpaper, mode), FileView+JsonAdapter
    Theme.qml                 singleton: Theme.color live off theme.json, shadcn zinc fallback statics
    Config.qml                 singleton: read-only watched settings.json (menu.customPowerButtons, …)
    qmldir
  Theme/
    matugen.js                 pure JS, .pragma library: merged matugen TOML config builder
    palette.js                 pure JS, .pragma library: theme.json validate() + shadcn zinc fallback()
    ThemeEngine.qml             singleton: serialized matugen Process queue
    templates/
      theme.json.tmpl           matugen template rendering theme.json
      hyprland-colors.conf.tmpl matugen template rendering the hyprlang colour variables
    qmldir
  Compositor/
    BackendBase.qml           the CompositorBackend contract (base component)
    CompositorService.qml     singleton facade over the one backend, forwards everything
    appmatch.js               pure JS, .pragma library: matchWindows()/nextWindow()/decorateAppRows():
                               which running windows belong to a DesktopEntry (startupClass then id,
                               first tier wins, no fuzzy tier), backing the menu's launch-or-focus
    keybinds.js                pure JS, .pragma library: parseHyprlandBinds() (the `hyprctl binds`
                               text table, never `-j`) + search()/rows(); inert "note" rows only
    keyboard.js                pure JS, .pragma library: parseHyprlandLayouts() normalized to one
                               {available, names, currentIdx, current} shape
    focus.js                   pure JS, .pragma library: holds the last focused window across the
                               gap a shell layer surface taking keyboard focus opens
    qmldir
    hyprland/
      model.js                  pure JS: Hyprland workspaces onto the contract, dropping the
                                 negative-id special:* overlays the quake console parks on
      HyprlandBackend.qml       Quickshell.Hyprland wrapper, usingLua dual dispatch
  Components/
    Cell.qml                    the shared cell: card fill, 1px border, radiusMd, with the
                                 active/selected/destructive/warning/cursor states and
                                 default-property content
    Panel.qml                    the shared per-widget popout: an omarchy-style card (full border,
                                  opaque fill, Theme.space.barMargin below the bar) anchored under its
                                  opening bar cell, on that cell's own output (anchorX/anchorScreen, both
                                  unset for an IPC open: bar's right region on the focused output),
                                  WlrLayershell top layer, keyboard OnDemand, closes on Escape/click-outside
    AuthPrompt.qml                the lock/greeter shared centre plate: one bordered card
                                  holding clock + date + a dividing rule + a single 3px-outlined
                                  password/username field (shrink-to-fit dot masking, CHECKING state,
                                  fingerprint glyph); LockSurface.qml and greeter/greeter.qml both
                                  instantiate it unchanged
    DitherImage.qml               content imagery's Canvas pass (DESIGN.md §2 item 12): duotone role-color
                                  1-bit, or "retro": an image-derived palette on a chunk grid
    dither.js                    pure JS, .pragma library: palette() (median cut, up to paletteSize
                                  colors from the image itself), quantize() (nearest entry, ordered-
                                  dithered against the second nearest only), BAYER/hex/hexPalette
    tooltip.js                   pure JS, .pragma library: placement(): where Tooltip.qml's card sits
                                  relative to the item that owns it, below by default, flipped above
                                  with no room, clamped inside the output on both axes
    qmldir
  Menu/
    model.js                     pure JS, .pragma library: parseJsonc()/buildTree()/visibleChildren()
    search.js                    pure JS, .pragma library: tiered fuzzy score()/rank()
    providers.js                 pure JS, .pragma library: appsProvider()/applyProviders()/customPowerButtonEntries()/clipboardProvider()/imageRows()/wallpaperVariants()/wallpaperListing()/captureEntries()
    actions.js                   pure JS, .pragma library: actionBar(): the bottom action bar's primary verb + key hints
    toggles.js                   pure JS, .pragma library: the "@state:" checked-condition allow-list
                                  (nightlight.active/screensaver.stayAwake/notifications.dnd/theme.dark),
                                  snapshot()/resolveState()/checkedFor(): live in-process state beats a
                                  cached Process result, an unlisted path answers false
    default-menu.jsonc           shipped default tree (apps, system/power, toggles, reminder, clipboard)
  Clipboard/
    history.js                   pure JS, .pragma library: add()/remove()/clear()/sanitize(), 300-entry cap, dedup-to-front
  Calendar/
    progress.js                  pure JS, .pragma library: yearFraction()/lifeFraction()/resolveOverride()
    ics.js                       pure JS, .pragma library: RFC 5545 VEVENT reader (unfold, DTSTART parse, no RRULE expansion)
  Weather/
    openmeteo.js                 pure JS, .pragma library: buildUrl()/parseResponse() with typed failure shapes
  Media/
    applemusic.js                 pure JS, .pragma library: URL construction, response parsing, cache-key/prune-decision logic
    model.js                      pure JS, .pragma library: active-player pick, player labels, loop names and cycle order, volume/seek clamps
  Capture/
    model.js                      pure JS, .pragma library: the capture family's shared logic:
                                   outputPath()/gifOutputPath()/parseGeometry()/hexFromPpmBytes()/
                                   parseAudioSetup()/recorderArgv()/gifArgv()/elapsedLabel()/ocrOutcome().
                                   argv builders return arrays that go straight onto Process.command,
                                   so a path carrying a quote can never splice a shell
  Reminders/
    model.js                      pure JS, .pragma library: parseDuration()/parseSpec()/makeEntry()/
                                   add()/normalize()/due()/barLabel()/countdownLabel(); the clock is
                                   always a nowMs parameter, never Date.now()
    ReminderService.qml           singleton: wiring only: mirrors Core.State.reminders one-directionally,
                                   1s tick while any are pending, fires at urgency 2 (DND bypass)
    qmldir
  Plugins/
    manifest.js                   pure JS, .pragma library: scanCommand()/splitScan()/validateRecord()/
                                   resolve(): the eight-key manifest schema and its failure contract
                                   (whole plugin dropped vs one key back to its default)
    PluginService.qml             singleton: the only QML touching ~/.config/formalshell/plugins;
                                   one scan Process, the surface registry, service-plugin creation
    qmldir
  SystemUpdate/
    model.js                      pure JS, .pragma library: parseLock() (direct flake inputs only),
                                   per-input-type upstream probe argv, countBehind()/summaryLabel()
  Screensaver/
    effect.js                     pure JS, .pragma library: frameState(): five converging effects (decrypt/rain/expand/slide/scatter) over a loaded ASCII banner, stepped off a frame counter; the engine an install with no ttfx on PATH falls back to
    ttfx.js                       pure JS, .pragma library: the ttfx wire protocol. command()/args()
                                   build the argv the surface spawns, parseFrame() reads the ANSI stream
                                   back, isKnownEffect()/rerollEffectName() own the 37 effect names, and
                                   isTimedEffect() names the two (matrix/thunderstorm) that are wall-clock
                                   gated and so never frame-stepped
  Airpods/
    model.js                     pure JS, .pragma library: parseStatus() (complete default shape on every
                                  bad-input path), batteryRows()/modesFor()/earDetectionLabel()/lidLabel()/
                                  noiseModeLabel()/stateLine(): the omarchy-pods librepods daemon's own
                                  status.json wire shape, reimplemented independently (GPL, read-reference
                                  only)
  Dualsense/
    model.js                     pure JS, .pragma library: parseSupply()/parseLightbar()/parsePlayerLeds()/
                                  stateLine() over hid-playstation's own sysfs text shapes, warn/critical
                                  thresholds mirroring the retired dualsense-bar script
  Services/
    AirpodsService.qml          singleton: FileView on $XDG_STATE_HOME/librepods/status.json (bounded
                                 rewatch, Config.qml's own retry shape), available = file present + parsed
                                 ok; send(verb) opens a one-shot self-destroying Socket to
                                 $XDG_RUNTIME_DIR/librepods.sock against a local wire allow-list
    DualsenseService.qml        singleton: one sh -c glob probe (power_supply capacity/status, leds
                                 multi_intensity, five player-N brightness files) per call; present/battery/
                                 lightbar/playerLeds properties; a 30s Timer that only runs while
                                 acquire()/release() report a live consumer (widget mounted or panel open)
    AudioService.qml            singleton: Quickshell.Services.Pipewire default-sink volume/mute, changed() signal
    BrightnessService.qml       singleton: brightnessctl-backed backlight, no polling loop (refresh()/set()/step())
    ClipboardService.qml        singleton: wl-paste --watch capture, drives Clipboard/history.js, writes clipboard.json
    LocationService.qml         singleton: QtPositioning PositionSource (geoclue2), settings.json lat/lon override
    CalendarEventsService.qml   singleton: reads Calendar/ics.js over a khal/vdir-style directory (calendar.icsDir)
    MediaService.qml             singleton: Quickshell.Services.Mpris player pick and full control surface (transport, seek, shuffle, loop, player volume, raise), honest available:false
    AppleMusicArtService.qml     singleton: opt-in (media.appleMusicArt), curl-driven iTunes Search + amp-api editorialVideo, cached MP4s
    IdleService.qml               singleton: one shared IdleMonitor (respectInhibitors:true), screensaver.timeoutSeconds
    RecordingService.qml          singleton: one wf-recorder child (`active` IS that child, never persisted,
                                   never pgrep'd), the transient pactl mix modules desktopmic needs, and the
                                   two-pass ffmpeg GIF transcode
    qmldir
  Notifications/
    model.js                    pure JS, .pragma library: three-tier reducer (popups/pending/past), DND bypass rule
    NotificationService.qml     singleton: owns NotificationServer, drives model.js, live-Notification side map
    qmldir
  Ipc/
    DebugIpc.qml                IpcHandler target "debug", function dump(): string, query(q): string
    ThemeIpc.qml                IpcHandler target "theme", retheme()/mode()/status()
    WallpaperIpc.qml            IpcHandler target "wallpaper", set()/get()
    MenuIpc.qml                 IpcHandler target "menu", toggle()/summon()/close()/refresh()/ping()/select()/input()
    NotificationsIpc.qml        IpcHandler target "notifications", dndState()/toggleDnd()/setDnd()/showHistory()/clear()/clearPending()/markAllSeen()/dismissAll()/dismissOne()/invokeLast()/expand(on|off)
    OsdIpc.qml                  IpcHandler target "osd", volume()/brightness()/media()/close()/state()
    PanelIpc.qml                 IpcHandler target "panel", open(name)/close()/toggle(name)/state(): registry maps name -> Panel instance
    ClipboardIpc.qml             IpcHandler target "clipboard", list()/copy(id)/remove(id)/clear()
    MediaIpc.qml                  IpcHandler target "media", playPause()/next()/previous()/status()
    LockIpc.qml                   IpcHandler target "lock", lock()/isLocked()/status(): no unlock(), see its own header comment
    ScreensaverIpc.qml            IpcHandler target "screensaver", start()/stop()/status()
    PickerIpc.qml                 IpcHandler target "picker", summon()/select(dir,token)/choose(path)/variant(dark|light)/close()/status()
    TrayIpc.qml                   IpcHandler target "tray", status()/activate(id)/menu(id)/menucursor(delta)/menuactivate(): spec addendum, same rationale as "panel"
    BarIpc.qml                    IpcHandler target "bar", chevron(action)/chevronAt(action,region): the bar's
                                   collapse boundary. Two verbs, not one with an optional region, because
                                   quickshell dispatches IPC on exact arity; chevron() infers the region when
                                   exactly one exists and refuses to guess otherwise
    ScreenshotIpc.qml             IpcHandler target "screenshot", full()/region()/pick(mode,processing)/
                                   key(name)/pickerStatus()/edit(path)/cancel()/status(); pick() drives
                                   Surfaces/Capture/RegionPicker.qml, edit() hands a PNG to screenshot.editor
    CaptureIpc.qml                IpcHandler target "capture", text()/color()/textAt(geom)/colorAt(geom)/
                                   cancel()/status(): a Scope,
                                   not a bare IpcHandler: the slurp/grim/tesseract Processes need a default
                                   property to live in. One busy flag guards all four verbs
    RecordIpc.qml                 IpcHandler target "record", start(scope,audio)/stop()/toggle(scope,audio)/
                                   gif(path)/status(): thin, every rule lives in RecordingService
    ReminderIpc.qml               IpcHandler target "reminder", set(duration,message)/show()/clear()/status()
    PluginsIpc.qml                IpcHandler target "plugins", list()/status()/reload(): introspection and
                                   lifecycle only; summoning a plugin surface stays on "panel" under its
                                   own "plugin:<id>" name
  Bar/
    layout.js                     pure JS, .pragma library: resolve(bar): {left,center,right} from bar.layout/bar.modules, default-layout fallback, unknown-name/dangling-module warnings.
                                   Also annotates every entry with its region and a `collapsible` flag (true on the governed side of a "chevron" in the same region, governsBefore() picking that side per region), and drops a chevron that is duplicated or has nothing on that side. collapsedNames()/hasChevron() read that back
    commandOutput.js               pure JS, .pragma library: resolve(exitCode, stdout)/errorState() for CommandModule.qml's Waybar-JSON parsing
  Surfaces/
    Bar/
      Bar.qml                  PanelWindow; three-region Row (left/center/right) resolved from Layout.resolve(Config.get("bar")), height tracks the tallest cell present
      TrayMenu.qml               shell-owned tray context menu: one shared instance (shell.qml), composes Panel.qml, driven by QsMenuOpener over the clicked item's DBusMenuHandle: replaces the old native QsMenuAnchor popup
      widgets/
        LauncherWidget.qml      leads the default left region: the "[F]" mark, toggles shell.qml's single Menu instance: the launcher's only pointer-reachable summon path
        Workspaces.qml          Repeater over CompositorService.workspaces
        ActiveWindow.qml        focused window's appId + title
        Clock.qml                center region: live clock, opens the calendar panel
        AudioWidget.qml          volume icon + %, primary underline while its panel is open
        Battery.qml               battery icon + NN%, right click hides the percent, hidden entirely when isLaptopBattery is false (exposes `shown`)
        NetworkWidget.qml         connection-state icon, primary underline while its panel is open
        BluetoothWidget.qml       adapter-state icon, primary underline while its panel is open
        WeatherWidget.qml         condition icon + rounded temperature, primary underline while its panel is open
        NowPlaying.qml             note icon + elided title, primary underline while its panel is open, hidden entirely with no MPRIS player (exposes `shown`)
        Tray.qml                   SNI tray over Quickshell.Services.SystemTray, a plain strip (exposes `shown`)
        Indicators.qml              recording / reminder / stay-awake / night-light glyphs, hidden entirely when none holds (exposes `shown`)
        MicWidget.qml               opt-in: default-source mute glyph, honest NO MIC label with no capture device
        KeyboardLayoutWidget.qml    opt-in: 2s per-output poll of `hyprctl devices -j`
                                     through Compositor/keyboard.js (exposes `shown`)
        SystemUpdateWidget.qml      opt-in: flake-inputs-behind glyph + count, full-bleed warning while behind
        AirpodsWidget.qml            opt-in: earbuds glyph + worst-bud %, hidden with no daemon/no known level (exposes `shown`)
        DualsenseWidget.qml          opt-in: gamepad glyph + battery %, warning/urgent thresholds, hidden with no controller (exposes `shown`)
        CommandModule.qml           bar.modules "command" entry: polled Waybar-JSON cell, honest MODULE ERROR on failure
        QmlModule.qml                bar.modules "qml" entry: Loader-hosted user file, load-time isolation only
        ChevronWidget.qml            opt-in: the collapse boundary. Its bar.layout position is its whole config; click toggles State.barCollapsed[region]
        PluginBarModule.qml          kind:"bar" plugin host: Loader-hosted entry file, forwards its `shown`
    Background/
      Background.qml            per-screen PanelWindow on WlrLayer.Background; shows State.wallpaper,
                                 plain, or through DitherImage's retro pass when wallpaper.dither is on
    Menu/
      Menu.qml                  keyboard-exclusive top-layer window covering the focused output; jsonc -> tree -> cond batch -> rank/browse -> cells.
                                 Scrim: plain black at 0.5, fading with the card. A dithered freeze of the screen was
                                 tried first and could not be made to hold still under refresh: see the file's own comment
                                 Two views over one row set: a ListView, or a GridView on the "wallpaper" route (the picker),
                                 plus that route's DARK | LIGHT variant switcher when the directory has the subdirectory pair
      MenuRow.qml                Cell subtype: icon+label, confirm-gate swap, ▸/✓ trailing indicator
      MenuActionBar.qml          Cell subtype: the card's bottom row: primary verb behind an accent key cap, key hints right
    Panels/
      AudioPanel.qml             Pipewire output/input node sliders (PwObjectTracker), MUTE toggle cells
      CalendarPanel.qml          month grid + year/life-progress bar + TODAY events section
      NetworkPanel.qml           WIRED/WI-FI grouped connections, 5-segment mono signal bar, connect/disconnect
      BluetoothPanel.qml         adapter state + paired devices, or a dim "NO ADAPTER" cell
      PowerPanel.qml              AC/battery row + keyboard-navigable power-profile picker (Up/Down/Enter)
      WeatherPanel.qml            current-conditions header + FORECAST rows off LocationService + open-meteo
      MediaPanel.qml               album art + NOW PLAYING meta row + flat progress cell + transport cells
      AnimatedAlbumArt.qml         opt-in muted looping video, active only while open and MediaService.isPlaying
      SystemUpdatePanel.qml        flake.lock via FileView (free, no nix invocation) + one queued upstream
                                    probe per direct input; the poll lives here, the widget only enables it
      AirpodsPanel.qml              honest NO DAEMON/NO AIRPODS gates, PanelHero, per-bud BATTERY tracks,
                                     LISTENING MODE rows (device-filtered, selected state real), Pro-only
                                     CA/one-bud toggles, EAR DETECTION cycling row; replaces the old
                                     bluetooth-panel AIRPODS NOISE group
      DualsensePanel.qml            read-only sysfs readout: NO CONTROLLER gate, PanelHero with the battery
                                     percent as its readout, LIGHTBAR swatch+hex and PLAYER LEDS dot rows,
                                     a dim READ ONLY title-band tag since the owner's host units own writes
    Notifications/
      Toasts.qml                 per-screen PanelWindow, Overlay layer; sonner-style depth stack off NotificationService.popups, anchored per notifications.position (default bottom-right), hover/IPC expand into a full column
      Center.qml                  single-instance PanelWindow, Top layer; right-anchored full-height Card, PENDING/SEEN sections, DND Switch
      NotificationCard.qml        shared Card: app icon, app name + time, summary/body, action Buttons; critical = destructive border and icon, never a fill
    Osd/
      Osd.qml                     single-instance PanelWindow, Overlay layer, bottom-centre; Card pill of Icon | Track | percentage, no keyboard focus
      icon.js                     pure JS, .pragma library: which Icon name each kind draws (volume ramp, mute, brightness, media)
    Lock/
      Lock.qml                    WlSessionLock wrapper + both PamContexts (password, parallel fingerprint) + idle-blank/resume-guard state
      LockSurface.qml              per-output Component WlSessionLock instantiates itself; dithered-wallpaper backdrop, oversized clock, one input cell
    Screensaver/
      Screensaver.qml              one controller Item (IdleService x MediaService guard) + per-monitor Variants overlay; a Canvas drawing the banner off ttfx, or off effect.js with no ttfx on PATH
    Capture/
      RegionPicker.qml              full-screen Overlay region picker over grim-frozen output frames;
                                     window rectangles, plus a named list card for any window with no box
    Plugins/
      PluginPanel.qml               kind:"panel" plugin host (a real Panel), registers itself in
                                     PluginService.surfaces as "plugin:<id>"
      PluginOverlay.qml             kind:"overlay" plugin host: summoned centered card, joins
                                     PanelRegistry's mutual-exclusion set by hand
      qmldir
greeter/
  greeter.qml                  greetd entry point (Quickshell.Services.Greetd); no WlSessionLock,
                               no Core.State reference: see the file's own header comment
tests/
  tst_matugen_builder.qml      qmltestrunner tests for Theme/matugen.js
  tst_palette.qml              qmltestrunner tests for Theme/palette.js
  tst_menu_model.qml            qmltestrunner tests for Menu/model.js
  tst_menu_search.qml           qmltestrunner tests for Menu/search.js
  tst_notifications_model.qml   qmltestrunner tests for Notifications/model.js
  tst_clipboard_history.qml     qmltestrunner tests for Clipboard/history.js
  tst_calendar_progress.qml     qmltestrunner tests for Calendar/progress.js
  tst_calendar_ics.qml          qmltestrunner tests for Calendar/ics.js
  tst_openmeteo.qml             qmltestrunner tests for Weather/openmeteo.js
  tst_applemusic.qml            qmltestrunner tests for Media/applemusic.js
  tst_media_model.qml           qmltestrunner tests for Media/model.js
  tst_screensaver_effect.qml    qmltestrunner tests for Screensaver/effect.js
  tst_screensaver_ttfx.qml      qmltestrunner tests for Screensaver/ttfx.js
  tst_bar_layout.qml             qmltestrunner tests for Bar/layout.js
  tst_capture_model.qml          qmltestrunner tests for Capture/model.js
  tst_reminders_model.qml        qmltestrunner tests for Reminders/model.js
  tst_plugin_manifest.qml        qmltestrunner tests for Plugins/manifest.js
  tst_systemupdate_model.qml     qmltestrunner tests for SystemUpdate/model.js
  tst_airpods_model.qml          qmltestrunner tests for Airpods/model.js
  tst_dualsense_model.qml        qmltestrunner tests for Dualsense/model.js
  tst_menu_toggles.qml           qmltestrunner tests for Menu/toggles.js, incl. the allow-list drift guard
  tst_keybinds.qml               qmltestrunner tests for Compositor/keybinds.js
  tst_keyboard_layout.qml        qmltestrunner tests for Compositor/keyboard.js
  tst_app_match.qml              qmltestrunner tests for Compositor/appmatch.js
  tst_hyprland_workspaces.qml    qmltestrunner tests for Compositor/hyprland/model.js
  tst_osd_icon.qml               qmltestrunner tests for Surfaces/Osd/icon.js
  tst_tooltip_placement.qml      qmltestrunner tests for Components/tooltip.js
dev/
  smoke.sh                      the rig scaffold: isolated HOME, settings fixture, private bus, session
                                 mode (nested on a host, vkms in the VM), build, launch, SMOKE_OK frame,
                                 teardown. It sources every leg, so adding one never edits it
  smoke.d/<leg>.sh              one file per leg (45 of them): its flag, its fixture additions, its
                                 in-session timeline and its assertions, documented in its own header,
                                 which is the authoritative description of that leg
  smoke.d/README.md             the file contract every leg is written against
  smoke-hyprland.sh             a shim that execs smoke.sh, the name older notes point at
  smoke-greeter.sh              the greeter's own loop (just vm-greeter): greetd's default_session is a
                                 standing service, so it drives that rather than composing a session
  vm.sh                         the mac rig driver: start/stop/status/sync/run/smoke/shell against the
                                 headless aarch64 testvm, pulling screenshots and JSON into artifacts/
  vm-lock.sh                    serialises VM commands from parallel worktrees on a lockfile, since sync
                                 rsyncs over the VM's single checkout with --delete
  sni-stub.py                    minimal PyGObject StatusNotifierItem producer for --tray's fixture items: registers for real on the session bus, never faked
nix/
  package.nix                   stdenvNoCC derivation wrapping `qs -p`; also installs formalshell-lock-before-sleep,
                                 the exit-0-always wrapper around `qs ipc call lock lock`, and carries the
                                 runtime CLI PATH (Process model, above)
  ttfx-package.nix               the screensaver's frame source (MIT), prefixed onto that PATH
  tensaku-package.nix            the annotation editor `screenshot edit` launches (MPL-2.0), suffixed onto
                                 it; a separate executable, never linked in, so the shell stays MIT
  greeter-package.nix            stdenvNoCC derivation wrapping `qs -p` at greeter/greeter.qml; copies
                                 shell/ verbatim and layers greeter.qml on top, no lock-before-sleep companion
  hm-module.nix                 home-manager module (programs.formalshell); wires formalshell-lock-before-sleep
                                 to a systemd --user oneshot bound to sleep.target (programs.formalshell.systemd.lockBeforeSleep)
  nixos-module.nix               nixosModules.formalshell: security.pam.services.formalshell-lock,
                                 services.geoclue2 (+ agent), NetworkManager/bluez/upower/
                                 power-profiles-daemon/pipewire, each an mkDefault-guarded sub-option
  nixos-greeter-module.nix       nixosModules.formalshell-greeter: services.greetd wired to the
                                 formalshell-greeter package under a wlroots compositor, generalizing
                                 the hand-rolled rig nix/testvm.nix built first
```

Every widget under `Surfaces/` reads only `Theme` and `CompositorService` , 
never a backend directly, and never a raw compositor socket. That boundary is
what keeps `Bar.qml` and its widgets ignorant of which compositor is under
them, and what makes a second backend a new file rather than a sweep.

**Pure model, thin QML wiring.** Most feature directories at the top of
`shell/` are one `.pragma library` JS module holding all of the domain's
logic, paired with a QML singleton or surface that does nothing but side
effects. `Capture/model.js` builds argv arrays and parses geometry and PPM
bytes while `Services/RecordingService.qml` owns the `Process` that runs
them; `Reminders/model.js` parses specs and decides what is due while
`ReminderService.qml` mirrors `Core.State` and fires notifications;
`Plugins/manifest.js` holds the manifest schema and its failure contract
while `PluginService.qml` reads the directory and creates components;
`SystemUpdate/model.js` parses `flake.lock` and counts inputs behind while
`SystemUpdatePanel.qml` runs the probes. `Menu/toggles.js`,
`Compositor/{keybinds,appmatch,keyboard}.js`, `Bar/layout.js`,
`Notifications/model.js` and `Screensaver/{effect,ttfx}.js` are the same
shape without a service of their own, called straight from the surface that
needs them.

The split is what makes the logic testable: `qmltestrunner` reaches a
`.pragma library` module head-on, so every one of these has a `tests/tst_*`
file, while a QML singleton needs a live engine, a compositor, or a D-Bus
name to say anything. That only holds while the models stay honest about
their inputs. The clock is always a
parameter (`nowMs`, `now`), never `Date.now()` inside the model. Argv
builders return arrays that go straight onto `Process.command`, so a path
containing a quote can never splice a shell. And anything the model cannot
know, it takes as an argument rather than reaching for a singleton, which is
why `toggles.js` is handed a state snapshot instead of importing
`NightLightService`.

## The CompositorBackend contract

Defined once, in `shell/Compositor/BackendBase.qml`. Hyprland is the only
implementation, and the contract stays a contract anyway: every surface is
written against it rather than against `HyprlandBackend`, so a second backend
is a new file under `shell/Compositor/<name>/` and nothing else.

```qml
// BackendBase.qml: QtObject base every backend extends
readonly property bool available          // backend detected its compositor and is connected
property var workspaces: []               // [{ id:string, idx:int, name:string, output:string, isActive:bool, isFocused:bool, isUrgent:bool }]
property var windows: []                  // [{ id:string, title:string, appId:string, workspaceId:string, isFocused:bool, isFloating:bool, isUrgent:bool }]
property var outputs: []                  // [{ name:string, x:int, y:int, width:int, height:int, scale:real }]
property string focusedWindowId: ""
property string focusedWorkspaceId: ""
property string focusedOutputName: ""
signal configReloaded(bool failed)
function focusWorkspace(id) {}
function focusWindow(id) {}
function closeWindow(id) {}
function spawn(argv) {}                   // argv: list<string>, no shell interpolation
function powerOffMonitors() {}
function powerOnMonitors() {}
```

`CompositorService` (the singleton facade, `import qs.Compositor`) exposes
the identical property/method surface, delegating to the one backend, plus:

- `readonly property string compositor`, the constant `"hyprland"`. There is
  nothing to detect: a session that is not Hyprland gets the backend's own
  `available: false` and the honest unavailable state every surface already
  renders off it, and `debug dump` reports both side by side.
- `readonly property var ext`, `{ overview: { available:bool, isOpen:bool,
  toggle() } }`, all-defaults-false when the backend doesn't support an
  overview.

Ids are **opaque strings everywhere above this line**. The one place that
changes is the backend's own IPC boundary, and on Hyprland even that is a
pass-through: window ids are hex addresses kept verbatim, and a dispatcher
takes them as an `address:0x…` selector. Nothing in the tree parses, compares
numerically, or assumes stability of an id.

`HyprlandBackend.qml` needs no hand-rolled event reducer: it reads
`Quickshell.Hyprland`'s own reactive `workspaces`/`toplevels`/`monitors`
models directly and maps them onto the contract shapes, so there's no event
stream or JSON parsing to test in isolation. `model.js` holds the one part
that is worth testing without a compositor (the workspace mapping and its
special-workspace exclusion, `tests/tst_hyprland_workspaces.qml`).

`focusedOutputName` comes from the focused monitor. Everything that opens "on
the focused screen", panels, menu, OSD, notification center, polkit dialog,
capture picker, resolves through it.

The one place the backend is NOT event-driven is `outputs`: Hyprland's
monitor events never mention disabled monitors, which is exactly what
`DisplayPanel` exists to switch back on, so `refreshOutputs()` re-reads
`hyprctl monitors all -j` and `outputsState` records whether that read
answered at all.

## Debug IPC

`shell/Ipc/DebugIpc.qml` registers `IpcHandler { target: "debug" }` with
`function dump(): string` returning
`JSON.stringify({ compositor, available, workspaces, windows, focusedWindowId, focusedWorkspaceId, configLoaded, audio: {volume, muted, available}, brightness: {available, percent} })`
read straight off `CompositorService`/`Core.Config`/`AudioService`/
`BrightnessService`. This is the textual
verification hook used by both smoke scripts (`qs ipc -p <path>
call debug dump`) and by hand during backend development, it's the fastest
way to confirm a backend is wired correctly without reading a screenshot.
`function query(q: string): string` ranks `q` against the live menu tree
(`Menu.qml#query()` → `search.js#rank()`) and returns the JSON result array,
verifying the model/provider/scorer pipeline without keyboard injection
(nested test sessions can't inject keystrokes into the surface itself).

## Theme engine data flow

```
Core.State (state.json: wallpaper, mode)
  |  Connections { onWallpaperChanged / onModeChanged -> ThemeEngine.retheme() }
  v
Theme.ThemeEngine (running/pending queue; a retheme() mid-run just sets pending)
  |  asserts the runtime light/dark signal: dconf write org.gnome.desktop.interface
  |    color-scheme prefer-{dark,light} + gtk-theme adw-gtk3[-dark] (portal re-broadcasts
  |    it as org.freedesktop.appearance, which is what GTK/browsers/Electron/Qt watch)
  |  reads ~/.config/matugen/config.toml + ~/.config/formalshell/matugen.d/*.toml (one `cat` Process)
  |  Theme.matugen.js#buildConfig() -> matugen-merged.toml (spec merge order)
  |  Process: matugen image <wallpaper> -m <mode> -c matugen-merged.toml --prefer darkness|lightness
  |    (no wallpaper set: skip matugen, write Theme.palette.js#fallback() as theme.json directly)
  v
matugen renders templates/theme.json.tmpl + templates/hyprland-colors.conf.tmpl
  -> <state-dir>/{theme.json,formalshell-colors.conf}.tmp
  |  atomic `mv` into place on success: theme.json into the state dir,
  |    formalshell-colors.conf into ~/.config/hypr/
  |  (same run also renders templates/gtk-colors.css.tmpl ->
  |   ~/.config/gtk-{3,4}.0/formalshell-colors.css and
  |   templates/qtct-colors.conf.tmpl -> ~/.config/qt{5,6}ct/colors/matugen.conf,
  |   written directly: apps read those at launch, nothing watches them)
  v
$XDG_STATE_HOME/formalshell/theme.json          ~/.config/hypr/formalshell-colors.conf
  |  FileView watch (Core/Theme.qml)               |  the user's hyprland.conf sources this path
  v                                                  v
Theme.color.* properties update live              Hyprland reloads on config write, so
  -> every Bar/widget token recolors                 col.active_border and friends apply live
     (plain property bindings, no restart)           with no action from the shell
```

`Core/Theme.qml` parses `theme.json`, validates it with `palette.js#validate()`,
and falls back to `palette.js#fallback()` (shadcn's own zinc palette,
2026-08-25 redesign) on absence or invalid content, so `Theme.color.*` is
always a fully-populated 26-key object: the shadcn role set
(`background`/`foreground`, `card`/`cardForeground`, `popover`/
`popoverForeground`, `primary`/`primaryForeground`, `secondary`/
`secondaryForeground`, `muted`/`mutedForeground`, `accent`/
`accentForeground`, `destructive`/`destructiveForeground`, `warning`/
`warningForeground`, `border`, `input`, `ring`, `chart1`..`chart5`), matugen-
driven or not. `primary` carries the wallpaper's own colour; `accent` is a
neutral hover fill, never the wallpaper colour. `mergeWithFallback()`
substitutes per key, not per file: a `theme.json` written before a newer
role existed keeps every other live matugen colour and only that one field
reads zinc. `Surfaces/Background/Background.qml` is the one other consumer
of `State.wallpaper` directly: a per-screen `WlrLayershell.layer:
WlrLayer.Background` surface showing the image, or a flat
`Theme.color.background` fill when unset.

`ThemeEngine` writes every file itself via a small `sh -c` `Process` rather
than `FileView.setText()`: `FileView` silently skips both the write and its
`saved()` signal when the new text is byte-identical to what's already on
disk, which two back-to-back `retheme()` runs for the same wallpaper/mode
routinely produce.

**Icons.** `shell/Theme/icons.js` looks up glyphs by name rather than a
surface carrying a raw codepoint: `glyph(set, name)` returns the codepoint
from `icons/lucide.js` or `icons/nerd.js` (falling back to that set's own
`circle-help` when the name is missing from it), and `family(set)` returns
the font family to render it in (`"lucide"`, or `""` for `nerd`, which
renders in the mono font itself). The active set is `theme.icons` in
`settings.json` (`lucide` default, `nerd`). `Components/Icon.qml` is the
one consumer: a `Text` reading `Config.get("theme.icons", "lucide")`, sized
to the neighbouring text's font size so a row can lay it out like a
character. `icons/lucide.js` is generated by `tools/gen-lucide-icons.sh`
from the pinned Lucide font release's CSS; `icons/nerd.js` is hand-written,
carrying only the names the shell's own surfaces use.

## Menu data flow

```
shell/Menu/default-menu.jsonc                 ~/.config/formalshell/menu.jsonc
  |  FileView (Menu.qml)                        |  FileView (Menu.qml, same bounded-retry pattern)
  v                                              v
Model.parseJsonc() -> defaultObj              Model.parseJsonc() -> userObj
  \                                             /
   \--------------- Model.buildTree(defaultObj, userObj) --------------/
                       |  dotted-id hierarchy, per-key user-over-default merge,
                       |  hidden:true drops a node+subtree, kind inferred from
                       |  action/target/provider/else-submenu
                       v
                 Providers.applyProviders(tree, { apps: appsProvider })
                       |  expands every "provider" node's children in-place
                       |  (DesktopEntries.applications.values -> kind:"app" nodes)
                       |  Config.get("menu.customPowerButtons") merged into the
                       |  default object first, via Providers.customPowerButtonEntries()
                       v
                 { rootIds, nodes }             (recomputed reactively: Config.settings
                                                  change, DesktopEntries change, jsonc reload)
                       |
                       |  on open()/level-descend only (never per-keystroke):
                       v
              one Process per when/checked condition -> _condResults cache
                       |  except a `checked` of the form "@state:<path>", which
                       |  Menu/toggles.js answers from Menu.qml's _stateSnapshot
                       |  in-process: no Process, never cached, so the checkmark
                       |  repaints in the same event-loop turn the state flips
                       |
        +--------------+---------------------------+
        v                                           v
Model.visibleChildren(nodes, id, condResults)   Search.rank(nodes, query, condResults)
  level browsing, self-pruning empty submenus      whole-tree fuzzy scoring (see search.js's
  and links recursively                            five tiers), depth/decl-order tie-break, cap 40
        \                                           /
         \-----------------------------------------/
                       v
              Surfaces/Menu/MenuRow.qml  (icon name via Menu/icons.js's
                                           iconFor(node), sans label, muted
                                           detail, chevron-right/check
                                           trailing icon, confirm-gate swap;
                                           accent-filled cursor/hover row,
                                           not a Cell)
```

**Toggle rows (`Menu/toggles.js`).** The `toggles` subtree's rows carry a
`checked` of `"@state:<path>"` against a closed allow-list of four paths:
`nightlight.active`, `screensaver.stayAwake`, `notifications.dnd`,
`theme.dark`. Membership is tested by list lookup, never by resolving the
string against anything, so a path outside the list answers `false` and a
hand-written `menu.jsonc` has no route into the QML engine through this
field. Adding a path means editing both `PATHS` and `Menu.qml`'s
`_stateSnapshot` literal; `tests/tst_menu_toggles.qml` fails when the two
disagree. `"@state:"` is a `checked` prefix only: a node carrying it in
`when` is hidden with a warning rather than evaluated, because a live `when`
would rebuild the tree under the cursor. Toggle rows also set
`keepOpen: true`, which returns from the activation path before
`root.close()`, so the surface stays at the same level and the row's own
checkmark flips in place. Every other action row still closes.

**Route-local rows.** Two routes build their rows outside the
`buildTree`/`applyProviders` pipeline above, because their content is a
parse of something the compositor owns. The `keybinds` route (`menu summon
keybinds`, or `:k <query>` from anywhere) runs `hyprctl binds`, whose table
already has hyprland's own sources and submaps expanded, and hands it to
`Compositor/keybinds.js`. Deliberately not `-j`: Hyprland 0.56.0's JSON
encoder writes every value from `modmask` on under the previous key's name
and emits `allow_input_capture` with no value, so the reply is not JSON at
all. The text table is one block per bind, headed by `bind` or `bindd`, with
tab-indented `name: value` fields. Its rows are inert notes, so there is no
activation path to get wrong, and every dead end is a named row rather than
an empty list: `NO BINDS`, `BINDS UNAVAILABLE`.

**Launch-or-focus.** `Compositor/appmatch.js` decorates each `kind:"app"`
row with the windows already running for that desktop entry
(`decorateAppRows`), matching on `startupClass` first and the entry id
second, first tier wins, no fuzzy tier. Activating a row with a match calls
`CompositorService.focusWindow()` on `nextWindow()`'s pick instead of
spawning a second copy, and repeat activation cycles that app's windows; a
miss falls through to the same `execute()` spawn path as before, which is
the only path that honors the entry's own `Exec` field codes. Focusing
records a frecency hit, since it is a use of the app.

**Cell contract.** `Components/Cell.qml` draws a `card` fill with a 1px
`border` at `radiusMd` (DESIGN.md §2), plus one layer each for the hover
fill, the cursor ring and the open-panel mark. Its states are `active`
(`primary` fill), `selected` (`accent` fill), `destructive` and `warning`
(colour on the border and the ink, never a fill) and `cursor` (the ring).
Every bar cell, panel row and chip goes through it, so a
`Rectangle`-with-border appearing outside `Components/` is drift, not a new
pattern; the launcher's list row is the one exception, below.

**Cell, and where the launcher doesn't use it.** `Components/Cell.qml` is
the shadcn item shared by every bar cell, panel row and chip (DESIGN.md
§2): a `card` fill with a 1px `border` at `radiusMd`, cursor state drawn as
a `ring`. The launcher's row list is the one place in the shell that opts
out of it: `MenuRow.qml` is a plain borderless item, since a Cell's own
border would double up with every other row's in a list that abuts, and
its cursor/hover state is an `accent` fill rather than a ring, the one
focus a modal surface needs. The picker grid's thumbnail cells and the
breadcrumb chips are `Cell`s, same as everywhere else; only the list row
carries its own paint.

## Notification data flow

```
Quickshell.Services.Notifications.NotificationServer  (NotificationService.qml)
  onNotification: notification => { notification.tracked = true; ... }
    |  server.cpp mutates the SAME Notification object in place on a
    |  replaces_id update rather than emitting a new `notification`: the
    |  handler above runs exactly once per id; per-property *Changed signals
    |  (appName/summary/body/urgency/actions/image) resync the model entry
    |  on every later replace instead
    v
Notifications/model.js  (.pragma library, pure: state in, state out)
  add(state, notif, now, opts)
    |  dnd && !bypassesDnd(notif) -> straight to pending
    |  else -> popups (capped at 4, overflow pushes oldest to pending;
    |          expiresAt = 0 (sticky) for urgency:critical, else now+6000)
    v
  { popups, pending, past, dnd }        1s Timer -> expire()   (popup timeout -> pending)
                                         60s Timer -> prunePast() (past entries >15min -> dropped)
        |                                       |
        v                                       v
Surfaces/Notifications/Toasts.qml       Surfaces/Notifications/Center.qml
  per-screen, Overlay layer,              single instance, Top layer, right-anchored
  notifications.position-anchored,
  sonner depth stack (hover/IPC expand)
  reads .popups                           reads .pending then .past (PENDING/EARLIER sections)
  dismiss -> dismissPopup() (seen, ->past) dismiss -> dismissOne() (dropped outright)
                                           open() -> markAllSeen() on close
```

`bypassesDnd(notif)` is Omarchy's narrow rule, encoded as one pure function
with tests on both sides (`tests/tst_notifications_model.qml`):
`notif.urgency === 2 && notif.senderIsNotifySend === true`, where
`senderIsNotifySend` is set by `NotificationService` from the sender's literal
app name (`notification.appName === "notify-send"`), never inferred from
urgency alone, a chat app marking its own messages critical does not bypass.

**Repeats collapse into one card.** `Model.groupEntries()` keys on the
sender's app name (trimmed, case-folded) plus the summary, deliberately not
the body: the case this exists for is a chat app firing one summary with a
different body per message, and keying on body too would degenerate to no
grouping at all. Each row is a copy of the group's newest member carrying
`count` and `memberIds`, rendered as a repeat count in the meta row, and
group order follows each group's newest member, so a repeat moves its group
to the top instead of adding a row. `MAX_POPUPS` caps groups rather than raw
entries, so five repeats of one notification cannot evict four unrelated
toasts. Grouping is derived at render time in all three tiers (`Toasts.qml`
over popups, `Center.qml` over pending and past) and never stored: every
entry keeps its own
server id and its own `expiresAt`, so the id-keyed side maps below keep
resolving and each member still times out on its own clock.

`NotificationService` keeps live `Notification` objects OUT of the reducer
state (which is plain JS data, safe to keep around after the server destroys
the notification) in a `_live` side map keyed by id, so `dismissPopup()`/
`invokeAction()` can still reach the real object while it's alive; a
`_selfClosing` flag distinguishes a close WE triggered (already applied to
the model) from a sender-initiated `CloseNotification` or action-implicit
close (never applied, so `closed` has to call `Model.dismissOne` itself).

## OSD trigger graph

```
AudioService.changed()  (any volume/mute change on the default sink , 
  |                       ours, wpctl, pavucontrol, hardware keys)
  v
Osd.qml: Connections { onChanged: showVolume() }
  |
  |  IpcHandler target "osd" (OsdIpc.qml): every other trigger, no
  |  automatic signal exists for these:
  +-- volume()      -> osd.showVolume()                     (manual re-show)
  +-- brightness()  -> BrightnessService.refresh(); osd.showBrightness()
  +-- media(text)   -> osd.showMedia(text)
  +-- close()       -> osd.close()
  v
Osd.qml: kind = "volume"|"brightness"|"media", hideTimer restarts (1.6s)
  -> visible = kind !== ""
  -> the Icon (Osd/icon.js), the Track and the readout re-render off
     AudioService/BrightnessService properties directly (no local copy: a
     still-open card tracks live changes, e.g. a second wpctl call while
     the card is showing)
```

The card is `popupWidthNarrow` wide whatever it is showing, and the readout
column is measured off a hidden `100%` rendered at the live font rather than
off whatever value happens to be showing. That is the no-jitter contract:
volume ticking 3% → 97% or a long media title swapping in never moves the
track's right edge.

`BrightnessService` has no polling loop by design (`brightnessctl -m`
queried once at startup, re-read straight from each `set()`/`step()` reply),
so a hardware brightness key is expected to call `brightnessctl` itself and
then poke the OSD to catch up: `brightnessctl set 5%+ && qs ipc call osd
brightness`. On the mac VM rig, where the guest has a pipewire virtual sink
but no backlight device, `AudioService.available` is honestly `true` and
`BrightnessService.available` is honestly `false`, the brightness leg of
`dev/smoke.sh --osd` still proves the surface renders that kind
correctly (the `sun` icon, `0%`, an empty track), not that hardware exists.
One VM-specific gotcha: the guest's null-audio-sink volume persists across
nested sessions (pipewire itself isn't restarted between runs), so a
`wpctl set-volume … 30%` that re-sets an already-30% sink is a no-op, and
`AudioService.changed` only fires on an actual value change. That is a
property of testing against durable state, not a bug in the trigger, so the
`--osd` leg sets the sink to a second value first and the auto-show one is
always a real change.

## Panel host + `panel` IPC data flow

One shared `Components/Panel.qml` is instantiated once per panel kind in
`shell.qml` (`audioPanelInstance`, `calendarPanelInstance`, …), each binding
its backend directly, `Quickshell.Services.Pipewire`,
`Quickshell.Networking`, `Quickshell.Bluetooth`, `Quickshell.Services.UPower`,
or (for `WeatherPanel`) the shell's own `LocationService` plus a direct
open-meteo fetch, rather than going through an intervening Services
wrapper, the same "panel binds its backend directly" pattern
`AudioPanel.qml` established first. A bar widget (`AudioWidget.qml`, …)
opens its panel two ways:

```
click on the bar cell                          qs ipc call panel open/toggle <name>
  -> panel.toggleFrom(the cell itself)            -> PanelIpc.qml: registry[name].open()
     (anchorX and anchorScreen both read off       (no cell, so both stay unset: Panel.qml
      the cell's OWN window: Wayland gives         falls back to the bar's right region on
      no cross-window global coordinates)           the compositor's focused output)
  v                                               v
Panel.qml: isOpen = true, forceActiveFocus() on its full-screen backdrop MouseArea
  -> frame positions at (anchorX, barHeight), sized to its content's implicitHeight
     (capped at 60% of screen height, Flickable scrolls beyond that)
  -> click outside the frame, or Escape, closes it (backdrop's onClicked / Keys.onEscapePressed)
```

**Keyboard cursor (spec "Keyboard model", 2026-08-25).** `Panel.qml` holds
the cursor as plain properties (`cursorIndex`, `cursorCount`, `cursorSection`,
`sectionCount`, `cursorActive`) and keeps the arithmetic in
`Components/cursor.js` as pure functions, the same split `tokens.js` and
`Bar/layout.js` already use: `moveCursor(dx, dy)` calls `Cursor.move()`,
`activateCursor()` calls `Cursor.activation()` and fires `cursorActivated(index)`,
`moveSection(direction)` wraps `cursorSection` through the panel's sections.
A `Components/KeyCatcher.qml` wraps the content column and drives these
three; it never holds focus itself; `keyPressed(event)` fires from the
backdrop's own `Keys.onPressed` **before** the catcher runs, so a surface
that has to see a raw event gets first refusal and only what nobody accepted
reaches the catcher's dispatch. No panel takes that path since M42; the one
consumer left is `TrayMenu.qml`, which composes the same `Panel.qml` and
drives its own row cursor.
The cursor stays hidden until `cursorActive` flips true, which happens on
the first navigation key or the first row hover, so a panel opened by
pointer shows no stale cursor position on open. `catcherBlocked()` mutes
the catcher entirely while an inline `Input` holds focus or the panel is
closed but still mapped.

`shell/Ipc/PanelIpc.qml` (`target: "panel"`) is a spec addendum this repo's
own plan records rather than a conflict with `docs/superpowers/specs/2026-07-27-formalshell-design.md`'s
§IPC list: per-widget popouts otherwise have no summon path for compositor
keybinds, and no way to be verified headlessly in the smoke rig.
`registry: { audio: audioPanelInstance, calendar: …, … }` is wired once in
`shell.qml`; `open(name)`/`toggle(name)` look the instance up and call its
own `open()`/`toggle()`, `close()` closes whichever panel is currently open
(scans the registry for `isOpen`), `state()` returns that same panel's name
or `""`. An unknown name returns `"error: unknown panel '<name>'"` from both
`open()` and `toggle()`, never a silent no-op.

`toggleAt(n)` is the positional keybind (M42 D4). It resolves the bar layout
here rather than reading it off a `Bar` instance, for the reason `BarIpc`
does the same: `Bar.qml` exists once per screen while this handler answers
for the whole shell, and `Layout.resolve` is pure. `shell/Bar/panels.js`
holds the widget-name to panel-name table and `panelAt()` walks the resolved
right region in order, skipping cells that open no panel and counting the
ones a collapsed chevron is hiding. Out of range returns `no panel at <n>`.

Every name in that registry has a `dev/smoke.sh --panel <name>` leg, run one
panel per invocation: the leg asserts `panel open <name>` answered `ok` and
that `panel state` names that panel and no other, then screenshots the open
card. The rig's honest empty states (`NO ADAPTER`, `NO CONTROLLER`, an
absent battery hero) are what a headless VM has to show, so the frame is
read for the chrome rather than for a populated list.

## Bar layout resolution + tray/custom-module lifecycle

`Bar.qml` has no fixed widget declarations; every region is a settings-driven
`Repeater`/`Loader` dispatch per region:

```
settings.json bar.layout/bar.modules          Bar.qml
  -> Config.get("bar", null)                    -> Layout.resolve(bar) (shell/Bar/layout.js, pure)
                                                    -> { regions: {left, center, right}, warnings }
                                                       each entry: {kind:"builtin", name} or
                                                       {kind:"module", id, module} (a "custom:<id>"
                                                       bar.layout name resolved against bar.modules)
                                                    -> unknown widget / dangling module ref dropped,
                                                       one console.warn per drop, never fatal
  -> Repeater { model: regions.<region> }        -> regionDelegate Loader per entry
       sourceComponent: builtin -> bar._builtinComponents[name] (pre-wired with this
                                    bar's own screen/panel context, e.g. AudioWidget's
                                    `panel: bar.audioPanel`)
                         module  -> CommandModule.qml ("command") or QmlModule.qml ("qml"),
                                    handed `module` (the bar.modules entry) once loaded
```

An absent `bar.layout` region falls back to `layout.js`'s own
`DEFAULT_LAYOUT` for that region alone, today's exact arrangement, so a
user with no `bar` config sees no change; a present-but-empty region
(`[]`) stays empty rather than falling back.

**Each conditionally-hidden widget's own `visible` never crosses the
Loader boundary directly.** This is the one real gotcha in the whole
mechanism, and it was found the hard way. A `Loader`'s own
`visible` needs to mirror its loaded item's `visible` so `Row` drops a
hidden widget's slot entirely (`Row` only inspects *direct* children, and
every entry here loads behind a `Loader`, whose own `visible` defaults
`true` regardless of its item's), but reading a Loader-hosted item's
built-in `visible` property from *any* binding or signal handler outside
that Loader, declarative or imperative, silently detaches the item's own
`visible` binding from ever updating again afterward (confirmed by
reproducing it in an isolated standalone repro, a property under any
other name doesn't have this problem). So `Tray.qml`, `Indicators.qml`,
`Battery.qml`, and `NowPlaying.qml` each expose a second property,
`shown`, computed the same way their own `visible` already is; `Bar.qml`'s
`regionDelegate` binds its `Loader`'s `visible` to
`entryLoader.item.shown` (falling back to `true` for every widget that
doesn't define one, since those never hide, so reading their `.visible` , 
which then never needs to update, is harmless). A widget that starts
hidden and later needs to show up reactively (a real tray item
registering, DND flipping on, an MPRIS player appearing) **must** follow
this `shown`-property pattern, not a bare `visible:` binding read from
Bar.qml.

`_regionHeight()`/`_cellHeight` (the bar's own content-derived height) read
each delegate's *loaded item*, never the `Loader` itself, for the same
kind of reason: a `Loader` with no explicit size mirrors its item's actual
size, so reading `Loader.implicitHeight` directly would close a cycle back
through the very property computing it.

**Tray** (`Tray.qml`, `TrayMenu.qml`, `shell/Ipc/TrayIpc.qml`):
referencing `Quickshell.Services.SystemTray` makes quickshell host and
watch `org.kde.StatusNotifierWatcher`, so every real StatusNotifierItem
registered on the session bus appears in `.items` with no extra wiring.
Every item is its own cell, with no visible limit and no drawer. Bounding a
long strip moved up one altitude to the bar chevron below, which is a spec
deviation (§Surfaces-1 says "grouped drawer") recorded in `Tray.qml`'s own
header. `dev/sni-stub.py` is the VM's real StatusNotifierItem producer
(PyGObject, registers on the session bus for real, never faked inside the
shell) and, behind `--menu`, exports a real `com.canonical.dbusmenu` tree
(plain/disabled/checkable/separator/submenu entries) for `TrayMenu.qml`'s
tests to drive.

Right click (or `tray menu <id>`) opens `TrayMenu.qml`, a shell-owned
context menu that replaced the old `Tray.qml`-hosted `QsMenuAnchor`.
That native QMenu was an xdg_popup with its own keyboard+pointer grab
(platformmenu.cpp); Hyprland's grab code never adds the layer-shell parent
to the grab's accept set on the path Qt takes to map it, and a click
anywhere outside that set, including the tray icon's own pixmap, inside
the same Cell's hit area the surrounding padding shares, tore the grab
down and closed the menu instantly (the same shell worked before the
owner's hosts moved to Hyprland, 2026-08-17). One shared
`TrayMenu` instance (`shell.qml`, wired through `Bar.qml` like every other
panel) drives `Quickshell.QsMenuOpener` over the clicked item's own
`DBusMenuHandle` (`item.menu`): assigning it to `QsMenuOpener.menu` fires
`AboutToShow(0)` + `GetLayout(0, -1, [])` once and loads the whole subtree
eagerly, so a `QsMenuEntry`'s own children are already populated by the
time a submenu row expands, no second D-Bus round trip. Submenus expand
in place as indented rows rather than spawning cascade popups, so the
surface stays one layer-shell window taking no xdg_popup grab at all,
which is what removes the Hyprland bug class rather than working around
it. `TrayIpc.qml`'s `menucursor <delta>`/`menuactivate` verbs stand in for
the menu's own Down/Up/Enter keys, the same "verify the action, not the
input method" idiom `picker`'s `choose`/`variant` already draw: an
IPC-opened popout gets no bar cell and so no real Wayland keyboard focus
in the smoke rig.

**Chevron** (`ChevronWidget.qml`, `shell/Ipc/BarIpc.qml`, `Bar/layout.js`):
macOS Hidden Bar / Bartender as a bar widget. `chevron` is an ordinary
`bar.layout` name and its position is its entire configuration: `layout.js`
annotates every entry on its governed side of the same region
`collapsible: true`, and `Bar.qml`'s region delegate ANDs that with
`State.barCollapsed[region]` to drive the `Loader`'s own width, which is
what the delegate's `visible` then reads. That last part is not a
style choice: reading a `Loader`-hosted item's built-in `visible` from
outside permanently detaches the item's own binding (see `Bar.qml`'s
delegate comment), which is why widgets expose `shown` and why the gate
lives on the `Loader` rather than being written into either property.
The governed side is the one away from the region's anchored edge
(`layout.js`'s `governsBefore`): a right-region chevron collapses what
precedes it, so the reveal grows into empty bar and the chevron itself never
moves. The group's width animates over `Theme.motion.standard`, and the
delegate's `visible` is gated on that animated width rather than on the
collapse flag, so a cell only leaves the `Row`'s spacing accounting once it
has actually reached zero. Collapsed is the default, per region, in
`state.json`.

**Indicators** (`Indicators.qml`): four glyph cells, each shown only while
its own condition holds, the whole row hidden when none does. Loudest
first: a live screen recording off `RecordingService.active` (the one
urgent cell here, full-bleed accent fill, click to stop, elapsed clock in
its tooltip rather than in the cell, since a per-second label would
relayout the bar every tick), then a pending reminder off
`ReminderService.count` (its `barLabel` countdown in the cell, the message
in the tooltip), then stay-awake off the
explicit `IdleService.stayAwake` toggle (click the glyph to turn it off;
the media guard that also holds the idle chain shows no glyph of its own),
then night light off `NightLightService.active`. DND has its own
always-visible cell in `BellWidget.qml` instead, no second DND state
machine.

**Custom modules** (`CommandModule.qml`, `QmlModule.qml`,
`shell/Bar/commandOutput.js`): a `"command"` module polls
`module.command` on a `Timer` (`module.interval`, default 5000ms), parses
stdout as Waybar-JSON-compatible `{text, tooltip, class}`
(`commandOutput.js`, pure), and renders the same honest `MODULE ERROR` cell
for a non-zero exit, malformed JSON, a run that outlives `module.timeout`
(SIGTERM'd), or a binary that fails to start at all (quickshell's `Process`
only emits `runningChanged` for that case, never `exited`, tracked via a
`_sawExit` flag so it isn't mistaken for a normal completion). A `"qml"`
module loads `module.source` into a `Loader`, isolating only *load-time*
failures (bad syntax, an unresolvable import) as `Loader.status ===
Loader.Error`; a file that parses fine has the exact same engine access as
any built-in widget (`qs.Core`, `qs.Services`, `Process`, …), this is not
a runtime sandbox.

## Clipboard data flow

```
wl-paste --type text --watch sh -c '… cat; printf "\0"'   (ClipboardService.qml, long-running Process)
  |  NUL-delimited stdout (clipboard text can itself contain newlines)
  |  a capture is skipped: no NUL emitted at all, when wl-paste itself
  |  sets CLIPBOARD_STATE=sensitive (its own x-kde-passwordManagerHint signal)
  v
Clipboard/history.js#add(state, entry, now)   (.pragma library, pure)
  |  sanitize() drops empty/whitespace-only text (the nil/clear watch-event shape)
  |  re-copying existing content moves that entry to the front, keeping its
  |  original id, instead of inserting a duplicate
  |  300-entry cap drops the oldest
  v
$XDG_STATE_HOME/formalshell/clipboard.json      (FileView + JsonAdapter, same
                                                  pattern as Core/State.qml)
  |
  +-- Ipc/ClipboardIpc.qml (target "clipboard"): list()/copy(id)/remove(id)/clear()
  |
  +-- Menu/providers.js#clipboardProvider(): one menu row per entry, newest
        first; selecting a row runs `qs ipc -p <selfPath> call
        clipboard copy <id>`: the exact same self-targeting invocation a
        CLI caller would use, so the menu row is the IPC verb, not a second
        code path
```

## Location → Weather chain

```
Services/LocationService.qml
  QtPositioning.PositionSource (geoclue2 D-Bus backend), left continuously
  `active` with a repeating updateInterval: never a one-shot update(), so
  an early inaccurate geoclue fix is just replaced by the next one instead
  of freezing in (the spec cites PR #2914's lesson by name for this)
    |
    |  settings.json's location.latitude/location.longitude, when BOTH are
    |  present, override geoclue entirely (root._hasOverride): the
    |  documented fallback for geoclue's own known failure modes, and the
    |  path exercised in the test VM, which has no Wi-Fi radio to associate
    |  with in the first place
    v
  available / latitude / longitude              (all live property bindings)
    |
    v
Surfaces/Panels/WeatherPanel.qml
  "NO LOCATION" cell when !LocationService.available
  otherwise: Weather/openmeteo.js#buildUrl(lat, lon) -> XMLHttpRequest ->
  parseResponse(status, bodyText) -> { ok:true, current, forecast[] } or
  { ok:false, error: "network_error"|"http_error"|"malformed_json"|"missing_fields" }
    |
    v
  header meta row (condition label + temperature + icon) + a FORECAST
  section (one row per daily period, icon + weekday + high/low mono temps
  pinned right); an "UNAVAILABLE" cell carrying the `error` code replaces
  those rows on any fetch failure: never a stale or fabricated forecast
```

`WeatherPanel.qml` owns its own `XMLHttpRequest` directly (no separate
`WeatherService`), the same "panel drives its own fetch" pattern
`AudioPanel`/`NetworkPanel` already establish for their respective
quickshell modules.

## MPRIS → panel chain

```
Quickshell.Services.Mpris.players.values
  |
  v
Services/MediaService.qml            (pick + clamps: Media/model.js)
  players = [{id: dbusName, identity, label, isPlaying}, …]
  activePlayer = the selected player while it is still registered,
                 else the first isPlaying:true one, else players[0], else null
  available / title / artist / album / artUrl / identity / isPlaying /
  canGoNext / canGoPrevious / canSeek / position / length /
  shuffle+shuffleSupported / loopState+loopSupported ("none"/"track"/
  "playlist") / volume+volumeSupported (the player's own 0..1, not the
  sink's) / canRaise
    |  (position doesn't emit positionChanged on ordinary playback ticks , 
    |   quickshell's own doc'd workaround: a 1s Timer re-emits it while
    |   isPlaying so any binding that reads position advances at all)
    |
    +-- Surfaces/Bar/widgets/NowPlaying.qml
    |     visible: MediaService.available (hidden entirely otherwise , 
    |     not a "nothing playing" lie); click toggles MediaPanel
    |
    +-- Surfaces/Panels/MediaPanel.qml
    |     album art cell (static Image off artUrl) + NOW PLAYING / <app>
    |     meta row + title/artist + one row per player when more than one is
    |     registered + flat accent-fill progress cell (draggable to seek when
    |     canSeek) + transport cells, flanked by shuffle and
    |     loop cells (active = on) when the player supports them + the
    |     player's own volume track + a RAISE label in the title band
    |     |
    |     v
    |   Loader { source: "AnimatedAlbumArt.qml" }
    |     active only when isOpen && isPlaying && AppleMusicArtService's
    |     animatedArtUrl !== "": the static Image above is the permanent
    |     fallback under every other condition
    |
    +-- Ipc/MediaIpc.qml (target "media"): playPause()/next()/previous()/
          shuffle(on|off|toggle)/loop(none|track|playlist|cycle)/
          volume(0-100)/raise()/select(id)/players()/status()
          calls MediaService directly: MediaPanel's own transport cells
          also call MediaService directly, this exists for compositor
          keybinds and headless smoke verification, same division of
          labour WallpaperIpc/ThemeIpc have over their own singletons

Services/AppleMusicArtService.qml   (opt-in: media.appleMusicArt, off by default)
  onCacheKeyChanged (artist+album) -> _schedule()
    |  disabled or no artist/album -> animatedArtUrl = "" (no network at all)
    |  cache hit (including a cached miss) -> animatedArtUrl set/cleared, no network
    |  cache miss -> 1.5s debounce -> _lookup()
    v
  _lookup(): disk cache file test -> _search(): Media/applemusic.js#searchUrl()
    -> curl iTunes Search -> parseSearchResult()
    -> (first time) _fetchToken(): scrape web-player page -> asset bundle -> JWT
    -> _fetchEditorialVideo(): amp-api editorialVideo (undocumented, curl
       Authorization: Bearer <token>) -> parseEditorialVideo()
    -> _fetchMaster()/_fetchVariant(): m3u8 playlists -> pickVariant()/extractMp4Url()
    -> _download(): curl to a per-lookup temp file -> atomic mv into
       ~/.cache/formalshell/applemusic-art/<cacheKey>.mp4
    |  every step's failure (parse error, http error, missing token, no
    |  match) falls back to _store(key, ""): a cached MISS, so a track
    |  without animated art is never re-fetched every play: never an
    |  uncaught error
    v
  animatedArtUrl (file:// or "") -> MediaPanel's AnimatedAlbumArt.qml Loader
```

`Media/applemusic.js` (pure, `.pragma library`, TDD'd first , 
`tests/tst_applemusic.qml`) owns every URL-building, response-parsing, and
cache-key/prune-decision function; `AppleMusicArtService.qml` is pure
side-effect orchestration around it, one fresh `Process` per `curl`/`find`/
`mv` call (never a shared/reused instance, so overlapping lookups for
different tracks never clobber each other's stdout) gated by a `_serial`
counter bumped on every reschedule so a slow in-flight lookup for a track
the user has since skipped past can never overwrite a newer result.

## Lock screen / PAM flow

```
Ipc/LockIpc.qml (target "lock") lock()
  v
Services/LockService.qml  (the one lock trigger: this route, the `lock` hot
                           corner, screensaver.lockAfterSeconds and the
                           launcher's Lock row all land here)
  |  lock.command set: CompositorService.spawn(argv), the surface below is
  |  never mapped and `isLocked` reports null, since a foreign locker never
  |  reports back
  |  lock.command empty: raise the surface, then read lockScreen.locked
  |  straight back, which catches WlSessionLock::realizeLockTarget()'s silent
  |  fail-open paths (no ext-session-lock-v1 support, no surface, no
  |  WlSessionLockSurface) that would otherwise report "ok" while the session
  |  stayed unlocked
  v
Surfaces/Lock/Lock.qml  (one Item wrapping WlSessionLock + both PamContexts;
                          see its own header comment for why a bare
                          PamContext can't be a WlSessionLock's direct child)
  lock(): sessionLock.locked = true; idleMonitor.enabled = true (imperative,
          not bound to `locked`: WlSessionLock only emits lockStateChanged()
          on its *unlock* path, verified against session_lock.cpp)
    |
    v
  WlSessionLock instantiates one LockSurface per output on its own
    (no manual Variants loop, unlike every other multi-output surface here)
    |
    v
  Surfaces/Lock/LockSurface.qml
dithered backdrop: Image { source: Core.State.wallpaper } (hidden) feeding
      a DitherImage { mode: "retro", chunk: 8, paletteSize: 6 }: was a
      MultiEffect blur (DESIGN.md's one blur exception) once; nothing
      in the shell blurs anything now. It has never captured the screen: a
      ScreencopyView-based capture crashes the shell outright, see the
      file's header comment: never reintroduce it
    Components/AuthPrompt.qml instance: one bordered plate holding an
      oversized clock, the date, a dividing rule, and a single 3px-outlined
      field (masked: true) whose border swaps to Theme.color.urgent on
      errorState
    onAccepted -> Lock.qml#submitPassword(password)
    onPositionChanged/Keys.onPressed -> Lock.qml#wake() (clears a resume-guard trip)

  PamContext { config: "formalshell-lock" }         PamContext { config: lock.fingerprintPamService }
    password conversation, the sole unlock path        parallel conversation, only started when a
    onCompleted(Success) -> _unlock()                  reader is enrolled (empty string = never starts,
    onCompleted(else) -> authError =                   the only "enrolled" this shell can express , 
      _resultError(result)  (WRONG PASSWORD /           no Fprintd binding); shares no state with the
      PAM ERROR / ACCOUNT LOCKED)                       password PamContext, so a pending scan never
                                                          blocks or disables the password field

  blanked: sessionLock.locked && (idleMonitor.isIdle || _resumeGuardActive)
    idleMonitor: dedicated IdleMonitor, respectInhibitors:false (a locked
      screen should blank regardless of an app-held inhibitor), timeout =
      lock.blankAfterSeconds (default 30)
    _resumeGuardActive: a 1s tickTimer compares Date.now() gaps: a jump
      much larger than one interval means the wall clock moved further than
      monotonic time would explain (suspend, or a stepped clock): set true
      on that gap, cleared by real activity or idleMonitor.isIdle going false
```

A real deployment needs `security.pam.services.formalshell-lock = { };`
declared system-side (`nix/testvm.nix`'s own copy is the reference), the
home-manager module alone cannot create a PAM service, only NixOS/system
config can. The `lock-before-sleep` contract (spec §8) is a separate,
narrower path: `nix/package.nix`'s `formalshell-lock-before-sleep` wraps
`qs ipc call lock lock` in `|| true; exit 0`, and `nix/hm-module.nix` binds
it to a `systemd --user` oneshot on `sleep.target`, so a lock failure can
never block suspend, verified directly by running the wrapper with no shell
instance up at all and reading `$?`.

## Idle → screensaver trigger graph

```
Services/IdleService.qml  (singleton, always-on, session-wide)
  one shared IdleMonitor, respectInhibitors:true (an app-held idle-inhibit
    or the compositor's own input-idle folding already keeps the whole
    session non-idle: no polling of our own needed)
  timeout = screensaver.timeoutSeconds (default 300): armed exactly ONCE,
    after Core.Config.loaded first resolves, never re-bound live: a live
    binding recreates IdleMonitor's underlying ext_idle_notification_v1
    object a moment after startup (settings.json loads asynchronously) and
    that recreation was reproduced silently and permanently breaking
    isIdle propagation to QML for the rest of the process's life: a stale
    settings edit needing a shell restart is the accepted trade for idle
    detection actually working
    |
    v
  isIdle                                    (this is a DIFFERENT IdleMonitor
    |                                         instance from Lock.qml's own , 
    |                                         that one is on-demand and
    |                                         respectInhibitors:false on
    |                                         purpose; see its header comment)
    v
Surfaces/Screensaver/Screensaver.qml  (one controller Item)
  _autoWant = IdleService.isIdle && !_suppressed
              && (!guardMediaPlayback || !MediaService.isPlaying)
    |  live, not edge-triggered: a track starting/ending mid-idle-stretch
    |  flips this immediately either way (spec §10's guard is a standing
    |  condition, not a one-time check)
  active = _forced || _autoWant
    |
    +-- Ipc/ScreensaverIpc.qml (target "screensaver"): start() sets _forced
    |     true; stop() sets _forced false AND _suppressed true (held until
    |     IdleService.isIdle next drops to false: i.e. real activity , 
    |     so one dismissal doesn't get instantly re-triggered by the same
    |     idle stretch, but the NEXT idle cycle still fires normally)
    |
    v
  Variants over Quickshell.screens -> one PanelWindow per output
    (WlrLayer.Overlay, keyboardFocus OnDemand while visible)
    |  a FileView loads branding/screensaver.txt (or screensaver.asciiPath,
    |    falling back to the bundled banner on failure) into a banner grid
    |  Canvas, repainted off whichever frame source is live:
    |    ttfx (Screensaver/ttfx.js, one process per output, argv built by
    |      command(), its ANSI stream read back by parseFrame() at
    |      screensaver.frameRate, default 60) whenever `command -v ttfx`
    |      succeeds: 37 effects, each painting in its own upstream gradient
    |    Screensaver/effect.js#frameState(name, frame, banner) otherwise:
    |      five effects (decrypt/rain/expand/slide/scatter) in
    |      Theme.color.accent, pure: frame counter + banner in, {char,
    |      opacity} grid out, tests/tst_screensaver_effect.qml
    |    `engine` (and so `screensaver frameInfo`) reports which one is live;
    |      "random" draws from the active engine's own pool, and a
    |      screensaver.effect naming an effect that engine doesn't have falls
    |      back to its random pick rather than going blank
    |  the shell's own Canvas draws every glyph in Theme.font.family either
    |    way. No terminal window is spawned; what ttfx moved out of QML is
    |    the frame math (spec addendum, see CLAUDE.md)
    |  any real key or pointer movement -> stop() (a MouseArea baseline
    |    swallows the single spurious positionChanged Qt fires the instant
    |    the surface becomes visible under an already-stationary cursor , 
    |    reproduced directly: without it, an auto-triggered screensaver
    |    dismissed itself instantly and never re-triggered for the rest of
    |    the session)
    v
  onActiveChanged: active && lockAfterSeconds > 0 -> lockChainTimer (optional
    chain into Lock.qml#lock() after continuing to show that much longer;
    0, the default, disables the chain outright)
```

## Picker answer-channel handshake

```
Ipc/PickerIpc.qml (target "picker")
  summon()              -> menu.openWallpaperPicker()
  select(dir, token)    -> menu.openImageSelect(dir, token)
  choose(path)           -> menu.chooseImage(path)  (same action Enter/click use)
  variant(dark|light)    -> menu.setPickerVariant(name)  (same action the DARK | LIGHT
                            cells and Tab use; refused where the listing has no variants)
  close()                -> menu.close()
  status()               -> JSON.stringify(menu.pickerStatus())
    |
    v
Surfaces/Menu/Menu.qml, the "wallpaper" ROUTE  (the picker has no
                                   surface of its own; it is one level of
                                   the menu that draws as a grid, so the
                                   card, search field, cursor, pointer gate,
                                   activate(index) and every close path are
                                   the menu's, not a second copy)
  open("wallpaper") -> _enterLevel("wallpaper") -> _enterPickerRoute():
    _pickerMode = "wallpaper"; _pickerDir = picker.directory setting
  openImageSelect(dir, token): _pickerMode = "select"; _pickerDir = dir (or
    the setting, if dir is empty); _pickerToken = token; the one-shot
    _pickerRequestPending flag stops the level entry resetting either
    |
    v
  _scanPickerDir(): `find <_pickerDir> -maxdepth 1 -type f \( -iname *.png
    -o ... \)` over a Process (Quickshell has no directory-listing QML type,
    same technique CalendarEventsService already uses) -> _pickerImages[]
    |
    v
  _displayRows -> Providers.imageRows(_pickerImages, query): kind "image"
    rows, filtered by basename; a GridView of Cell delegates renders them,
    `selected: index === _cursorIndex`. Left/Right move the cursor by one
    and Up/Down by a row through the menu's own key handling; Enter/click
    both reach chooseImage(path)
    |
    v
  chooseImage(path):
    mode "wallpaper" -> Core.State.setWallpaper(path)   (the exact call
                         WallpaperIpc's set() makes: ThemeEngine's retheme
                         pipeline runs through the one trigger path, never
                         duplicated here)
    mode "select"    -> _writeSelectionFile(_pickerSelectionPath,
                         { token, value: path })
    root.close()
    |
    v (mode "select" only, and only if a request was actually pending)
  $XDG_STATE_HOME/formalshell/picker-selection.txt
    written via a Process (never FileView.setText(), which silently skips
    both the write and its saved() signal when the new text is
    byte-identical to what's already on disk). Kept distinct from
    menu-selection.txt: two documented channels, different callers
    |
    +-- _leavePickerRoute(): leaving the level (Escape, backspace-on-empty,
          the menu closing) still resolves the caller's poll loop, writing
          { token, cancelled: true } instead: and drops _pickerImages,
          which destroys the grid delegates holding the decoded thumbnails
```

This is the exact request/answer handshake `Menu/MenuIpc.qml`'s
`select()`/`input()` already established (see `Menu.qml`'s header comment
for the full rationale: an `IpcHandler` call is synchronous request/
response, so the UI's eventual answer can't ride back on the call that
opened it), reused rather than reinvented, correlated the same way by a
caller-supplied token.

## Capture family: `screenshot` / `capture` / `record`

Three IPC targets, split by what each one leaves behind rather than by which
binary it drives: `screenshot` writes a PNG (and copies it), `capture` puts
recognized text or a pixel's color on the clipboard and keeps no file,
`record` owns video. All three share `shell/Capture/model.js`, which is pure:
argv builders, `slurp` geometry parsing, the PPM byte read, the OCR
pipeline's own exit-code meanings, and every path/label formatter.

```
Ipc/ScreenshotIpc.qml (target "screenshot", a Scope so its Processes have a home)
  full()/region()          -> grim (slurp supplies region's geometry)
  pick(mode, processing)   -> Surfaces/Capture/RegionPicker.qml
    |  mode: smart|region|windows|fullscreen; processing: default|copy|save
    |  BOTH arguments are required: IpcHandler dispatches on exact arity, so
    |  a one-argument `pick` finds no method rather than defaulting the second
    v
  picked(rect)        -> grim -g against the still-mapped freeze, chrome hidden
  cancelled(reason)   -> SCREENSHOT CANCELLED, the shared watchdog stopped
    |
    +-- key(name)/pickerStatus(): the picker's keyboard model driven from
    |     outside the process, for a rig with no synthetic pointer or key
    |     delivery into an Exclusive-focus layer surface
    +-- edit(path): sh -c '"$FS_EDITOR" "$FS_EDIT_PATH"' (screenshot.editor,
          default tensaku-edit), the same call the SAVED notification's
          EDIT action makes, reachable from a compositor keybind. The PNG is
          already saved and copied by then, so a failed launch warns and
          never repaints the capture as failed

Ipc/CaptureIpc.qml (target "capture", a Scope so its Processes have a home)
  text()  -> slurp -d  -> grim -g <geom> PNG -> tesseract -> tr -d "\f" -> wl-copy
  color() -> slurp -p -x -> grim -g <geom> -t ppm 1x1 -> od -An -tu1 (last 3 bytes)
                                                       -> Capture.hexFromPpmBytes -> wl-copy
  textAt(geom)/colorAt(geom): the identical pipelines from a caller-supplied
    "X,Y WxH", skipping the selection entirely
    |  one _busy flag + one watchdog (capture.timeoutSeconds) across ALL FOUR verbs
    |  slurp exit 1 is the user declining: no toast, no lastError
    |  OCR exit 3 is "no readable text": a real answer, no clipboard write
    |  geometry and paths ride Process.environment, never the script text

Services/RecordingService.qml   (Ipc/RecordIpc.qml forwards, holds no state)
  start(scope, audio)
    |  region -> slurp (same chrome, same 0</dev/null stdin trap)
    v
  mkdir -p recording.directory
    v
  _setupAudio(): one sh script, two lines out (pactl module ids, then the
    device to record). desktopmic loads module-null-sink + two loopbacks and
    unloads whatever it already loaded if a later step fails
    v
  Capture.recorderArgv() -> wf-recorder -y -f <path> [-r][-o][-g][-c][--no-dmabuf][--audio=<dev>]
    |  -y is mandatory, not a convenience: without it wf-recorder blocks on a
    |  getline() from a stdin pipe quickshell never closes
    |  --audio takes an optional_argument, so the device must ride the SAME argv element
    v
  stop(): running = false (SIGTERM, one of wf-recorder's own graceful signals,
    so the container is finalized) + a 5s SIGKILL escalation that reports
    RECORDING TRUNCATED rather than a save
    v
  gif(path): Capture.gifArgv() two-pass ffmpeg palettegen -> paletteuse,
    dither=bayer per DESIGN.md §2, written next to its source
```

**The region picker is the shell's own surface** (`Surfaces/Capture/
RegionPicker.qml`), a full-screen `WlrLayer.Overlay` window rather than a
themed slurp. It freezes first: `grim` captures every output before the
surface maps, the surface renders those frames 1:1, and the capture then
grims the surface itself with the chrome hidden for one frame, so content
cannot shift mid-pick and the overlay cannot photograph its own scrim. No
`ScreencopyView` is involved (see `LockSurface.qml`'s header for why).
Owning its own highlight state is what keeps it to one code path: omarchy's
upstream picker moves the selection by warping the cursor so slurp's hover
highlight follows, and binds its keys from Hyprland Lua at runtime, which the
shell cannot install into a compositor.

**A window with no box is named, never taken.** Hyprland reports a rect for
every window it does not hide, so this is normally empty; an unfocused member
of a tabbed group is the case that fills it. Those windows are listed in a
labelled card (title over dim app id) saying they cannot be captured, rather
than vanishing from a mode that lists their neighbours. **The branch is on
`rect === null`, never on a compositor name.**

`active` is `recProc.running` and nothing else: never persisted (a crashed
shell would leave a stale `true` in state.json) and never derived from
`pgrep`. `Surfaces/Bar/widgets/Indicators.qml` binds it directly, which is
also what forces the singleton's lazy construction. The recording scope
vocabulary is `screen` and `region`, with no window scope at all: wf-recorder
takes an output or a geometry, and a window supplies a geometry only while
the compositor reports a box for it.

## Reminder lifecycle

```
Ipc/ReminderIpc.qml (target "reminder")     Menu "Set Reminder" row
  set(duration, message)                      @ipc:reminder.set -> Menu.openInput(token)
    |                                           |  answer arrives on Menu's selectionResolved
    |                                           v
    |                                    ReminderService.resolveInput(token, value, cancelled)
    v                                           |  Model.parseSpec("25m coffee break")
Reminders/ReminderService.qml <-----------------+
  Model.parseDuration / parseSpec -> Model.makeEntry -> Model.add (sorted by dueAt)
    v
  Core.State.setReminders(list)          <-- the ONLY writer
    v
  state.json `reminders`
    |  Connections { onRemindersChanged } mirrors it back into _pending
    |  (one-directional: nothing ever assigns _pending itself, so state.json's
    |   async FileView load is an ordinary case rather than a special one)
    v
  1s Timer while _pending is non-empty -> Model.due(list, now)
    |  fired -> NotificationService.notify(msg, urgency 2) per entry
    |           (urgency 2 + `local` IS the DND bypass, and also forces
    |            expiresAt 0, so the toast is sticky until dismissed)
    |  nothing fired -> due() returns the SAME array identity, and _tick
    |                   returns before touching Core.State, so an idle
    |                   countdown never rewrites state.json once a second
    v
  barLabel (soonest countdown, or "12:30 / 3") -> Indicators.qml's reminder cell
```

An entry whose `dueAt` passed while the shell was down is treated exactly
like one that just crossed, so it fires on the first tick after state.json
loads. Late is honest; silently dropped is not.

## Plugin loading

```
~/.config/formalshell/plugins/<id>/manifest.json
  |  Plugins/PluginService.qml: ONE sh Process enumerates the directory and
  |  cats every manifest in a single pass (Quickshell has no directory-listing
  |  QML type; the same read ThemeEngine performs over matugen.d), records
  |  separated by a boundary line rather than by a process per file
  v
Plugins/manifest.js#resolve(text, settings.json plugins.disabled)
  |  splitScan -> validateRecord per plugin -> id-sorted plugins, byId, warnings
  |  whole plugin dropped: unparsable, missing required key, wrong apiVersion,
  |    id != dirname, unknown kind, entry escaping the directory
  |  one key dropped to its default: unknown key, key on the wrong kind, bad
  |    region/width/keepLoaded/name value
  v
PluginService.{plugins, barPlugins, surfacePlugins, servicePlugins, warnings, errors, loaded}
  |
  +-- bar     -> Bar/layout.js resolves a "plugin:<id>" layout name against
  |              barPlugins ({kind:"plugin", id, plugin}); an unplaced bar
  |              plugin is appended to its manifest's own region, id-sorted
  |              -> Surfaces/Bar/widgets/PluginBarModule.qml (a Loader)
  |
  +-- panel   -> shell.qml Variants over surfacePlugins
  +-- overlay    -> Surfaces/Plugins/PluginPanel.qml / PluginOverlay.qml
  |                 each registers ITSELF as PluginService.surfaces["plugin:<id>"]
  |                 on completion, because a Variants delegate cannot be named
  |                 as an id in shell.qml the way the builtin panels are
  |                 -> PanelIpc's registry binding merges `surfaces` with the
  |                    static builtin map, so `panel open plugin:<id>` needs no
  |                    branch of its own and an unknown name gets the same error
  |
  +-- service -> Qt.createComponent (not a Loader: a service root is any
                 QtObject, and a failed component gives a real errorString()
                 that Loader's status enum cannot)
```

`rescan()` closes every open plugin surface first, deliberately rather than
as a flicker: a `Variants` may destroy and recreate its delegates when the
model identity changes, and a surface torn down mid-open would leave
`PanelRegistry` pointing at a dead object. Nothing watches the directory, so
a new plugin needs `plugins reload` or a restart.

The isolation is load-time only. A `Loader` (or `Qt.createComponent`) catches
bad syntax and unresolvable imports, reported through
`PluginService.errors` and rendered as a `PLUGIN ERROR` cell or a dim row. A
plugin file that parses fine has the same engine access as any built-in
widget and can wedge or crash this single-process shell. What it never gets
is a window of its own: layer, exclusive zone and keyboard focus stay
shell-side, because a permanently-`Exclusive` surface makes Hyprland route
every pointer event on every output to it (`Panel.qml`'s own documented
finding), and a third-party file getting that wrong would brick the session.

## Greeter / greetd flow

```
services.greetd  (nixosModules.formalshell-greeter)
  default_session.command = <sessionScript>   (a module-generated wrapper,
                                                not formalshell-greeter itself)
    |
    v
sessionScript  (nix/nixos-greeter-module.nix)
  exports XDG_RUNTIME_DIR/HOME/XDG_CONFIG_HOME/extraEnvironment
    (greetd's worker.rs resets the session environment to PAM's own envlist
    : nothing this module's systemd units export reaches the script for
     free, confirmed by reading greetd's own Rust source, not the nixpkgs
     module)
  backgrounds compositorPackage (default pkgs.sway) with WAYLAND_DISPLAY
    deliberately left unset (a real seat's wlr_backend_autocreate treats its
    mere presence as "nested inside another Wayland session" and never
    falls through to DRM), discovers whichever socket the compositor
    actually created, exports WAYLAND_DISPLAY for that, THEN runs
    formalshell-greeter in the FOREGROUND: greetd-ipc(7):
    "the session will start after the greeter process terminates", which is
    what lets the script know the exact moment that happens, for
    postGreeterCommand and verification alike (never an async compositor
    `exec` line racing that signal)
    |
    v
greeter/greeter.qml  (Quickshell.Services.Greetd; no WlSessionLock: greetd
                       already isolates this process into its own disposable
                       compositor with no other client ever attached, so
                       there's nothing for a lock primitive to exclude here)
  Connections { target: Greetd }
    onAuthMessage(message, error, responseRequired, echoResponse)
      -> _promptMessage/_promptEcho/_awaitingResponse drive the one input
         cell's meta label and TextInput.echoMode
    onAuthFailure(message) -> authError = message (inverts the input cell,
      shows greetd's own PAM string verbatim: e.g. "pam_authenticate:
      AUTH_ERR": no second mapping table like Lock.qml's PamResult, since
      greetd hands back plain text, not an enum)
    onError(message) -> authError = message, UNLESS authError is already
      set: greetd (0.10.3) unconditionally follows every auth_error with a
      cancel_session it can no longer deliver, and the resulting "unable to
      send message: Connection refused" must never clobber the real
      onAuthFailure text already showing (a confirmed, fixed defect, 0757fc2)
    onReadyToLaunch() -> Greetd.launch(sessionCommand, [], true)
      ("Performing animations and such should be done *before* calling
       launch": Greetd::launch's own doc; nothing here to animate)
    |
    v (successful auth)
greetd starts sessionCommand as the real user's session (from
  greeter.sessionCommand in settings.json when run loose, or the static
  settings.json nixos-greeter-module.nix writes for the `greeter` account
  when deployed via the module); formalshell-greeter exits,
  sessionScript's postGreeterCommand runs (a verification hook a normal
  login ignores), the module's compositor is torn down
```

`Quickshell.Services.Greetd` exposes no session/user enumeration at all
(confirmed against greetd's own `connection.cpp` , 
`create_session`/`cancel_session`/`post_auth_message_response`/
`start_session` is the entire wire protocol), so unlike the lock screen
there is deliberately no picker here: typing a username into the one input
cell is the same free-text conversation step the password prompt already
is, just started by this process instead of a display manager.
`dev/smoke-greeter.sh` (`just vm-greeter`) drives the whole chain above with
real `wtype` keystrokes across the `test` -> `greeter` system-account
boundary rather than an IPC shortcut, the same "verify the action, not the
input method" reasoning `LockIpc.qml`'s missing `unlock()` already
establishes.

## Adding a backend

1. Create `shell/Compositor/<name>/<Name>Backend.qml`. QML can't literally
   `extend` `BackendBase` as its root type (its properties are read-only),
   so every backend is a duck-typed `Scope` (needs a default `children`/`data`
   property to nest `Socket`/`Timer`/etc. children, plain `QtObject` doesn't
   have one) that declares the exact same property/signal/function names as
   the contract.
2. Populate `workspaces`/`windows`/`outputs`/`focused*` from whatever IPC or
   Quickshell module the compositor exposes, normalizing every id to a
   string at the boundary.
3. Implement the six action functions against that compositor's real
   dispatch mechanism.
4. Give `CompositorService.qml` a way to pick between the two. It holds one
   backend today and reports the constant `"hyprland"`; adding a second means
   restoring a detection block, and `compositor` becomes the answer it gives.
5. Verify with a smoke leg under `dev/smoke.d/`: build, launch nested,
   screenshot, and assert the `debug dump` JSON has `available: true` and at
   least one workspace. Hyprland is the only supported target since the
   2026-08-25 redesign
   (`docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`, "Hyprland
   first"), so nothing here is speculative scaffolding: it is what the
   contract already costs, written down.
