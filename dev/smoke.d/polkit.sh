# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --polkit runs a real `pkexec true` against the real setuid wrapper, so the
# shell's registered agent is what the authority hands the conversation to.
# Both frames are the live dialog (prompt, then the error state after a wrong
# password), and the claim no frame can make is the last one: pkexec's own
# exit code, which is 0 only if the real password went through the agent and
# out to PAM.
#
# pkexec runs backgrounded inside the drive script with a trailing `wait`
# rather than as its own exec-once entry: the script has to keep typing into
# the dialog while pkexec sits blocked on the conversation, then collect its
# real exit code once that resolves.
leg_polkit_flag="--polkit"
leg_polkit_order=280
leg_polkit_needs="pkexec wtype"

polkit_active_path="$shot_dir/polkit-active.png"
polkit_error_path="$shot_dir/polkit-error.png"
polkit_rc_path="$shot_dir/polkit-rc.txt"
polkit_stderr_path="$shot_dir/polkit-stderr.txt"
polkit_debug_path="$shot_dir/polkit-debug.log"

# No nix fallback: a pkexec built as a plain derivation has no setuid bit
# (the store never preserves one), so it cannot escalate at all. This one has
# to already be the wrapper-owned binary a real polkit host installs.
need_pkexec() {
  if [ -z "${pkexec_bin:-}" ]; then
    if command -v pkexec >/dev/null 2>&1; then
      pkexec_bin=$(command -v pkexec)
    else
      echo "SMOKE_FAIL: pkexec not found on PATH, this leg needs a real security.polkit.enablePkexecWrapper host (the setuid wrapper), not a nix fallback" >&2
      exit 1
    fi
    # pkexec resets PATH to its own compiled-in secure default before exec'ing
    # the target, which has no notion of the nix store, so a bare `true`
    # 127s. `type -P`, not `command -v`: bash's own builtin shadows the real
    # binary and command -v returns the bare word, which 127s just the same.
    polkit_true_bin=$(type -P true)
  fi
}

# The dialog covers the whole output, so under --wallpaper this starts after
# that leg's last frame rather than sampling the desktop through a scrim.
polkit_t0() {
  if leg_on wallpaper; then echo 16; else echo 3; fi
}

leg_polkit_timing() {
  local t0
  t0=$(polkit_t0)
  # The script's own sleeps sum to t0+21; the `wait` past that blocks for
  # however long the socket-activated polkit-agent-helper conversation takes
  # to resolve, and a first-ever activation in this session is the slow path.
  leg_timing $((t0 + 29)) $((t0 + 60))
}

leg_polkit_drive() {
  local t0 script="$shot_dir/polkit-drive.sh"
  t0=$(polkit_t0)
  write_script "$script" <<EOF
#!/usr/bin/env bash
: > "$polkit_debug_path"
log() { echo "\$(date +%s.%N) \$1" >> "$polkit_debug_path"; }
log start
sleep $t0
"$pkexec_bin" "$polkit_true_bin" 2> "$polkit_stderr_path" &
polkit_pid=\$!
log "pkexec launched pid=\$polkit_pid"
sleep 3
"$grim_bin" "$polkit_active_path" > /dev/null 2>&1
log active-screenshot
sleep 1
"$wtype_bin" "wrong-password"
"$wtype_bin" -k Return
log wrong-password-typed
# polkit's PAM round trip is socket-activated (polkit-agent-helper@.service)
# rather than an in-process PamContext like --lock's, so the first
# conversation is genuinely slower to fail than --lock's 5s buffer allows.
sleep 10
"$grim_bin" "$polkit_error_path" > /dev/null 2>&1
log error-screenshot
sleep 1
"$wtype_bin" "formalshell-test"
"$wtype_bin" -k Return
log real-password-typed
sleep 3
wait \$polkit_pid
polkit_rc=\$?
log "pkexec exited rc=\$polkit_rc"
echo \$polkit_rc > "$polkit_rc_path"
EOF
  echo "exec-once = bash $script"
}

leg_polkit_assert() {
  [ -f "$polkit_active_path" ] || fail "no polkit-active screenshot produced"
  echo "SMOKE_POLKIT_ACTIVE $polkit_active_path"
  [ -f "$polkit_error_path" ] || fail "no polkit-error screenshot produced"
  echo "SMOKE_POLKIT_ERROR $polkit_error_path"
  if [ ! -s "$polkit_rc_path" ] || ! grep -q "^0$" "$polkit_rc_path"; then
    fail "pkexec true did not exit 0 after real authentication. Got: $(cat "$polkit_rc_path" 2>/dev/null); stderr: $(cat "$polkit_stderr_path" 2>/dev/null); debug: $(cat "$polkit_debug_path" 2>/dev/null)"
  fi
  # A prompt frame and an error frame cannot be the same picture: the wrong
  # password has to have visibly landed somewhere.
  if cmp -s "$polkit_active_path" "$polkit_error_path"; then
    fail "polkit-active and polkit-error screenshots are byte-identical: the wrong password never reached the dialog"
  fi
}
