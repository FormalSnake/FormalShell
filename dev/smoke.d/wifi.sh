# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --wifi drives the network panel against the two real hostapd radios
# nix/testvm.nix stands up on mac80211_hwsim: wait for a genuine scan to
# surface both SSIDs, a wrong-password round trip that must settle to a
# stable disconnected state, the real password reaching connected:true (so
# hostapd's own dnsmasq handed the station an address), forget, then the
# enterprise round trip through hostapd's integrated PEAP/MSCHAPv2 server,
# and a closing forget.
#
# Everything is strictly ordered, so it is one script. Each poll writes over
# its own path, so what the loop last saw is exactly what the assertions read
# back, never a stale earlier snapshot passing by accident.
leg_wifi_flag="--wifi"
leg_wifi_order=190

wifi_reset_status_path="$shot_dir/wifi-reset-status.json"
wifi_scan_status_path="$shot_dir/wifi-scan-status.json"
wifi_wrong_path="$shot_dir/wifi-wrong.png"
wifi_wrong_status_path="$shot_dir/wifi-wrong-status.json"
wifi_connected_path="$shot_dir/wifi-connected.png"
wifi_connected_status_path="$shot_dir/wifi-connected-status.json"
wifi_forget_status_path="$shot_dir/wifi-forget-status.json"
wifi_eap_connected_path="$shot_dir/wifi-eap-connected.png"
wifi_eap_status_path="$shot_dir/wifi-eap-status.json"
wifi_eap_forget_status_path="$shot_dir/wifi-eap-forget-status.json"

leg_wifi_timing() {
  # Every ceiling below is a poll that breaks the moment the state settles;
  # the sum is the worst case NetworkManager and hostapd can genuinely take.
  leg_timing 190 215
}

