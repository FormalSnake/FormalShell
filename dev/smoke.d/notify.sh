# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --notify: a normal and a critical notify-send into the private bus, then
# `notifications expand on/off`, the rig's stand-in for hovering the stack
# (there is no synthetic pointer here). The expanded frame lands a beat
# after the toggle so the reflow has settled, and `expand off` restores the
# collapsed pile the run's own smoke.png reads.
leg_notify_flag="--notify"
leg_notify_order=30
leg_notify_needs="notify-send"

toasts_expanded_path="$shot_dir/toasts-expanded.png"
toasts_expand_status_path="$shot_dir/toasts-expand-status.txt"

leg_notify_drive() {
  local script="$shot_dir/notify-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 3
"$notify_send_bin" -u normal 'Test' 'Hello'
sleep 1
"$notify_send_bin" -u critical 'Crit' 'Now'
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications expand on > "$toasts_expand_status_path" 2>&1
sleep 1
"$grim_bin" "$toasts_expanded_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications expand off > /dev/null 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_notify_assert() {
  echo "host org.freedesktop.Notifications owner PID unchanged: $host_notifications_owner_after"
  if [ ! -s "$toasts_expand_status_path" ]; then
    fail "no notifications expand status produced"
  fi
  cat "$toasts_expand_status_path"
  if ! grep -q "^on$" "$toasts_expand_status_path"; then
    fail "notifications expand on did not report on, got: $(cat "$toasts_expand_status_path")"
  fi
  if [ ! -f "$toasts_expanded_path" ]; then
    fail "no toasts-expanded screenshot produced"
  fi
  echo "SMOKE_TOASTS_EXPANDED $toasts_expanded_path"
}
