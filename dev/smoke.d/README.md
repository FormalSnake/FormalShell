# Smoke legs

`dev/smoke.sh` is the scaffold (isolated HOME, settings fixture, private
bus, session mode, binaries, Hyprland config, shell launch, `SMOKE_OK`
frame, teardown) and sources every file here. A leg defines:

- `leg_<n>_flag` `"--flag"` or `"--flag <arg>"` (`leg_arg <n>` reads it);
  `leg_<n>_order` its place in the flags, fragments, `exec-once` lines and
  results (default 500); `leg_<n>_needs` binaries to resolve.
- `leg_<n>_fixture_window` `keep` to leave the base run's fixture window in
  the frame; `leg_<n>_validate` usage checks, run before the build.
- `leg_<n>_fixture` `settings_fragment '<json>'` and staged files;
  `leg_<n>_timing` `leg_timing <delay> <timeout> [tail_gap]`, max-merged.
- `leg_<n>_drive` writes the drive scripts, echoes their `exec-once` lines,
  may `add_cleanup '<line>'`; `leg_<n>_assert` prints `SMOKE_*`, calls `fail`.

Exported: `shot_dir`, `iso_home`, `shell_path`, `*_bin`, `write_script`,
`leg_on <n>`, `host_notifications_owner_after`. Legs sharing a surface wait
on the owner's marker (`picker_done_path`); one covering the whole output
starts at its `<n>_t0`, past any desktop sampler (`--wallpaper` sets 16).
