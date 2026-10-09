# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --sleep suspends the machine through logind with the session unlocked and
# reads the lock back after wake. `sudo systemctl suspend` is the real path:
# logind signals PrepareForSleep(true), waits on every delay inhibitor, then
# starts suspend.target. Only the kernel's freeze is stubbed (nix/testvm.nix
# carries why), and the stub stamps the millisecond logind got there, which
# has to come after the shell let its inhibitor go with the surface secure.
# The FormalShell delay inhibitor is read off `systemd-inhibit --list` before
# the suspend and again after wake, when it has to be held again.
leg_sleep_flag="--sleep"
leg_sleep_order=112
leg_sleep_vm_only="it suspends the machine through logind with sudo"
leg_sleep_needs="jq wtype"

sleep_inhibit_before_path="$shot_dir/sleep-inhibitors-before.txt"
sleep_inhibit_after_path="$shot_dir/sleep-inhibitors-after.txt"
sleep_status_before_path="$shot_dir/sleep-lock-status-before.json"
sleep_status_after_path="$shot_dir/sleep-lock-status-after.json"
sleep_suspend_rc_path="$shot_dir/sleep-suspend-rc.txt"
sleep_suspended_at_path="$shot_dir/sleep-suspended-at.txt"
sleep_locked_path="$shot_dir/sleep-locked.png"

leg_sleep_timing() {
  leg_timing 24 50
}

leg_sleep_drive() {
  local script="$shot_dir/sleep-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sudo -n rm -f /run/formalshell-suspended-at
sleep 5
systemd-inhibit --list --no-pager > "$sleep_inhibit_before_path" 2>&1
$ipc call lock status > "$sleep_status_before_path" 2>&1
sudo -n systemctl suspend
echo \$? > "$sleep_suspend_rc_path"
# The stub holds suspend.target for 2s, and PrepareForSleep(false) follows it.
for _ in \$(seq 1 30); do
  [ -s /run/formalshell-suspended-at ] && break
  sleep 0.5
done
sleep 4
cat /run/formalshell-suspended-at > "$sleep_suspended_at_path" 2>&1
$ipc call lock status > "$sleep_status_after_path" 2>&1
systemd-inhibit --list --no-pager > "$sleep_inhibit_after_path" 2>&1
"$grim_bin" "$sleep_locked_path" > /dev/null 2>&1
"$wtype_bin" "formalshell-test"
"$wtype_bin" -k Return
EOF
  hypr_exec_once "bash $script"
}

sleep_inhibitor_held() {
  grep -E '^FormalShell +[0-9]+ +test .* sleep +Lock the session before sleep +delay' "$1" > /dev/null
}

leg_sleep_assert() {
  local f suspended released
  for f in "$sleep_inhibit_before_path" "$sleep_status_before_path" "$sleep_suspend_rc_path" \
    "$sleep_suspended_at_path" "$sleep_status_after_path" "$sleep_inhibit_after_path"; do
    [ -s "$f" ] || fail "sleep: $f missing or empty"
    cat "$f"; echo
  done
  [ -s "$sleep_locked_path" ] && echo "SMOKE_SLEEP_LOCKED $sleep_locked_path"
  sleep_inhibitor_held "$sleep_inhibit_before_path" \
    || fail "sleep: no FormalShell delay inhibitor on sleep before the suspend"
  jq -e '.locked == false and .beforeSleep.enabled == true and .beforeSleep.monitoring == true
    and .beforeSleep.inhibiting == true and .beforeSleep.last == null' "$sleep_status_before_path" > /dev/null \
    || fail "sleep: the shell was not unlocked and watching logind before the suspend"
  grep -q '^0$' "$sleep_suspend_rc_path" || fail "sleep: systemctl suspend exited $(cat "$sleep_suspend_rc_path")"
  jq -e '.locked == true and .secure == true and .beforeSleep.last.result == "ok"
    and .beforeSleep.last.release == "secure"' "$sleep_status_after_path" > /dev/null \
    || fail "sleep: PrepareForSleep did not lock the session and release on secure"
  suspended=$(cat "$sleep_suspended_at_path")
  released=$(jq -r '.beforeSleep.last.releasedAt' "$sleep_status_after_path")
  [[ "$suspended" =~ ^[0-9]+$ ]] || fail "sleep: logind never reached the suspend stub"
  [ "$released" -le "$suspended" ] \
    || fail "sleep: suspend began at $suspended, before the inhibitor was let go at $released"
  echo "sleep: inhibitor released at $released, suspend began at $suspended ($((suspended - released))ms later)"
  sleep_inhibitor_held "$sleep_inhibit_after_path" \
    || fail "sleep: the FormalShell delay inhibitor was not taken again after wake"
  jq -e '.beforeSleep.inhibiting == true' "$sleep_status_after_path" > /dev/null \
    || fail "sleep: lock status reports no inhibitor after wake"
}
