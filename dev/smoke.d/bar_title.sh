# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --bar-title focuses a window whose title is far longer than any strip, in
# a strip crowded with six `custom:` CommandModules on the right, and reads
# the result off `bar room` (Ipc/BarIpc.qml): the title's budget is the room
# its region actually has (Bar/layout.js's labelBudgets), the label is drawn
# at exactly that budget with the marquee running, and no two cells on the
# strip intersect, none is cut by its region's clip, none runs past the
# strip's own end insets and no region hid a cell to make room. "At its
# budget" is read off the rects too: either the strip has no slack left, or
# the title cell stops one gap short of the centre region's first cell.
#
# Rides `--bar-position <edge>`, which pins the edge in this leg's own `bar`
# key: a left or right bar turns the title and runs every region down the
# strip, which is where cells used to land on top of each other. Two frames
# a second apart, `bar-title.png` and `bar-title-later.png`, are the marquee
# moving, read by eye.
leg_bar_title_flag="--bar-title"
leg_bar_title_order=196
leg_bar_title_needs="foot jq"

bar_title_json_path="$shot_dir/bar-title.json"
bar_title_poll_path="$shot_dir/bar-title-poll.json"
bar_title_png_path="$shot_dir/bar-title.png"
bar_title_later_png_path="$shot_dir/bar-title-later.png"
bar_title_cmd_dir="$shot_dir/bar-title-cmd"
bar_title_samples_dir="$shot_dir/bar-title-samples"
bar_title_text="FormalShell bar title verification with a window title far longer than any strip it could ever sit on so the only thing that decides how much of it shows is the room the bar hands the cell"

leg_bar_title_validate() {
  local other
  for other in bar_layout bar_room chevron join; do
    if leg_on "$other"; then
      echo "usage: --bar-title carries its own bar.layout and cannot combine with --${other//_/-}" >&2
      exit 1
    fi
  done
}

leg_bar_title_fixture() {
  local i position="" modules="" layout_right='"battery", "audio", "network", "bluetooth", "weather", "tray", "bell", "indicators"'
  if leg_on bar_position; then
    position='"position": "'"$(leg_arg bar_position)"'", '
  fi
  mkdir -p "$bar_title_cmd_dir"
  for i in 1 2 3 4 5 6; do
    write_script "$bar_title_cmd_dir/cmd$i.sh" <<EOF
#!/usr/bin/env bash
printf '{"text": "ROOM $i", "tooltip": "", "class": ""}'
EOF
    modules="$modules{\"id\": \"bartitle$i\", \"type\": \"command\", \"command\": [\"bash\", \"$bar_title_cmd_dir/cmd$i.sh\"], \"interval\": 30000},"
    layout_right="$layout_right, \"custom:bartitle$i\""
  done
  modules="${modules%,}"
  settings_fragment ', "bar": {'"$position"'"layout": {"left": ["launcher", "workspaces", "activeWindow"], "center": ["clock", "nowPlaying"], "right": ['"$layout_right"']}, "modules": ['"$modules"']}'
}

leg_bar_title_timing() {
  leg_timing 30 60
}

leg_bar_title_drive() {
  local script="$shot_dir/bar-title-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 2
"$hyprctl_bin" dispatch exec "$foot_bin --app-id=formalshell-bar-title --title='$bar_title_text' sh -c 'sleep 300'"
# Waits for the title to reach the cell rather than sleeping at it; the
# beat after is the label refit (Theme.motion.spatial past the last change)
# and the cells' own width glide settling behind it.
for _ in \$(seq 1 40); do
  "$qs_bin" ipc -p "$shell_path" call bar room > "$bar_title_poll_path" 2>&1
  "$jq_bin" -e '.[0].activeWindow.natural > 1000' "$bar_title_poll_path" > /dev/null 2>&1 && break
  sleep 0.5
done
sleep 3
"$qs_bin" ipc -p "$shell_path" call bar room > "$bar_title_json_path" 2>&1
"$grim_bin" "$bar_title_png_path" > /dev/null 2>&1
sleep 1
"$grim_bin" "$bar_title_later_png_path" > /dev/null 2>&1
# Focus to a short title and back, sampling the strip as fast as the IPC
# answers while the title cell, the centre and both region clips travel.
mkdir -p "$bar_title_samples_dir"
"$hyprctl_bin" dispatch exec "$foot_bin --app-id=formalshell-bar-short --title=short sh -c 'sleep 300'"
for i in \$(seq 1 12); do
  "$qs_bin" ipc -p "$shell_path" call bar room > "$bar_title_samples_dir/to-short-\$i.json" 2>&1
done
"$hyprctl_bin" dispatch focuswindow class:formalshell-bar-title > /dev/null 2>&1
for i in \$(seq 1 12); do
  "$qs_bin" ipc -p "$shell_path" call bar room > "$bar_title_samples_dir/to-long-\$i.json" 2>&1
done
EOF
  echo "exec-once = bash $script"
}

