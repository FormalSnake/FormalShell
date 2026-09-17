# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --pantheon pins `theme.preset` to `pantheon` in the settings fixture and
# drives nothing itself, the same rider retro.sh is: `--pantheon --gallery`
# is the gallery sheet with elementary's relief on every control and a
# shadow under every card, `--pantheon --panel audio` that panel casting
# one. The preset is read at startup, which is why it is a fixture and not
# an IPC call, and why there is nothing to assert here beyond the frame the
# other leg takes.
leg_pantheon_flag="--pantheon"
leg_pantheon_order=6

leg_pantheon_fixture() {
  settings_fragment ', "theme": {"preset": "pantheon"}'
}
