# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --tray-overflow reads back where the tray lives with nothing configured at
# all, which since 2026-08-28 is the second bar: the strip carries the dots
# toggle and no icons, whatever room it has (Bar/tray.js's `maxVisible` 0
# default). What has to be true is that the tray moved WHOLE, nothing of it
# left on the strip but the toggle and every registered item reachable in the
# second bar, and that the bar itself opens as a real popout.
# `tray.maxVisible: -1` is the other half of that key, the strip carrying
# what fits; --tray pins it and reads the six-cell strip back.
# tests/tst_tray_overflow.qml pins the arithmetic behind both.
#
# It also puts the tray behind a bar chevron, alone on its governed side, and
# rides it down and back up. Collapsed and expanded then differ by exactly one
# cell, this one, so two byte-identical frames mean the toggle did not come
# back: Bar.qml reveals a governed entry only while it measures more than 0,
# and a tray drawing nothing until it has decided something measures 0 and
# stays hidden forever. That shipped (owner, 2026-08-28: "I just opened the
# chevron and its not there"), with `tray status` reporting the collapse
# correctly the whole time, which is why the claim here is a picture and not
# a reply.
#
# It owns bar.layout, so it does not combine with --bar-layout, --bar-position
# or --chevron, and it registers stubs of its own, so --tray's own count
# assert does not survive that pair either.
leg_tray_overflow_flag="--tray-overflow"
leg_tray_overflow_order=172
# need_python3 is tray.sh's (sourced first, alphabetically), the same shared
# `need_<bin>` resolution every leg uses.
leg_tray_overflow_needs="python3 jq"

tray_overflow_pids_path="$shot_dir/tray-overflow-pids.txt"
tray_overflow_status_path="$shot_dir/tray-overflow-status.json"
tray_overflow_open_path="$shot_dir/tray-overflow-open.json"
tray_overflow_layers_path="$shot_dir/tray-overflow-layers.json"
tray_overflow_strip_path="$shot_dir/tray-overflow-strip.png"
tray_overflow_bar_path="$shot_dir/tray-overflow-bar.png"
tray_overflow_collapsed_path="$shot_dir/tray-overflow-collapsed.png"
tray_overflow_expanded_path="$shot_dir/tray-overflow-expanded.png"
tray_overflow_menu_reply_path="$shot_dir/tray-overflow-menu-reply.txt"
tray_overflow_menu_path="$shot_dir/tray-overflow-menu.json"
tray_overflow_menu_shot_path="$shot_dir/tray-overflow-menu.png"

leg_tray_overflow_fixture() {
  # The chevron governs what precedes it in a right region, so the tray is the
  # whole of its governed side and `clock`, outboard of it, is what keeps the
  # two frames from differing by anything else.
  settings_fragment ', "bar": {"layout": {"left": [], "center": [], "right": ["tray", "chevron", "clock"]}}'
}

leg_tray_overflow_timing() {
  # The drive's last step lands ~24s in; the run's own frame is taken past
  # it, with the second bar closed and the chevron expanded again.
  leg_timing 28 60
}

leg_tray_overflow_drive() {
  local script="$shot_dir/tray-overflow-drive.sh"
  local kill_script="$shot_dir/tray-overflow-kill.sh"
  local stub="$PWD/dev/sni-stub.py"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 1
"$python3_bin" "$stub" --id overflow-fixture-1 --title "Overflow Fixture 1" --color c0392b & echo \$! >> "$tray_overflow_pids_path"
"$python3_bin" "$stub" --id overflow-fixture-2 --title "Overflow Fixture 2" --color 27ae60 --menu & echo \$! >> "$tray_overflow_pids_path"
"$python3_bin" "$stub" --id overflow-fixture-3 --title "Overflow Fixture 3" --color 2980b9 & echo \$! >> "$tray_overflow_pids_path"
"$python3_bin" "$stub" --id overflow-fixture-4 --title "Overflow Fixture 4" --color f1c40f & echo \$! >> "$tray_overflow_pids_path"
"$python3_bin" "$stub" --id overflow-fixture-5 --title "Overflow Fixture 5" --color 8e44ad & echo \$! >> "$tray_overflow_pids_path"
"$python3_bin" "$stub" --id overflow-fixture-6 --title "Overflow Fixture 6" --color 16a085 & echo \$! >> "$tray_overflow_pids_path"
sleep 7
"$qs_bin" ipc -p "$shell_path" call tray status > "$tray_overflow_status_path" 2>&1
"$grim_bin" "$tray_overflow_strip_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call panel toggle trayoverflow > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call tray status > "$tray_overflow_open_path" 2>&1
"$hyprctl_bin" -j layers > "$tray_overflow_layers_path" 2>&1
"$grim_bin" "$tray_overflow_bar_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call tray menu overflow-fixture-2 > "$tray_overflow_menu_reply_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call tray status > "$tray_overflow_menu_path" 2>&1
"$grim_bin" "$tray_overflow_menu_shot_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call panel close > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call bar chevron collapse > /dev/null 2>&1
sleep 2
"$grim_bin" "$tray_overflow_collapsed_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call bar chevron expand > /dev/null 2>&1
sleep 2
"$grim_bin" "$tray_overflow_expanded_path" > /dev/null 2>&1
EOF

  # The stubs sit in GLib.MainLoop().run() forever, same as --tray's.
  write_script "$kill_script" <<EOF
#!/usr/bin/env bash
if [ -f "$tray_overflow_pids_path" ]; then
  while read -r pid; do
    kill "\$pid" 2>/dev/null || true
  done < "$tray_overflow_pids_path"
fi
EOF
  add_cleanup "bash $kill_script"
  echo "exec-once = bash $script"
}

