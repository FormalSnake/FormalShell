# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --plugins drops real plugin directories into the isolated config home, in
# the exact shape manifest.js documents, and reads them back through the
# `plugins` target. No `bar` key is written for this leg on purpose: the
# manifest's own `region` is what places the cell, so dropping the directory
# in is the whole install, which is the contract worth proving. `list` is the
# resolved manifest record and `status` is the load outcome.
#
# Under QML the plugin is a QML entry, and `status` is the one place its
# entry failing to load is visible from outside the process, since plugin
# QML lives outside the repo and qmllint never sees it. The entry imports
# qs.Core and reads Theme, the same proof --bar-layout's `qml` module makes.
#
# Under FS_IMPL=rust a plugin is an executable (the spec's "User code"
# section): `entry` names a shell script that prints JSON lines and reads
# events as JSON lines. Two plugins prove the contract. smoke-bar prints one
# line and logs every event it is sent, and the leg then clicks and scrolls
# its cell with a real pointer. smoke-crash logs its start and exits, which
# has to read as a PLUGIN ERROR in `status` and be started again on the
# backoff, so its start log has to grow.
#
# Three more cover the surface kinds. smoke-panel is a panel plugin that is
# not kept loaded: no process before `panel open plugin:smoke-panel`, one
# while its card is up, rows of every type on the card, a real Enter on the
# row under the cursor and another on the toggle (`activate` events with
# the row id, `checked` on the toggle, the plugin reprinting its rows as
# the reply), and no process again after `panel close`. smoke-panel-crash is
# a kept-loaded panel that exits, so its card reads PLUGIN ERROR and it is
# started again on the backoff. smoke-overlay is an overlay plugin opened
# over IPC, one real Enter reaching it and a real Escape closing it.
leg_plugins_flag="--plugins"
leg_plugins_rust=1
leg_plugins_order=200

plugins_list_path="$shot_dir/plugins-list.json"
plugins_status_path="$shot_dir/plugins-status.json"
plugins_room_path="$shot_dir/plugins-room.json"
plugins_events_path="$shot_dir/plugins-events.log"
plugins_starts_path="$shot_dir/plugins-crash-starts.log"
plugins_bar_png="$shot_dir/plugins-bar.png"
plugins_root="$iso_home/.config/formalshell/plugins"
plugins_panel_events_path="$shot_dir/plugins-panel-events.log"
plugins_panel_starts_path="$shot_dir/plugins-panel-starts.log"
plugins_panel_crash_starts_path="$shot_dir/plugins-panel-crash-starts.log"
plugins_overlay_events_path="$shot_dir/plugins-overlay-events.log"
plugins_panel_state_path="$shot_dir/plugins-panel-state.txt"
plugins_panel_procs_path="$shot_dir/plugins-panel-procs.txt"
plugins_overlay_state_path="$shot_dir/plugins-overlay-state.txt"
plugins_unknown_path="$shot_dir/plugins-unknown.txt"
plugins_panel_png="$shot_dir/plugins-panel.png"
plugins_panel_after_png="$shot_dir/plugins-panel-activated.png"
plugins_panel_crash_png="$shot_dir/plugins-panel-crash.png"
plugins_overlay_png="$shot_dir/plugins-overlay.png"
plugin_dir="$iso_home/.config/formalshell/plugins/smoke-bar"
plugin_crash_dir="$iso_home/.config/formalshell/plugins/smoke-crash"

leg_plugins_validate() {
  if [ "${fs_impl:-qml}" = rust ]; then
    leg_plugins_needs="jq wlrctl wtype"
  fi
}

leg_plugins_fixture() {
  mkdir -p "$plugin_dir"
  if [ "$fs_impl" = rust ]; then
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
    leg_plugins_surface_fixture
    return
  fi
  cat > "$plugin_dir/manifest.json" <<'EOF'
{
  "apiVersion": 1,
  "id": "smoke-bar",
  "kind": "bar",
  "entry": "entry.qml",
  "name": "Smoke Bar Plugin",
  "region": "right"
}
EOF
  cat > "$plugin_dir/entry.qml" <<'EOF'
import QtQuick
import qs.Core

Text {
    text: "PLUGIN OK"
    color: Theme.color.accent
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize.body
}
EOF
}

