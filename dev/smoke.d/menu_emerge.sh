# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --menu-emerge proves the launcher's own open (M57 D5): the card buds off the
# top line, the same metamorphosis a panel does off the bar's hairline, and is
# a plain card at its resting rect once it has let go. It replaced the unfold,
# where the card appeared at its search row's height and grew downward.
#
# At full speed the card is on the line for about as long as one screencopy
# takes, so the open runs at a tenth of its speed (`debug motionScale`, the
# same instrument --join uses) and is photographed frame by frame, back to
# back, with the wall clock stamped after each capture. Four claims, plus the
# number the whole change was made against:
#
#   out of the line   an early frame carries the card's own fill directly
#                     under the line at the card's centre column and nothing
#                     at the card's resting bottom rows. A card materialising
#                     in place covers its own bottom from the first frame and
#                     never touches the line at all.
#   the lit bar       on that same frame a bar pixel clear of the join is
#                     byte-equal to the closed output's, while the desktop
#                     below it is not: the scrim's share over the line's own
#                     band rides `1 - attach`, so the card buds off a lit bar.
#   the plain card    the rest frame has the card at its resting rect with a
#                     top border of its own and a row of desktop-through-scrim
#                     between the line and it, and the bar's band dimmed like
#                     the rest of the output.
#   the settle        the first captured frame byte-equal to the rest frame,
#                     stamped against the summon that started it and divided
#                     by the motion scale. Printed before anything is
#                     asserted: it is the figure the owner's "don't make the
#                     animation any slower" is checked against, and it has to
#                     survive a run whose assertions fail.
#
# Probes are read by mean brightness, not by identity: the card is still being
# squashed for a beat after it lands (M54 D7), so a probe standing well inside
# it compares unequal to the settled frame for most of the open, and the scrim
# over the whole output makes --panel-emerge's "anything but the desktop" say
# nothing. Nothing the card draws is darker than its own fill, so a threshold
# halfway between that fill and the scrim under it separates "the card has
# reached this row" from "this is still the scrim" whatever is underneath.
#
# The card's own left edge, width and top are spelled out rather than measured:
# a `popupWidthMenu` card centred on the output with its top at 30% of it is
# what the tokens and Menu.qml's `_topFraction` say, so a token change has to
# be a deliberate edit here too (tst_panel_geometry.qml draws the same line).
leg_menu_emerge_flag="--menu-emerge"
leg_menu_emerge_order=21
leg_menu_emerge_needs="convert jq"

menu_emerge_scale_path="$shot_dir/menu-emerge-scale.txt"
menu_emerge_summon_path="$shot_dir/menu-emerge-summon.txt"
menu_emerge_close_path="$shot_dir/menu-emerge-close.txt"
menu_emerge_status_path="$shot_dir/menu-emerge-status.json"
menu_emerge_t0_path="$shot_dir/menu-emerge-t0.txt"
menu_emerge_stamp_path="$shot_dir/menu-emerge-stamps.txt"

menu_emerge_closed_path="$shot_dir/menu-emerge-closed.png"
menu_emerge_rest_path="$shot_dir/menu-emerge-rest.png"

# Back to back rather than armed at fractions of the clock: grim's own start-up
# costs about as much as the open does at full speed (panel_handoff.sh's
# finding), and ten of them armed at once come back out of order (the unfold
# leg's finding). One sequential loop at a tenth speed lands a frame every fifth
# of a second of a travel that runs for several, which is both a dense enough
# ladder and a stamp per frame that means what it says. The ladder has to
# outlast the spatial curve's own overshoot and its return, not just its
# nominal length: the card reads several pixels past its resting edge for most
# of a second after it has stopped travelling.
menu_emerge_frames=45
menu_emerge_frame_gap=0.09

# The motion scale the open runs at, as a percent, and the divisor the settle
# figure is reported in real milliseconds through.
menu_emerge_scale=1000

# The card's own geometry (DESIGN.md §1 Space, Menu.qml's `_topFraction`):
# `popupWidthMenu` 560 centred on a 1920 output, top at 30% of 1080. The bar is
# 40 rows on this rig, so the line it buds off is the last of them.
menu_emerge_card_x=680
menu_emerge_card_y=324
menu_emerge_card_w=560
menu_emerge_line_row=39

