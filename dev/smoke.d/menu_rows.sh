# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --menu-rows: RowListView.qml's transitions in the launcher's row list. On a
# re-rank inside one level a row that kept its place in the list slides to
# its new slot, one that arrived fades in, and one that left fades out where
# it stood. The toggle hub is the level: its six rows filter down to the two
# whose names hold "o" past the first letter... and back, at a tenth of the
# motion speed (set before the open, which a window keeps).
#
# The claim is the in-between: frames taken while the list re-ranks, read
# over the rows' band, must include one that matches neither the settled
# list before the filter nor the one after it. A list that redrew in one
# step only ever shows one or the other.
leg_menu_rows_flag="--menu-rows"
leg_menu_rows_order=127
leg_menu_rows_needs="convert"

menu_rows_frames=16
# The body's row band under the card's header (a 560 card at 30% of 1080).
menu_rows_box="520x260+700+390"

leg_menu_rows_validate() {
  local other
  for other in clipboard menu menu_emerge menu_morph picker emoji monitor mirror toggles; do
    if leg_on "$other"; then
      echo "usage: --menu-rows measures the launcher's own frames and cannot combine with --${other//_/-}" >&2
      exit 1
    fi
  done
}

leg_menu_rows_timing() {
  leg_timing 30 70
}

leg_menu_rows_drive() {
  local script="$shot_dir/menu-rows-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
call() { $ipc call "\$@"; }
sleep 4
call debug motionScale 1000 > /dev/null 2>&1
call menu summon toggles > /dev/null 2>&1
sleep 8
"$grim_bin" "$shot_dir/menu-rows-before.png" > /dev/null 2>&1
call menu filter "o" > "$shot_dir/menu-rows-filter.txt" 2>&1
for i in \$(seq 1 $menu_rows_frames); do
  "$grim_bin" "$shot_dir/menu-rows-\$i.png" > /dev/null 2>&1
  sleep 0.1
done
sleep 6
"$grim_bin" "$shot_dir/menu-rows-after.png" > /dev/null 2>&1
call menu status > "$shot_dir/menu-rows-status.json" 2>&1
call debug motionScale 100 > /dev/null 2>&1
call menu close > /dev/null 2>&1
EOF
  hypr_exec_once "bash $script"
}

# The share of the rows' band that differs at all between two frames.
menu_rows_diff() {
  $convert_bin "$1" "$2" -compose difference -composite -colorspace Gray \
    -crop "$menu_rows_box" +repage -threshold 0 -format '%[fx:mean]' info: 2>/dev/null
}

leg_menu_rows_assert() {
  local i a b between=0
  grep -q '^filter o$\|^ok$' "$shot_dir/menu-rows-filter.txt" 2>/dev/null \
    || fail "menu filter did not answer: $(cat "$shot_dir/menu-rows-filter.txt" 2>/dev/null)"
  cat "$shot_dir/menu-rows-status.json"; echo
  a=$(menu_rows_diff "$shot_dir/menu-rows-before.png" "$shot_dir/menu-rows-after.png")
  awk -v v="$a" 'BEGIN { exit !(v > 0) }' || fail "the filter changed nothing in the rows' band"
  for i in $(seq 1 $menu_rows_frames); do
    a=$(menu_rows_diff "$shot_dir/menu-rows-$i.png" "$shot_dir/menu-rows-before.png")
    b=$(menu_rows_diff "$shot_dir/menu-rows-$i.png" "$shot_dir/menu-rows-after.png")
    echo "frame $i: differs from before $a, from after $b"
    if awk -v a="$a" -v b="$b" 'BEGIN { exit !(a > 0 && b > 0) }'; then
      between=$((between + 1))
    fi
  done
  [ "$between" -ge 1 ] || fail "no frame between the two lists: the rows jumped"
  echo "SMOKE_MENU_ROWS $shot_dir/menu-rows-after.png ($between frames mid-transition)"
}