leg_plugins_surface_fixture() {
  local d
  d="$plugins_root/smoke-panel"
  mkdir -p "$d"
  cat > "$d/manifest.json" <<'EOF'
{
  "apiVersion": 1,
  "id": "smoke-panel",
  "kind": "panel",
  "entry": "entry.sh",
  "name": "Smoke Panel",
  "width": "narrow"
}
EOF
  cat > "$d/entry.sh" <<EOF
#!/usr/bin/env bash
echo start >> "$plugins_panel_starts_path"
detail=idle
checked=false
show() {
  printf '{"rows":[{"type":"label","text":"Smoke rows"},'
  printf '{"id":"r1","icon":"zap","text":"First row","detail":"%s"},' "\$detail"
  printf '{"type":"toggle","id":"t1","icon":"moon","text":"A toggle","checked":%s},' "\$checked"
  printf '{"type":"button","id":"b1","text":"Press me"}]}\n'
}
show
while IFS= read -r line; do
  printf '%s\n' "\$line" >> "$plugins_panel_events_path"
  case \$(jq -r .id <<<"\$line") in
    r1) detail=activated ;;
    t1) checked=\$(jq -r .checked <<<"\$line") ;;
  esac
  show
done
EOF
  d="$plugins_root/smoke-panel-crash"
  mkdir -p "$d"
  cat > "$d/manifest.json" <<'EOF'
{
  "apiVersion": 1,
  "id": "smoke-panel-crash",
  "kind": "panel",
  "entry": "entry.sh",
  "name": "Smoke Panel Crash",
  "keepLoaded": true
}
EOF
  cat > "$d/entry.sh" <<EOF
#!/usr/bin/env bash
echo start >> "$plugins_panel_crash_starts_path"
exit 4
EOF
  d="$plugins_root/smoke-overlay"
  mkdir -p "$d"
  cat > "$d/manifest.json" <<'EOF'
{
  "apiVersion": 1,
  "id": "smoke-overlay",
  "kind": "overlay",
  "entry": "entry.sh",
  "name": "Smoke Overlay"
}
EOF
  cat > "$d/entry.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '{"rows":[{"id":"ov1","icon":"zap","text":"Overlay row","detail":"summoned"}]}'
while IFS= read -r line; do
  printf '%s\n' "\$line" >> "$plugins_overlay_events_path"
done
EOF
  chmod +x "$plugins_root/smoke-panel/entry.sh" "$plugins_root/smoke-panel-crash/entry.sh" "$plugins_root/smoke-overlay/entry.sh"
}

leg_plugins_timing() {
  # A 5s startup wait plus two dumps and one grim; 12 leaves llvmpipe real
  # margin on the capture rather than racing the default 8s frame.
  leg_timing 12 90
}

