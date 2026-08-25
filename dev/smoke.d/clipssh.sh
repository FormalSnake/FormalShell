# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --clipssh: the menu's clipssh route driven the way a user drives it, over
# `menu activate` (the rig's Enter stand-in), against a PATH-shimmed clipssh
# speaking the real one's output contract: `box` takes six seconds and
# succeeds, `nohost` fails at once.
#
# What is under test is the shell's own path (row -> `@ipc:clipssh.send:` ->
# ClipsshService -> Process -> exit code -> toast plus the bar indicator that
# is up for exactly as long as the process runs), not whether the rig can
# reach an ssh host, so the shim stands in for the binary the same way the
# gpu leg's nvidia-smi does. It records every invocation, which is the one
# claim no frame can make: the alias the row carried reached the command
# line.
#
# Four frames off one timeline: the route's own rows, the transfer in flight
# (indicator cell up, SENDING toast beside it), the same transfer landed
# (COPIED, carrying the remote path the shim printed), and the failure card
# carrying clipssh's own `Error:` line. The two transfers are sequential on
# purpose: the service refuses a second while one is in flight, so an overlap
# would test the refusal rather than the failure path.
leg_clipssh_flag="--clipssh"
leg_clipssh_order=135

clipssh_shim_dir="$shot_dir/clipssh-shim"
clipssh_calls_path="$shot_dir/clipssh-calls.txt"
clipssh_summon_reply_path="$shot_dir/clipssh-summon-reply.txt"
clipssh_send_reply_path="$shot_dir/clipssh-send-reply.txt"
clipssh_fail_summon_reply_path="$shot_dir/clipssh-fail-summon-reply.txt"
clipssh_fail_reply_path="$shot_dir/clipssh-fail-reply.txt"
clipssh_notify_status_path="$shot_dir/clipssh-notify-status.json"
clipssh_route_png="$shot_dir/clipssh-route.png"
clipssh_sending_png="$shot_dir/clipssh-sending.png"
clipssh_copied_png="$shot_dir/clipssh-copied.png"
clipssh_failed_png="$shot_dir/clipssh-failed.png"

leg_clipssh_fixture() {
  # clipssh's own alias store, in the isolated HOME so the route's rows are
  # this run's two and not whatever the host has saved. `nohost` is the row
  # whose transfer fails; the shim keys its failure off that name.
  mkdir -p "$iso_home/.clipssh"
  printf '%s\n' 'box=test@10.255.255.7' 'nohost=test@10.255.255.1' > "$iso_home/.clipssh/aliases"

  mkdir -p "$clipssh_shim_dir"
  # clipssh's own output contract, read off its script (v1.0.0): "Uploaded:
  # <path>" on stdout at exit 0, "Error: <reason>" on stderr otherwise, both
  # ANSI-coloured. Six seconds over the success case so the in-flight state
  # is a thing a frame can catch.
  cat > "$clipssh_shim_dir/clipssh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${1:-}" >> "$clipssh_calls_path"
if [ "\${1:-}" = "nohost" ]; then
  printf '\033[0;31mError:\033[0m Failed to upload to test@10.255.255.1\n' >&2
  exit 1
fi
sleep 6
printf '\033[0;32mUploaded: /tmp/clipboard-1755180000.png\033[0m\n'
printf 'Path copied to clipboard - paste it directly\n'
EOF
  chmod +x "$clipssh_shim_dir/clipssh"
  # The scaffold owns the shell's launch line, so a shim reaches the shell by
  # riding the rig's own environment into the session: PATH is not in
  # session_env, so this is what Hyprland and everything it spawns inherit.
  # Safe to widen that far because the shim answers to one name and every
  # binary the scaffold itself resolved is already an absolute path. The
  # route is gated on `command -v clipssh` (default-menu.jsonc), so this is
  # also what makes it exist at all.
  export PATH="$clipssh_shim_dir:$PATH"
}

leg_clipssh_timing() {
  # The frame script's last grim lands at 26s; this run's own smoke.png comes
  # after all four, on a session with nothing in flight and the indicator
  # gone again.
  leg_timing 30 70
}

