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
# Every frame is saved for reading by eye; two claims are asserted, both on
# an attached frame of case a:
#
#   the seam (M57 D1)   the line's own row inside the gap must be byte-equal
#                       to the bar's fill two rows above it: the bar paints
#                       that row, and a card whose fill starts on it too
#                       leaves a line across the whole gap wherever the
#                       surfaces are translucent.
#   the wall (M57 D2)   case a rests a screenPadding off the output and its
#                       fillet wants radiusXl, so there is no room for one:
#                       the attached silhouette runs out to the screen's own
#                       edge instead, and the output's last column carries
#                       card fill from under the line down to the shape's far
#                       edge. At rest that column is bare desktop again.
#
# Both probes are pinned to the unframed rig's own numbers, so `--join
# --frame` photographs the ring case and leaves them out; that combination is
# read by eye.
leg_join_flag="--join"
leg_join_order=182
leg_join_needs="wlrctl convert"

join_region="1380,0 540x600"
join_crop_width=540
join_frames=10
join_reply_path="$shot_dir/join-replies.txt"
join_desktop_path="$shot_dir/join-desktop.png"

# Case a's card in the crop's own coordinates: `panel open network` with no
# cell is `Theme.space.n` (380) wide and rests one screenPadding (12) off the
# 1920 output's right edge, and the crop starts at x = 1380, so it ends on
# the output's own last column. The bar is 40 rows, so its inward line is the
# last of them.
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

# One whole column of a frame, as six hex digits per row, top to bottom: the
# wall runs the length of the card, and one read beats a probe per row.
join_column() {
  $convert_bin "$1" -crop "1x4096+$2+0" +repage -depth 8 txt:- 2>/dev/null \
    | awk 'NR > 1 { print toupper(substr($3, 2, 6)) }'
}

# One row of a frame from column $2 to the crop's own end, the same way.
join_row() {
  $convert_bin "$1" -crop "4096x1+$2+$3" +repage -depth 8 txt:- 2>/dev/null \
    | awk 'NR > 1 { print toupper(substr($3, 2, 6)) }'
}

# How far under the line the shape reaches at column $2 of frame $1: the last
# row that is not the bare desktop's own. The card comes out from under the
# line, so this is what says how much of the wall there is to read.
join_shape_depth() {
  local i last=$join_line_row
  local -a shot desk
  mapfile -t shot < <(join_column "$1" "$2")
  mapfile -t desk < <(join_column "$join_desktop_path" "$2")
  for ((i = join_line_row + 1; i < ${#shot[@]} && i < ${#desk[@]}; i++)); do
    [ "${shot[i]}" = "${desk[i]}" ] && break
    last=$i
  done
  echo "$last"
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

  if leg_on frame; then
    echo "SMOKE_JOIN_FRAMED read by eye: the probes below are pinned to the unframed rig's own numbers"
    return 0
  fi

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

  local edge ink far top bottom row
  edge=$((join_crop_width - 1))
  ink=$(join_pixel "$attached" "$col" $((join_line_row + 5)))
  far=$(join_shape_depth "$attached" "$col")
  top=$((join_line_row + 2))
  bottom=$((far - 3))
  [ "$bottom" -gt "$top" ] || fail \
    "the shape reaches only row $far at column $col of $attached: too shallow to read the wall against"
  local -a wall rest desk
  mapfile -t wall < <(join_column "$attached" "$edge")
  mapfile -t rest < <(join_column "$shot_dir/join-a-rest.png" "$edge")
  mapfile -t desk < <(join_column "$join_desktop_path" "$edge")
  for ((row = top; row <= bottom; row++)); do
    [ "${wall[row]}" = "$ink" ] || fail \
      "the output's last column reads ${wall[row]} at row $row of $attached against the card's own $ink: the walled silhouette stops short of the screen's edge"
    [ "${rest[row]}" = "${desk[row]}" ] || fail \
      "the output's last column still reads ${rest[row]} at row $row of join-a-rest.png against the bare desktop's ${desk[row]}: the card has let go and the edge should be desktop again"
  done

  # And the run out to the wall is one unbroken fill: two whole rows read
  # across, from the card's own middle to that last column, may not carry the
  # bare desktop's ink anywhere. A column probe alone misses a seam between
  # the card's side and the run-out, which is exactly where the two meet.
  local -a scan bare
  local depth col_i bad
  for depth in $((join_line_row + 8)) $((join_line_row + (bottom - join_line_row) * 2 / 3)); do
    mapfile -t scan < <(join_row "$attached" "$col" "$depth")
    mapfile -t bare < <(join_row "$join_desktop_path" "$col" "$depth")
    bad=""
    for ((col_i = 0; col_i < ${#scan[@]}; col_i++)); do
      [ "${scan[col_i]}" = "${bare[col_i]}" ] && bad="$bad $((col + col_i))"
    done
    [ -z "$bad" ] || fail \
      "row $depth of $attached shows the bare desktop at column(s)$bad between the card's middle and the output's end: the attached silhouette is not one unbroken fill"
    echo "SMOKE_JOIN_WALL_ROW ok row $depth columns $col-$edge $attached"
  done
  echo "SMOKE_JOIN_WALL ok $ink rows $top-$bottom at column $edge $attached"
}
