# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --frame pins `frame.thickness` (10) in the settings fixture, so the screen
# frame paints round the bar for the run's own frame, and rides whichever
# bar edge the run has (`--bar-position left --frame` is the frame wrapping
# a left bar). What the screenshot cannot say is asserted off `hyprctl -j
# layers`: the bar's own window grown to the size of the output (it paints
# the ring, Bar.qml), and a formalshell:frame-zone on every edge, since
# those zones are what keep windows inside the cut-out.
leg_frame_flag="--frame"
leg_frame_order=190
leg_frame_needs="jq"

frame_layers_path="$shot_dir/frame-layers.json"
frame_monitors_path="$shot_dir/frame-monitors.json"

leg_frame_fixture() {
  settings_fragment ', "frame": {"thickness": 10, "radius": 20}'
}

leg_frame_timing() {
  leg_timing 8 30
}

leg_frame_drive() {
  local script="$shot_dir/frame-drive.sh"
  write_script "$script" <<EOS
#!/usr/bin/env bash
sleep 5
"$hyprctl_bin" -j layers > "$frame_layers_path" 2>&1
"$hyprctl_bin" -j monitors > "$frame_monitors_path" 2>&1
EOS
  echo "exec-once = bash $script"
}

leg_frame_assert() {
  local box mw mh zones edge
  if [ ! -s "$frame_layers_path" ] || [ ! -s "$frame_monitors_path" ]; then
    fail "no layer or monitor dump produced for the frame check"
  fi
  box=$("$jq_bin" -r '[.[] | .levels[] | .[] | select(.namespace == "formalshell:bar")] | first | "\(.x) \(.y) \(.w) \(.h)"' "$frame_layers_path" 2>/dev/null)
  read -r mw mh <<< "$("$jq_bin" -r 'first | "\(.width / .scale | floor) \(.height / .scale | floor)"' "$frame_monitors_path")"
  echo "framed bar window: $box on ${mw}x${mh}"
  if [ "$box" != "0 0 $mw $mh" ]; then
    fail "with the frame on the bar's window should span the whole output, got: $box"
  fi
  zones=$("$jq_bin" -r '[.[] | .levels[] | .[] | select(.namespace == "formalshell:frame-zone")] | length' "$frame_layers_path")
  echo "frame zones: $zones"
  # One per edge, the bar's included: its window reserves nothing itself
  # while it is the whole output.
  if [ "$zones" -ne 4 ]; then
    fail "expected four frame exclusion zones (one per edge), got $zones"
  fi
  if leg_on bar_position; then
    edge=$(leg_arg bar_position)
  else
    edge=top
  fi
  echo "frame wraps a $edge bar"
}
