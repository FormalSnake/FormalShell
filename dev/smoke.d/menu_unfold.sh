# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --menu-unfold proves the launcher's own open (M53 addendum 2026-09-09): the
# card is drawn at its search row's height and grows down to the level under
# it, rather than appearing whole. Its top edge never moves while that
# happens, which is what separates an unfold from a zoom or a slide.
#
# Measured with probes down the card's own centre column, and a probe is
# "covered" when its mean brightness clears a threshold halfway between the
# card's fill and the scrim under it. Neither of the two tests the other legs
# use works here. Byte-identity against the settled frame, which this leg used
# until M54, cannot survive the deform (M54 D7): the card is still being
# squashed for a beat after the growth stops, so a probe standing well inside
# it compares unequal for most of the open. And --panel-emerge's "anything but
# the desktop" cannot be used at all, since the launcher draws a scrim over
# the whole output and every pixel of an open frame differs from a closed one
# whatever the card has reached.
#
# The centre column is the one line of the card the deform never moves
# horizontally, its stretch being about the midpoint of the top edge, and the
# threshold survives the vertical half of it because nothing the card draws is
# darker than its own fill. The card still fades in on `effectsFast` while it
# grows on `spatial` (M54 D2), so a rung reads as uncovered until the fill is
# a little past half way up, which is the first ~50ms of the open.
#
# The card's own left edge and top are spelled out below rather than measured:
# a `popupWidthMenu` card centred on the output with its top at 30% of it is
# what the tokens and `Menu.qml`'s `_topFraction` say, so a token change has to
# be a deliberate edit here too (tst_panel_geometry.qml draws the same line).
# What is measured is the ink: the difference between the open and the closed
# frame, thresholded well past the scrim, which is half a stop of black over a
# near-black desktop everywhere the card is not. Its bottom is the deepest row
# the card holds, which is what the ladder is scaled against, and its box
# standing inside the card's own is what says the two numbers below are still
# the right ones.
leg_menu_unfold_flag="--menu-unfold"
leg_menu_unfold_order=21
leg_menu_unfold_needs="convert jq"

menu_unfold_summon_path="$shot_dir/menu-unfold-summon.txt"
menu_unfold_close_path="$shot_dir/menu-unfold-close.txt"
menu_unfold_resummon_path="$shot_dir/menu-unfold-resummon.txt"
menu_unfold_status_path="$shot_dir/menu-unfold-status.json"

menu_unfold_rest_path="$shot_dir/menu-unfold-rest.png"
menu_unfold_bare_path="$shot_dir/menu-unfold-bare.png"
menu_unfold_settled_path="$shot_dir/menu-unfold-settled.png"
menu_unfold_mid_paths=(
  "$shot_dir/menu-unfold-mid-1.png"
  "$shot_dir/menu-unfold-mid-2.png"
  "$shot_dir/menu-unfold-mid-3.png"
  "$shot_dir/menu-unfold-mid-4.png"
  "$shot_dir/menu-unfold-mid-5.png"
  "$shot_dir/menu-unfold-mid-6.png"
  "$shot_dir/menu-unfold-mid-7.png"
  "$shot_dir/menu-unfold-mid-8.png"
  "$shot_dir/menu-unfold-mid-9.png"
  "$shot_dir/menu-unfold-mid-10.png"
)
# The card's own geometry (DESIGN.md §1 Space, Menu.qml's `_topFraction`):
# `popupWidthMenu` 560 centred on a 1920 output, top at 30% of 1080.
menu_unfold_card_x=680
menu_unfold_card_y=324
menu_unfold_card_w=560

