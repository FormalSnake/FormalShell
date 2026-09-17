# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --join photographs the join mid-flight. At full speed a card is on the line
# for about as long as one screencopy takes, so every open here runs at a
# tenth of its speed (`debug motionScale`) and is sampled across the travel:
#
#   a  `panel open network` with no cell, which lands against the far end of
#      the bar, a `screenPadding` off the screen's own edge
#   b  the chevron's second bar
#   c  a panel opened by a click on a cell inside that second bar
#
# Every frame is saved for reading by eye; the one claim asserted here is the
# seam (M57 D1). On an attached frame of case a the line's own row inside the
# gap must be byte-equal to the bar's fill two rows above it: the bar paints
# that row, and a card whose fill starts on it too leaves a line across the
# whole gap wherever the surfaces are translucent.
leg_join_flag="--join"
leg_join_order=182
leg_join_needs="wlrctl convert"

join_region="1380,0 540x600"
join_frames=10
join_reply_path="$shot_dir/join-replies.txt"
join_desktop_path="$shot_dir/join-desktop.png"

# Case a's card in the crop's own coordinates: `panel open network` with no
# cell is `Theme.space.n` (380) wide and rests one screenPadding (12) off the
# 1920 output's right edge, and the crop starts at x = 1380. The bar is 40
# rows, so its inward line is the last of them.
join_card_x=148
join_card_width=380
join_line_row=39

leg_join_validate() {
  local other
  for other in bar_layout bar_position chevron chevron_quiet panel_handoff tray_overflow; do
    if leg_on "$other"; then
      echo "usage: --join carries its own bar.layout and cannot combine with --${other//_/-}" >&2
      exit 1
    fi
  done
}

leg_join_fixture() {
  settings_fragment ', "bar": {"layout": {"right": ["bluetooth", "weather", "tray", "bell", "indicators", "chevron", "battery", "audio", "network"]}}'
}

leg_join_timing() {
  leg_timing 75 140
}

leg_join_drive() {
  local script="$shot_dir/join-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
call() { "$qs_bin" ipc -p "$shell_path" call "\$@" >> "$join_reply_path" 2>&1; }
sample() {
  local name=\$1 i
  for i in \$(seq 1 $join_frames); do
    sleep 0.3
    "$grim_bin" -g "$join_region" "$shot_dir/join-\$name-\$i.png" > /dev/null 2>&1
  done
}
sleep 5
call debug motionScale 1000
"$grim_bin" -g "$join_region" "$join_desktop_path" > /dev/null 2>&1
call panel open network
sample a
sleep 3
"$grim_bin" -g "$join_region" "$shot_dir/join-a-rest.png" > /dev/null 2>&1
call panel close
sample a-close
sleep 3
call bar chevron expand
sample b
sleep 3
"$grim_bin" -g "$join_region" "$shot_dir/join-b-rest.png" > /dev/null 2>&1
"$wlrctl_bin" pointer move -4000 -4000 >> "$join_reply_path" 2>&1
sleep 0.5
"$wlrctl_bin" pointer move 1813 72 >> "$join_reply_path" 2>&1
sleep 0.5
"$wlrctl_bin" pointer click left >> "$join_reply_path" 2>&1
sample c
sleep 3
"$grim_bin" -g "$join_region" "$shot_dir/join-c-rest.png" > /dev/null 2>&1
call panel close
sample c-close
sleep 2
call bar chevron collapse
sample b-close
call debug motionScale 100
EOF
  echo "exec-once = bash $script"
}

# One pixel out of a frame, as six hex digits.
join_pixel() {
  local rgb
  rgb=$($convert_bin "$1" -format \
    "%[fx:int(255*p{$2,$3}.r+0.5)] %[fx:int(255*p{$2,$3}.g+0.5)] %[fx:int(255*p{$2,$3}.b+0.5)]" \
    info: 2>/dev/null)
  [ -n "$rgb" ] || fail "could not read the pixel at ($2,$3) out of $1"
  # shellcheck disable=SC2086  # three fields, one per channel
  printf '%02X%02X%02X' $rgb
}

# The first frame of case a with the card attached: its fill both a few rows
# under the line and on the very first row under it, that first row the same
# ink as the one below it. A card that has begun to let go pulls its near
# edge off the line and brings its own border up there, so both of those
# rows change and the frame is passed over; a card still behind the line has
# not reached the deep probe yet.
join_attached_frame() {
  local col=$1 i path deep near below deep_desk near_desk
  deep_desk=$(join_pixel "$join_desktop_path" "$col" $((join_line_row + 5)))
  near_desk=$(join_pixel "$join_desktop_path" "$col" $((join_line_row + 1)))
  for i in $(seq 1 $join_frames); do
    path="$shot_dir/join-a-$i.png"
    [ -f "$path" ] || continue
    deep=$(join_pixel "$path" "$col" $((join_line_row + 5)))
    near=$(join_pixel "$path" "$col" $((join_line_row + 1)))
    below=$(join_pixel "$path" "$col" $((join_line_row + 2)))
    if [ "$deep" != "$deep_desk" ] && [ "$near" != "$near_desk" ] && [ "$near" = "$below" ]; then
      echo "$path"
      return 0
    fi
  done
  return 1
}

leg_join_assert() {
  local name i path
  for name in a a-close b c c-close b-close; do
    for i in $(seq 1 $join_frames); do
      path="$shot_dir/join-$name-$i.png"
      [ -f "$path" ] || fail "no join frame $path"
      echo "SMOKE_JOIN_$(echo "$name" | tr 'a-z-' 'A-Z_')_$i $path"
    done
  done
  for name in a b c; do
    path="$shot_dir/join-$name-rest.png"
    [ -f "$path" ] || fail "no join frame $path"
    echo "SMOKE_JOIN_$(echo "$name" | tr 'a-z' 'A-Z')_REST $path"
  done
  [ -f "$join_desktop_path" ] || fail "no bare desktop frame at $join_desktop_path"
  echo "SMOKE_JOIN_DESKTOP $join_desktop_path"

  local col attached seam bar
  col=$((join_card_x + join_card_width / 2))
  attached=$(join_attached_frame "$col") || fail \
    "no attached frame among join-a-1..$join_frames: nothing sits on the line's row at column $col"
  seam=$(join_pixel "$attached" "$col" "$join_line_row")
  bar=$(join_pixel "$attached" "$col" $((join_line_row - 2)))
  if [ "$seam" != "$bar" ]; then
    fail "the line's row at ($col,$join_line_row) reads $seam against the bar's own $bar two rows up in $attached: the card's fill covers it a second time"
  fi
  echo "SMOKE_JOIN_SEAM ok $seam $attached"
}
