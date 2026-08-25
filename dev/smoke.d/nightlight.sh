# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --nightlight enables the wlsunset-backed night light over IPC, photographs
# the warmed session, then disables it and proves the flip back.
#
# Honest bifurcation is the contract: active:true means the session
# implements wlr-gamma-control-unstable-v1 and wlsunset held; active:false
# WITH a populated lastError is the correctly-surfaced failure of a session
# that does not, and is just as real a pass. active:false with an EMPTY
# lastError is the one shape that never is: a silent no-op.
leg_nightlight_flag="--nightlight"
leg_nightlight_order=210

nightlight_active_path="$shot_dir/nightlight-active.png"
nightlight_status1_path="$shot_dir/nightlight-status-1.json"
nightlight_status2_path="$shot_dir/nightlight-status-2.json"

# This leg's own clock. A gamma shift repaints every pixel on the output, so
# under --wallpaper it starts after that leg's last frame rather than warming
# the exact colours its dither assertions read back.
nightlight_t0() {
  if leg_on wallpaper; then echo 16; else echo 3; fi
}

leg_nightlight_timing() {
  local t0
  t0=$(nightlight_t0)
  leg_timing $((t0 + 13)) $((t0 + 42))
}

leg_nightlight_drive() {
  local t0 script="$shot_dir/nightlight-drive.sh"
  t0=$(nightlight_t0)
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep $t0
"$qs_bin" ipc -p "$shell_path" call nightlight enable > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 8 ]; do
  "$qs_bin" ipc -p "$shell_path" call nightlight status > "$nightlight_status1_path" 2>&1
  grep -qF '"active":true' "$nightlight_status1_path" && break
  # A populated lastError is a settled answer too, so the poll stops there
  # rather than spinning out its whole budget on a session that already said
  # what went wrong.
  grep -qF '"lastError":""' "$nightlight_status1_path" || break
  sleep 1
done
"$grim_bin" "$nightlight_active_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call nightlight disable > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call nightlight status > "$nightlight_status2_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_nightlight_assert() {
  [ -f "$nightlight_active_path" ] || fail "no nightlight-active screenshot produced"
  echo "SMOKE_NIGHTLIGHT_ACTIVE $nightlight_active_path"
  if [ ! -s "$nightlight_status1_path" ]; then
    fail "no nightlight status produced after enable"
  fi
  cat "$nightlight_status1_path"; echo
  if grep -qF '"active":true' "$nightlight_status1_path"; then
    echo "nightlight: reached active:true, this session implements wlr-gamma-control-unstable-v1"
  elif grep -qF '"active":false' "$nightlight_status1_path" && ! grep -qF '"lastError":""' "$nightlight_status1_path"; then
    echo "nightlight: honest failure surface (active:false, lastError populated), this session likely lacks wlr-gamma-control-unstable-v1"
  else
    fail "nightlight enable produced neither active:true nor an honest lastError, got: $(cat "$nightlight_status1_path")"
  fi
  if [ ! -s "$nightlight_status2_path" ] || ! grep -qF '"active":false' "$nightlight_status2_path"; then
    fail "nightlight disable did not confirm active:false, got: $(cat "$nightlight_status2_path" 2>/dev/null)"
  fi
  cat "$nightlight_status2_path"; echo
}