leg_plugins_drive() {
  local script="$shot_dir/plugins-drive.sh"
  if [ "$fs_impl" = rust ]; then
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
# Off the card's rows, whose hover would put the keyboard cursor on one.
"$wlrctl_bin" pointer move -4000 -4000 > /dev/null 2>&1
procs() { pgrep -fc '$plugins_root/smoke-panel/entry.sh' || true; }
echo "before: \$(procs)" > "$plugins_panel_procs_path"
$ipc call panel open plugin:nope > "$plugins_unknown_path" 2>&1
$ipc call panel open plugin:smoke-panel > "$plugins_panel_state_path" 2>&1
sleep 2
$ipc call panel state >> "$plugins_panel_state_path" 2>&1
echo "open: \$(procs)" >> "$plugins_panel_procs_path"
"$grim_bin" "$plugins_panel_png" > /dev/null 2>&1
# Up clamps at the first row wherever the cursor starts, then one row down
# per Enter: the row, the toggle, the button.
"$wtype_bin" -k Up -k Up -k Up -k Return
sleep 1
"$wtype_bin" -k Down -k Return
sleep 1
"$wtype_bin" -k Down -k Return
sleep 1
"$grim_bin" "$plugins_panel_after_png" > /dev/null 2>&1
$ipc call panel close > /dev/null 2>&1
sleep 2
echo "closed: \$(procs)" >> "$plugins_panel_procs_path"
$ipc call panel open plugin:smoke-panel-crash > /dev/null 2>&1
sleep 3
"$grim_bin" "$plugins_panel_crash_png" > /dev/null 2>&1
$ipc call panel close > /dev/null 2>&1
sleep 1
$ipc call panel open plugin:smoke-overlay > /dev/null 2>&1
sleep 2
$ipc call panel state > "$plugins_overlay_state_path" 2>&1
"$grim_bin" "$plugins_overlay_png" > /dev/null 2>&1
"$wtype_bin" -k Down -k Return
sleep 1
"$wtype_bin" -k Escape
sleep 2
$ipc call panel state >> "$plugins_overlay_state_path" 2>&1
$ipc call plugins status > "$plugins_status_path" 2>&1
EOF
  else
    write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 5
$ipc call plugins list > "$plugins_list_path" 2>&1
$ipc call plugins status > "$plugins_status_path" 2>&1
"$grim_bin" "$plugins_bar_png" > /dev/null 2>&1
EOF
  fi
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
  if [ "$fs_impl" = rust ]; then
    leg_plugins_assert_command
  else
    leg_plugins_assert_qml
  fi
  echo "SMOKE_PLUGINS $plugins_bar_png (no bar key in settings.json: the manifest's own region is what placed the cell)"
}

leg_plugins_assert_qml() {
  if ! grep -qF '"id":"smoke-bar"' "$plugins_list_path" \
    || ! grep -qF '"kind":"bar"' "$plugins_list_path" \
    || ! grep -qF '"region":"right"' "$plugins_list_path" \
    || ! grep -qF "\"entryUrl\":\"file://$plugin_dir/entry.qml\"" "$plugins_list_path"; then
    fail "the drop-in plugin did not resolve out of its manifest: $(cat "$plugins_list_path")"
  fi
  if ! grep -qF '"loaded":true' "$plugins_status_path" \
    || ! grep -qF '"count":1' "$plugins_status_path" \
    || ! grep -qF '"bar":1' "$plugins_status_path"; then
    fail "plugins status did not report one loaded bar plugin: $(cat "$plugins_status_path")"
  fi
  if ! grep -qF '"errors":[]' "$plugins_status_path" || ! grep -qF '"warnings":[]' "$plugins_status_path"; then
    fail "the plugin loaded with errors or warnings: $(cat "$plugins_status_path")"
  fi
}

leg_plugins_assert_command() {
  local id
  for id in smoke-bar smoke-crash; do
    jq -e --arg id "$id" --arg url "file://$iso_home/.config/formalshell/plugins/$id/entry.sh" \
      '.[] | select(.id == $id and .kind == "bar" and .region == "right" and .entryUrl == $url)' \
      "$plugins_list_path" > /dev/null \
      || fail "the drop-in plugin $id did not resolve out of its manifest: $(cat "$plugins_list_path")"
  done
  jq -e '[.errors[] | select(.id == "smoke-crash") | .message | test("status 3")] == [true]' "$plugins_status_path" > /dev/null \
    || fail "the crashed bar plugin should read as failed with its exit status: $(cat "$plugins_status_path")"
  [ "$(wc -l < "$plugins_starts_path" 2>/dev/null || echo 0)" -ge 2 ] \
    || fail "the crashed plugin was not started again on its backoff: $(cat "$plugins_starts_path" 2>/dev/null)"
  grep -qF '"event":"click"' "$plugins_events_path" 2>/dev/null \
    && grep -qF '"button":"left"' "$plugins_events_path" \
    || fail "a click on the plugin's cell never reached its stdin: $(cat "$plugins_events_path" 2>/dev/null) room: $(cat "$plugins_room_path")"
  grep -qF '"event":"scroll"' "$plugins_events_path" \
    || fail "a wheel notch over the plugin's cell never reached its stdin: $(cat "$plugins_events_path" 2>/dev/null)"
  leg_plugins_assert_surfaces
}

