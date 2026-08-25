# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --plugins drops one real plugin directory into the isolated config home, in
# the exact shape manifest.js documents, and reads it back through the
# `plugins` target. No `bar` key is written for this leg on purpose: the
# manifest's own `region` is what places the cell, so dropping the directory
# in is the whole install, which is the contract worth proving. `list` is the
# resolved manifest record and `status` is the load outcome, the one place a
# plugin's entry QML failing to load is visible from outside the process,
# since plugin QML lives outside the repo and qmllint never sees it. The entry
# imports qs.Core and reads Theme, the same proof --bar-layout's `qml` module
# makes.
leg_plugins_flag="--plugins"
leg_plugins_order=200

plugins_list_path="$shot_dir/plugins-list.json"
plugins_status_path="$shot_dir/plugins-status.json"
plugins_bar_png="$shot_dir/plugins-bar.png"
plugin_dir="$iso_home/.config/formalshell/plugins/smoke-bar"

leg_plugins_fixture() {
  mkdir -p "$plugin_dir"
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
"$qs_bin" ipc -p "$shell_path" call plugins list > "$plugins_list_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call plugins status > "$plugins_status_path" 2>&1
"$grim_bin" "$plugins_bar_png" > /dev/null 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_plugins_assert() {
  local f
  for f in "$plugins_list_path" "$plugins_status_path"; do
    if [ ! -s "$f" ]; then
      fail "no plugins artifact produced at $f"
    fi
  done
  cat "$plugins_list_path"; echo
  if ! grep -qF '"id":"smoke-bar"' "$plugins_list_path" \
    || ! grep -qF '"kind":"bar"' "$plugins_list_path" \
    || ! grep -qF '"region":"right"' "$plugins_list_path" \
    || ! grep -qF "\"entryUrl\":\"file://$plugin_dir/entry.qml\"" "$plugins_list_path"; then
    fail "the drop-in plugin did not resolve out of its manifest: $(cat "$plugins_list_path")"
  fi
  cat "$plugins_status_path"; echo
  if ! grep -qF '"loaded":true' "$plugins_status_path" \
    || ! grep -qF '"count":1' "$plugins_status_path" \
    || ! grep -qF '"bar":1' "$plugins_status_path"; then
    fail "plugins status did not report one loaded bar plugin: $(cat "$plugins_status_path")"
  fi
  if ! grep -qF '"errors":[]' "$plugins_status_path" || ! grep -qF '"warnings":[]' "$plugins_status_path"; then
    fail "the plugin loaded with errors or warnings: $(cat "$plugins_status_path")"
  fi
  if [ ! -f "$plugins_bar_png" ]; then
    fail "no plugins screenshot produced at $plugins_bar_png"
  fi
  echo "SMOKE_PLUGINS $plugins_bar_png (no bar key in settings.json: the manifest's own region is what placed the cell)"
}
