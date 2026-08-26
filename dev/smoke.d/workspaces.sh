# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --workspaces proves the bar's workspace indicator is ONE pill that travels
# rather than a per-dot width (M48). The dots hold fixed slots, so the only
# thing that may move between two settled frames is the pill.
#
# A second foot window is spawned on workspace 2 first: workspaces.js hides
# an empty unfocused workspace, so without it the second dot would vanish on
# the way back and the frames would be comparing different rows rather than
# the same row with the pill in two places.
#
# `hyprctl dispatch workspace 1` then fires and the run takes a burst of
# frames across the next half second, plus a settled one three seconds on.
# Every frame is cropped to the workspace cell alone, never the whole bar:
# the switch changes the active-window title two cells over, so a wider crop
# would differ between any two frames whether or not the indicator moved.
#
# Two assertions. The settled cells either side of the switch must differ,
# which is the pill occupying a different slot. And at least one burst frame
# must differ from the settled cell, which says the indicator was still
# resolving after the switch had landed: at `motion.enabled=false` every one
# of these tokens is 0 and all four frames would be the settled cell exactly.
#
# What the burst deliberately does NOT claim is a picture of the pill
# stretched between the two slots. A nested software-rendered session cannot
# pin a 250ms chrome animation to a chosen frame (grim's own capture is a
# large fraction of it, and the compositor's event has to reach the shell
# first: at 80ms the bar was still painting the old workspace entirely). The
# durations themselves are asserted in tests/tst_theme_tokens.qml.
leg_workspaces_flag="--workspaces"
leg_workspaces_order=195
leg_workspaces_needs="foot convert"
leg_workspaces_fixture_window=keep

workspaces_two_path="$shot_dir/workspaces-two.png"
workspaces_settled_path="$shot_dir/workspaces-settled.png"
workspaces_dispatch_path="$shot_dir/workspaces-dispatch.txt"
workspaces_crop_dir="$shot_dir/workspaces-crops"
# The workspace cell alone, at the left end of the bar's left region, past
# the launcher cell beside it.
workspaces_crop_geometry="50x24+48+8"
workspaces_burst="1 2 3"

workspaces_burst_path() {
  echo "$shot_dir/workspaces-moving-$1.png"
}

workspaces_crop_path() {
  echo "$workspaces_crop_dir/cell-$(basename "$1")"
}

leg_workspaces_timing() {
  leg_timing 16 50
}

leg_workspaces_drive() {
  local script="$shot_dir/workspaces-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 5
"$hyprctl_bin" dispatch workspace 2 > "$workspaces_dispatch_path" 2>&1
sleep 1
"$hyprctl_bin" dispatch exec "$foot_bin --app-id=formalshell-smoke-workspace --title='formalshell workspace two' sh -c 'sleep 300'" >> "$workspaces_dispatch_path" 2>&1
sleep 3
"$grim_bin" "$workspaces_two_path" > /dev/null 2>&1
"$hyprctl_bin" dispatch workspace 1 >> "$workspaces_dispatch_path" 2>&1
sleep 0.15
"$grim_bin" "$(workspaces_burst_path 1)" > /dev/null 2>&1
sleep 0.15
"$grim_bin" "$(workspaces_burst_path 2)" > /dev/null 2>&1
sleep 0.15
"$grim_bin" "$(workspaces_burst_path 3)" > /dev/null 2>&1
sleep 3
"$grim_bin" "$workspaces_settled_path" > /dev/null 2>&1
EOF
  add_cleanup "pkill -f formalshell-smoke-workspace 2>/dev/null || true"
  echo "exec-once = bash $script"
}

leg_workspaces_assert() {
  local f n crop crop_two crop_settled caught
  mkdir -p "$workspaces_crop_dir"
  for f in "$workspaces_two_path" "$workspaces_settled_path"; do
    if [ ! -f "$f" ]; then
      fail "no workspace frame produced at $f"
    fi
  done
  cat "$workspaces_dispatch_path"
  echo "SMOKE_WORKSPACES_TWO $workspaces_two_path"
  echo "SMOKE_WORKSPACES_SETTLED $workspaces_settled_path"
  for n in $workspaces_burst; do
    f=$(workspaces_burst_path "$n")
    if [ ! -f "$f" ]; then
      fail "no workspace burst frame produced at $f"
    fi
    echo "SMOKE_WORKSPACES_MOVING_$n $f"
  done

  for f in "$workspaces_two_path" "$workspaces_settled_path" \
      $(for n in $workspaces_burst; do workspaces_burst_path "$n"; done); do
    crop=$(workspaces_crop_path "$f")
    if ! $convert_bin "$f" -crop "$workspaces_crop_geometry" +repage "$crop"; then
      fail "could not crop the workspace cell out of $f"
    fi
  done
  crop_two=$(workspaces_crop_path "$workspaces_two_path")
  crop_settled=$(workspaces_crop_path "$workspaces_settled_path")
  echo "SMOKE_WORKSPACES_CELL_TWO $crop_two"
  echo "SMOKE_WORKSPACES_CELL_SETTLED $crop_settled"

  if cmp -s "$crop_two" "$crop_settled"; then
    fail "the workspace cell is identical before and after the switch: the indicator did not move"
  fi

  # Still resolving after the switch landed. With every motion token at 0
  # the cell would already be the settled one in all three burst frames.
  caught=""
  for n in $workspaces_burst; do
    crop=$(workspaces_crop_path "$(workspaces_burst_path "$n")")
    echo "SMOKE_WORKSPACES_CELL_MOVING_$n $crop"
    if [ -z "$caught" ] && ! cmp -s "$crop" "$crop_settled"; then
      caught="$crop"
    fi
  done
  if [ -z "$caught" ]; then
    fail "every burst frame is already the settled cell: the indicator changed with no transition at all"
  fi
}