# Shared with --bar-room: every drawn cell in one `bar room` answer held
# against every other and against the strip. Prints one line per defect and
# nothing when the strip is sound.
bar_cells_defects() {
  "$jq_bin" -r '
    .[0] as $b
    | ($b.edge == "left" or $b.edge == "right") as $v
    | $b.cells as $c
    | ([range(0; $c | length) as $i | range($i + 1; $c | length) as $j
        | select($c[$i].x < $c[$j].x + $c[$j].width - 0.5 and $c[$j].x < $c[$i].x + $c[$i].width - 0.5
            and $c[$i].y < $c[$j].y + $c[$j].height - 0.5 and $c[$j].y < $c[$i].y + $c[$i].height - 0.5)
        | "overlap: \($c[$i].name) (\($c[$i].region)) and \($c[$j].name) (\($c[$j].region))"]
      + [$c[] | select(.whole | not) | "cut by its region clip: \(.name)"]
      + [$c[] | (if $v then .y else .x end) as $s | (if $v then .height else .width end) as $w
          | select($s < $b.edgeInset - 0.5 or $s + $w > $b.along - $b.edgeInset + 0.5)
          | "past the strip end: \(.name) at \($s)+\($w) on \($b.along)"])
    | .[]' "$1"
}

leg_bar_title_assert() {
  local defects edge budget natural extent scrolling hidden verdict
  if [ ! -s "$bar_title_json_path" ]; then
    fail "no bar room output produced for --bar-title"
  fi
  cat "$bar_title_json_path"; echo
  echo "SMOKE_BAR_TITLE_STATE $bar_title_json_path"
  edge=$("$jq_bin" -r '.[0].edge' "$bar_title_json_path")
  if leg_on bar_position && [ "$edge" != "$(leg_arg bar_position)" ]; then
    fail "bar room answered for a $edge bar, not the $(leg_arg bar_position) one asked for"
  fi
  read -r budget natural extent scrolling <<< "$("$jq_bin" -r '.[0].activeWindow | "\(.budget) \(.natural) \(.extent) \(.scrolling)"' "$bar_title_json_path")"
  echo "title on a $edge bar: budget=$budget natural=$natural extent=$extent scrolling=$scrolling"
  if ! awk -v b="$budget" -v n="$natural" -v e="$extent" 'BEGIN { exit !(b > 0 && n > b && e >= b - 1 && e <= b + 1) }'; then
    fail "the title is not drawn at a positive budget short of its natural width: budget=$budget natural=$natural extent=$extent"
  fi
  if [ "$scrolling" != "true" ]; then
    fail "the title overflows its budget but its marquee is not running"
  fi
  hidden=$("$jq_bin" -r '[.[0].regions[].hidden] | add' "$bar_title_json_path")
  if [ "$hidden" != "0" ]; then
    fail "a region hid $hidden cell(s) while the title still had room to give"
  fi
  defects=$(bar_cells_defects "$bar_title_json_path")
  if [ -n "$defects" ]; then
    fail "cells on the $edge strip do not sit clear of each other: $defects"
  fi
  # At its budget: the strip has no slack left, or the title cell ends one
  # gap short of the centre region's first cell (the centre held centred).
  verdict=$("$jq_bin" -r '
    .[0] as $b
    | ($b.edge == "left" or $b.edge == "right") as $v
    | ([$b.cells[] | select(.name == "activeWindow")] | first) as $t
    | ([$b.cells[] | select(.region == "center")] | first) as $c
    | (if $v then ($c.y - $t.y - $t.height) else ($c.x - $t.x - $t.width) end) as $gap
    | if $b.slack < 1 then "strip slack \($b.slack)"
      elif ($gap >= $b.gap - 1 and $gap <= $b.gap + 1) then "gap to the centre \($gap)"
      else "slack \($b.slack), gap to the centre \($gap)" end' "$bar_title_json_path")
  case "$verdict" in
    "strip slack "*|"gap to the centre "*) echo "title cell at its budget: $verdict" ;;
    *) fail "the title cell stops short of the room it was given: $verdict" ;;
  esac
  local sample count=0 bad=0
  for sample in "$bar_title_samples_dir"/*.json; do
    [ -s "$sample" ] || continue
    count=$((count + 1))
    defects=$(bar_cells_defects "$sample")
    if [ -n "$defects" ]; then
      echo "mid-switch $(basename "$sample"): $defects"
      bad=$((bad + 1))
      "$jq_bin" -c '.[0] | {slack, cells: [.cells[] | [.name, .x, .y, .width, .height]]}' "$sample"
    fi
  done
  [ "$bad" -eq 0 ] || fail "cells on the $edge strip ran into each other in $bad of $count samples while the title changed"
  [ "$count" -ge 12 ] || fail "only $count mid-switch bar room samples came back"
  echo "mid-switch samples clear: $count"
  for f in "$bar_title_png_path" "$bar_title_later_png_path"; do
    [ -f "$f" ] || fail "no screenshot produced at $f"
  done
  echo "SMOKE_BAR_TITLE $bar_title_png_path"
  echo "SMOKE_BAR_TITLE_LATER $bar_title_later_png_path"
}