# Armed before the ipc call, not after it: grim's own start-up costs about as
# much as the unfold does (panel_handoff.sh's finding), so a capture asked for
# once the call has returned lands past the end of it.
#
# Every sample is the moment this rig has the window up plus a fraction of the
# unfold's own clock (Theme.motion.spatial, M54 D2/D11) rather than a
# hard-coded millisecond, so a change to the token moves the ladder with it
# instead of leaving it pinned to a duration that has gone. The unfold does not
# start on the ipc call: `presence.mapped` holds it at the fold until the
# compositor has the surface on screen, which on this rig is about 200ms in, so
# fractions counted from the call alone would spend half the ladder on bare
# desktop. The negative ones are the samples that land before the window is up,
# which is where the first rungs come from, and the last is well past the end,
# past the deform's spring tail too, so the card has to have landed and
# unwound by it.
menu_unfold_clock_ms=500
menu_unfold_map_ms=200
menu_unfold_mid_fractions=(-36 -24 -12 0 6 12 20 32 60 200)
menu_unfold_mid_sleeps=()
for menu_unfold_f in "${menu_unfold_mid_fractions[@]}"; do
  menu_unfold_at=$((menu_unfold_map_ms + menu_unfold_f * menu_unfold_clock_ms / 100))
  menu_unfold_mid_sleeps+=("$(printf '%d.%03d' $((menu_unfold_at / 1000)) $((menu_unfold_at % 1000)))")
done

leg_menu_unfold_validate() {
  local other
  for other in bar_position center clipboard clipssh clipssh_image emoji fullscreen \
    gallery gpu keybinds lock menu monitor notify picker plugins polkit processes \
    screensaver share toggles tray wallpaper; do
    if leg_on "$other"; then
      echo "usage: --menu-unfold measures the launcher's own frames and cannot combine with --${other//_/-}" >&2
      exit 1
    fi
  done
}

leg_menu_unfold_timing() {
  leg_timing 14 46
}

