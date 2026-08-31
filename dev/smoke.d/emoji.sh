# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --emoji: what the route finds and what order it finds it in. menu.sh owns
# the grid's chrome (columns, headings, placeholder); this leg owns the two
# halves a frame cannot state.
#
# Keywords: Unicode's name for 😭 is "loudly crying face" and carries no
# "sob" anywhere, so a ':e sob' that lands on it proves the shipped
# emoji.json carries CLDR's annotations and that the search reads them.
#
# Usage order: ':e cry' is read before any copy (😢 leads, file order inside
# the name-prefix rank), the second cell is copied through the surface's own
# Enter path, and the same query is read back. 😿 leading it then is
# state.json's `emojiUses` reaching the ranking with menu.emoji.sortByUsage
# never written, which is the default this leg exists to hold. 😭 staying
# below both is the other half of the contract: a copy reorders a rank, it
# never promotes a row out of one.
#
# The clipboard read-back sits between the two: `menu activate` running the
# row's own `wl-copy` is what makes the recorded use a real use, and without
# it a reordered query would only prove the shell wrote its own state file.
#
# Both queries go through `debug query`, which ranks against the same dataset
# the surface does with no keyboard delivery needed, and both are narrow on
# purpose: the whole 3,944-entry set is a 300KB reply and the IPC socket
# drops it.
leg_emoji_flag="--emoji"
leg_emoji_order=25
leg_emoji_needs="wl-paste jq"

# This leg's own clock: the launcher covers the whole output, so under
# --wallpaper it starts after that leg's last frame, the rule menu_t0 draws.
emoji_t0() {
  if leg_on wallpaper; then echo 16; else echo 3; fi
}

emoji_keyword_path="$shot_dir/emoji-keyword-query.json"
emoji_before_path="$shot_dir/emoji-rank-before.json"
emoji_after_path="$shot_dir/emoji-rank-after.json"
emoji_status_path="$shot_dir/emoji-status.json"
emoji_clipboard_path="$shot_dir/emoji-clipboard.txt"
emoji_state_path="$shot_dir/emoji-state.json"
emoji_png="$shot_dir/emoji-search.png"

leg_emoji_timing() {
  local t0
  t0=$(emoji_t0)
  leg_timing $((t0 + 13)) $((t0 + 43))
}

leg_emoji_drive() {
  local t0 script="$shot_dir/emoji-drive.sh"
  t0=$(emoji_t0)
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep $t0
"$qs_bin" ipc -p "$shell_path" call debug query ':e sob' > "$emoji_keyword_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug query ':e cry' > "$emoji_before_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu summon emoji > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu filter ':e cry' > /dev/null 2>&1
sleep 2
"$grim_bin" "$emoji_png" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$emoji_status_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu activate 1 > /dev/null 2>&1
sleep 3
"$wl_paste_bin" -n > "$emoji_clipboard_path" 2>&1
cat "$iso_home/.local/state/formalshell/state.json" > "$emoji_state_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug query ':e cry' > "$emoji_after_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

# The glyph of the row at `$2`, off `debug query`'s own JSON: the rows carry
# the char as their icon, and where one sits in that list is the whole claim
# every assertion below makes.
emoji_row_icon() {
  "$jq_bin" -r ".[$2].icon // \"\"" "$1" 2>/dev/null
}

leg_emoji_assert() {
  local f icon
  for f in "$emoji_keyword_path" "$emoji_before_path" "$emoji_after_path" \
    "$emoji_status_path" "$emoji_clipboard_path" "$emoji_state_path"; do
    [ -s "$f" ] || fail "no emoji artifact produced at $f"
  done
  [ -f "$emoji_png" ] || fail "no emoji screenshot produced at $emoji_png"

  cat "$emoji_keyword_path"; echo
  icon=$(emoji_row_icon "$emoji_keyword_path" 0)
  if [ "$icon" != "😭" ]; then
    fail "':e sob' led with '$icon', not the emoji whose only 'sob' is a CLDR keyword"
  fi
  if ! grep -qF '"label":"LOUDLY CRYING FACE"' "$emoji_keyword_path"; then
    fail "':e sob' did not name the row it matched: $(cat "$emoji_keyword_path")"
  fi

  cat "$emoji_before_path"; echo
  if [ "$(emoji_row_icon "$emoji_before_path" 0)" != "😢" ] \
    || [ "$(emoji_row_icon "$emoji_before_path" 1)" != "😿" ]; then
    fail "':e cry' did not open in file order on an empty ledger: $(cat "$emoji_before_path")"
  fi

  if ! grep -q '"level":"emoji"' "$emoji_status_path"; then
    fail "the route was not open when the row was activated: $(cat "$emoji_status_path")"
  fi
  if [ "$(cat "$emoji_clipboard_path")" != "😿" ]; then
    fail "Enter on the second cell put '$(cat "$emoji_clipboard_path")' on the clipboard, not that emoji"
  fi
  cat "$emoji_state_path"; echo
  # Through jq rather than a grep: JsonAdapter's own spacing is not this
  # leg's claim, and a \u-escaped glyph in the file would read the same.
  if [ "$("$jq_bin" -r '.emojiUses[0].id // ""' "$emoji_state_path")" != "emoji.😿" ] \
    || [ "$("$jq_bin" -r '.emojiUses[0].count // 0' "$emoji_state_path")" != "1" ]; then
    fail "the copy recorded no use in state.json: $(cat "$emoji_state_path")"
  fi

  cat "$emoji_after_path"; echo
  icon=$(emoji_row_icon "$emoji_after_path" 0)
  if [ "$icon" != "😿" ]; then
    fail "after one copy ':e cry' still led with '$icon': the usage ranking is not on by default"
  fi
  # 😭 matches "cry" on a word start, a rank below the two the copy shuffled.
  # Promoting it here would mean usage outranks the match itself.
  if [ "$(emoji_row_icon "$emoji_after_path" 1)" != "😢" ]; then
    fail "the copy did more than reorder its own rank: $(cat "$emoji_after_path")"
  fi
  echo "SMOKE_EMOJI $emoji_png (':e sob' → 😭, one copy leads its rank)"
}
