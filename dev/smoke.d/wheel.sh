# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, iso_home, the *_bin paths and fail()
# --wheel (M47 D3): the mouse wheel scrolls a launcher view, and the cursor
# stays where it is. The wallpaper grid is the surface that reported the
# bug, so it is the one driven here, over a directory of 40 fixtures, which
# is enough rows to overflow the card whatever the output height does to the
# cap.
#
# wlrctl, not an IPC "scroll" verb: what needs proving is the pointer path
# end to end (a real zwlr_virtual_pointer_v1 axis event, into the layer
# surface, past the cell under it, into the flickable), and a shell-side
# call would skip exactly the part that was broken. Same line the tooltip
# leg draws for hover, including its relative-only pointer trick: the
# pointer is slammed into the corner first, then moved once from a known
# origin.
#
# The reading, not the frame, is the claim. Two screenshots of a scrolled
# grid look alike whether the cursor followed the wheel or not, so the
# assertion is `menu status`'s scrollTop against `picker status`'s cursor.
#
# The other half of the contract runs on the same timeline once the grid is
# closed: a notch on the bar's audio cell has to keep adjusting the sink.
# That is the one path `Cell` still accepts the wheel on (`Cell.wheeled` with
# a consumer that re-accepts), so a fix that made lists scroll by making
# every cell transparent to the wheel would pass the half above and silently
# break this one. wpctl reads the sink back, since no frame can show that a
# volume moved for the right reason.
leg_wheel_flag="--wheel"
leg_wheel_order=125
leg_wheel_needs="wlrctl convert wpctl"

wheel_before_png="$shot_dir/wheel-before.png"
wheel_after_png="$shot_dir/wheel-after.png"
wheel_menu_before_path="$shot_dir/wheel-menu-before.json"
wheel_menu_after_path="$shot_dir/wheel-menu-after.json"
wheel_picker_before_path="$shot_dir/wheel-picker-before.json"
wheel_picker_after_path="$shot_dir/wheel-picker-after.json"
wheel_dispatch_path="$shot_dir/wheel-dispatch.txt"
wheel_bar_png="$shot_dir/wheel-bar.png"
wheel_volume_before_path="$shot_dir/wheel-volume-before.txt"
wheel_volume_after_path="$shot_dir/wheel-volume-after.txt"
wheel_dir="$iso_home/.local/share/formalshell/wheel-pictures"

# Both legs own picker.directory, and the picker leg asserts its own fixture
# count down to the number, so the two cannot share one settings file.
leg_wheel_validate() {
  if leg_on picker; then
    echo "usage: $0 --wheel and --picker both set picker.directory, run them separately" >&2
    exit 1
  fi
}

leg_wheel_fixture() {
  local i
  mkdir -p "$wheel_dir"
  # Small: 40 of them, and nothing here reads a pixel of the thumbnails.
  # The hue walks so a screenshot shows which rows are on screen.
  for i in $(seq 0 39); do
    $convert_bin -size 320x180 "xc:hsl($((i * 9)),70%,45%)" "$wheel_dir/img-$(printf '%02d' "$i").png"
  done
  settings_fragment ', "picker": {"directory": "'"$wheel_dir"'"}'
}

# The grid covers the whole output, so under --wallpaper this starts past
# that leg's own last frame, the same clock picker_t0 keeps.
wheel_t0() {
  if leg_on wallpaper; then echo 16; else echo 4; fi
}

leg_wheel_timing() {
  local t0
  t0=$(wheel_t0)
  leg_timing $((17 + t0)) $((50 + t0))
}

