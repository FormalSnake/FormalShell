# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --toast-motion proves the row toast's own motion (Toasts.qml), slowed to a
# tenth (`debug motionScale`) and photographed back to back:
#
#   arrive   one sticky critical toast slides in from past the screen's right
#            edge: some frame has the card's box starting right of where it
#            rests, and the last one has it at rest.
#   restack  a second toast stacks in front of it, then `notifications
#            dismissOne` sends the front one away: the departing card keeps
#            its place while it fades and the older one closes up behind it,
#            so some frame in that burst matches neither settled pile.
#   rest     with motion back at full speed and the pile still, the toast
#            surface commits nothing for four seconds (rust only: only the
#            rust shell logs its commits).
#
# The row habit only: the bubble's own arrival is --notify-emerge's. The
# card's box is measured as the difference from the frame taken before any
# notification, below the bar so the bell cell's unread mark stays out of it.
leg_toast_motion_flag="--toast-motion"
leg_toast_motion_order=32
leg_toast_motion_needs="notify-send convert"

toast_motion_scale=1000
toast_motion_frames=24
toast_motion_frame_gap=0.12
toast_motion_body_top=60
toast_motion_scale_path="$shot_dir/toast-motion-scale.txt"
toast_motion_bare_path="$shot_dir/toast-motion-bare.png"
toast_motion_one_path="$shot_dir/toast-motion-one.png"
toast_motion_two_path="$shot_dir/toast-motion-two.png"
toast_motion_left_path="$shot_dir/toast-motion-left.png"
toast_motion_dismiss_path="$shot_dir/toast-motion-dismiss.txt"
toast_motion_rest_path="$shot_dir/toast-motion-rest.txt"

leg_toast_motion_validate() {
  local other
  for other in pantheon retro notify notify_emerge notify_close center reminder capture_edit \
    menu_emerge panel_emerge panel_handoff panel_morph join deform chevron_quiet osd polkit screensaver; do
    if leg_on "$other"; then
      echo "usage: --toast-motion measures the row toast's own frames and cannot combine with --${other//_/-}" >&2
      exit 1
    fi
  done
}

leg_toast_motion_timing() {
  leg_timing 50 110
}

leg_toast_motion_drive() {
  local script="$shot_dir/toast-motion-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
call() { $ipc call "\$@"; }
burst() {
  for i in \$(seq 1 $toast_motion_frames); do
    "$grim_bin" "$shot_dir/toast-motion-\$1-\$i.png" > /dev/null 2>&1
    sleep $toast_motion_frame_gap
  done
}
sleep 4
call debug motionScale $toast_motion_scale > "$toast_motion_scale_path" 2>&1
sleep 1
"$grim_bin" "$toast_motion_bare_path" > /dev/null 2>&1
"$notify_send_bin" -u critical 'First' 'The card that arrives'
burst arrive
sleep 4
"$grim_bin" "$toast_motion_one_path" > /dev/null 2>&1
"$notify_send_bin" -u critical 'Second' 'The card that leaves'
sleep 9
"$grim_bin" "$toast_motion_two_path" > /dev/null 2>&1
call notifications dismissOne > "$toast_motion_dismiss_path" 2>&1
burst leave
sleep 6
"$grim_bin" "$toast_motion_left_path" > /dev/null 2>&1
call debug motionScale 100 > /dev/null 2>&1
sleep 2
# Two status calls bracket the rest window in the shell's own log.
call notifications status > "$toast_motion_rest_path" 2>&1
sleep 4
call notifications status >> "$toast_motion_rest_path" 2>&1
EOF
  hypr_exec_once "bash $script"
}

