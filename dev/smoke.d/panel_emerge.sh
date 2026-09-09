# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --panel-emerge proves the drawer open (M53 addendum 2026-09-09): a panel
# comes out from under the bar rather than fading in where it will end up. The
# card is displaced behind the bar's inner line by its own height while closed
# and travels out from under it, so its visible height grows from nothing to
# the whole card and no part of it is ever drawn inside the bar's own band.
#
# Measured off the card's left gutter, the `panelPadding` column between its
# border and its content: it is plain card fill at every height, so a probe in
# it says "the card reaches this far down" and nothing else. Rows would answer
# the same question wrongly, since the Wi-Fi list rescans during the run
# (panel_handoff.sh's own note) and a probe over a row compares content rather
# than presence. A probe is "covered" when it is byte-identical to the same
# probe in the settled frame: the card neither fades nor zooms on the way in,
# so wherever it has arrived it is already drawing exactly what it will draw
# at rest.
#
# The ladder sits deep in the card (60%, 75%, 88% and 97% of its height) on
# purpose. `emphasized` on OutQuint is front-loaded, half the travel is gone
# in 32ms, and probes near the top would be covered before the first frame
# lands; the last tenth of the travel is the part a screenshot can catch.
#
# The card rect is not hardcoded: it comes out of the difference between the
# frame with the panel open and the frame without it, cropped below the bar
# first so the cell's own panel mark is not in the box.
#
# Eight samples, each armed BEFORE the ipc call rather than after it: grim's
# own start-up costs about as much as the travel does, so a capture asked for
# once the call has returned lands past the end of it every time (again
# panel_handoff.sh's finding). Arming first spends that start-up during the
# round trip instead.
leg_panel_emerge_flag="--panel-emerge"
leg_panel_emerge_order=79
leg_panel_emerge_needs="convert"

panel_emerge_open_path="$shot_dir/panel-emerge-open.txt"
panel_emerge_close_path="$shot_dir/panel-emerge-close.txt"
panel_emerge_reopen_path="$shot_dir/panel-emerge-reopen.txt"
panel_emerge_state_path="$shot_dir/panel-emerge-state.txt"

panel_emerge_rest_path="$shot_dir/panel-emerge-rest.png"
panel_emerge_bare_path="$shot_dir/panel-emerge-bare.png"
panel_emerge_settled_path="$shot_dir/panel-emerge-settled.png"
panel_emerge_mid_paths=(
  "$shot_dir/panel-emerge-mid-1.png"
  "$shot_dir/panel-emerge-mid-2.png"
  "$shot_dir/panel-emerge-mid-3.png"
  "$shot_dir/panel-emerge-mid-4.png"
  "$shot_dir/panel-emerge-mid-5.png"
  "$shot_dir/panel-emerge-mid-6.png"
  "$shot_dir/panel-emerge-mid-7.png"
  "$shot_dir/panel-emerge-mid-8.png"
  "$shot_dir/panel-emerge-mid-9.png"
  "$shot_dir/panel-emerge-mid-10.png"
)
# Bunched where the travel is: the window maps around 0.20 on this rig and
# OutQuint spends over half the 250ms in its own last tenth.
panel_emerge_mid_sleeps=(0.02 0.08 0.11 0.14 0.17 0.20 0.26 0.34 0.46 0.62)

# The bar's own band, over the stretch of it the card hangs under and clear of
# the right region's cells, whose panel mark and icons move on their own
# clocks. Nothing may ever paint here: the whole claim of the clip.
panel_emerge_bar_box="180x36+1540+2"

leg_panel_emerge_validate() {
  local other
  for other in bar_layout bar_position center chevron config_reload frame fullscreen \
    gallery lock menu notify panel panel_anchor panel_at panel_handoff panel_keys \
    screensaver toggles tray_overflow wallpaper; do
    if leg_on "$other"; then
      echo "usage: --panel-emerge measures one panel's own frames and cannot combine with --${other//_/-}" >&2
      exit 1
    fi
  done
}

leg_panel_emerge_timing() {
  leg_timing 14 46
}

