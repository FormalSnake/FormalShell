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
leg_join_flag="--join"
leg_join_order=182
leg_join_needs="wlrctl"

join_region="1380,0 540x600"
join_frames=10
join_reply_path="$shot_dir/join-replies.txt"

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
}
