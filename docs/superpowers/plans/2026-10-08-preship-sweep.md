# Pre-ship sweep, 2026-10-08

Tree: main at 43e163a9, run through dev/vm-lock.sh just vm-smoke, one leg per run, two VM slots. Skipped: --screensaver-gif, --r0-measure.

Totals: 134 runs, 133 PASS, 0 FLAKY, 1 FAIL (--radio).

- `--radio` fails twice, same way: `SMOKE_FAIL: media outputs does not list the second sink` (media outputs is `[]`, `canRoute` false while the radio player plays).
- `--notify-emerge`, `--tooltip` and `--tooltip-travel` exited 1 in about a second on a usage line (they ride `--pantheon` / `--panel <name>`). Rerun with the rider they need, all three pass; listed once below as PASS.
- `--menu-budget` (known to read high in the VM): worst open first_commit 11ms, configure 10ms, bar_gap 57ms, shell share 8ms, compositor wait 56ms, 5 opens, frame 16ms. Run passed.

| Leg | Result | Seconds |
| --- | --- | --- |
| `--pantheon --gallery` | PASS | 57 |
| `--retro --gallery` | PASS | 58 |
| `--gallery` | PASS | 57 |
| `--bar-position top` | PASS | 56 |
| `--bar-position left` | PASS | 56 |
| `--bar-position bottom` | PASS | 57 |
| `--bar-position right` | PASS | 57 |
| `SMOKE_WALLPAPER_DITHER=1 --wallpaper` | PASS | 58 |
| `--idle` | PASS | 187 |
| `--idle --bluez-rssi` | PASS | 196 |
| `--menu-budget` | PASS | 57 |
| `--panel-at 1` | PASS | 57 |
| `--panel appmenu` | PASS | 56 |
| `--panel audio` | PASS | 56 |
| `--panel calendar` | PASS | 56 |
| `--panel network` | PASS | 56 |
| `--panel bluetooth` | PASS | 56 |
| `--panel earbuds` | PASS | 56 |
| `--panel iphone` | PASS | 56 |
| `--panel dualsense` | PASS | 55 |
| `--panel power` | PASS | 56 |
| `--panel weather` | PASS | 56 |
| `--panel media` | PASS | 55 |
| `--panel github` | PASS | 56 |
| `--panel usage` | PASS | 57 |
| `--panel tailscale` | PASS | 56 |
| `--panel systemupdate` | PASS | 56 |
| `--panel display` | PASS | 56 |
| `--panel monitor` | PASS | 56 |
| `--panel radio` | PASS | 56 |
| `--airplay` | PASS | 56 |
| `--app-grid` | PASS | 59 |
| `--appmenu` | PASS | 56 |
| `--bar-adaptive` | PASS | 57 |
| `--bar-layout` | PASS | 56 |
| `--bar-room` | PASS | 56 |
| `--bar-title` | PASS | 56 |
| `--caffeinate` | PASS | 56 |
| `--capture-edit` | PASS | 57 |
| `--capture` | PASS | 57 |
| `--center` | PASS | 75 |
| `--chevron-quiet` | PASS | 63 |
| `--chevron` | PASS | 57 |
| `--clipboard` | PASS | 58 |
| `--clipssh-image` | PASS | 56 |
| `--clipssh` | PASS | 57 |
| `--config-reload` | PASS | 57 |
| `--console` | PASS | 56 |
| `--deform` | PASS | 62 |
| `--display` | PASS | 56 |
| `--dump` | PASS | 57 |
| `--device-routes` | PASS | 205 |
| `--earbuds` | PASS | 84 |
| `--emoji` | PASS | 57 |
| `--flexoki` | PASS | 56 |
| `--frame` | PASS | 56 |
| `--fullscreen` | PASS | 57 |
| `--gpu` | PASS | 56 |
| `--grid-relaunch` | PASS | 57 |
| `--hdr` | PASS | 56 |
| `--hotcorner-relock` | PASS | 58 |
| `--headset-card` | PASS | 70 |
| `--hotcorner` | PASS | 56 |
| `--instance` | PASS | 56 |
| `--iphone` | PASS | 80 |
| `--join` | PASS | 125 |
| `--keybinds` | PASS | 57 |
| `--lights` | PASS | 56 |
| `--localsend` | PASS | 56 |
| `--lock-media` | PASS | 59 |
| `--lock` | PASS | 60 |
| `--lyrics-blur` | PASS | 60 |
| `--media-progress` | PASS | 142 |
| `--media` | PASS | 57 |
| `--menu-actions` | PASS | 56 |
| `--lyrics` | PASS | 326 |
| `--menu-morph` | PASS | 57 |
| `--menu-emerge` | PASS | 96 |
| `--menu-rows` | PASS | 63 |
| `--menu` | PASS | 59 |
| `--mic` | PASS | 56 |
| `--mirror` | PASS | 61 |
| `--monitor` | PASS | 57 |
| `--nightlight` | PASS | 57 |
| `--nix-run` | PASS | 56 |
| `--motion-art` | PASS | 185 |
| `--notify-close` | PASS | 58 |
| `--notify` | PASS | 56 |
| `--ocr` | PASS | 57 |
| `--osd` | PASS | 62 |
| `--overnight` | PASS | 56 |
| `--panel-anchor` | PASS | 56 |
| `--panel-emerge` | PASS | 60 |
| `--panel-handoff` | PASS | 57 |
| `--panel-keys` | PASS | 56 |
| `--picker` | PASS | 57 |
| `--plugins` | PASS | 59 |
| `--polkit` | PASS | 58 |
| `--panel-morph` | PASS | 190 |
| `--processes` | PASS | 56 |
| `--radio-atlas` | PASS | 57 |
| `--record` | PASS | 74 |
| `--radio` | FAIL | 57 |
| `--reminder` | PASS | 57 |
| `--screenshot` | PASS | 63 |
| `--screensaver` | PASS | 110 |
| `--share` | PASS | 57 |
| `--shoulders` | PASS | 57 |
| `--showcase` | PASS | 62 |
| `--sleep` | PASS | 56 |
| `--spectrum` | PASS | 56 |
| `--spaces` | PASS | 86 |
| `--speedtest` | PASS | 57 |
| `--switcher-keys` | PASS | 95 |
| `--switcher-off` | PASS | 57 |
| `--switcher` | PASS | 58 |
| `--systemupdate` | PASS | 56 |
| `--theme-auto` | PASS | 56 |
| `--theme-toggle` | PASS | 56 |
| `--toggles` | PASS | 56 |
| `--toast-motion` | PASS | 74 |
| `--tray-overflow` | PASS | 57 |
| `--tray` | PASS | 56 |
| `--visualizer` | PASS | 56 |
| `--visualizer-styles` | PASS | 71 |
| `--wallpaper` | PASS | 57 |
| `--wheel` | PASS | 59 |
| `--workspaces` | PASS | 58 |
| `--wifi` | PASS | 195 |
| `--panel audio --tooltip` (replaces the bare leg) | PASS | 64 |
| `--pantheon --notify-emerge` (replaces the bare leg) | PASS | 133 |
| `--panel audio --tooltip-travel` (replaces the bare leg) | PASS | 65 |
| `just vm-greeter` | PASS | |
| `dev/install-check.sh trixie` | PASS | |