# A bar pixel clear of the join: the card spans columns 680-1240 and its
# fillets reach a `radiusXl` past either end, so the output's own corner is
# nowhere near it and carries nothing that ticks.
menu_emerge_bar_box="8x8+2+2"
# And a desktop one, well below the card, for the other half of the same claim.
menu_emerge_desk_box="8x8+2+1040"

leg_menu_emerge_validate() {
  local other
  for other in bar_position center clipboard clipssh clipssh_image emoji fullscreen \
    gallery gpu keybinds lock menu monitor notify picker plugins polkit processes \
    screensaver share toggles tray wallpaper; do
    if leg_on "$other"; then
      echo "usage: --menu-emerge measures the launcher's own frames and cannot combine with --${other//_/-}" >&2
      exit 1
    fi
  done
}

leg_menu_emerge_timing() {
  leg_timing 32 80
}

leg_menu_emerge_drive() {
  local script="$shot_dir/menu-emerge-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
call() { "$qs_bin" ipc -p "$shell_path" call "\$@"; }
sleep 4
call debug motionScale $menu_emerge_scale > "$menu_emerge_scale_path" 2>&1
sleep 1
# The same output with the launcher closed: what the bar's band and the
# desktop under it read as before any scrim is drawn over either.
"$grim_bin" "$menu_emerge_closed_path" > /dev/null 2>&1
call menu summon "" > "$menu_emerge_summon_path" 2>&1
date +%s%N > "$menu_emerge_t0_path"
for i in \$(seq 1 $menu_emerge_frames); do
  "$grim_bin" "$shot_dir/menu-emerge-\$i.png" > /dev/null 2>&1
  echo "\$i \$(date +%s%N)" >> "$menu_emerge_stamp_path"
  sleep $menu_emerge_frame_gap
done
sleep 5
"$grim_bin" "$menu_emerge_rest_path" > /dev/null 2>&1
call menu status > "$menu_emerge_status_path" 2>&1
call menu close > "$menu_emerge_close_path" 2>&1
call debug motionScale 100 > /dev/null 2>&1
EOF
  echo "exec-once = bash $script"
}

# How bright one box is on average. The card's own fill sits several times
# above the scrim it is drawn over, so this separates "the card has reached
# this row" from "this is still the scrim".
menu_emerge_level() {
  $convert_bin "$1" -crop "$2" +repage -format "%[fx:mean]" info: 2>/dev/null
}

menu_emerge_covered() {
  awk -v v="$(menu_emerge_level "$1" "$2")" 'BEGIN { exit !(v > 0.06) }'
}

# One pixel of a frame as six hex digits, --join's own read-out.
menu_emerge_pixel() {
  local rgb
  rgb=$($convert_bin "$1" -format \
    "%[fx:int(255*p{$2,$3}.r+0.5)] %[fx:int(255*p{$2,$3}.g+0.5)] %[fx:int(255*p{$2,$3}.b+0.5)]" \
    info: 2>/dev/null)
  [ -n "$rgb" ] || fail "could not read the pixel at ($2,$3) out of $1"
  # shellcheck disable=SC2086  # three fields, one per channel
  printf '%02X%02X%02X' $rgb
}

# What fraction of one crop differs at all between two frames. The share, not
# the bounding box `--join` reads: ImageMagick answers a box of `0x0+W+H` for a
# difference that covers the whole crop as well as for one that covers none of
# it, and the two mean opposite things.
menu_emerge_diff() {
  $convert_bin "$1" "$2" -compose difference -composite -colorspace Gray \
    -crop "$3" +repage -threshold 0 -format '%[fx:mean]' info: 2>/dev/null
}

menu_emerge_same() {
  awk -v v="$(menu_emerge_diff "$1" "$2" "$3")" 'BEGIN { exit !(v == 0) }'
}

