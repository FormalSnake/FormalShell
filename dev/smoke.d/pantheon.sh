# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --pantheon pins `theme.preset` to `pantheon` in the settings fixture and
# drives nothing itself: it rides whichever legs it is combined with, so
# `--pantheon --gallery` is the gallery sheet in elementary's material
# (raised buttons over sunken troughs, cards on a cast) and `--pantheon
# --notify` is the same toast under it. The preset is read at startup, which
# is why it is a fixture and not an IPC call, and why there is nothing to
# assert here beyond the frame the other leg takes.
leg_pantheon_flag="--pantheon"
leg_pantheon_order=6

leg_pantheon_fixture() {
  settings_fragment ', "theme": {"preset": "pantheon"}'
}
