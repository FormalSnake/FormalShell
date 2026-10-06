# R3: panels

Goal: every popout panel in Rust, hanging off its cell through the joined
shape, keyboard-driven, with the shared component set it is built from.

Facts this plan rests on (checked 2026-10-06):

- R2 Task 1 gave the bar a stand-in panel: `panel open` hangs a joined
  card carrying only the panel's title on any edge, and a tooltip anchor
  (`Bar::tooltip()`). R0 ported Presence, Joint, Deform and Shoulders.
- The QML panels are `shell/Surfaces/Panels/` (22 files, ~11k lines) on
  `shell/Components/` (Panel, PanelSlot, PanelHero, Card, Box, BoxCast,
  Button, IconButton, ButtonGroup, Segmented, Switch, Input, Track,
  Rail, Separator, SectionLabel, Sparkline, PowerFlow, FlowNode/Link,
  Tooltip/TooltipGroup, SizeMorph, Drawer/DrawerJoin/DrawerPopover,
  Picture, Cover, Avatar, Keycap, KeyCatcher, WheelScroll, MarqueeText).
- Service crates for every panel's backend are merged; R2 Tasks 2 to 6
  wire them into the runtime.

Task 1 first; Tasks 2 to 5 then run in parallel worktrees, each owning its
panels. The lyrics pane, visualizer canvas and media panel are R7; the
Spaces preview is R8.

## Task 1: panel framework and components

- The panel host: one open panel at a time (`panel state`), the joined
  shape against every edge and the frame ring, popover cards for a
  vertical bar, the handoff between two panels as one card travelling,
  size morph when content changes, the drawer and emerge motion on the
  QML constants, Escape and click-outside, focus grab and release.
- The component set above as Rust widgets on the scene, each measured and
  drawn once and damaged only where it changed, every one in all three
  themes (pantheon's raised buttons, sunken troughs, casts and rims;
  retro's dither). The dev gallery sheet (`--gallery`) drawn from them.
- Row-level keyboard navigation (`--panel-keys`), tooltips with the
  group's grace window (`--tooltip`, `--tooltip-travel`).
- Legs: `--gallery` (and `--pantheon`, `--retro`), `--panel <name>`
  for one simple panel, `--panel-anchor`, `--panel-at`, `--panel-emerge`,
  `--panel-handoff`, `--panel-morph`, `--panel-keys`, `--join`,
  `--shoulders`, `--deform`, `--tooltip`, `--tooltip-travel`.

## Task 2: network, Bluetooth, audio, display panels

- NetworkPanel (scan, wrong password, connect, forget, enterprise, the
  speed test), BluetoothPanel, AudioPanel, DisplayPanel (scale, mirror,
  enable, HDR's honest unavailable line), DualsensePanel, EarbudsPanel.
- Legs: `--wifi`, `--speedtest`, `--display`, `--hdr`, `--earbuds`,
  `--panel bluetooth`, `--panel audio`.

## Task 3: power, monitor, system panels

- PowerPanel (PowerFlow, profiles, the honest "No power sources"),
  MonitorPanel and the process table, SystemUpdatePanel, TailscalePanel,
  UsagePanel, GithubPanel.
- Legs: `--processes`, `--monitor`, `--systemupdate`, `--panel power`,
  `--panel tailscale`, `--panel usage`, `--panel github`.

## Task 4: calendar, weather, iPhone panels

- CalendarPanel (grid, agenda, ics events, life progress), WeatherPanel,
  IphonePanel (connected state, recent list, now playing, pair again).
- Legs: `--iphone` (panel half), `--panel calendar`, `--panel weather`.

## Task 5: app menu and the toggle hub

- AppMenuPanel and MenuTrigger, the toggle hub's rows repainting from a
  state snapshot without moving.
- Legs: `--toggles`, `--panel appmenu`.
