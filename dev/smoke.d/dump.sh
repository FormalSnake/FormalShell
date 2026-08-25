# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --dump: the debug IPC target's whole state dump, taken in-session and
# printed on stdout so dev/vm.sh saves it as this run's JSON sidecar.
leg_dump_flag="--dump"
leg_dump_order=10

dump_path="$shot_dir/dump.json"

leg_dump_drive() {
  local script="$shot_dir/dump.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 4
"$qs_bin" ipc -p "$shell_path" call debug dump > "$dump_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_dump_assert() {
  if [ -s "$dump_path" ]; then
    cat "$dump_path"
  else
    fail "no debug dump produced"
  fi
}
