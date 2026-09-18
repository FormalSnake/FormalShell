# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --switcher: Gala's Alt+Tab as a keyboard-only surface (M60 T6, the
# 2026-09-17 spec's Part 2). Three windows in one session, the cursor walked
# over IPC the way the compositor's bind walks it, and both halves of the
# claim at every step: what `switcher state` says the cursor is on, and the
# card as drawn.
#
# The three windows are the base run's own fixture window plus two more of
# the same app id, so all three cells resolve the same 48px icon out of the
# isolated home's icon theme (#CE5D97, which nothing else in a frame is) and
# a cell carrying an icon is telling apart from an empty one by colour alone.
#
# What the frames are read for, without hardcoding a single colour the
# palette owns: the icon's pink at all three cell centres (three icon cells,
# not one card with a gap in it), and the 12px margin the icon leaves inside
# its cell sampled on each of them. The selected cell takes a quarter-strength
# `accent` tint, so its margin differs from the other two while theirs match
# each other, and after one `switcher prev` that difference has moved one cell
# left. A patch read per cell rather than a colour compared against a
# constant: the fill is the wallpaper's own accent under matugen, and a leg
# naming a hex would be asserting the palette rather than the cursor.
#
# It pins `theme.preset` itself, so it needs no --pantheon (and does not
# fight one): the switcher is a habit, and no other preset has it.
leg_switcher_flag="--switcher"
leg_switcher_order=102
leg_switcher_needs="foot jq convert"
# The base run's fixture window is the third of the three, and the one the
# commit lands on.
leg_switcher_fixture_window=keep

switcher_second_json="$shot_dir/switcher-second.json"
switcher_first_json="$shot_dir/switcher-first.json"
switcher_closed_json="$shot_dir/switcher-closed.json"
switcher_second_png="$shot_dir/switcher-second.png"
switcher_first_png="$shot_dir/switcher-first.png"
switcher_layers_open="$shot_dir/switcher-layers-open.json"
switcher_layers_closed="$shot_dir/switcher-layers-closed.json"
switcher_active_json="$shot_dir/switcher-active.json"

# The card's own geometry on this rig, off the tokens rather than off a
# screenshot: a 64px icon inside `panelPadding` on all four sides is an 88px
# cell, the cells touch (Gala sets no spacing on its flow layout), three of
# them make a 264px row, and the card is exactly as wide as that row plus its
# own padding, with no floor under it. That puts the card at 288 wide,
# centred on 1920, with cells at x 828, 916 and 1004.
#
# The y is the output's own centre minus half a card whose height carries one
# line of `heading`, so it moves by a pixel or two with the font. Every patch
# below is 20 rows tall about the middle of an 88px cell, which leaves 20
# rows of slack against the 64px icon inside it.
switcher_icon_patches="20x20+862+512 20x20+950+512 20x20+1038+512"
switcher_margin_patches="4x20+831+512 4x20+919+512 4x20+1007+512"

leg_switcher_fixture() {
  # --pantheon pins the same preset; two "theme" keys in one settings.json
  # would be one object silently winning over the other.
  if ! leg_on pantheon; then
    settings_fragment ', "theme": {"preset": "pantheon"}'
  fi
}

leg_switcher_validate() {
  if leg_on retro; then
    echo "usage: --switcher pins its own theme.preset and cannot combine with --retro" >&2
    exit 1
  fi
  if leg_on switcher_off; then
    echo "usage: --switcher-off runs the same target under a preset without the habit, so it cannot share a session with --switcher" >&2
    exit 1
  fi
}

leg_switcher_timing() {
  leg_timing 34 90
}