# The box of everything that differs from the bare frame below the bar, as
# "w h x y", or nothing when the two match there.
toast_motion_box() {
  local frame="$1" h=$((1080 - toast_motion_body_top)) rect
  rect=$($convert_bin "$toast_motion_bare_path" "$frame" -crop "1920x${h}+0+${toast_motion_body_top}" +repage \
    -compose difference -composite -threshold 2% -format "%@" info: 2>/dev/null)
  local w=${rect%%x*} rh=${rect#*x}
  rh=${rh%%+*}
  [ "${w:-0}" -gt 0 ] || return 0
  local x y
  x=$(echo "$rect" | sed -n 's/.*+\([0-9]*\)+[0-9]*$/\1/p')
  y=$(echo "$rect" | sed -n 's/.*+\([0-9]*\)$/\1/p')
  echo "$w $rh $x $((y + toast_motion_body_top))"
}

leg_toast_motion_assert() {
  local f i
  grep -q '^ok$' "$toast_motion_scale_path" 2>/dev/null \
    || fail "debug motionScale did not answer ok, got: $(cat "$toast_motion_scale_path" 2>/dev/null)"
  for f in "$toast_motion_bare_path" "$toast_motion_one_path" "$toast_motion_two_path" "$toast_motion_left_path"; do
    [ -f "$f" ] || fail "no screenshot produced at $f"
    echo "SMOKE_TOAST_MOTION_FRAME $f"
  done

  local rest rw rh rx ry
  rest=$(toast_motion_box "$toast_motion_one_path")
  read -r rw rh rx ry <<< "$rest"
  [ "${rw:-0}" -ge 200 ] && [ "${rh:-0}" -ge 40 ] || fail "could not measure the resting toast, got '$rest'"
  echo "SMOKE_TOAST_MOTION_REST ${rw}x${rh}+${rx}+${ry}"

  local box w h x y slid=0 last="" xs=""
  for i in $(seq 1 $toast_motion_frames); do
    box=$(toast_motion_box "$shot_dir/toast-motion-arrive-$i.png")
    [ -n "$box" ] || { xs+=" -"; continue; }
    read -r w h x y <<< "$box"
    xs+=" $x"
    if [ "$x" -gt $((rx + 4)) ]; then
      slid=$((slid + 1))
    fi
    last="$box"
  done
  echo "SMOKE_TOAST_MOTION_ARRIVE_X$xs rest=$rx"
  [ "$slid" -gt 0 ] || fail "no arrival frame had the card right of its rest (x$xs, rest $rx): the row toast did not slide in"
  read -r w h x y <<< "$last"
  [ "$x" -eq "$rx" ] || fail "the arrival's last frame was not at rest (x $x, rest $rx)"

  grep -q '^ok$' "$toast_motion_dismiss_path" 2>/dev/null \
    || fail "notifications dismissOne did not answer ok, got: $(cat "$toast_motion_dismiss_path" 2>/dev/null)"
  local crop="1920x$((1080 - toast_motion_body_top))+0+${toast_motion_body_top}" between=0 to_two to_left trail=""
  ae() { $convert_bin "$1" "$2" -crop "$crop" +repage -metric AE -compare -format '%[distortion]' info: 2>/dev/null; }
  same() { [ "$(ae "$1" "$2")" = 0 ]; }
  for i in $(seq 1 $toast_motion_frames); do
    f="$shot_dir/toast-motion-leave-$i.png"
    [ -f "$f" ] || fail "no screenshot produced at $f"
    to_two=$(ae "$f" "$toast_motion_two_path")
    to_left=$(ae "$f" "$toast_motion_left_path")
    trail+=" $to_two/$to_left"
    if [ "$to_two" != 0 ] && [ "$to_left" != 0 ]; then
      between=$((between + 1))
    fi
    case $i in 2|5|9|14) echo "SMOKE_TOAST_MOTION_LEAVE_$i $f" ;; esac
  done
  # Pixels off the pile of two and off the one left behind, per frame.
  echo "SMOKE_TOAST_MOTION_LEAVE_AE$trail"
  echo "SMOKE_TOAST_MOTION_LEAVE $between of $toast_motion_frames frames between the two piles"
  [ "$between" -gt 0 ] || fail "the dismissal cut from one pile to the other with no frame between"
  # The box rather than every pixel: QML's card can land on a fractional y
  # after a restack and antialias its last row differently.
  local left
  left=$(toast_motion_box "$toast_motion_left_path")
  [ "$left" = "$rest" ] || fail "the pile left behind is not the one card at rest (box '$left', rest '$rest')"

  local commits
  commits=$(awk '
    function t(line) { match(line, /t=[0-9]+ms/); return substr(line, RSTART + 2, RLENGTH - 4) + 0 }
    /^ipc t=.*target: "notifications", function: "status"/ { lo = hi; hi = t($0) }
    /^commit surface=toasts / { c[++n] = t($0) }
    END { k = 0; for (i = 1; i <= n; i++) if (c[i] > lo && c[i] < hi) k++; print (lo > 0 ? k : -1) }' "$shell_log_path")
  echo "SMOKE_TOAST_MOTION_QUIET commits=$commits"
  [ "$commits" -ge 0 ] || fail "no rest window bracketed in the shell log"
  [ "$commits" -eq 0 ] || fail "the toast surface committed $commits times with the pile at rest"
}
