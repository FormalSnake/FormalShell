# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --chevron-overflow is --chevron's other half (M52): the same right region,
# the same five governed cells, on a bar with no room left to open them in.
# A `command` module in the centre stands in for the track that made the owner
# report it (2026-09-01): a wide centre squeezes both end regions, and an
# expanded group used to clip against it and simply not be there. It now moves
# whole into a second bar hanging off the chevron, the way the tray already
# answers a strip that has run out of edge.
#
# The centre's width is the whole fixture: nothing about the run drives it,
# Bar.qml measures the room and decides, and `bar chevron status` publishes
# which of the two the region is in.
leg_chevron_overflow_flag="--chevron-overflow"
leg_chevron_overflow_order=182

chevron_overflow_wide_path="$shot_dir/chevron-overflow-wide.qml"
chevron_overflow_status_closed_path="$shot_dir/chevron-overflow-status-closed.json"
chevron_overflow_status_open_path="$shot_dir/chevron-overflow-status-open.json"
chevron_overflow_status_shut_path="$shot_dir/chevron-overflow-status-shut.json"
chevron_overflow_expand_reply_path="$shot_dir/chevron-overflow-expand-reply.txt"
chevron_overflow_closed_path="$shot_dir/chevron-overflow-closed.png"
chevron_overflow_open_path="$shot_dir/chevron-overflow-open.png"

leg_chevron_overflow_fixture() {
  # A `qml` module rather than a `command` one, for a centre whose width is a
  # number rather than a guess about a font: 1580px of fixture plus the cell's
  # own padding leaves the right region less than its governed group costs on
  # this rig's 1920px output, and still enough for the cells outboard of the
  # chevron. A text length would have decided both of those in whatever
  # metrics the VM's fontconfig resolved.
  cat > "$chevron_overflow_wide_path" <<'EOF'
import QtQuick
import qs.Core

Item {
    implicitWidth: 1580
    implicitHeight: label.implicitHeight

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: "A WIDE CENTRE CELL, STANDING IN FOR A PLAYING TRACK"
        color: Theme.color.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.body
    }
}
EOF
  settings_fragment ', "bar": {"layout": {"center": ["custom:widecentre"], "right": ["bluetooth", "weather", "tray", "bell", "indicators", "chevron", "battery", "audio", "network"]}, "modules": [{"id": "widecentre", "type": "qml", "source": "'"$chevron_overflow_wide_path"'"}]}'
}

leg_chevron_overflow_timing() {
  leg_timing 14 40
}

leg_chevron_overflow_drive() {
  local script="$shot_dir/chevron-overflow-drive.sh"
  # 5s: the shell up, the centre module loaded, and the fit settled
  # (Bar.qml refits a frame's worth past its last input, an order of magnitude
  # inside this).
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 5
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_overflow_status_closed_path" 2>&1
sleep 1
"$grim_bin" "$chevron_overflow_closed_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call bar chevron expand > "$chevron_overflow_expand_reply_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_overflow_status_open_path" 2>&1
sleep 1
"$grim_bin" "$chevron_overflow_open_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call bar chevron collapse > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_overflow_status_shut_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_chevron_overflow_assert() {
  local names='"bluetooth","weather","tray","bell","indicators"'
  if [ ! -s "$chevron_overflow_status_closed_path" ]; then
    fail "no bar chevron status (closed) produced"
  fi
  cat "$chevron_overflow_status_closed_path"; echo
  # Named before the claims below, so a run that fails one still hands the
  # frame back to look at.
  if [ -f "$chevron_overflow_closed_path" ]; then
    echo "SMOKE_CHEVRON_OVERFLOW_CLOSED $chevron_overflow_closed_path"
  fi
  if [ -f "$chevron_overflow_open_path" ]; then
    echo "SMOKE_CHEVRON_OVERFLOW_OPEN $chevron_overflow_open_path"
  fi
  # The measurement itself: this bar has no room for the group, so it is off
  # the strip and the second bar is where it opens.
  if ! grep -q '"offStrip":true' "$chevron_overflow_status_closed_path"; then
    fail "the right group still claims room on a bar with a 1600px centre. Got: $(cat "$chevron_overflow_status_closed_path")"
  fi
  if ! grep -q "\"hidden\":\[$names\]" "$chevron_overflow_status_closed_path"; then
    fail "bar chevron status did not report the governed names as off the strip. Got: $(cat "$chevron_overflow_status_closed_path")"
  fi
  if [ ! -f "$chevron_overflow_closed_path" ]; then
    fail "no chevron-overflow-closed screenshot produced"
  fi
  if ! grep -q '^ok$' "$chevron_overflow_expand_reply_path" 2>/dev/null; then
    fail "bar chevron expand was refused. Got: $(cat "$chevron_overflow_expand_reply_path" 2>/dev/null)"
  fi
  if [ ! -s "$chevron_overflow_status_open_path" ]; then
    fail "no bar chevron status (open) produced"
  fi
  cat "$chevron_overflow_status_open_path"; echo
  # Expanding a group with nowhere to go opens the second bar instead of
  # writing a state the strip cannot act on: the stored collapse is untouched,
  # so the group comes back where the user left it once the room does.
  if ! grep -q '"overflowOpen":true' "$chevron_overflow_status_open_path"; then
    fail "bar chevron expand did not open the second bar. Got: $(cat "$chevron_overflow_status_open_path")"
  fi
  if ! grep -q '"collapsed":true' "$chevron_overflow_status_open_path"; then
    fail "bar chevron expand wrote the collapse state on a group that never reached the strip. Got: $(cat "$chevron_overflow_status_open_path")"
  fi
  if ! grep -q "\"hidden\":\[$names\]" "$chevron_overflow_status_open_path"; then
    fail "the governed names left the off-strip set while the second bar was up. Got: $(cat "$chevron_overflow_status_open_path")"
  fi
  if [ ! -f "$chevron_overflow_open_path" ]; then
    fail "no chevron-overflow-open screenshot produced"
  fi
  if cmp -s "$chevron_overflow_closed_path" "$chevron_overflow_open_path"; then
    fail "chevron-overflow-closed and chevron-overflow-open screenshots are byte-identical: the second bar opened and rendered nothing"
  fi
  if [ ! -s "$chevron_overflow_status_shut_path" ]; then
    fail "no bar chevron status (shut) produced"
  fi
  if ! grep -q '"overflowOpen":false' "$chevron_overflow_status_shut_path"; then
    fail "bar chevron collapse left the second bar open. Got: $(cat "$chevron_overflow_status_shut_path")"
  fi
}
