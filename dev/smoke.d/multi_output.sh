# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --multi-output: the wallpaper, the bar and the frame's four zones on every
# output, read off the compositor's own layer list. g815's shape: a second
# output to the right of the first at scale 1.25, here a headless one created
# after the shell started (so it reaches the shell as a new wl_output, not in
# the first roundtrip) and given its mode, position and scale with
# `hl.monitor`. Each output is grabbed on its own with `grim -o`, and the
# frame the run ends on covers both.
#
# The second output is then removed: the shell has to drop that output's
# surfaces and keep the first one's, still running.
leg_multi_output_flag="--multi-output"
leg_multi_output_order=217
leg_multi_output_needs="jq"

multi_output_second="FS-MULTI"
multi_output_create="$shot_dir/multi-output-create.txt"
multi_output_monitors="$shot_dir/multi-output-monitors.json"
multi_output_layers_one="$shot_dir/multi-output-layers-one.json"
multi_output_layers_two="$shot_dir/multi-output-layers-two.json"
multi_output_layers_gone="$shot_dir/multi-output-layers-gone.json"
multi_output_first_png="$shot_dir/multi-output-first.png"
multi_output_second_png="$shot_dir/multi-output-second.png"

leg_multi_output_fixture() {
  settings_fragment ', "frame": {"thickness": 6, "radius": 20}'
}

leg_multi_output_timing() {
  leg_timing 13 40
}

leg_multi_output_drive() {
  local script="$shot_dir/multi-output-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 4
"$hyprctl_bin" -j layers > "$multi_output_layers_one" 2>&1
first=\$("$hyprctl_bin" -j monitors | "$jq_bin" -r '.[0].name')
width=\$("$hyprctl_bin" -j monitors | "$jq_bin" -r '.[0].width')
"$hyprctl_bin" output create headless "$multi_output_second" > "$multi_output_create" 2>&1
"$hyprctl_bin" eval "hl.monitor({ output = \\"$multi_output_second\\", mode = \\"1600x1000@60\\", position = \\"\${width}x0\\", scale = 1.25 })" >> "$multi_output_create" 2>&1
sleep 4
"$hyprctl_bin" -j monitors > "$multi_output_monitors" 2>&1
"$hyprctl_bin" -j layers > "$multi_output_layers_two" 2>&1
"$grim_bin" -o "\$first" "$multi_output_first_png" > /dev/null 2>&1
"$grim_bin" -o "$multi_output_second" "$multi_output_second_png" > /dev/null 2>&1
sleep 6
"$hyprctl_bin" output remove "$multi_output_second" >> "$multi_output_create" 2>&1
sleep 3
"$hyprctl_bin" -j layers > "$multi_output_layers_gone" 2>&1
EOF
  hypr_exec_once "bash $script"
}

# Surfaces on output $2 under namespace $3 in layers dump $1.
_multi_output_count() {
  "$jq_bin" -r --arg o "$2" --arg ns "$3" '[.[$o].levels[]?[]? | select(.namespace == $ns)] | length' "$1" 2>/dev/null
}

# Every output in dump $1 carrying one wallpaper, one bar and four frame zones.
_multi_output_check() {
  local dump="$1" when="$2" out wall bar zones
  for out in $("$jq_bin" -r 'keys[]' "$dump"); do
    wall=$(_multi_output_count "$dump" "$out" "formalshell:wallpaper")
    bar=$(_multi_output_count "$dump" "$out" "formalshell:bar")
    zones=$(_multi_output_count "$dump" "$out" "formalshell:frame-zone")
    echo "$when: $out wallpaper=$wall bar=$bar frame-zone=$zones"
    [ "$wall" = 1 ] || fail "$when: $out carries $wall wallpaper surfaces, want 1"
    [ "$bar" = 1 ] || fail "$when: $out carries $bar bar surfaces, want 1"
    [ "$zones" = 4 ] || fail "$when: $out carries $zones frame zones, want 4"
  done
}

leg_multi_output_assert() {
  local f n
  for f in "$multi_output_layers_one" "$multi_output_layers_two" "$multi_output_layers_gone" "$multi_output_monitors"; do
    [ -s "$f" ] || fail "multi-output leg produced no $(basename "$f")"
  done
  cat "$multi_output_create"
  "$jq_bin" -e --arg s "$multi_output_second" '.[] | select(.name == $s) | (.scale - 1.25 | fabs) < 0.01' "$multi_output_monitors" > /dev/null \
    || fail "the second output is not at scale 1.25: $("$jq_bin" -c '.[] | {name,scale,x,width}' "$multi_output_monitors")"

  n=$("$jq_bin" -r 'keys | length' "$multi_output_layers_one")
  [ "$n" = 1 ] || fail "expected one output before the second was created, got $n"
  _multi_output_check "$multi_output_layers_one" "one output"

  n=$("$jq_bin" -r 'keys | length' "$multi_output_layers_two")
  [ "$n" = 2 ] || fail "expected two outputs in the layer list, got $n"
  _multi_output_check "$multi_output_layers_two" "two outputs"
  echo "SMOKE_MULTI_OUTPUT wallpaper, bar and frame on both outputs, $multi_output_second at scale 1.25"

  "$jq_bin" -e --arg s "$multi_output_second" 'has($s) | not' "$multi_output_layers_gone" > /dev/null \
    || fail "$multi_output_second still listed after its removal"
  _multi_output_check "$multi_output_layers_gone" "after removal"
  echo "SMOKE_MULTI_OUTPUT_REMOVED the first output keeps its chrome once $multi_output_second is gone"

  for f in "$multi_output_first_png" "$multi_output_second_png"; do
    [ -s "$f" ] || fail "no frame at $f"
  done
  echo "SMOKE_MULTI_OUTPUT_FIRST $multi_output_first_png"
  echo "SMOKE_MULTI_OUTPUT_SECOND $multi_output_second_png"
}
