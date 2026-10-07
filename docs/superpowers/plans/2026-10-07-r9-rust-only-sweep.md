# R9 rust-only leg sweep

Run 2026-10-07 after Task 2 (the QML shell deleted), on the worktree branch at 276bbb60 (main 4f706b0d merged), gpu rerun on f18a3dda. Every leg through dev/vm-lock.sh just vm-smoke, one leg per run, two slots, one retry on failure. Skipped: --screensaver-gif (writes docs/media), --r0-measure (a 600 s measurement with no verdict), --installed (run through dev/install-check.sh below).

- 114 runs: 113 PASS, 0 FLAKY, 1 FAIL
- just vm-greeter: SMOKE_GREETER_OK, on a slot 0 VM rebooted onto the new testvm image (the first run of the rust greeter there; it needed a299ee83)
- dev/install-check.sh trixie: PASS (slot 1; slot 0 had 5.9 GB free and ran out of space building the trixie image)

Same riders as the final sweep: panel as --panel audio, panel_at as --panel-at 1, tooltip and tooltip_travel ride --panel audio, notify_emerge rides --pantheon, pantheon+gallery and retro+gallery, bar_position_<edge> for the four edges, wallpaper_dither is SMOKE_WALLPAPER_DITHER=1 --wallpaper. idle is new since the final sweep.

| leg | result | cause |
|---|---|---|
| airplay | PASS |  |
| app_grid | PASS |  |
| appmenu | PASS |  |
| bar_adaptive | PASS |  |
| bar_layout | PASS |  |
| bar_position_bottom | PASS |  |
| bar_position_left | PASS |  |
| bar_position_right | PASS |  |
| bar_position_top | PASS |  |
| bar_room | PASS |  |
| bar_title | FAIL | fails the same way on main 4de50f54 (baseline run): the title cell alone after the settings rewrite reports natural 37, extent 37, not its ceiling 248; pre-existing, suspected da2f495b (text shaped off the ui loop) |
| caffeinate | PASS |  |
| capture | PASS |  |
| capture_edit | PASS |  |
| center | PASS |  |
| chevron | PASS |  |
| chevron_quiet | PASS |  |
| clipboard | PASS |  |
| clipssh | PASS |  |
| clipssh_image | PASS |  |
| config_reload | PASS |  |
| console | PASS |  |
| deform | PASS |  |
| device_routes | PASS |  |
| display | PASS |  |
| dump | PASS |  |
| earbuds | PASS |  |
| emoji | PASS |  |
| flexoki | PASS |  |
| frame | PASS |  |
| fullscreen | PASS |  |
| gallery | PASS |  |
| gpu | PASS | first run read tests/fixtures/gpu-hybrid.txt, gone with tests/; fixed in f18a3dda and rerun |
| grid_relaunch | PASS |  |
| hdr | PASS |  |
| headset_card | PASS |  |
| hotcorner | PASS |  |
| hotcorner_relock | PASS |  |
| instance | PASS |  |
| iphone | PASS |  |
| join | PASS |  |
| keybinds | PASS |  |
| lights | PASS |  |
| localsend | PASS |  |
| lock | PASS |  |
| lock_media | PASS |  |
| lyrics | PASS |  |
| lyrics_blur | PASS |  |
| media | PASS |  |
| media_progress | PASS |  |
| menu | PASS |  |
| menu_actions | PASS |  |
| menu_budget | PASS |  |
| menu_emerge | PASS |  |
| menu_morph | PASS |  |
| menu_rows | PASS |  |
| mic | PASS |  |
| mirror | PASS |  |
| monitor | PASS |  |
| motion_art | PASS |  |
| nightlight | PASS |  |
| nix_run | PASS |  |
| notify | PASS |  |
| notify_close | PASS |  |
| notify_emerge | PASS |  |
| ocr | PASS |  |
| osd | PASS |  |
| overnight | PASS |  |
| panel | PASS |  |
| panel_anchor | PASS |  |
| panel_at | PASS |  |
| panel_emerge | PASS |  |
| panel_handoff | PASS |  |
| panel_keys | PASS |  |
| panel_morph | PASS |  |
| pantheon+gallery | PASS |  |
| picker | PASS |  |
| plugins | PASS |  |
| polkit | PASS |  |
| processes | PASS |  |
| radio | PASS |  |
| radio_atlas | PASS |  |
| record | PASS |  |
| reminder | PASS |  |
| retro+gallery | PASS |  |
| screensaver | PASS |  |
| screenshot | PASS |  |
| share | PASS |  |
| shoulders | PASS |  |
| showcase | PASS |  |
| sleep | PASS |  |
| spaces | PASS |  |
| spectrum | PASS |  |
| speedtest | PASS |  |
| switcher | PASS |  |
| switcher_keys | PASS |  |
| switcher_off | PASS |  |
| systemupdate | PASS |  |
| theme_auto | PASS |  |
| theme_toggle | PASS |  |
| toast_motion | PASS |  |
| toggles | PASS |  |
| tooltip | PASS |  |
| tooltip_travel | PASS |  |
| tray | PASS |  |
| tray_overflow | PASS |  |
| visualizer | PASS |  |
| visualizer_styles | PASS |  |
| wallpaper | PASS |  |
| wallpaper_dither | PASS |  |
| wheel | PASS |  |
| wifi | PASS |  |
| workspaces | PASS |  |
| idle | PASS |  |