leg_wheel_drive() {
  local t0 script="$shot_dir/wheel-drive.sh"
  t0=$(wheel_t0)
  # 893x604 is the middle of a THUMBNAIL, second row, second column: the
  # card is centred and popupWidthMenu wide, its top edge sits at 30% of a
  # 1080-tall output, and the grid starts a search row plus its rule and the
  # breadcrumb below that. The middle of the grid is not good enough: 960
  # lands in the gutter between two cells, where the wheel reaches the
  # GridView without passing a cell at all, which is the one path that was
  # never broken.
  #
  # 1731x20 is the bar's audio cell, the leading cell of the right group,
  # vertically centred in the bar. It is the second half's target, once the
  # grid is closed and the bar is reachable again.
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep $t0
"$qs_bin" ipc -p "$shell_path" call picker summon > /dev/null 2>&1
sleep 2
"$wlrctl_bin" pointer move -4000 -4000 > "$wheel_dispatch_path" 2>&1
sleep 1
"$wlrctl_bin" pointer move 893 604 >> "$wheel_dispatch_path" 2>&1
sleep 2
"$grim_bin" "$wheel_before_png" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$wheel_menu_before_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call picker status > "$wheel_picker_before_path" 2>&1
"$wlrctl_bin" pointer scroll 10 0 >> "$wheel_dispatch_path" 2>&1
sleep 3
"$grim_bin" "$wheel_after_png" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$wheel_menu_after_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call picker status > "$wheel_picker_after_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
sleep 1
"$wpctl_bin" get-volume @DEFAULT_AUDIO_SINK@ 2>&1 | grep '^Volume:' > "$wheel_volume_before_path"
"$wlrctl_bin" pointer move -4000 -4000 >> "$wheel_dispatch_path" 2>&1
sleep 1
"$wlrctl_bin" pointer move 1731 20 >> "$wheel_dispatch_path" 2>&1
sleep 1
"$wlrctl_bin" pointer scroll 10 0 >> "$wheel_dispatch_path" 2>&1
sleep 2
"$grim_bin" -c "$wheel_bar_png" > /dev/null 2>&1
"$wpctl_bin" get-volume @DEFAULT_AUDIO_SINK@ 2>&1 | grep '^Volume:' > "$wheel_volume_after_path"
EOF
  echo "exec-once = bash $script"
}

wheel_field() {
  sed -n 's/.*"'"$2"'":\([0-9-]*\).*/\1/p' "$1"
}

leg_wheel_assert() {
  local f before_scroll after_scroll before_cursor after_cursor
  for f in "$wheel_menu_before_path" "$wheel_menu_after_path" \
    "$wheel_picker_before_path" "$wheel_picker_after_path"; do
    if [ ! -s "$f" ]; then
      fail "no status dump produced at $f"
    fi
    cat "$f"; echo
  done
  # Printed on the happy path too: the only evidence of where the pointer
  # ended up and that the axis event was sent at all.
  cat "$wheel_dispatch_path" 2>/dev/null || true
  if ! grep -q '"count":40' "$wheel_picker_before_path"; then
    fail "the grid did not list all 40 fixtures, so an unscrolled view proves nothing, got: $(cat "$wheel_picker_before_path")"
  fi
  before_scroll=$(wheel_field "$wheel_menu_before_path" scrollTop)
  after_scroll=$(wheel_field "$wheel_menu_after_path" scrollTop)
  before_cursor=$(wheel_field "$wheel_picker_before_path" cursor)
  after_cursor=$(wheel_field "$wheel_picker_after_path" cursor)
  if [ -z "$before_scroll" ] || [ -z "$after_scroll" ]; then
    fail "menu status carried no scrollTop"
  fi
  if [ "$before_scroll" != "0" ]; then
    fail "the grid was already scrolled to $before_scroll before the wheel moved"
  fi
  if [ "$after_scroll" -le 0 ]; then
    fail "the wheel did not scroll the grid: scrollTop stayed at $after_scroll"
  fi
  if [ -z "$before_cursor" ] || [ "$before_cursor" != "$after_cursor" ]; then
    fail "the wheel moved the cursor from $before_cursor to $after_cursor"
  fi
  echo "SMOKE_WHEEL scrollTop $before_scroll -> $after_scroll, cursor held at $after_cursor"
  for f in "$wheel_before_png" "$wheel_after_png" "$wheel_bar_png"; do
    if [ ! -f "$f" ]; then
      fail "no wheel screenshot produced at $f"
    fi
  done
  echo "SMOKE_WHEEL_BEFORE $wheel_before_png"
  echo "SMOKE_WHEEL_AFTER $wheel_after_png"
  # The slider half: a notch on the bar's audio cell still moves the sink.
  local before_volume after_volume
  before_volume=$(cat "$wheel_volume_before_path" 2>/dev/null)
  after_volume=$(cat "$wheel_volume_after_path" 2>/dev/null)
  echo "bar audio cell volume: $before_volume -> $after_volume"
  case "$before_volume" in
    Volume:*) ;;
    *) fail "wpctl read no sink volume before the bar notch, got: $before_volume" ;;
  esac
  if [ "$before_volume" = "$after_volume" ]; then
    fail "a notch on the bar's audio cell left the sink at $after_volume, so Cell.wheeled no longer reaches its consumer"
  fi
  echo "SMOKE_WHEEL_BAR $wheel_bar_png"
}