leg_panel_emerge_drive() {
  local script="$shot_dir/panel-emerge-drive.sh" i arm=""
  for i in "${!panel_emerge_mid_paths[@]}"; do
    arm+="( sleep ${panel_emerge_mid_sleeps[$i]}; \"$grim_bin\" \"${panel_emerge_mid_paths[$i]}\" > /dev/null 2>&1 ) &"$'\n'
  done
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 4
# The card's resting place, and then the same output without it: between them
# they say where the card is and what the desktop under it looks like.
"$qs_bin" ipc -p "$shell_path" call panel open network > "$panel_emerge_open_path" 2>&1
sleep 2
"$grim_bin" "$panel_emerge_rest_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call panel toggle network > "$panel_emerge_close_path" 2>&1
sleep 2
"$grim_bin" "$panel_emerge_bare_path" > /dev/null 2>&1
sleep 1
$arm
"$qs_bin" ipc -p "$shell_path" call panel open network > "$panel_emerge_reopen_path" 2>&1
wait
sleep 2
"$grim_bin" "$panel_emerge_settled_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call panel state > "$panel_emerge_state_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

# One box out of a saved frame, named after what it is looking at. -strip
# because ImageMagick writes the wall clock into a PNG's tIME chunk, which
# would leave two byte-identical pictures comparing unequal.
panel_emerge_crop() {
  local source="$1" box="$2" name="$3" out
  out="$shot_dir/panel-emerge-crop-$name.png"
  $convert_bin "$source" -crop "$box" +repage -strip "$out" > /dev/null 2>&1
  [ -s "$out" ] || fail "could not crop $box out of $source"
  echo "$out"
}

# How many of the four probes the card has reached in this frame.
panel_emerge_depth() {
  local frame="$1" name="$2" i depth=0 probe settled_probe
  for i in "${!panel_emerge_probe_boxes[@]}"; do
    probe=$(panel_emerge_crop "$frame" "${panel_emerge_probe_boxes[$i]}" "$name-$i")
    settled_probe="$shot_dir/panel-emerge-crop-settled-$i.png"
    if cmp -s "$probe" "$settled_probe"; then
      depth=$((depth + 1))
    fi
  done
  echo "$depth"
}

leg_panel_emerge_assert() {
  local f i
  for f in "$panel_emerge_open_path" "$panel_emerge_close_path" "$panel_emerge_reopen_path"; do
    if ! grep -q '^ok$' "$f" 2>/dev/null; then
      fail "a panel route did not answer ok at $f, got: $(cat "$f" 2>/dev/null)"
    fi
  done
  if ! grep -q '^network$' "$panel_emerge_state_path" 2>/dev/null; then
    fail "panel state after the emerge is not network, got: $(cat "$panel_emerge_state_path" 2>/dev/null)"
  fi
  for f in "$panel_emerge_rest_path" "$panel_emerge_bare_path" "$panel_emerge_settled_path" \
    "${panel_emerge_mid_paths[@]}"; do
    [ -f "$f" ] || fail "no screenshot produced at $f"
  done

  echo "SMOKE_PANEL_EMERGE_REST $panel_emerge_rest_path"
  echo "SMOKE_PANEL_EMERGE_BARE $panel_emerge_bare_path"
  echo "SMOKE_PANEL_EMERGE_SETTLED $panel_emerge_settled_path"
  for i in "${!panel_emerge_mid_paths[@]}"; do
    echo "SMOKE_PANEL_EMERGE_MID_$((i + 1)) ${panel_emerge_mid_paths[$i]}"
  done

  # The card's own rect, off the two frames that differ by exactly one card.
  # Cropped below the bar first: the cell that owns an open panel draws a mark
  # of its own, which is a difference and is not the card.
  local body_h=$((1080 - 46)) bare_body rest_body rect
  bare_body="$shot_dir/panel-emerge-body-bare.png"
  rest_body="$shot_dir/panel-emerge-body-rest.png"
  $convert_bin "$panel_emerge_bare_path" -crop "1920x${body_h}+0+46" +repage "$bare_body" > /dev/null 2>&1
  $convert_bin "$panel_emerge_rest_path" -crop "1920x${body_h}+0+46" +repage "$rest_body" > /dev/null 2>&1
  rect=$($convert_bin "$bare_body" "$rest_body" -compose difference -composite \
    -threshold 8% -format "%@" info: 2>/dev/null)
  local card_w card_h card_x card_y
  card_w=${rect%%x*}
  card_h=${rect#*x}; card_h=${card_h%%+*}
  card_x=$(echo "$rect" | sed -n 's/.*+\([0-9]*\)+[0-9]*$/\1/p')
  card_y=$(echo "$rect" | sed -n 's/.*+\([0-9]*\)$/\1/p')
  card_y=$((card_y + 46))
  if [ -z "$card_w" ] || [ "${card_w:-0}" -lt 200 ] || [ "${card_h:-0}" -lt 200 ]; then
    fail "could not measure the network card off the open/closed pair, got rect '$rect'"
  fi
  echo "SMOKE_PANEL_EMERGE_CARD ${card_w}x${card_h}+${card_x}+${card_y}"

  # The ladder, deep in the card's own left gutter (see the header).
  local gutter_x=$((card_x + 3)) depth_at
  panel_emerge_probe_boxes=()
  for depth_at in 60 75 88 97; do
    panel_emerge_probe_boxes+=("5x4+${gutter_x}+$((card_y + card_h * depth_at / 100 - 4))")
  done

  # The settled frame's own probes are the reference every other frame is read
  # against, so they are cropped first and by hand.
  for i in "${!panel_emerge_probe_boxes[@]}"; do
    panel_emerge_crop "$panel_emerge_settled_path" "${panel_emerge_probe_boxes[$i]}" "settled-$i" > /dev/null
  done
  # The classifier has to be able to tell the two apart at every rung, or a
  # depth of 4 would mean nothing.
  local bare_probe
  for i in "${!panel_emerge_probe_boxes[@]}"; do
    bare_probe=$(panel_emerge_crop "$panel_emerge_bare_path" "${panel_emerge_probe_boxes[$i]}" "bare-$i")
    if cmp -s "$bare_probe" "$shot_dir/panel-emerge-crop-settled-$i.png"; then
      fail "probe ${panel_emerge_probe_boxes[$i]} reads the same with the card there and gone, so it measures nothing"
    fi
  done

  # Nothing may ever paint in the bar's band: the card is cut at the bar's
  # inner line, so every frame of the travel has to leave it exactly as the
  # closed output does.
  local bare_bar frame_bar name
  bare_bar=$(panel_emerge_crop "$panel_emerge_bare_path" "$panel_emerge_bar_box" "bar-bare")
  for i in "${!panel_emerge_mid_paths[@]}"; do
    frame_bar=$(panel_emerge_crop "${panel_emerge_mid_paths[$i]}" "$panel_emerge_bar_box" "bar-mid-$((i + 1))")
    if ! cmp -s "$frame_bar" "$bare_bar"; then
      fail "sample $((i + 1)) painted inside the bar's own band: ${panel_emerge_mid_paths[$i]} differs from the closed output over $panel_emerge_bar_box"
    fi
  done
  frame_bar=$(panel_emerge_crop "$panel_emerge_settled_path" "$panel_emerge_bar_box" "bar-settled")
  if ! cmp -s "$frame_bar" "$bare_bar"; then
    fail "the settled card painted inside the bar's own band over $panel_emerge_bar_box"
  fi

  # The travel itself: how far down the card reaches in each sample, in order.
  local settled_depth first_depth last_depth depth previous=-1 ladder=""
  settled_depth=$(panel_emerge_depth "$panel_emerge_settled_path" "settled-check")
  if [ "$settled_depth" -ne 4 ]; then
    fail "the settled card does not cover its own ladder ($settled_depth of 4), so the probes are not where the measurement thinks"
  fi
  for i in "${!panel_emerge_mid_paths[@]}"; do
    depth=$(panel_emerge_depth "${panel_emerge_mid_paths[$i]}" "mid-$((i + 1))")
    ladder+=" $depth"
    if [ "$depth" -lt "$previous" ]; then
      fail "the card went back up between samples $i and $((i + 1)): depths$ladder"
    fi
    previous=$depth
    [ "$i" -eq 0 ] && first_depth=$depth
    last_depth=$depth
  done
  echo "SMOKE_PANEL_EMERGE_LADDER$ladder settled=$settled_depth"
  if [ "$first_depth" -ge "$settled_depth" ]; then
    fail "the first sample already showed the whole card (depths$ladder): the panel appeared rather than emerging"
  fi
  if [ "$last_depth" -ne "$settled_depth" ]; then
    fail "the last sample never reached the card's own height (depths$ladder): the emerge did not land"
  fi

  # And it landed on exactly the rect it rests at. The box straddles the
  # card's own bottom edge (its padding, its border and the desktop under it)
  # rather than taking in the rows, which rescan.
  local rest_edge settled_edge edge_box
  edge_box="${card_w}x14+${card_x}+$((card_y + card_h - 7))"
  rest_edge=$(panel_emerge_crop "$panel_emerge_rest_path" "$edge_box" "edge-rest")
  settled_edge=$(panel_emerge_crop "$panel_emerge_settled_path" "$edge_box" "edge-settled")
  if ! cmp -s "$rest_edge" "$settled_edge"; then
    fail "the emerged card's own bottom edge is not where the resting one's is: $panel_emerge_settled_path differs from $panel_emerge_rest_path over $edge_box"
  fi
}
