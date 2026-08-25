# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --lock's whole sequence lives in one script: everything in it is strictly
# ordered (lock, prove it over IPC, photograph, type a wrong password,
# photograph the error state, type the real one, photograph unlocked, prove
# the flip back over IPC) with nothing needing to interleave.
#
# grim, not any compositor-side capture: the frames have to be taken while
# the session is genuinely locked, and grim talks wlr-screencopy as an
# ordinary client. wtype is a real virtual-keyboard-unstable-v1 client;
# LockIpc deliberately has no "type this password" verb (see its header), so
# the only way to prove the unlock path is to actually type into it.
leg_lock_flag="--lock"
leg_lock_order=110
leg_lock_needs="wtype"

lock_locked_path="$shot_dir/lock-locked.png"
lock_typing_path="$shot_dir/lock-typing.png"
lock_error_path="$shot_dir/lock-error.png"
lock_unlocked_path="$shot_dir/lock-unlocked.png"
lock_islocked1_path="$shot_dir/lock-islocked-1.txt"
lock_islocked2_path="$shot_dir/lock-islocked-2.txt"
lock_status_path="$shot_dir/lock-status.json"
lock_call_rc_path="$shot_dir/lock-call-rc.txt"
lock_before_sleep_rc_path="$shot_dir/lock-before-sleep-rc.txt"

# This leg's own clock. It starts late under --wallpaper so the two
# wallpaper frames land first, which puts a real matugen-recoloured gradient
# behind the lock plate in the bargain.
lock_t0() {
  if leg_on wallpaper; then echo 16; else echo 5; fi
}

leg_lock_fixture() {
  # lock-before-sleep's exit-0-always proof (spec §8), run BEFORE the
  # session ever starts a shell instance: the exact "no running instance"
  # case a real lock-before-sleep systemd unit has to survive. A bare `qs
  # ipc call lock lock` exits 255 here; the wrapper must not.
  local rc=0
  "$PWD/result/bin/formalshell-lock-before-sleep" || rc=$?
  echo "$rc" > "$lock_before_sleep_rc_path"
}

leg_lock_timing() {
  local t0
  t0=$(lock_t0)
  leg_timing $((t0 + 21)) $((t0 + 45))
}

leg_lock_drive() {
  local t0 script="$shot_dir/lock-drive.sh"
  t0=$(lock_t0)
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep $t0
"$qs_bin" ipc -p "$shell_path" call lock lock > /dev/null 2>&1
echo \$? > "$lock_call_rc_path"
sleep 1
"$qs_bin" ipc -p "$shell_path" call lock isLocked > "$lock_islocked1_path" 2>&1
sleep 3
"$grim_bin" "$lock_locked_path" > /dev/null 2>&1
sleep 2
"$wtype_bin" "wrong-password"
sleep 1
"$grim_bin" "$lock_typing_path" > /dev/null 2>&1
"$wtype_bin" -k Return
# The PAM round trip for a wrong password forks and execs through the whole
# auth stack, which on this VM is slower than a first glance suggests: a 2s
# buffer intermittently caught the frame before authError had updated.
sleep 5
"$grim_bin" "$lock_error_path" > /dev/null 2>&1
sleep 2
"$wtype_bin" "formalshell-test"
"$wtype_bin" -k Return
sleep 3
"$grim_bin" "$lock_unlocked_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call lock isLocked > "$lock_islocked2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call lock status > "$lock_status_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_lock_assert() {
  local f
  if [ ! -s "$lock_before_sleep_rc_path" ] || ! grep -q "^0$" "$lock_before_sleep_rc_path"; then
    fail "formalshell-lock-before-sleep did not exit 0 with no shell instance running. Got: $(cat "$lock_before_sleep_rc_path" 2>/dev/null)"
  fi
  if [ ! -s "$lock_call_rc_path" ] || ! grep -q "^0$" "$lock_call_rc_path"; then
    fail "lock lock IPC call exited non-zero. Got: $(cat "$lock_call_rc_path" 2>/dev/null)"
  fi
  if [ ! -s "$lock_islocked1_path" ] || ! grep -q "^true$" "$lock_islocked1_path"; then
    fail "lock isLocked did not report true right after lock(). Got: $(cat "$lock_islocked1_path" 2>/dev/null)"
  fi
  for f in "$lock_locked_path" "$lock_typing_path" "$lock_error_path" "$lock_unlocked_path"; do
    [ -f "$f" ] || fail "no lock screenshot produced at $f"
  done
  echo "SMOKE_LOCK_LOCKED $lock_locked_path"
  echo "SMOKE_LOCK_TYPING $lock_typing_path"
  echo "SMOKE_LOCK_ERROR $lock_error_path"
  echo "SMOKE_LOCK_UNLOCKED $lock_unlocked_path"
  if [ ! -s "$lock_islocked2_path" ] || ! grep -q "^false$" "$lock_islocked2_path"; then
    fail "lock isLocked did not flip back to false after the real password. Got: $(cat "$lock_islocked2_path" 2>/dev/null)"
  fi
  if [ ! -s "$lock_status_path" ]; then
    fail "no lock status produced"
  fi
  cat "$lock_status_path"; echo
  if ! grep -q '"locked":false' "$lock_status_path"; then
    fail "lock status did not report locked:false after unlock. Got: $(cat "$lock_status_path")"
  fi
  # The swappable-locker half (M45 D2): this run writes no `lock.command`, so
  # the built-in surface is the one that came up and `external` has to say so.
  if ! grep -q '"external":false' "$lock_status_path"; then
    fail "lock status did not report external:false with no lock.command set. Got: $(cat "$lock_status_path")"
  fi
  # A locked frame and an unlocked one cannot be the same picture. The
  # cheapest guard there is against a leg that photographed the desktop four
  # times while every IPC answer stayed perfectly plausible.
  if cmp -s "$lock_locked_path" "$lock_unlocked_path"; then
    fail "lock-locked and lock-unlocked screenshots are byte-identical: the lock surface never mapped"
  fi
}
