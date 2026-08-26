# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --retro pins `theme.preset` to `retro` in the settings fixture and drives
# nothing itself: it rides whichever legs it is combined with, so
# `--retro --gallery` is the gallery sheet square, mono and dithered, and
# `--retro --panel network` is that panel under the same preset. The preset
# is read at startup, which is why it is a fixture and not an IPC call, and
# why there is nothing to assert here beyond the frame the other leg takes.
leg_retro_flag="--retro"
leg_retro_order=5

leg_retro_fixture() {
  settings_fragment ', "theme": {"preset": "retro"}'
}
