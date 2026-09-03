# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --fullscreen proves the fullscreen chrome auto-hide (fullscreen.hideChrome,
# default on): while a focused fullscreen window covers an output, the bar,
# the screen frame's zones and the hot corners all leave the overlay/top
# layers, so the window reaches Hyprland's solitary / direct-scanout path
# (nothing mapped above it), and they all come straight back when it leaves
# fullscreen. The frame is pinned on so all three chrome kinds are present to
# begin with.
#
# The base run's own focused fixture window is what gets fullscreened
# (leg_fullscreen_fixture_window=keep), so `hyprctl dispatch fullscreen 2`
# lands on it. Three `hyprctl -j layers` dumps off one timeline: before, while
# fullscreen, and after `fullscreen 0`. The claim is read off the compositor's
# own layer list, not the pixels: the formalshell chrome namespaces are gone
# in the middle dump and back to their starting counts in the last one, and
# `hyprctl -j clients` confirms a window really was fullscreen in the middle
# (so the disappearance is the cause under test, not a window that closed).
leg_fullscreen_flag="--fullscreen"
leg_fullscreen_order=200
leg_fullscreen_needs="jq"
leg_fullscreen_fixture_window=keep

fullscreen_before_layers="$shot_dir/fullscreen-before-layers.json"
fullscreen_on_layers="$shot_dir/fullscreen-on-layers.json"
fullscreen_after_layers="$shot_dir/fullscreen-after-layers.json"
fullscreen_on_clients="$shot_dir/fullscreen-on-clients.json"
fullscreen_before_path="$shot_dir/fullscreen-before.png"
fullscreen_on_path="$shot_dir/fullscreen-on.png"
fullscreen_after_path="$shot_dir/fullscreen-after.png"

leg_fullscreen_fixture() {
  settings_fragment ', "frame": {"thickness": 10, "radius": 20}'
}

leg_fullscreen_timing() {
  leg_timing 16 50
}

leg_fullscreen_drive() {
  local script="$shot_dir/fullscreen-drive.sh"
  write_script "$script" <<EOS
#!/usr/bin/env bash
sleep 5
"$hyprctl_bin" -j layers > "$fullscreen_before_layers" 2>&1
"$grim_bin" "$fullscreen_before_path" > /dev/null 2>&1
"$hyprctl_bin" dispatch fullscreen 2 > /dev/null 2>&1
sleep 3
"$hyprctl_bin" -j layers > "$fullscreen_on_layers" 2>&1
"$hyprctl_bin" -j clients > "$fullscreen_on_clients" 2>&1
"$grim_bin" "$fullscreen_on_path" > /dev/null 2>&1
"$hyprctl_bin" dispatch fullscreen 0 > /dev/null 2>&1
sleep 3
"$hyprctl_bin" -j layers > "$fullscreen_after_layers" 2>&1
"$grim_bin" "$fullscreen_after_path" > /dev/null 2>&1
EOS
  echo "exec-once = bash $script"
}

# Count layer surfaces across every output whose namespace starts with the
# given prefix (the frame-zone namespace is exactly "formalshell:frame-zone",
# the bar "formalshell:bar", the hot corners "formalshell:hotcorner").
_fullscreen_count() {
  "$jq_bin" -r --arg ns "$2" '[.[] | .levels[] | .[] | select(.namespace == $ns)] | length' "$1" 2>/dev/null
}

leg_fullscreen_assert() {
  local f
  for f in "$fullscreen_before_layers" "$fullscreen_on_layers" "$fullscreen_after_layers" "$fullscreen_on_clients"; do
    [ -s "$f" ] || fail "no dump produced at $f"
  done

  local bar_before frame_before corner_before
  bar_before=$(_fullscreen_count "$fullscreen_before_layers" "formalshell:bar")
  frame_before=$(_fullscreen_count "$fullscreen_before_layers" "formalshell:frame-zone")
  corner_before=$(_fullscreen_count "$fullscreen_before_layers" "formalshell:hotcorner")
  echo "before: bar=$bar_before frame-zone=$frame_before hotcorner=$corner_before"
  [ "$bar_before" -ge 1 ] || fail "no bar surface before fullscreen"
  [ "$frame_before" -eq 4 ] || fail "expected four frame zones before fullscreen, got $frame_before"

  # A window really is fullscreen in the middle dump, so the chrome vanishing
  # is the auto-hide firing, not the fixture window having closed.
  local fs_windows
  fs_windows=$("$jq_bin" -r '[.[] | select(.fullscreen != 0 and .fullscreen != false)] | length' "$fullscreen_on_clients" 2>/dev/null)
  echo "fullscreen windows while on: $fs_windows"
  [ "${fs_windows:-0}" -ge 1 ] || fail "no window was actually fullscreen; the hide would be untested"

  local bar_on frame_on corner_on
  bar_on=$(_fullscreen_count "$fullscreen_on_layers" "formalshell:bar")
  frame_on=$(_fullscreen_count "$fullscreen_on_layers" "formalshell:frame-zone")
  corner_on=$(_fullscreen_count "$fullscreen_on_layers" "formalshell:hotcorner")
  echo "while fullscreen: bar=$bar_on frame-zone=$frame_on hotcorner=$corner_on"
  [ "$bar_on" -eq 0 ] || fail "bar stayed mapped under fullscreen ($bar_on), blocking scanout"
  [ "$frame_on" -eq 0 ] || fail "frame zones stayed mapped under fullscreen ($frame_on)"
  [ "$corner_on" -eq 0 ] || fail "hot corners stayed mapped under fullscreen ($corner_on)"

  local bar_after frame_after corner_after
  bar_after=$(_fullscreen_count "$fullscreen_after_layers" "formalshell:bar")
  frame_after=$(_fullscreen_count "$fullscreen_after_layers" "formalshell:frame-zone")
  corner_after=$(_fullscreen_count "$fullscreen_after_layers" "formalshell:hotcorner")
  echo "after: bar=$bar_after frame-zone=$frame_after hotcorner=$corner_after"
  [ "$bar_after" -eq "$bar_before" ] || fail "bar did not return after fullscreen ($bar_after vs $bar_before)"
  [ "$frame_after" -eq "$frame_before" ] || fail "frame zones did not return after fullscreen ($frame_after vs $frame_before)"
  [ "$corner_after" -eq "$corner_before" ] || fail "hot corners did not return after fullscreen ($corner_after vs $corner_before)"

  echo "SMOKE_FULLSCREEN_BEFORE $fullscreen_before_path"
  echo "SMOKE_FULLSCREEN_ON $fullscreen_on_path"
  echo "SMOKE_FULLSCREEN_AFTER $fullscreen_after_path"
}