leg_wifi_drive() {
  local script="$shot_dir/wifi-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 3

# Self-heal, part one: wpa_supplicant's internal scan-request queue can wedge
# across runs independently of anything NetworkManager persists ("Reject scan
# trigger since one is already pending" forever, with no SME authenticate
# ever reaching the radio). Restarting the per-interface unit is the fix that
# unwedged it by hand; NM reconnects to the fresh supplicant over D-Bus on
# its own. Cheap and idempotent, so it runs unconditionally.
sudo systemctl restart wpa_supplicant-wlan0.service
sleep 2

"$qs_bin" ipc -p "$shell_path" call panel open network > /dev/null 2>&1

# Self-heal, part two: NetworkManager's system-connections dir is not part of
# the isolated per-run HOME, so an interrupted earlier run can leave a
# fixture profile parked on wlan0 with autoconnect=yes, and the station then
# never rescans up the other SSID at all. An SSID this VM has not associated
# with returns "unknown ssid" from the IPC, which arms nothing.
for ssid in FORMALTEST FORMALTEST-EAP; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_reset_status_path" 2>&1
  if grep -qF "\"name\":\"\$ssid\",\"known\":true" "$wifi_reset_status_path"; then
    "$qs_bin" ipc -p "$shell_path" call network forget "\$ssid" > /dev/null 2>&1
    SECONDS=0
    while [ "\$SECONDS" -lt 15 ]; do
      "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_reset_status_path" 2>&1
      if grep -qE "\"name\":\"\$ssid\",\"known\":false,\"connected\":false,\"stateChanging\":false" "$wifi_reset_status_path"; then
        break
      fi
      sleep 1
    done
  fi
done

SECONDS=0
while [ "\$SECONDS" -lt 25 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_scan_status_path" 2>&1
  if grep -qF '"name":"FORMALTEST"' "$wifi_scan_status_path" && grep -qF '"name":"FORMALTEST-EAP"' "$wifi_scan_status_path"; then
    break
  fi
  sleep 1
done

"$qs_bin" ipc -p "$shell_path" call network connect FORMALTEST wrong-formaltest-psk > /dev/null 2>&1
# connect() replies as soon as the IPC call returns, well before NM's own
# ActiveConnection exists, so polling for the settled state right away would
# see the identical pre-attempt idle snapshot and declare victory before
# anything happened. Waiting for stateChanging:true first proves NM started.
SECONDS=0
while [ "\$SECONDS" -lt 10 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_wrong_status_path" 2>&1
  if grep -qE '"name":"FORMALTEST","known":(true|false),"connected":(true|false),"stateChanging":true' "$wifi_wrong_status_path"; then
    break
  fi
  sleep 1
done
SECONDS=0
while [ "\$SECONDS" -lt 45 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_wrong_status_path" 2>&1
  if grep -qE '"name":"FORMALTEST","known":(true|false),"connected":false,"stateChanging":false' "$wifi_wrong_status_path"; then
    break
  fi
  sleep 1
done
"$grim_bin" "$wifi_wrong_path" > /dev/null 2>&1

"$qs_bin" ipc -p "$shell_path" call network connect FORMALTEST formaltest-psk > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 25 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_connected_status_path" 2>&1
  if grep -qF '"name":"FORMALTEST","known":true,"connected":true' "$wifi_connected_status_path"; then
    break
  fi
  sleep 1
done
"$grim_bin" "$wifi_connected_path" > /dev/null 2>&1

"$qs_bin" ipc -p "$shell_path" call network forget FORMALTEST > /dev/null 2>&1
# known:false alone is not enough to move on: the panel's own action
# bookkeeping only clears once BOTH !known and !stateChanging, and
# connectEap below refuses to run while an action is still in flight.
SECONDS=0
while [ "\$SECONDS" -lt 15 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_forget_status_path" 2>&1
  if grep -qE '"name":"FORMALTEST","known":false,"connected":false,"stateChanging":false' "$wifi_forget_status_path"; then
    break
  fi
  sleep 1
done

"$qs_bin" ipc -p "$shell_path" call network connectEap FORMALTEST-EAP formaltest formaltest-eap-pw > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 35 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_eap_status_path" 2>&1
  if grep -qF '"name":"FORMALTEST-EAP","known":true,"connected":true' "$wifi_eap_status_path"; then
    break
  fi
  sleep 1
done
"$grim_bin" "$wifi_eap_connected_path" > /dev/null 2>&1

# Symmetric with the FORMALTEST forget above: leaving this out is exactly how
# an earlier run corrupted the VM's persistent NM state and broke every scan
# after it.
"$qs_bin" ipc -p "$shell_path" call network forget FORMALTEST-EAP > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 15 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_eap_forget_status_path" 2>&1
  if grep -qE '"name":"FORMALTEST-EAP","known":false,"connected":false,"stateChanging":false' "$wifi_eap_forget_status_path"; then
    break
  fi
  sleep 1
done
EOF
  echo "exec-once = bash $script"
}

leg_wifi_assert() {
  if [ ! -s "$wifi_scan_status_path" ] \
    || ! grep -qF '"name":"FORMALTEST"' "$wifi_scan_status_path" \
    || ! grep -qF '"name":"FORMALTEST-EAP"' "$wifi_scan_status_path"; then
    [ -f "$wifi_scan_status_path" ] && cat "$wifi_scan_status_path" >&2
    fail "FORMALTEST/FORMALTEST-EAP never surfaced in a wifi scan"
  fi
  cat "$wifi_scan_status_path"; echo
  # NetworkManager must have genuinely given up before the frame below can be
  # trusted as the failure state rather than a lucky mid-flight capture.
  if [ ! -s "$wifi_wrong_status_path" ] \
    || ! grep -qE '"name":"FORMALTEST","known":(true|false),"connected":false,"stateChanging":false' "$wifi_wrong_status_path"; then
    [ -f "$wifi_wrong_status_path" ] && cat "$wifi_wrong_status_path" >&2
    fail "wrong-password connect never settled to a stable disconnected state within the poll budget"
  fi
  cat "$wifi_wrong_status_path"; echo
  [ -f "$wifi_wrong_path" ] || fail "no wifi-wrong screenshot produced"
  echo "SMOKE_WIFI_WRONG $wifi_wrong_path"
  if [ ! -s "$wifi_connected_status_path" ] \
    || ! grep -qF '"name":"FORMALTEST","known":true,"connected":true' "$wifi_connected_status_path"; then
    [ -f "$wifi_connected_status_path" ] && cat "$wifi_connected_status_path" >&2
    fail "real-password connect never reached connected:true within the poll budget"
  fi
  cat "$wifi_connected_status_path"; echo
  [ -f "$wifi_connected_path" ] || fail "no wifi-connected screenshot produced"
  echo "SMOKE_WIFI_CONNECTED $wifi_connected_path"
  if [ ! -s "$wifi_forget_status_path" ] \
    || ! grep -qE '"name":"FORMALTEST","known":false,"connected":false,"stateChanging":false' "$wifi_forget_status_path"; then
    [ -f "$wifi_forget_status_path" ] && cat "$wifi_forget_status_path" >&2
    fail "forget did not settle FORMALTEST to known:false/stateChanging:false within the poll budget"
  fi
  cat "$wifi_forget_status_path"; echo
  if [ ! -s "$wifi_eap_status_path" ] \
    || ! grep -qF '"name":"FORMALTEST-EAP","known":true,"connected":true' "$wifi_eap_status_path"; then
    [ -f "$wifi_eap_status_path" ] && cat "$wifi_eap_status_path" >&2
    fail "connectEap never reached connected:true for FORMALTEST-EAP within the poll budget"
  fi
  cat "$wifi_eap_status_path"; echo
  [ -f "$wifi_eap_connected_path" ] || fail "no wifi-eap-connected screenshot produced"
  echo "SMOKE_WIFI_EAP_CONNECTED $wifi_eap_connected_path"
  # A leftover profile here is what corrupts the VM's persistent NM state for
  # every run after this one.
  if [ ! -s "$wifi_eap_forget_status_path" ] \
    || ! grep -qE '"name":"FORMALTEST-EAP","known":false,"connected":false,"stateChanging":false' "$wifi_eap_forget_status_path"; then
    [ -f "$wifi_eap_forget_status_path" ] && cat "$wifi_eap_forget_status_path" >&2
    fail "closing forget did not settle FORMALTEST-EAP to known:false/stateChanging:false within the poll budget"
  fi
  cat "$wifi_eap_forget_status_path"; echo
}