leg_switcher_drive() {
  local script="$shot_dir/switcher-drive.sh"
  write_script "$script" <<EOS
#!/usr/bin/env bash
sleep 4
# Two more windows of the same app id as the base fixture's, spawned through
# the compositor so they are tracked from the moment they map.
"$hyprctl_bin" dispatch exec "$foot_bin --app-id=formalshell-smoke-iconic --title='formalshell smoke two' sh -c 'sleep 300'"
sleep 2
"$hyprctl_bin" dispatch exec "$foot_bin --app-id=formalshell-smoke-iconic --title='formalshell smoke three' sh -c 'sleep 300'"
sleep 4

# The first press opens the card on the window before the focused one; the
# second walks on to the third entry.
"$qs_bin" ipc -p "$shell_path" call switcher next > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call switcher next > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call switcher state > "$switcher_second_json" 2>&1
"$hyprctl_bin" -j layers > "$switcher_layers_open" 2>&1
"$grim_bin" "$switcher_second_png" > /dev/null 2>&1

"$qs_bin" ipc -p "$shell_path" call switcher prev > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call switcher state > "$switcher_first_json" 2>&1
"$grim_bin" "$switcher_first_png" > /dev/null 2>&1

"$qs_bin" ipc -p "$shell_path" call switcher commit > /dev/null 2>&1
sleep 3
"$qs_bin" ipc -p "$shell_path" call switcher state > "$switcher_closed_json" 2>&1
"$hyprctl_bin" -j layers > "$switcher_layers_closed" 2>&1
"$hyprctl_bin" -j activewindow > "$switcher_active_json" 2>&1
EOS
  echo "exec-once = bash $script"
}

# One patch of a frame as its own mean colour, as a plain string: two crops of
# a flat region answer the same string, and two different fills never do.
_switcher_patch() {
  $convert_bin "$1" -crop "$2" +repage \
    -format '%[fx:int(mean.r*255+0.5)].%[fx:int(mean.g*255+0.5)].%[fx:int(mean.b*255+0.5)]' \
    info: 2>/dev/null
}

# Whether two `r.g.b` patches are the same colour within the rig's own
# rounding. Only the icon read needs it: the same-or-different reads below
# are two crops of one flat region and answer identically or not at all.
_switcher_near() {
  local a b i tolerance=8
  IFS='.' read -r -a a <<< "$1"
  IFS='.' read -r -a b <<< "$2"
  for i in 0 1 2; do
    local delta=$(( ${a[$i]:-0} - ${b[$i]:-0} ))
    [ "$delta" -lt 0 ] && delta=$(( -delta ))
    [ "$delta" -le "$tolerance" ] || return 1
  done
  return 0
}

# Hyprland's own address for a window, and the shell's id for it, differ by
# the prefix alone (HyprlandBackend: ids are the hex address verbatim, the
# dispatcher's selector adds the 0x).
_switcher_bare_address() {
  echo "${1#0x}"
}

_switcher_count_layers() {
  "$jq_bin" -r '[.[] | .levels[] | .[] | select(.namespace == "formalshell:switcher")] | length' \
    "$1" 2>/dev/null
}