leg_tray_overflow_assert() {
  local total inline hidden open panels
  if [ ! -s "$tray_overflow_status_path" ]; then
    fail "no tray status produced for the overflow check"
  fi
  cat "$tray_overflow_status_path"; echo
  total=$("$jq_bin" -r '.items | length' "$tray_overflow_status_path")
  inline=$("$jq_bin" -r '.overflow.inline' "$tray_overflow_status_path")
  hidden=$("$jq_bin" -r '.overflow.hidden | length' "$tray_overflow_status_path")
  echo "tray: $inline of $total left on the strip, $hidden in the second bar"
  if [ "$total" -lt 6 ]; then
    fail "tray status did not report the 6 fixture items (got $total), stub registration likely failed"
  fi
  if [ "$inline" -ne 0 ]; then
    fail "the tray kept $inline items on a strip with no room for them; it moves whole or not at all"
  fi
  if [ "$hidden" -ne "$total" ]; then
    fail "the second bar holds $hidden of $total items; it holds the whole tray or the strip keeps it"
  fi
  if [ ! -f "$tray_overflow_strip_path" ]; then
    fail "no squeezed-strip screenshot produced"
  fi
  echo "SMOKE_TRAY_OVERFLOW_STRIP $tray_overflow_strip_path"
  # The same split, with the second bar up: the surface is a popout like any
  # other, so it answers PanelIpc and shows up as a formalshell:panel layer.
  if [ ! -s "$tray_overflow_open_path" ]; then
    fail "no tray status produced with the second bar open"
  fi
  open=$("$jq_bin" -r '.overflow.open' "$tray_overflow_open_path")
  if [ "$open" != "true" ]; then
    fail "panel toggle trayoverflow did not open the second bar, got: $(cat "$tray_overflow_open_path")"
  fi
  panels=$("$jq_bin" -r '[.[] | .levels[] | .[] | select(.namespace == "formalshell:panel")] | length' "$tray_overflow_layers_path" 2>/dev/null)
  echo "panel layers while the second bar is open: $panels"
  if [ "${panels:-0}" -lt 1 ]; then
    fail "the second bar reported itself open with no formalshell:panel layer mapped"
  fi
  if [ ! -f "$tray_overflow_bar_path" ]; then
    fail "no second-bar screenshot produced"
  fi
  echo "SMOKE_TRAY_OVERFLOW_BAR $tray_overflow_bar_path"
  # An item's own menu belongs to the bar its cell is in, so opening one
  # leaves that bar where it was. It used to take the bar down with it, which
  # is the gesture cancelling itself (owner, 2026-08-28: "right clicking a
  # tray item closes the bar").
  if ! grep -q '^ok$' "$tray_overflow_menu_reply_path" 2>/dev/null; then
    fail "tray menu was refused inside the second bar, got: $(cat "$tray_overflow_menu_reply_path" 2>/dev/null)"
  fi
  if [ "$("$jq_bin" -r '.overflow.open' "$tray_overflow_menu_path")" != "true" ]; then
    fail "opening a tray item's menu closed the second bar out from under it, got: $(cat "$tray_overflow_menu_path")"
  fi
  # Where the two sit is the frame's to say: both hang off the same bar edge
  # by the same rule, so a menu that did not stand clear of its owner drew
  # straight over it (owner, 2026-08-28). No layer box can show that, they are
  # both full-output surfaces.
  if [ ! -f "$tray_overflow_menu_shot_path" ]; then
    fail "no menu-over-the-second-bar screenshot produced"
  fi
  echo "SMOKE_TRAY_OVERFLOW_MENU $tray_overflow_menu_shot_path"
  # The regression the model cannot see: the toggle has to draw again after a
  # collapse, and it is the only cell on its side of the chevron, so these two
  # frames differ by it alone.
  if [ ! -f "$tray_overflow_collapsed_path" ] || [ ! -f "$tray_overflow_expanded_path" ]; then
    fail "no chevron round-trip screenshots produced"
  fi
  echo "SMOKE_TRAY_OVERFLOW_COLLAPSED $tray_overflow_collapsed_path"
  echo "SMOKE_TRAY_OVERFLOW_EXPANDED $tray_overflow_expanded_path"
  if cmp -s "$tray_overflow_collapsed_path" "$tray_overflow_expanded_path"; then
    fail "the tray's toggle did not come back from a chevron collapse: the two frames are byte-identical"
  fi
}
