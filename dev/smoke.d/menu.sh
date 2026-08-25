# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --menu: the launcher summoned at root, its fuzzy ranking against the live
# tree (`debug query`), and the select round trip. The run's own smoke.png
# lands in select mode; menu-root.png is the root level, where the row icons
# and the tree's own chrome are.
leg_menu_flag="--menu"
leg_menu_order=20

# This leg's own clock. The launcher covers the whole output, so under
# --wallpaper it starts after that leg's last frame (t=14) rather than
# sampling the desktop through a scrim, the same rule lock_t0 draws.
menu_t0() {
  if leg_on wallpaper; then echo 16; else echo 3; fi
}

query_path="$shot_dir/query.json"
selection_path="$shot_dir/menu-selection.txt"
menu_root_path="$shot_dir/menu-root.png"

leg_menu_timing() {
  # menu-finish.sh's own read-back lands 7s after menu_t0, so the session has
  # to outlive that, not just the screenshot.
  local t0
  t0=$(menu_t0)
  leg_timing $((8 + t0 - 3)) $((40 + t0 - 3)) 4
}

leg_menu_drive() {
  # `qs ipc call`'s CLI11 parser splits any positional argument that starts
  # with "[" and ends with "]" into several comma-joined arguments (its
  # vector-literal shorthand), so the select list carries a leading space to
  # defeat that check. JSON.parse tolerates the whitespace.
  local t0 menu_script="$shot_dir/menu-drive.sh"
  t0=$(menu_t0)
  write_script "$menu_script" <<EOF
#!/usr/bin/env bash
sleep $t0
"$qs_bin" ipc -p "$shell_path" call menu summon "" > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call debug query 'e' > "$query_path" 2>&1
"$grim_bin" "$menu_root_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu select "Pick" ' ["a","b","c"]' tok1 > /dev/null 2>&1
EOF

  # Runs after the screenshot, never before: closing the surface first would
  # leave nothing to photograph. The close cancels the still-pending select,
  # and the state file is what proves the {cancelled:true} write happened.
  local menu_finish_script="$shot_dir/menu-finish.sh"
  write_script "$menu_finish_script" <<EOF
#!/usr/bin/env bash
sleep $((t0 + 6))
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
sleep 1
cat "$iso_home/.local/state/formalshell/menu-selection.txt" > "$selection_path" 2>&1
EOF
  echo "exec-once = bash $menu_script"
  echo "exec-once = bash $menu_finish_script"
}

leg_menu_assert() {
  if [ -s "$query_path" ]; then
    cat "$query_path"
  else
    fail "no menu query result produced"
  fi
  # Printed before the selection read-back, whose `cat` has no trailing
  # newline and would otherwise swallow this line's own start-of-line anchor.
  if [ ! -f "$menu_root_path" ]; then
    fail "no root-level menu screenshot produced"
  fi
  echo "SMOKE_MENU_ROOT $menu_root_path"
  if [ -s "$selection_path" ] && grep -q '"cancelled":true' "$selection_path"; then
    cat "$selection_path"
  else
    [ -f "$selection_path" ] && cat "$selection_path" >&2
    fail "menu close in select mode did not write {cancelled:true}"
  fi
}