leg_switcher_assert() {
  local f
  for f in "$switcher_second_json" "$switcher_first_json" "$switcher_closed_json" \
    "$switcher_layers_open" "$switcher_layers_closed" "$switcher_active_json"; do
    [ -s "$f" ] || fail "no switcher reply produced at $f"
  done
  for f in "$switcher_second_png" "$switcher_first_png"; do
    [ -f "$f" ] || fail "no frame produced at $f"
  done

  # Two presses over three windows: open on the second entry, then on the
  # third.
  local open count index selected_id selected_title
  open=$("$jq_bin" -r '.open' "$switcher_second_json")
  count=$("$jq_bin" -r '.count' "$switcher_second_json")
  index=$("$jq_bin" -r '.index' "$switcher_second_json")
  selected_id=$("$jq_bin" -r '.id' "$switcher_second_json")
  selected_title=$("$jq_bin" -r '.title' "$switcher_second_json")
  echo "two presses: open=$open index=$index count=$count title='$selected_title'"
  [ "$open" = "true" ] || fail "the switcher is not open after two next calls: $(cat "$switcher_second_json")"
  [ "$count" = "3" ] || fail "the switcher offers $count windows, not the session's three"
  [ "$index" = "2" ] || fail "the cursor is on entry $index, not the third"
  [ -n "$selected_id" ] || fail "the switcher reports no window under the cursor"

  # The surface itself, off the compositor's own layer list.
  local mapped
  mapped=$(_switcher_count_layers "$switcher_layers_open")
  echo "layers while open: formalshell:switcher=$mapped"
  [ "${mapped:-0}" -ge 1 ] || fail "no formalshell:switcher layer surface while the card is open"

  # Three cells carrying the fixture's own icon, which is the only pink in
  # the session.
  local patch icon_colours=""
  for patch in $switcher_icon_patches; do
    icon_colours="$icon_colours $(_switcher_patch "$switcher_second_png" "$patch")"
  done
  echo "icon cells: $icon_colours"
  local expected_icon="206.93.151"
  local colour
  for colour in $icon_colours; do
    _switcher_near "$colour" "$expected_icon" \
      || fail "a cell centre reads $colour, not the fixture icon's $expected_icon: three icon cells are not what was drawn"
  done

  # The margin the icon leaves inside each cell: the selected one fills with
  # `accent`, the other two show the card under it.
  local second_margins=() first_margins=()
  for patch in $switcher_margin_patches; do
    second_margins+=("$(_switcher_patch "$switcher_second_png" "$patch")")
    first_margins+=("$(_switcher_patch "$switcher_first_png" "$patch")")
  done
  echo "cell margins on the third: ${second_margins[*]}"
  echo "cell margins on the second: ${first_margins[*]}"

  [ "${second_margins[0]}" = "${second_margins[1]}" ] \
    || fail "the first two cells differ (${second_margins[0]} vs ${second_margins[1]}) with the cursor on the third"
  [ "${second_margins[2]}" != "${second_margins[1]}" ] \
    || fail "the third cell draws what the unselected ones do (${second_margins[2]}), so no accent fill reached the frame"

  # One `prev`, and the fill has moved one cell left.
  local first_index
  first_index=$("$jq_bin" -r '.index' "$switcher_first_json")
  echo "after prev: index=$first_index"
  [ "$first_index" = "1" ] || fail "prev left the cursor on entry $first_index, not the second"
  [ "${first_margins[0]}" = "${first_margins[2]}" ] \
    || fail "the unselected cells differ (${first_margins[0]} vs ${first_margins[2]}) with the cursor on the second"
  [ "${first_margins[1]}" != "${first_margins[0]}" ] \
    || fail "the second cell draws what the unselected ones do (${first_margins[1]}), so the fill did not travel"
  [ "${first_margins[1]}" = "${second_margins[2]}" ] \
    || fail "the fill on the second cell (${first_margins[1]}) is not the one the third carried (${second_margins[2]})"

  # Commit: the card closes and focus lands on the window it named.
  local committed_id closed_open closed_layers active_address
  committed_id=$("$jq_bin" -r '.id' "$switcher_first_json")
  closed_open=$("$jq_bin" -r '.open' "$switcher_closed_json")
  closed_layers=$(_switcher_count_layers "$switcher_layers_closed")
  active_address=$("$jq_bin" -r '.address' "$switcher_active_json")
  echo "commit: open=$closed_open layers=$closed_layers active=$active_address want=$committed_id"
  [ "$closed_open" = "false" ] || fail "the switcher is still open after a commit: $(cat "$switcher_closed_json")"
  [ "${closed_layers:-0}" -eq 0 ] || fail "the switcher's layer surface stayed mapped after a commit ($closed_layers)"
  [ -n "$active_address" ] || fail "hyprctl reports no active window after the commit"
  [ "$(_switcher_bare_address "$active_address")" = "$(_switcher_bare_address "$committed_id")" ] \
    || fail "focus landed on $active_address, not on the committed $committed_id"

  echo "SMOKE_SWITCHER ok index=$index->$first_index count=$count committed=$committed_id"
  echo "SMOKE_SWITCHER_SECOND $switcher_second_png"
  echo "SMOKE_SWITCHER_FIRST $switcher_first_png"
}
