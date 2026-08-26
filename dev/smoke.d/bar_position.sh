# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --bar-position <top|bottom|left|right> pins `bar.position` in the settings
# fixture and proves the strip really moved: the formalshell:bar layer's box
# is read off `hyprctl -j layers` and held against the output's own size,
# since a screenshot of a bar drawn on the wrong edge would look like a bar.
# On a left or right bar that box is the strip's thickness wide and the
# whole output tall; on a bottom bar it ends on the output's last row.
#
# It carries a right region long enough to be worth a chevron (thirteen
# governed cells ahead of it, battery/audio/network outboard), which on a
# 1080-tall vertical strip is more than fits under the centre once opened:
# the expanded frame is where the overflow rule shows, the outboard cells
# still against the screen edge and the group clipped on the centre's side
# (Bar.qml's region comment). Collapsed frame, `bar chevron expand`,
# expanded frame, the two asserted to differ. Then `panel open audio` hangs a panel
# off the bar's inner edge for the run's own frame, with `panel state`
# agreeing it is the open one. This leg owns the `bar` key, so it does not
# combine with --chevron or --bar-layout, which write the same key.
leg_bar_position_flag="--bar-position <edge>"
leg_bar_position_order=185
leg_bar_position_needs="jq"

bar_position_layers_path="$shot_dir/bar-position-layers.json"
bar_position_monitors_path="$shot_dir/bar-position-monitors.json"
bar_position_status_collapsed_path="$shot_dir/bar-position-chevron-collapsed.json"
bar_position_status_expanded_path="$shot_dir/bar-position-chevron-expanded.json"
bar_position_expand_reply_path="$shot_dir/bar-position-expand-reply.txt"
bar_position_collapsed_path="$shot_dir/bar-position-collapsed.png"
bar_position_expanded_path="$shot_dir/bar-position-expanded.png"
bar_position_panel_open_path="$shot_dir/bar-position-panel-open.txt"
bar_position_panel_state_path="$shot_dir/bar-position-panel-state.txt"

leg_bar_position_validate() {
  case "$(leg_arg bar_position)" in
    top|bottom|left|right) ;;
    *)
      echo "usage: $0 --bar-position <top|bottom|left|right>" >&2
      exit 1
      ;;
  esac
  if leg_on chevron || leg_on bar_layout; then
    echo "usage: --bar-position carries its own bar.layout and cannot combine with --chevron or --bar-layout" >&2
    exit 1
  fi
}

leg_bar_position_fixture() {
    settings_fragment ', "bar": {"position": "'"$(leg_arg bar_position)"'", "layout": {"right": ["bluetooth", "weather", "tray", "bell", "indicators", "monitor", "keyboardLayout", "display", "github", "usage", "tailscale", "systemUpdate", "clock", "chevron", "battery", "audio", "network"]}}'
}

leg_bar_position_timing() {
  # The drive's last step (the panel open) lands ~12s in; the run's own
  # frame is taken past that, so it shows the panel hanging off the bar.
  leg_timing 16 40
}

leg_bar_position_drive() {
  local script="$shot_dir/bar-position-drive.sh"
  write_script "$script" <<EOS
#!/usr/bin/env bash
sleep 5
"$hyprctl_bin" -j layers > "$bar_position_layers_path" 2>&1
"$hyprctl_bin" -j monitors > "$bar_position_monitors_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$bar_position_status_collapsed_path" 2>&1
sleep 1
"$grim_bin" "$bar_position_collapsed_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call bar chevron expand > "$bar_position_expand_reply_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$bar_position_status_expanded_path" 2>&1
"$grim_bin" "$bar_position_expanded_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call panel open audio > "$bar_position_panel_open_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call panel state > "$bar_position_panel_state_path" 2>&1
EOS
  echo "exec-once = bash $script"
}

