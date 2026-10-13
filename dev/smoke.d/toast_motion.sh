# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --toast-motion proves the row toast's own motion, slowed to a
# tenth (`debug motionScale`) and photographed back to back:
#
#   arrive   one sticky critical toast rises out of the bottom edge the way
#            sonner's does: some frame has the card's box starting below
#            where it rests at the same x, and the last one has it at rest.
#   pile     a second toast stacks in front of it: the pile is the front
#            card at the first one's rest plus one peek offset of the card
#            behind showing above it, and nothing below the front card's
#            bottom edge, since a card behind takes the front one's height.
#   fan      `notifications expand on`, the rig's stand-in for the pointer
#            over the pile, fans it out: on every frame of the burst no
#            pixel of the front card's own rect is more than 1% off what it
#            was collapsed (the card in front neither moves nor resizes while the one
#            behind comes forward), and the settled column is both cards a
#            `panelPadding` apart in the pile's own order, the front one
#            still last. `expand off` folds it back before the next phase.
#   restack  `notifications dismissOne` then sends the front one away: it
#            drops back toward the edge while it fades and the older one
#            comes forward, so some frame in that burst matches neither
#            settled pile.
#   rest     with motion at full speed and the one card at rest, between
#            arrive and pile, the toast surface commits nothing for four
#            seconds (rust only: only the
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
# `panelPadding`, the collapsed pile's peek offset.
toast_motion_peek=12
toast_motion_scale_path="$shot_dir/toast-motion-scale.txt"
toast_motion_bare_path="$shot_dir/toast-motion-bare.png"
toast_motion_one_path="$shot_dir/toast-motion-one.png"
toast_motion_two_path="$shot_dir/toast-motion-two.png"
toast_motion_fanned_path="$shot_dir/toast-motion-fanned.png"
toast_motion_folded_path="$shot_dir/toast-motion-folded.png"
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
  leg_timing 80 150
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
# The rest window runs while the one card is seconds old, well clear of
# its relative time ticking from "now" to "1m".
call debug motionScale 100 > /dev/null 2>&1
sleep 2
# Two status calls bracket the rest window in the shell's own log.
call notifications status > "$toast_motion_rest_path" 2>&1
sleep 4
call notifications status >> "$toast_motion_rest_path" 2>&1
call debug motionScale $toast_motion_scale > /dev/null 2>&1
"$notify_send_bin" -u critical 'Second' 'The card that leaves'
sleep 9
"$grim_bin" "$toast_motion_two_path" > /dev/null 2>&1
call notifications expand on > /dev/null 2>&1
burst fan
sleep 4
"$grim_bin" "$toast_motion_fanned_path" > /dev/null 2>&1
call notifications expand off > /dev/null 2>&1
sleep 8
"$grim_bin" "$toast_motion_folded_path" > /dev/null 2>&1
call notifications dismissOne > "$toast_motion_dismiss_path" 2>&1
burst leave
sleep 6
"$grim_bin" "$toast_motion_left_path" > /dev/null 2>&1
call debug motionScale 100 > /dev/null 2>&1
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

  local box w h x y slid=0 last="" ys=""
  for i in $(seq 1 $toast_motion_frames); do
    box=$(toast_motion_box "$shot_dir/toast-motion-arrive-$i.png")
    [ -n "$box" ] || { ys+=" -"; continue; }
    read -r w h x y <<< "$box"
    ys+=" $y"
    [ "$x" -eq "$rx" ] || fail "an arrival frame had the card off its column (x $x, rest $rx): the row toast moves on y alone"
    if [ "$y" -gt $((ry + 4)) ]; then
      slid=$((slid + 1))
    fi
    last="$box"
  done
  echo "SMOKE_TOAST_MOTION_ARRIVE_Y$ys rest=$ry"
  [ "$slid" -gt 0 ] || fail "no arrival frame had the card below its rest (y$ys, rest $ry): the row toast did not rise in"
  read -r w h x y <<< "$last"
  [ "$x $y" = "$rx $ry" ] || fail "the arrival's last frame was not at rest ($x,$y, rest $rx,$ry)"

  local pile pw ph px py
  pile=$(toast_motion_box "$toast_motion_two_path")
  read -r pw ph px py <<< "$pile"
  echo "SMOKE_TOAST_MOTION_PILE ${pw}x${ph}+${px}+${py}"
  [ "$px $pw" = "$rx $rw" ] || fail "the pile of two is not the front card's column (box '$pile', rest '$rest')"
  [ $((py + ph)) -eq $((ry + rh)) ] || fail "the pile's bottom edge moved off the front card's (box '$pile', rest '$rest'): a card behind shows under it"
  [ "$ph" -eq $((rh + toast_motion_peek)) ] || fail "the pile of two is $ph tall, not the front card's $rh plus one ${toast_motion_peek}px peek"

  local front="${rw}x${rh}+${rx}+${ry}" moved=0 drift="" d
  for f in "$toast_motion_fanned_path" "$toast_motion_folded_path"; do
    [ -f "$f" ] || fail "no screenshot produced at $f"
  done
  for i in $(seq 1 $toast_motion_frames); do
    f="$shot_dir/toast-motion-fan-$i.png"
    [ -f "$f" ] || fail "no screenshot produced at $f"
    # Past 1%: the damage a card behind leaves recomposites the front
    # card's tiles, which can land its antialiased text a value off.
    d=$($convert_bin "$f" "$toast_motion_two_path" -crop "$front" +repage -fuzz 1% -metric AE -compare -format '%[distortion]' info: 2>/dev/null)
    drift+=" $d"
    [ "$d" = 0 ] || moved=$((moved + 1))
    case $i in 3|8|14) echo "SMOKE_TOAST_MOTION_FAN_$i $f" ;; esac
  done
  echo "SMOKE_TOAST_MOTION_FAN_FRONT_AE$drift"
  [ "$moved" -eq 0 ] || fail "the front card's own pixels changed on $moved of $toast_motion_frames frames while the pile fanned out"
  local fan fw fh fx fy
  fan=$(toast_motion_box "$toast_motion_fanned_path")
  read -r fw fh fx fy <<< "$fan"
  echo "SMOKE_TOAST_MOTION_FANNED ${fw}x${fh}+${fx}+${fy}"
  [ "$fx $fw" = "$rx $rw" ] && [ $((fy + fh)) -eq $((ry + rh)) ] && [ "$fh" -eq $((rh * 2 + toast_motion_peek)) ] \
    || fail "the fanned column is not two cards ${toast_motion_peek}px apart ending on the front card's rest (box '$fan', rest '$front')"
  [ "$(toast_motion_box "$toast_motion_folded_path")" = "$pile" ] || fail "expand off did not fold the column back into the pile of two"

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
  # The box rather than every pixel: the card can land on a fractional y
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
