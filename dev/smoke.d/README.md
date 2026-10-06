# Smoke legs

`dev/smoke.sh` is the scaffold (isolated HOME, settings fixture, private
bus, session mode, binaries, Hyprland config, shell launch, `SMOKE_OK`
frame, teardown) and sources every file here. A leg defines:

- `leg_<n>_flag` `"--flag"` or `"--flag <arg>"` (`leg_arg <n>` reads it);
  `leg_<n>_order` its place in the flags, fragments, autostart lines and
  results (default 500); `leg_<n>_needs` binaries to resolve.
- `leg_<n>_fixture_window` `keep` to leave the base run's fixture window in
  the frame; `leg_<n>_validate` usage checks, run before the build.
- `leg_<n>_fixture` `settings_fragment '<json>'` and staged files;
  `leg_<n>_timing` `leg_timing <delay> <timeout> [tail_gap]`, max-merged.
- `leg_<n>_drive` writes the drive scripts, echoes their autostart lines (`hypr_exec_once`),
  may `add_cleanup '<line>'`; `leg_<n>_assert` prints `SMOKE_*`, calls `fail`.
- `leg_<n>_wayland_debug=1` runs the shell under `WAYLAND_DEBUG`, so
  `$shell_log_path` carries its wire traffic for an assert that has to read
  what the shell sent rather than what the screen shows (`--frame`).
- `leg_<n>_shell <path>` writes the shell start script at `<path>` in place
  of the scaffold's, for a leg that runs some other build of the shell
  (`--native`). It still logs to `$shell_log_path` and may write the
  shell's pid to `$shot_dir/shell.pid` for the memory sample.
- `leg_<n>_rust=1` lets the leg run under `FS_IMPL=rust`, which refuses
  every other leg: it drives the spike's control socket itself
  (`--r0-measure`).
- `leg_<n>_takeover` runs the whole thing itself and exits, for a leg that
  cannot share the one session (`--screensaver-gif` needs one per effect).
  It runs with the build done, the binaries resolved and the bus baseline
  taken, and owns its own `SMOKE_OK` line.

Exported: `shot_dir`, `iso_home`, `shell_path`, `shell_log_path`, `*_bin`,
`write_script`, `leg_on <n>`, `host_notifications_owner_after`. Legs sharing a surface wait
on the owner's marker (`picker_done_path`); one covering the whole output
starts at its `<n>_t0`, past any desktop sampler (`--wallpaper` sets 16).
