# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --plugins drops real plugin directories into the isolated config home, in
# the exact shape manifest.js documents, and reads them back through the
# `plugins` target. No `bar` key is written for this leg on purpose: the
# manifest's own `region` is what places the cell, so dropping the directory
# in is the whole install, which is the contract worth proving. `list` is the
# resolved manifest record and `status` is the load outcome.
#
# A plugin is an executable (the spec's "User code" section): `entry` names a shell script that prints JSON lines and reads
# events as JSON lines. Two plugins prove the contract. smoke-bar prints one
# line and logs every event it is sent, and the leg then clicks and scrolls
# its cell with a real pointer. smoke-crash logs its start and exits, which
# has to read as a PLUGIN ERROR in `status` and be started again on the
# backoff, so its start log has to grow.
leg_plugins_flag="--plugins"
leg_plugins_order=200
leg_plugins_needs="jq wlrctl"

plugins_list_path="$shot_dir/plugins-list.json"
plugins_status_path="$shot_dir/plugins-status.json"
plugins_room_path="$shot_dir/plugins-room.json"
plugins_events_path="$shot_dir/plugins-events.log"
plugins_starts_path="$shot_dir/plugins-crash-starts.log"
plugins_bar_png="$shot_dir/plugins-bar.png"
plugin_dir="$iso_home/.config/formalshell/plugins/smoke-bar"
plugin_crash_dir="$iso_home/.config/formalshell/plugins/smoke-crash"

leg_plugins_fixture() {
  mkdir -p "$plugin_dir"
  mkdir -p "$plugin_crash_dir"
  cat > "$plugin_dir/manifest.json" <<'EOF'
{
  "apiVersion": 1,
  "id": "smoke-bar",
  "kind": "bar",
  "entry": "entry.sh",
  "name": "Smoke Bar Plugin",
  "region": "right"
}
EOF
  cat > "$plugin_dir/entry.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '{"text": "PLUGIN OK", "icon": "puzzle", "tooltip": "smoke plugin", "class": ""}'
while IFS= read -r line; do
  printf '%s\n' "\$line" >> "$plugins_events_path"
done
EOF
  cat > "$plugin_crash_dir/manifest.json" <<'EOF'
{
  "apiVersion": 1,
  "id": "smoke-crash",
  "kind": "bar",
  "entry": "entry.sh",
  "region": "right"
}
EOF
  cat > "$plugin_crash_dir/entry.sh" <<EOF
#!/usr/bin/env bash
echo start >> "$plugins_starts_path"
exit 3
EOF
  chmod +x "$plugin_dir/entry.sh" "$plugin_crash_dir/entry.sh"
}

leg_plugins_timing() {
  # A 5s startup wait plus two dumps and one grim; 12 leaves llvmpipe real
  # margin on the capture rather than racing the default 8s frame.
  leg_timing 12 40
}

leg_plugins_drive() {
  local script="$shot_dir/plugins-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 5
$ipc call plugins list > "$plugins_list_path" 2>&1
$ipc call bar room > "$plugins_room_path" 2>&1
rect=\$(jq -r '.[].cells[] | select(.name == "plugin:smoke-bar") | "\(.x + .width / 2 | floor) \(.y + .height / 2 | floor)"' "$plugins_room_path")
if [ -n "\$rect" ]; then
  "$wlrctl_bin" pointer move -4000 -4000 > /dev/null 2>&1
  sleep 1
  "$wlrctl_bin" pointer move \${rect% *} \${rect#* } > /dev/null 2>&1
  sleep 1
  "$wlrctl_bin" pointer click left > /dev/null 2>&1
  sleep 1
  "$wlrctl_bin" pointer scroll -10 0 > /dev/null 2>&1
  sleep 1
fi
$ipc call plugins status > "$plugins_status_path" 2>&1
"$grim_bin" "$plugins_bar_png" > /dev/null 2>&1
EOF
  hypr_exec_once "bash $script"
}

leg_plugins_assert() {
  local f
  for f in "$plugins_list_path" "$plugins_status_path"; do
    if [ ! -s "$f" ]; then
      fail "no plugins artifact produced at $f"
    fi
  done
  cat "$plugins_list_path"; echo
  cat "$plugins_status_path"; echo
  if [ ! -f "$plugins_bar_png" ]; then
    fail "no plugins screenshot produced at $plugins_bar_png"
  fi
  leg_plugins_assert_command
  echo "SMOKE_PLUGINS $plugins_bar_png (no bar key in settings.json: the manifest's own region is what placed the cell)"
}

leg_plugins_assert_command() {
  local id
  for id in smoke-bar smoke-crash; do
    jq -e --arg id "$id" --arg url "file://$iso_home/.config/formalshell/plugins/$id/entry.sh" \
      '.[] | select(.id == $id and .kind == "bar" and .region == "right" and .entryUrl == $url)' \
      "$plugins_list_path" > /dev/null \
      || fail "the drop-in plugin $id did not resolve out of its manifest: $(cat "$plugins_list_path")"
  done
  jq -e '.loaded == true and .count == 2 and .bar == 2 and .warnings == []' "$plugins_status_path" > /dev/null \
    || fail "plugins status did not report two loaded bar plugins and no warnings: $(cat "$plugins_status_path")"
  jq -e '(.errors | length) == 1 and .errors[0].id == "smoke-crash" and (.errors[0].message | test("status 3"))' \
    "$plugins_status_path" > /dev/null \
    || fail "only the plugin that exited should read as failed, with its exit status: $(cat "$plugins_status_path")"
  [ "$(wc -l < "$plugins_starts_path" 2>/dev/null || echo 0)" -ge 2 ] \
    || fail "the crashed plugin was not started again on its backoff: $(cat "$plugins_starts_path" 2>/dev/null)"
  grep -qF '"event":"click"' "$plugins_events_path" 2>/dev/null \
    && grep -qF '"button":"left"' "$plugins_events_path" \
    || fail "a click on the plugin's cell never reached its stdin: $(cat "$plugins_events_path" 2>/dev/null) room: $(cat "$plugins_room_path")"
  grep -qF '"event":"scroll"' "$plugins_events_path" \
    || fail "a wheel notch over the plugin's cell never reached its stdin: $(cat "$plugins_events_path" 2>/dev/null)"
}