leg_bar_position_assert() {
  local edge box bx by bw bh mw mh
  edge=$(leg_arg bar_position)
  if [ ! -s "$bar_position_layers_path" ] || [ ! -s "$bar_position_monitors_path" ]; then
    fail "no layer or monitor dump produced for the bar position check"
  fi
  # hyprctl -j layers nests every surface under its monitor and level; the
  # bar is the one surface in the formalshell:bar namespace.
  box=$("$jq_bin" -r '[.[] | .levels[] | .[] | select(.namespace == "formalshell:bar")] | first | "\(.x) \(.y) \(.w) \(.h)"' "$bar_position_layers_path" 2>/dev/null)
  if [ -z "$box" ] || [ "$box" = "null" ]; then
    fail "no formalshell:bar layer surface in $bar_position_layers_path"
  fi
  read -r bx by bw bh <<< "$box"
  # The output's logical size, the space layer geometry is reported in.
  read -r mw mh <<< "$("$jq_bin" -r 'first | "\(.width / .scale | floor) \(.height / .scale | floor)"' "$bar_position_monitors_path")"
  echo "bar layer: x=$bx y=$by w=$bw h=$bh on ${mw}x${mh} ($edge)"
  case "$edge" in
    top)
      [ "$by" -eq 0 ] && [ "$bw" -eq "$mw" ] && [ "$bh" -lt "$bw" ] || fail "a top bar should span the top edge, got x=$bx y=$by w=$bw h=$bh"
      ;;
    bottom)
      [ $((by + bh)) -eq "$mh" ] && [ "$bw" -eq "$mw" ] && [ "$bh" -lt "$bw" ] || fail "a bottom bar should span the bottom edge, got x=$bx y=$by w=$bw h=$bh"
      ;;
    left)
      [ "$bx" -eq 0 ] && [ "$bh" -eq "$mh" ] && [ "$bw" -lt "$bh" ] || fail "a left bar should span the left edge, got x=$bx y=$by w=$bw h=$bh"
      ;;
    right)
      [ $((bx + bw)) -eq "$mw" ] && [ "$bh" -eq "$mh" ] && [ "$bw" -lt "$bh" ] || fail "a right bar should span the right edge, got x=$bx y=$by w=$bw h=$bh"
      ;;
  esac
  # The strip is one cell row plus its margin band, never a stretched
  # window: 60 is well past the 40 the default scale resolves and well
  # short of anything a wrongly sized surface would report.
  local thickness=$bh
  case "$edge" in left|right) thickness=$bw ;; esac
  if [ "$thickness" -gt 60 ]; then
    fail "bar strip is $thickness thick, which is not a cell row plus its margin band"
  fi

  local hidden_names='"bluetooth","weather","tray","bell","indicators","monitor","keyboardLayout","display","github","usage","tailscale","systemUpdate","clock"'
  if ! grep -q "\"collapsed\":true,\"collapses\":\[$hidden_names\],\"hidden\":\[$hidden_names\]" "$bar_position_status_collapsed_path" 2>/dev/null; then
    fail "bar chevron status did not report the governed names hidden while collapsed. Got: $(cat "$bar_position_status_collapsed_path" 2>/dev/null)"
  fi
  if ! grep -q '^ok$' "$bar_position_expand_reply_path" 2>/dev/null; then
    fail "bar chevron expand was refused. Got: $(cat "$bar_position_expand_reply_path" 2>/dev/null)"
  fi
  if ! grep -q "\"collapsed\":false,\"collapses\":\[$hidden_names\],\"hidden\":\[\]" "$bar_position_status_expanded_path" 2>/dev/null; then
    fail "bar chevron expand did not clear the hidden set. Got: $(cat "$bar_position_status_expanded_path" 2>/dev/null)"
  fi
  for f in "$bar_position_collapsed_path" "$bar_position_expanded_path"; do
    if [ ! -f "$f" ]; then
      fail "no screenshot produced at $f"
    fi
  done
  echo "SMOKE_BAR_POSITION_COLLAPSED $bar_position_collapsed_path"
  echo "SMOKE_BAR_POSITION_EXPANDED $bar_position_expanded_path"
  if cmp -s "$bar_position_collapsed_path" "$bar_position_expanded_path"; then
    fail "collapsed and expanded screenshots are byte-identical: the chevron changed the state but rendered nothing along the $edge bar"
  fi
  if ! grep -q '^ok$' "$bar_position_panel_open_path" 2>/dev/null; then
    fail "panel open audio did not answer ok. Got: $(cat "$bar_position_panel_open_path" 2>/dev/null)"
  fi
  if ! grep -q '^audio$' "$bar_position_panel_state_path" 2>/dev/null; then
    fail "panel state is not audio. Got: $(cat "$bar_position_panel_state_path" 2>/dev/null)"
  fi
}
