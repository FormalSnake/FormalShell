# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --menu: the launcher summoned at root, its fuzzy ranking against the live
# tree (`debug query`), a root query grouped by the route each row came
# from, the emoji route's grid, and the select round trip. The run's own
# smoke.png lands in select mode; menu-root.png is the root level, where
# the row icons, the group headings and the tree's own chrome are,
# menu-search.png is the same field with a query in it, one heading per
# route block, and menu-emoji.png is the grid.
#
# The chrome that a frame cannot state is asserted off `menu status` instead
# (M48): the field's placeholder, the group headings in the order they
# appear, and the column count. That last one is what tells a grid from a
# list at all, since a frame cannot say whether eight glyphs on one line are
# eight cells of a grid or one wide row of a list. Whether a search heading
# names one block or two comes off `debug query`'s per-row `section`
# instead, since `menu status` lists each heading once.
leg_menu_flag="--menu"
leg_menu_order=20
leg_menu_needs="jq"

# This leg's own clock. The launcher covers the whole output, so under
# --wallpaper it starts after that leg's last frame (t=14) rather than
# sampling the desktop through a scrim, the same rule lock_t0 draws.
menu_t0() {
  if leg_on wallpaper; then echo 16; else echo 3; fi
}

query_path="$shot_dir/query.json"
selection_path="$shot_dir/menu-selection.txt"
menu_root_path="$shot_dir/menu-root.png"
menu_search_path="$shot_dir/menu-search.png"
menu_emoji_path="$shot_dir/menu-emoji.png"
menu_status_root_path="$shot_dir/menu-status-root.json"
menu_status_search_path="$shot_dir/menu-status-search.json"
menu_status_emoji_path="$shot_dir/menu-status-emoji.json"

leg_menu_timing() {
  # menu-finish.sh's own read-back lands 13s after menu_t0, so the session
  # has to outlive that, not just the screenshot.
  local t0
  t0=$(menu_t0)
  leg_timing $((14 + t0 - 3)) $((46 + t0 - 3)) 4
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
"$qs_bin" ipc -p "$shell_path" call menu status > "$menu_status_root_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu filter e > /dev/null 2>&1
sleep 1
"$grim_bin" "$menu_search_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$menu_status_search_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu summon emoji > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu filter smiling > /dev/null 2>&1
sleep 2
"$grim_bin" "$menu_emoji_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$menu_status_emoji_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu select "Pick" ' ["a","b","c"]' tok1 > /dev/null 2>&1
EOF

  # Runs after the screenshot, never before: closing the surface first would
  # leave nothing to photograph. The close cancels the still-pending select,
  # and the state file is what proves the {cancelled:true} write happened.
  local menu_finish_script="$shot_dir/menu-finish.sh"
  write_script "$menu_finish_script" <<EOF
#!/usr/bin/env bash
sleep $((t0 + 12))
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
sleep 1
cat "$iso_home/.local/state/formalshell/menu-selection.txt" > "$selection_path" 2>&1
EOF
  echo "exec-once = bash $menu_script"
  echo "exec-once = bash $menu_finish_script"
}

menu_field() {
  sed -n 's/.*"'"$2"'":\([0-9-]*\).*/\1/p' "$1"
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
  # The root's own chrome: shadcn's placeholder, the two group headings in
  # declaration order, and a row list rather than a grid.
  if [ ! -s "$menu_status_root_path" ]; then
    fail "no root menu status produced"
  fi
  cat "$menu_status_root_path"; echo
  if ! grep -q '"placeholder":"Type a command or search..."' "$menu_status_root_path"; then
    fail "the root field did not carry the command-palette placeholder, got: $(cat "$menu_status_root_path")"
  fi
  if ! grep -q '"sections":\["Suggestions","Commands"\]' "$menu_status_root_path"; then
    fail "the root rows did not group into Suggestions then Commands, got: $(cat "$menu_status_root_path")"
  fi
  if ! grep -q '"columns":1' "$menu_status_root_path"; then
    fail "the root level reported a grid rather than a row list, got: $(cat "$menu_status_root_path")"
  fi
  # The emoji route: a grid, filtered, with the route's own prompt in the
  # field. More columns than one is the whole claim, and it is not readable
  # off the frame.
  if [ ! -f "$menu_emoji_path" ]; then
    fail "no emoji-grid screenshot produced"
  fi
  echo "SMOKE_MENU_EMOJI $menu_emoji_path"
  # A root query: the rows of `debug query` come out one block per
  # heading (a heading that appears, stops, and appears again is the
  # score order leaking through the grouping), every row carries one, and
  # the live tree groups the query into at least two of them, since a
  # single heading over the whole list says nothing about what any row is.
  if ! "$jq_bin" -e 'all(.[]; (.section // "") != "")
      and ([.[].section] as $s
        | ([range(1; $s | length) | select($s[.] != $s[. - 1])] | length) + 1
          == ($s | unique | length))' "$query_path" > /dev/null 2>&1; then
    fail "debug query rows are not one contiguous block per heading, got: $(cat "$query_path")"
  fi
  if [ ! -f "$menu_search_path" ]; then
    fail "no search-level menu screenshot produced"
  fi
  echo "SMOKE_MENU_SEARCH $menu_search_path"
  if [ ! -s "$menu_status_search_path" ]; then
    fail "no search-level menu status produced"
  fi
  cat "$menu_status_search_path"; echo
  search_sections=$("$jq_bin" -r '.sections | length' "$menu_status_search_path" 2>/dev/null)
  if [ -z "$search_sections" ] || [ "$search_sections" -lt 2 ]; then
    fail "a root query for 'e' grouped into ${search_sections:-0} heading(s), got: $(cat "$menu_status_search_path")"
  fi
  if [ ! -s "$menu_status_emoji_path" ]; then
    fail "no emoji menu status produced"
  fi
  cat "$menu_status_emoji_path"; echo
  if ! grep -q '"level":"emoji"' "$menu_status_emoji_path" \
    || ! grep -q '"placeholder":"Search emoji"' "$menu_status_emoji_path"; then
    fail "the emoji route did not report itself, got: $(cat "$menu_status_emoji_path")"
  fi
  # A grid draws no group headings, so it must not report any either.
  if ! grep -q '"sections":\[\]' "$menu_status_emoji_path"; then
    fail "the emoji grid claimed group headings it cannot draw, got: $(cat "$menu_status_emoji_path")"
  fi
  local emoji_columns emoji_rows
  emoji_columns=$(menu_field "$menu_status_emoji_path" columns)
  emoji_rows=$(menu_field "$menu_status_emoji_path" rows)
  if [ -z "$emoji_columns" ] || [ "$emoji_columns" -le 1 ]; then
    fail "the emoji route rendered $emoji_columns column(s), so it is still a row list"
  fi
  if [ -z "$emoji_rows" ] || [ "$emoji_rows" -le "$emoji_columns" ]; then
    fail "the filtered emoji grid holds $emoji_rows cell(s), too few to fill a row of $emoji_columns"
  fi
  echo "SMOKE_MENU_GRID $emoji_rows emoji in $emoji_columns columns"
  if [ -s "$selection_path" ] && grep -q '"cancelled":true' "$selection_path"; then
    cat "$selection_path"
  else
    [ -f "$selection_path" ] && cat "$selection_path" >&2
    fail "menu close in select mode did not write {cancelled:true}"
  fi
}