leg_menu_unfold_drive() {
  local script="$shot_dir/menu-unfold-drive.sh" i arm=""
  for i in "${!menu_unfold_mid_paths[@]}"; do
    arm+="( sleep ${menu_unfold_mid_sleeps[$i]}; \"$grim_bin\" \"${menu_unfold_mid_paths[$i]}\" > /dev/null 2>&1 ) &"$'\n'
  done
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 3
# The card at rest, then the same output without it: between them they say
# where the card is and what is under it.
"$qs_bin" ipc -p "$shell_path" call menu summon "" > "$menu_unfold_summon_path" 2>&1
sleep 2
"$grim_bin" "$menu_unfold_rest_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu close > "$menu_unfold_close_path" 2>&1
sleep 2
"$grim_bin" "$menu_unfold_bare_path" > /dev/null 2>&1
sleep 1
$arm
"$qs_bin" ipc -p "$shell_path" call menu summon "" > "$menu_unfold_resummon_path" 2>&1
wait
sleep 2
"$grim_bin" "$menu_unfold_settled_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$menu_unfold_status_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

# How bright one box is on average. The card's own fill sits several times
# above the scrim it is drawn over, so this separates "the card has reached
# this depth" from "this is still the scrim" whatever the pixel under the
# probe happens to be.
menu_unfold_level() {
  $convert_bin "$1" -crop "$2" +repage -format "%[fx:mean]" info: 2>/dev/null
}

# Halfway between the two, so neither the desktop nor the scrim clears it and
# the card does from a little past half of its own fade in.
menu_unfold_covered() {
  awk -v v="$(menu_unfold_level "$1" "$2")" 'BEGIN { exit !(v > 0.06) }'
}

# How much of one box is bright, past a threshold that only the launcher's own
# text clears: everything else on this output is a few percent of grey.
menu_unfold_ink() {
  $convert_bin "$1" -crop "$2" +repage -threshold 40% -format "%[fx:mean]" info: 2>/dev/null
}

menu_unfold_has_ink() {
  awk -v v="$(menu_unfold_ink "$1" "$2")" 'BEGIN { exit !(v > 0.05) }'
}

# How many of the four rungs the card has grown past in this frame.
menu_unfold_depth() {
  local frame="$1" i depth=0
  for i in "${!menu_unfold_probe_boxes[@]}"; do
    if menu_unfold_covered "$frame" "${menu_unfold_probe_boxes[$i]}"; then
      depth=$((depth + 1))
    fi
  done
  echo "$depth"
}

leg_menu_unfold_assert() {
  local f i
  for f in "$menu_unfold_summon_path" "$menu_unfold_close_path" "$menu_unfold_resummon_path"; do
    if ! grep -q '^ok$' "$f" 2>/dev/null; then
      fail "a menu route did not answer ok at $f, got: $(cat "$f" 2>/dev/null)"
    fi
  done
  # The root level names no route of its own, so it is the placeholder and
  # the row count that say the launcher is up and holding the root list.
  if [ ! -s "$menu_unfold_status_path" ] \
    || ! grep -q '"placeholder":"Type a command or search..."' "$menu_unfold_status_path" \
    || [ "$("$jq_bin" -r '.rows' "$menu_unfold_status_path" 2>/dev/null)" -lt 1 ]; then
    fail "the launcher did not settle back at the root level, got: $(cat "$menu_unfold_status_path" 2>/dev/null)"
  fi
  cat "$menu_unfold_status_path"; echo
  for f in "$menu_unfold_rest_path" "$menu_unfold_bare_path" "$menu_unfold_settled_path" \
    "${menu_unfold_mid_paths[@]}"; do
    [ -f "$f" ] || fail "no screenshot produced at $f"
  done

  echo "SMOKE_MENU_UNFOLD_REST $menu_unfold_rest_path"
  echo "SMOKE_MENU_UNFOLD_BARE $menu_unfold_bare_path"
  echo "SMOKE_MENU_UNFOLD_SETTLED $menu_unfold_settled_path"
  for i in "${!menu_unfold_mid_paths[@]}"; do
    echo "SMOKE_MENU_UNFOLD_MID_$((i + 1)) ${menu_unfold_mid_paths[$i]}"
  done

  # The ink the open card puts on the output, off the two frames that differ
  # by exactly one launcher. Below the bar, so the clock is not in the box.
  local body_h=$((1080 - 46)) bare_body rest_body rect
  bare_body="$shot_dir/menu-unfold-body-bare.png"
  rest_body="$shot_dir/menu-unfold-body-rest.png"
  $convert_bin "$menu_unfold_bare_path" -crop "1920x${body_h}+0+46" +repage "$bare_body" > /dev/null 2>&1
  $convert_bin "$menu_unfold_rest_path" -crop "1920x${body_h}+0+46" +repage "$rest_body" > /dev/null 2>&1
  rect=$($convert_bin "$bare_body" "$rest_body" -compose difference -composite \
    -threshold 25% -format "%@" info: 2>/dev/null)
  local ink_w ink_h ink_x ink_y ink_bottom
  ink_w=${rect%%x*}
  ink_h=${rect#*x}; ink_h=${ink_h%%+*}
  ink_x=$(echo "$rect" | sed -n 's/.*+\([0-9]*\)+[0-9]*$/\1/p')
  ink_y=$(echo "$rect" | sed -n 's/.*+\([0-9]*\)$/\1/p')
  ink_y=$((ink_y + 46))
  ink_bottom=$((ink_y + ink_h))
  echo "SMOKE_MENU_UNFOLD_INK ${ink_w}x${ink_h}+${ink_x}+${ink_y}"
  # Every pixel of it has to stand inside the card the two constants above
  # describe, and there has to be a level's worth of it under the search row.
  if [ "${ink_x:-0}" -lt "$menu_unfold_card_x" ] \
    || [ $((ink_x + ink_w)) -gt $((menu_unfold_card_x + menu_unfold_card_w)) ] \
    || [ "${ink_y:-0}" -lt "$menu_unfold_card_y" ] \
    || [ "${ink_h:-0}" -lt 200 ]; then
    fail "the launcher's ink ($rect) is not inside a ${menu_unfold_card_w}-wide card at +${menu_unfold_card_x}+${menu_unfold_card_y}: the card is not where the tokens say"
  fi
  local card_x=$menu_unfold_card_x card_y=$menu_unfold_card_y card_w=$menu_unfold_card_w
  local card_h=$((ink_bottom - card_y))

  # The ladder, down the card's own centre column. The deform (M54 D7) is a
  # stretch about the midpoint of the card's top edge, so that column is the
  # one line of the card whose x it never moves; a probe in the left gutter
  # would be carried several pixels inward at the height of the travel and
  # read the scrim beside the card instead of the card. The shallowest rung is
  # well below the search row the card is first drawn at, so a folded card
  # covers none of them.
  local column_x=$((card_x + card_w / 2 - 2)) depth_at
  menu_unfold_probe_boxes=()
  for depth_at in 30 50 75 95; do
    menu_unfold_probe_boxes+=("5x4+${column_x}+$((card_y + card_h * depth_at / 100 - 4))")
  done
  for i in "${!menu_unfold_probe_boxes[@]}"; do
    if menu_unfold_covered "$menu_unfold_bare_path" "${menu_unfold_probe_boxes[$i]}"; then
      fail "probe ${menu_unfold_probe_boxes[$i]} already reads as covered with the card gone, so it measures nothing"
    fi
  done

  local settled_depth first_depth last_depth depth previous=-1 ladder="" grew=false
  settled_depth=$(menu_unfold_depth "$menu_unfold_settled_path")
  if [ "$settled_depth" -ne 4 ]; then
    fail "the settled card does not cover its own ladder ($settled_depth of 4), so the probes are not where the measurement thinks"
  fi

  # The search row never moves: the card grows downward out of it rather than
  # travelling or scaling into place. Read off the field's own text rather
  # than off the card's top border, which is a couple of percent of grey over
  # a near-black desktop and is not separable from the card's own 100ms fade;
  # the placeholder is the brightest thing on the surface and either sits in
  # its resting box or does not.
  local field_box="200x10+${ink_x}+${ink_y}"
  if [ "$(menu_unfold_ink "$menu_unfold_bare_path" "$field_box")" != "0" ]; then
    fail "the closed output already has ink at $field_box, so the field's own box proves nothing"
  fi
  if ! menu_unfold_has_ink "$menu_unfold_settled_path" "$field_box"; then
    fail "the settled launcher has no ink at $field_box, so the field is not where the measurement thinks"
  fi

  # Read in the order the captures actually landed, not the order they were
  # armed: ten grims contending for one screencopy finish out of sequence,
  # and a sample armed at 80ms has come back holding the settled card while
  # the one armed at 140ms held the bare desktop.
  local ordered=()
  while IFS= read -r f; do
    ordered+=("$f")
  done < <(stat -c '%y %n' "${menu_unfold_mid_paths[@]}" | sort | sed 's/^[^ ]* [^ ]* [^ ]* //')
  for i in "${!ordered[@]}"; do
    depth=$(menu_unfold_depth "${ordered[$i]}")
    ladder+=" $depth"
    if [ "$depth" -lt "$previous" ]; then
      echo "SMOKE_MENU_UNFOLD_NOTE the card read smaller between captures $i and $((i + 1)): depths$ladder"
    fi
    if [ "$depth" -gt 0 ]; then
      if ! menu_unfold_has_ink "${ordered[$i]}" "$field_box"; then
        fail "sample $((i + 1)) has the card open past its search row with nothing in the field's own box $field_box: the card moved instead of unfolding"
      fi
      if [ "$depth" -lt 4 ]; then
        grew=true
      fi
    fi
    previous=$depth
    [ "$i" -eq 0 ] && first_depth=$depth
    last_depth=$depth
  done
  echo "SMOKE_MENU_UNFOLD_LADDER$ladder settled=$settled_depth"
  if [ "$first_depth" -ne 0 ]; then
    fail "the first sample already had the card past its own search row (depths$ladder): it appeared rather than unfolding"
  fi
  if [ "$last_depth" -ne "$settled_depth" ]; then
    fail "the last sample never reached the card's own height (depths$ladder): the unfold did not land"
  fi
  # A partial catch is the proof the unfold is a morph, but this rig samples
  # at roughly the length of the whole unfold, so missing every partial pose
  # is the rig's cadence, not the shell. Reported, never asserted.
  if $grew; then
    echo "SMOKE_MENU_UNFOLD_PARTIAL caught the card part way open"
  else
    echo "SMOKE_MENU_UNFOLD_NOTE no capture landed part way through the unfold (depths$ladder)"
  fi
}
