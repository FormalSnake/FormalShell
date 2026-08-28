# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --tray-overflow squeezes the tray until it has to give ground, and reads
# back where the items went. The strip is pinned to one region holding a
# qml module of a fixed width and the tray behind it, so the room the tray
# is left with is arithmetic rather than a guess: a 1692px module on a
# 1920px output leaves the rail a couple of hundred pixels, which is a few
# cells and the toggle. What has to be true is the split itself: some items
# still on the strip, the rest reachable in the second bar, and the two
# adding up to every item registered. The exact cut is left loose on
# purpose, since it is a pixel measurement of real font metrics and pinning
# it would fail on a rebuild that moved a cell by 2px, while
# tests/tst_tray_overflow.qml pins the arithmetic itself.
#
# The second bar is opened over `panel toggle trayoverflow` (it is a popout
# in PanelIpc's registry like any other), which is also the only way in
# without a synthetic pointer to click the toggle with.
#
# It owns bar.layout, so it does not combine with --bar-layout or
# --bar-position, and it registers stubs of its own, so --tray's own count
# assert does not survive the pair either.
leg_tray_overflow_flag="--tray-overflow"
leg_tray_overflow_order=172
# need_python3 is tray.sh's (sourced first, alphabetically), the same shared
# `need_<bin>` resolution every leg uses.
leg_tray_overflow_needs="python3 jq"

tray_overflow_pad_path="$shot_dir/tray-overflow-pad.qml"
tray_overflow_pids_path="$shot_dir/tray-overflow-pids.txt"
tray_overflow_status_path="$shot_dir/tray-overflow-status.json"
tray_overflow_open_path="$shot_dir/tray-overflow-open.json"
tray_overflow_layers_path="$shot_dir/tray-overflow-layers.json"
tray_overflow_strip_path="$shot_dir/tray-overflow-strip.png"
tray_overflow_bar_path="$shot_dir/tray-overflow-bar.png"

leg_tray_overflow_fixture() {
  # A cell of a stated width and nothing else: the point is the room it
  # takes, so a Text whose width is a font metric would put the whole
  # measurement at the mercy of the fixture's own string.
  cat > "$tray_overflow_pad_path" <<'EOF'
import QtQuick

Item {
    implicitWidth: 1692
    implicitHeight: 13
}
EOF
  # Both other regions empty, so the strip's whole length is this one
  # region's to run out of.
  settings_fragment ', "bar": {"layout": {"left": [], "center": [], "right": ["custom:traypad", "tray"]}, "modules": [{"id": "traypad", "type": "qml", "source": "'"$tray_overflow_pad_path"'"}]}'
}

leg_tray_overflow_timing() {
  # The drive's last step lands ~14s in; the run's own frame is taken past
  # it, with the second bar closed again and the squeezed strip in view.
  leg_timing 18 45
}

leg_tray_overflow_drive() {
  local script="$shot_dir/tray-overflow-drive.sh"
  local kill_script="$shot_dir/tray-overflow-kill.sh"
  local stub="$PWD/dev/sni-stub.py"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 1
"$python3_bin" "$stub" --id overflow-fixture-1 --title "Overflow Fixture 1" --color c0392b & echo \$! >> "$tray_overflow_pids_path"
"$python3_bin" "$stub" --id overflow-fixture-2 --title "Overflow Fixture 2" --color 27ae60 & echo \$! >> "$tray_overflow_pids_path"
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
"$qs_bin" ipc -p "$shell_path" call panel close > /dev/null 2>&1
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
  echo "tray split: $inline of $total inline, $hidden in the second bar"
  if [ "$total" -lt 6 ]; then
    fail "tray status did not report the 6 fixture items (got $total), stub registration likely failed"
  fi
  if [ "$hidden" -lt 1 ]; then
    fail "the tray kept all $total items on a strip with no room for them"
  fi
  if [ "$inline" -lt 1 ]; then
    fail "the tray gave up every item; the pad module left it no room at all, so this measures nothing"
  fi
  if [ "$((inline + hidden))" -ne "$total" ]; then
    fail "the split loses items: $inline inline + $hidden hidden is not $total"
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
}