leg_clipssh_drive() {
  local script="$shot_dir/clipssh-drive.sh" frames="$shot_dir/clipssh-frames.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc -p "$shell_path" call menu summon clipssh > "$clipssh_summon_reply_path" 2>&1
sleep 3
"$qs_bin" ipc -p "$shell_path" call menu activate 0 > "$clipssh_send_reply_path" 2>&1
sleep 12
"$qs_bin" ipc -p "$shell_path" call menu summon clipssh > "$clipssh_fail_summon_reply_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call menu activate 1 > "$clipssh_fail_reply_path" 2>&1
sleep 4
"$qs_bin" ipc -p "$shell_path" call notifications status > "$clipssh_notify_status_path" 2>&1
EOF
  # Frames on their own clock rather than interleaved with the calls above:
  # each `qs ipc` spawn costs about a second on llvmpipe, and both toast
  # windows the middle two frames aim at are only six seconds wide.
  write_script "$frames" <<EOF
#!/usr/bin/env bash
sleep 6
"$grim_bin" "$clipssh_route_png" > /dev/null 2>&1
sleep 5
"$grim_bin" "$clipssh_sending_png" > /dev/null 2>&1
sleep 5
"$grim_bin" "$clipssh_copied_png" > /dev/null 2>&1
sleep 10
"$grim_bin" "$clipssh_failed_png" > /dev/null 2>&1
EOF
  echo "exec-once = bash $script"
  echo "exec-once = bash $frames"
}

leg_clipssh_assert() {
  local f
  if ! grep -q '^ok$' "$clipssh_summon_reply_path" 2>/dev/null \
    || ! grep -q '^ok$' "$clipssh_fail_summon_reply_path" 2>/dev/null; then
    fail "menu summon clipssh did not answer ok, got: $(cat "$clipssh_summon_reply_path" "$clipssh_fail_summon_reply_path" 2>/dev/null)"
  fi
  if ! grep -q '^ok$' "$clipssh_send_reply_path" 2>/dev/null; then
    fail "menu activate on the box row did not answer ok, got: $(cat "$clipssh_send_reply_path" 2>/dev/null)"
  fi
  if ! grep -q '^ok$' "$clipssh_fail_reply_path" 2>/dev/null; then
    fail "menu activate on the nohost row did not answer ok, got: $(cat "$clipssh_fail_reply_path" 2>/dev/null)"
  fi
  # The claim no frame can make: both rows ran clipssh, with the alias the
  # row carried, in the order they were activated. A row that never reached
  # ClipsshService, or one that handed it the wrong alias, leaves this file
  # short or wrong while the toasts still look plausible.
  if [ ! -s "$clipssh_calls_path" ]; then
    fail "clipssh was never invoked: no row reached ClipsshService"
  fi
  cat "$clipssh_calls_path"
  if [ "$(cat "$clipssh_calls_path")" != "box
nohost" ]; then
    fail "clipssh was invoked with $(tr '\n' ' ' < "$clipssh_calls_path"), want box then nohost"
  fi
  # The failure toast is urgency 2, so it is sticky: a popup still up four
  # seconds after the failing row is the FAILED card itself, while the two
  # normal-urgency ones have long expired into pending.
  if [ ! -s "$clipssh_notify_status_path" ]; then
    fail "no notifications status produced"
  fi
  cat "$clipssh_notify_status_path"; echo
  if grep -q '"popups":0' "$clipssh_notify_status_path"; then
    fail "no popup is up after the failed transfer, the urgent CLIPSSH FAILED toast never landed: $(cat "$clipssh_notify_status_path")"
  fi
  for f in "$clipssh_route_png" "$clipssh_sending_png" "$clipssh_copied_png" "$clipssh_failed_png"; do
    if [ ! -f "$f" ]; then
      fail "no clipssh screenshot produced at $f"
    fi
  done
  echo "SMOKE_CLIPSSH_ROUTE $clipssh_route_png"
  echo "SMOKE_CLIPSSH_SENDING $clipssh_sending_png"
  echo "SMOKE_CLIPSSH_COPIED $clipssh_copied_png"
  echo "SMOKE_CLIPSSH_FAILED $clipssh_failed_png"
}