leg_plugins_assert_surfaces() {
  local f
  for f in "$plugins_panel_png" "$plugins_panel_after_png" "$plugins_panel_crash_png" "$plugins_overlay_png"; do
    [ -f "$f" ] || fail "no plugin surface screenshot produced at $f"
  done
  jq -e '[.[] | select(.kind == "panel" or .kind == "overlay")] | length == 3' "$plugins_list_path" > /dev/null \
    || fail "the panel and overlay plugins did not all resolve: $(cat "$plugins_list_path")"
  jq -e '.loaded == true and .count == 5 and .bar == 2 and .surface == 3 and .warnings == [] and (.surfaces | index("plugin:smoke-panel") != null)' \
    "$plugins_status_path" > /dev/null \
    || fail "plugins status did not report two bar and three surface plugins: $(cat "$plugins_status_path")"
  jq -e '([.errors[].id] | sort) == ["smoke-crash", "smoke-panel-crash"] and ([.errors[] | select(.id == "smoke-panel-crash") | .message | test("status 4")] | all)' \
    "$plugins_status_path" > /dev/null \
    || fail "exactly the two plugins that exited should read as failed, the closed panel plugin not among them: $(cat "$plugins_status_path")"
  grep -qF "unknown panel" "$plugins_unknown_path" \
    || fail "a plugin that does not exist resolved as a panel: $(cat "$plugins_unknown_path")"
  grep -qxF 'before: 0' "$plugins_panel_procs_path" \
    || fail "the panel plugin ran before its card opened: $(cat "$plugins_panel_procs_path")"
  grep -qxF 'open: 1' "$plugins_panel_procs_path" \
    || fail "the panel plugin did not run while its card was open: $(cat "$plugins_panel_procs_path")"
  grep -qxF 'closed: 0' "$plugins_panel_procs_path" \
    || fail "the panel plugin kept running after its card closed: $(cat "$plugins_panel_procs_path")"
  [ "$(sed -n 1p "$plugins_panel_state_path")" = ok ] && [ "$(sed -n 2p "$plugins_panel_state_path")" = plugin:smoke-panel ] \
    || fail "panel open/state did not answer for the panel plugin: $(cat "$plugins_panel_state_path")"
  grep -qF '"event":"activate"' "$plugins_panel_events_path" 2>/dev/null \
    && grep -qF '"id":"r1"' "$plugins_panel_events_path" \
    || fail "Enter on the first row never reached the panel plugin: $(cat "$plugins_panel_events_path" 2>/dev/null)"
  grep -qF '"id":"t1","checked":true' "$plugins_panel_events_path" \
    || fail "Enter on the toggle row did not send its new state: $(cat "$plugins_panel_events_path" 2>/dev/null)"
  grep -qF '{"event":"activate","id":"b1"}' "$plugins_panel_events_path" \
    || fail "Enter on the button row never reached the panel plugin: $(cat "$plugins_panel_events_path" 2>/dev/null)"
  [ "$(wc -l < "$plugins_panel_events_path")" -eq 3 ] \
    || fail "one Enter per row should have sent exactly three events: $(cat "$plugins_panel_events_path")"
  [ "$(wc -l < "$plugins_panel_crash_starts_path" 2>/dev/null || echo 0)" -ge 2 ] \
    || fail "the crashed panel plugin was not started again on its backoff: $(cat "$plugins_panel_crash_starts_path" 2>/dev/null)"
  [ "$(sed -n 1p "$plugins_overlay_state_path")" = plugin:smoke-overlay ] && [ -z "$(sed -n 2p "$plugins_overlay_state_path")" ] \
    || fail "the overlay did not open on panel open and close on Escape: $(cat "$plugins_overlay_state_path")"
  grep -qF '"id":"ov1"' "$plugins_overlay_events_path" 2>/dev/null \
    || fail "Enter on the overlay's row never reached its plugin: $(cat "$plugins_overlay_events_path" 2>/dev/null)"
  echo "SMOKE_PLUGINS_PANEL $plugins_panel_png"
  echo "SMOKE_PLUGINS_PANEL_ACTIVATED $plugins_panel_after_png"
  echo "SMOKE_PLUGINS_PANEL_CRASH $plugins_panel_crash_png"
  echo "SMOKE_PLUGINS_OVERLAY $plugins_overlay_png"
}
