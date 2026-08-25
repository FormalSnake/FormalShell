# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --center: a notify-send of this leg's own, then a long enough wait for the
# model's 8s popup timeout to move it (and --notify's, when the two flags
# combine) into the `pending` tier the centre lists. The wait is 14s rather
# than the 9 that timeout alone would need: on the VM's software renderer
# the shell reaches the bus several seconds after the drive script starts,
# so a notification's own clock begins well after its notify-send. Combine
# with --notify and the critical popup is still sticky in the popup layer,
# which is what makes the suppression claim readable: Center.qml is a fixed
# right-anchored full-height card wherever notifications.position puts the
# toast stack, so Toasts.qml drops its whole stack for as long as the centre
# is open and center.png shows the centre alone.
#
# `notifications status` brackets a showHistory round trip (the IPC stand-in
# for the bell cell's own click, which calls the same center.open()/close()),
# and `dismissOne` is asserted here rather than in --notify: it drops the
# front toast, which would change what that leg's own frames show.
leg_center_flag="--center"
leg_center_order=40
leg_center_needs="notify-send"

center_path="$shot_dir/center.png"
center_status_before_path="$shot_dir/center-status-before.json"
center_status_open_path="$shot_dir/center-status-open.json"
center_status_closed_path="$shot_dir/center-status-closed.json"
center_dismiss_one_path="$shot_dir/center-dismiss-one.txt"

leg_center_timing() {
  # center-drive.sh's own last status dump lands at 23s; this run's generic
  # smoke.png is taken after it, showing the session with the centre closed
  # again and the front toast gone.
  leg_timing 25 70
}

leg_center_drive() {
  local script="$shot_dir/center-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 3
"$notify_send_bin" -u normal 'Second' 'World'
sleep 14
"$qs_bin" ipc -p "$shell_path" call notifications status > "$center_status_before_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications showHistory > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call notifications status > "$center_status_open_path" 2>&1
"$grim_bin" "$center_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications dismissOne > "$center_dismiss_one_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications showHistory > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications status > "$center_status_closed_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_center_assert() {
  local f
  for f in "$center_status_before_path" "$center_status_open_path" "$center_status_closed_path"; do
    if [ -s "$f" ]; then
      cat "$f"; echo
    else
      fail "no notifications status produced at $f"
    fi
  done
  # "pending":0 would mean the expired notify-sends never reached the tier
  # the bell cell counts, and the summon would have shown an empty list.
  if grep -q '"pending":0,' "$center_status_before_path"; then
    fail "pending count was zero before the centre summon: $(cat "$center_status_before_path")"
  fi
  if ! grep -q '"centerOpen":false' "$center_status_before_path"; then
    fail "centre reported open before the summon: $(cat "$center_status_before_path")"
  fi
  if ! grep -q '"centerOpen":true' "$center_status_open_path"; then
    fail "showHistory did not open the centre: $(cat "$center_status_open_path")"
  fi
  if ! grep -q '"centerOpen":false' "$center_status_closed_path"; then
    fail "second showHistory did not close the centre: $(cat "$center_status_closed_path")"
  fi
  if [ ! -s "$center_dismiss_one_path" ]; then
    fail "no notifications dismissOne answer produced"
  fi
  cat "$center_dismiss_one_path"
  if leg_on notify; then
    # --notify's critical toast is sticky (expiresAt 0), so it is still the
    # only thing in the popup tier when dismissOne runs, and the tier has to
    # be empty afterwards.
    if ! grep -q "^ok$" "$center_dismiss_one_path"; then
      fail "dismissOne did not drop the sticky critical toast, got: $(cat "$center_dismiss_one_path")"
    fi
    if ! grep -q '"popups":0' "$center_status_closed_path"; then
      fail "a toast survived dismissOne: $(cat "$center_status_closed_path")"
    fi
  else
    # Run alone, every popup this leg fired has expired into pending by the
    # time dismissOne runs, and an empty popup tier answers `none` rather
    # than erroring.
    if ! grep -q "^none$" "$center_dismiss_one_path"; then
      fail "dismissOne on an empty popup tier did not answer none, got: $(cat "$center_dismiss_one_path")"
    fi
  fi
  if [ ! -f "$center_path" ]; then
    fail "no notification centre screenshot produced"
  fi
  echo "SMOKE_CENTER $center_path"
}