leg_menu_emerge_assert() {
  local f i path
  for f in "$menu_emerge_summon_path" "$menu_emerge_close_path"; do
    if ! grep -q '^ok$' "$f" 2>/dev/null; then
      fail "a menu route did not answer ok at $f, got: $(cat "$f" 2>/dev/null)"
    fi
  done
  grep -q '^ok$' "$menu_emerge_scale_path" 2>/dev/null \
    || fail "debug motionScale did not answer ok, got: $(cat "$menu_emerge_scale_path" 2>/dev/null)"

  for f in "$menu_emerge_closed_path" "$menu_emerge_rest_path"; do
    [ -f "$f" ] || fail "no screenshot produced at $f"
  done
  echo "SMOKE_MENU_EMERGE_CLOSED $menu_emerge_closed_path"
  echo "SMOKE_MENU_EMERGE_REST $menu_emerge_rest_path"
  for i in $(seq 1 $menu_emerge_frames); do
    path="$shot_dir/menu-emerge-$i.png"
    [ -f "$path" ] || fail "no screenshot produced at $path"
    echo "SMOKE_MENU_EMERGE_$i $path"
  done

  # --- The settle, printed before anything is asserted ------------------
  #
  # The first frame that is byte-equal to the rest frame below the search row.
  # The field itself is left out of the comparison: its text cursor blinks, so
  # a crop carrying it is never equal to anything twice.
  local t0 settle_ns settle_ms stamp n d trace="" rest_box="1920x640+0+400"
  t0=$(cat "$menu_emerge_t0_path" 2>/dev/null)
  [ -n "$t0" ] || fail "no summon stamp at $menu_emerge_t0_path"
  settle_ns=""
  for i in $(seq 1 $menu_emerge_frames); do
    d=$(menu_emerge_diff "$shot_dir/menu-emerge-$i.png" "$menu_emerge_rest_path" "$rest_box")
    trace="$trace $i:$d"
    [ -n "$settle_ns" ] && continue
    awk -v v="$d" 'BEGIN { exit !(v == 0) }' || continue
    stamp=$(awk -v n="$i" '$1 == n { print $2 }' "$menu_emerge_stamp_path" 2>/dev/null)
    [ -n "$stamp" ] || fail "frame $i has no stamp in $menu_emerge_stamp_path"
    settle_ns=$((stamp - t0))
    n=$i
  done
  echo "SMOKE_MENU_EMERGE_SETTLE_TRACE$trace"
  if [ -n "$settle_ns" ]; then
    settle_ms=$(( settle_ns / 1000000 * 100 / menu_emerge_scale ))
    echo "SMOKE_MENU_EMERGE_SETTLE_MS $settle_ms frame=$n scale=$menu_emerge_scale raw_ms=$((settle_ns / 1000000))"
  else
    echo "SMOKE_MENU_EMERGE_SETTLE_MS none no frame among $menu_emerge_frames matched the rest frame in $rest_box"
  fi

  # The root level names no route of its own, so it is the placeholder and
  # the row count that say the launcher is up and holding the root list.
  if [ ! -s "$menu_emerge_status_path" ] \
    || ! grep -q '"placeholder":"Type a command or search..."' "$menu_emerge_status_path" \
    || [ "$("$jq_bin" -r '.rows' "$menu_emerge_status_path" 2>/dev/null)" -lt 1 ]; then
    fail "the launcher did not settle back at the root level, got: $(cat "$menu_emerge_status_path" 2>/dev/null)"
  fi
  cat "$menu_emerge_status_path"; echo

  # --- Where the card rests ---------------------------------------------
  #
  # Its bottom is measured rather than stated: the row count is the rig's
  # own, and only the three numbers the tokens fix are spelled out above.
  local column_x=$((menu_emerge_card_x + menu_emerge_card_w / 2 - 2))
  local rest_bottom=0 row
  for ((row = menu_emerge_card_y + 40; row < 1080; row += 4)); do
    if menu_emerge_covered "$menu_emerge_rest_path" "5x4+${column_x}+${row}"; then
      rest_bottom=$row
    elif [ "$rest_bottom" -gt 0 ]; then
      break
    fi
  done
  [ "$rest_bottom" -gt $((menu_emerge_card_y + 200)) ] || fail \
    "the rest frame's card reaches only row $rest_bottom down its own centre column: it is not the card the tokens describe"
  echo "SMOKE_MENU_EMERGE_RESTING card ${menu_emerge_card_w}x$((rest_bottom - menu_emerge_card_y))+${menu_emerge_card_x}+${menu_emerge_card_y}"

  # The two probes the travel is read with, and the guard that says they
  # measure something: neither may read as covered with the launcher closed.
  local neck_box="5x4+${column_x}+$((menu_emerge_line_row + 2))"
  local floor_box="5x4+${column_x}+$((rest_bottom - 12))"
  for f in "$neck_box" "$floor_box"; do
    if menu_emerge_covered "$menu_emerge_closed_path" "$f"; then
      fail "probe $f already reads as covered with the launcher closed, so it measures nothing"
    fi
  done
  menu_emerge_covered "$menu_emerge_rest_path" "$floor_box" || fail \
    "the settled card does not cover $floor_box, so the floor probe is not where the measurement thinks"

  # --- Out of the line --------------------------------------------------
  local attached="" last_attached="" ladder=""
  for i in $(seq 1 $menu_emerge_frames); do
    path="$shot_dir/menu-emerge-$i.png"
    if menu_emerge_covered "$path" "$neck_box"; then
      if menu_emerge_covered "$path" "$floor_box"; then
        ladder="$ladder $i:both"
      else
        ladder="$ladder $i:neck"
        [ -n "$attached" ] || attached="$path"
        last_attached="$path"
      fi
    else
      ladder="$ladder $i:-"
    fi
  done
  echo "SMOKE_MENU_EMERGE_LADDER$ladder"
  [ -n "$attached" ] || fail \
    "no frame among menu-emerge-1..$menu_emerge_frames carries the card's fill at $neck_box with nothing at $floor_box: the card never came out of the line"
  echo "SMOKE_MENU_EMERGE_BUD ok $attached"

  # --- The lit bar ------------------------------------------------------
  #
  # Read off the LAST frame the card is still on the line for, not the first:
  # the scrim rides the same pose the travel does, so on the first frame of an
  # open there is barely any of it on the output yet and "the desktop is
  # dimmed" says nothing. By the last attached frame the pose is well along
  # and the two halves of the claim are both worth making.
  local bar_open bar_closed desk_open desk_closed
  bar_open=$(menu_emerge_level "$last_attached" "$menu_emerge_bar_box")
  bar_closed=$(menu_emerge_level "$menu_emerge_closed_path" "$menu_emerge_bar_box")
  desk_open=$(menu_emerge_level "$last_attached" "$menu_emerge_desk_box")
  desk_closed=$(menu_emerge_level "$menu_emerge_closed_path" "$menu_emerge_desk_box")
  menu_emerge_same "$last_attached" "$menu_emerge_closed_path" "$menu_emerge_bar_box" || fail \
    "the bar's own band at $menu_emerge_bar_box reads $bar_open in $last_attached against $bar_closed closed: the scrim dims the line the card is still budding off"
  awk -v o="$desk_open" -v c="$desk_closed" 'BEGIN { exit !(o < c * 0.9) }' || fail \
    "the desktop at $menu_emerge_desk_box reads $desk_open in $last_attached against $desk_closed closed: the scrim is not on the output at all while the card is attached"
  echo "SMOKE_MENU_EMERGE_LIT_BAR ok bar $bar_open = $bar_closed, desktop $desk_open under $desk_closed in $last_attached"

  # --- The plain card ---------------------------------------------------
  #
  # A row of desktop-through-scrim between the line and the card says the
  # near edge let go of the line, and a border pixel differing from both the
  # scrim above it and the fill below says the card closed its own top back
  # up rather than staying open onto the gap.
  menu_emerge_covered "$menu_emerge_rest_path" "$neck_box" && fail \
    "the rest frame still carries the card's fill at $neck_box: the card never let go of the line"
  local above border fill
  above=$(menu_emerge_pixel "$menu_emerge_rest_path" "$column_x" $((menu_emerge_card_y - 4)))
  border=$(menu_emerge_pixel "$menu_emerge_rest_path" "$column_x" "$menu_emerge_card_y")
  fill=$(menu_emerge_pixel "$menu_emerge_rest_path" "$column_x" $((menu_emerge_card_y + 6)))
  if [ "$border" = "$above" ] || [ "$border" = "$fill" ]; then
    fail "the rest frame reads $above above, $border on and $fill under row $menu_emerge_card_y at column $column_x: the card has no top border of its own"
  fi
  menu_emerge_same "$menu_emerge_rest_path" "$menu_emerge_closed_path" "$menu_emerge_bar_box" && fail \
    "the bar's own band at $menu_emerge_bar_box is unchanged in the rest frame: the scrim never reached it after the card let go"
  echo "SMOKE_MENU_EMERGE_PLAIN ok border $border between $above and $fill, bar band dimmed"
}
