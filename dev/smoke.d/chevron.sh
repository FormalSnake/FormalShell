# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --chevron points bar.layout at today's exact default right region reordered
# around one `chevron` name: the five governed cells lead the region, then the
# chevron, then battery/audio/network sit outboard against the screen edge. A
# right-region chevron governs what PRECEDES it, so those five are never on
# the strip at all (M52): they are drawn in the second bar the cell opens, the
# way the tray lives behind its own dots, and everything outboard of the
# chevron keeps its x whether that bar is up or not.
#
# `bar chevron expand` stands in for a click on the cell (no synthetic pointer
# here), deliberately with no region argument, since a single-chevron layout
# is meant to infer it. The two PNGs are asserted to differ: M24 shipped a
# correct IPC contract over a bar that rendered nothing, and these two frames
# were byte-identical the whole time with every dump passing.
#
# Ridden by --pantheon it also carries the ink claim (M66): that band reads
# its paint off the wallpaper, so the leg sets a flat bright field first and
# the strip goes to dark ink over it. The card the chevron opens is not the
# band, and its cells have to say so, which is read off one patch of the
# frame inside the card: a dark plate with light words on it, not the band's
# black ink drawn onto it.
leg_chevron_flag="--chevron"
leg_chevron_order=180
leg_chevron_needs="wlrctl convert jq"

chevron_status_shut_path="$shot_dir/chevron-status-shut.json"
chevron_status_open_path="$shot_dir/chevron-status-open.json"
chevron_status_closed_again_path="$shot_dir/chevron-status-closed-again.json"
chevron_expand_reply_path="$shot_dir/chevron-expand-reply.txt"
chevron_shut_path="$shot_dir/chevron-shut.png"
chevron_open_path="$shot_dir/chevron-open.png"
chevron_child_path="$shot_dir/chevron-child.png"
chevron_status_child_path="$shot_dir/chevron-status-child.json"
chevron_panel_state_path="$shot_dir/chevron-panel-state.txt"
chevron_dispatch_path="$shot_dir/chevron-pointer.txt"
chevron_bright_wp="$shot_dir/chevron-bright.png"
chevron_paint_path="$shot_dir/chevron-paint.json"
chevron_card_ink_path="$shot_dir/chevron-card-ink.png"

# One patch of the open frame: the middle cell of the card, 30px either side
# of the point the pointer below is already asserted to land a panel from, and
# clear of both the card's own lit top edge and its ends. Two readings off it,
# since either alone passes for the wrong reason: the mean says the patch is
# on the card rather than on the wallpaper beside it, and the maximum says
# there are light words on that card.
chevron_card_patch="60x20+1783+62"

leg_chevron_fixture() {
  settings_fragment ', "bar": {"layout": {"right": ["bluetooth", "weather", "tray", "bell", "indicators", "chevron", "battery", "audio", "network"]}}'
  # The wallpaper the band's dark ink comes from, the flat bright field
  # --bar-adaptive reads `dark` off: mean 230, no spread, nothing busy.
  if leg_on pantheon; then
    $convert_bin -size 1920x1080 xc:'#e6e6e6' "$chevron_bright_wp"
  fi
}

leg_chevron_timing() {
  # chevron-drive.sh's own last step lands ~19s in; the run's own frame is
  # taken past that, so it shows the bar left with the group's card shut.
  # Under --pantheon the wallpaper set and the retheme behind it push every
  # step of that ~9s later.
  if leg_on pantheon; then
    leg_timing 32 62
  else
    leg_timing 22 50
  fi
}

leg_chevron_drive() {
  local script="$shot_dir/chevron-drive.sh"
  # The open shot sits two seconds behind the expand call, an order of
  # magnitude past the card's own entrance, which is what makes it a picture
  # of the end state rather than of a frame somewhere inside it.
  #
  # Then a real pointer click on a cell INSIDE that card, which is the half
  # no IPC verb can stand in for: `panel open weather` would open the same
  # panel from nowhere, and what is being proved is that a cell living in a
  # popout opens its own panel on top of that popout rather than in place of
  # it. wlrctl's pointer is relative-only, hence the slam into the corner
  # before the move, the same trick --wheel documents. 1813x72 is the middle
  # cell of the card, which sits on the chevron's own centre whatever the
  # cells either side of it measure: the weather cell on this fixture. A miss
  # fails the panel assert loudly rather than passing quietly.
  #
  # The bright wallpaper and the shell's own reading of the band over it,
  # both empty under any preset but pantheon: the strip habit hands its cells
  # no ink at all, so there is nothing for the card to inherit wrongly and
  # nothing here to prove.
  local paint_step=""
  if leg_on pantheon; then
    paint_step="\"$qs_bin\" ipc -p \"$shell_path\" call wallpaper set \"$chevron_bright_wp\" > /dev/null 2>&1
sleep 8
\"$qs_bin\" ipc -p \"$shell_path\" call bar paint > \"$chevron_paint_path\" 2>&1"
  fi
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 5
$paint_step
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_status_shut_path" 2>&1
sleep 1
"$grim_bin" "$chevron_shut_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call bar chevron expand > "$chevron_expand_reply_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_status_open_path" 2>&1
sleep 1
"$grim_bin" "$chevron_open_path" > /dev/null 2>&1
sleep 1
"$wlrctl_bin" pointer move -4000 -4000 > "$chevron_dispatch_path" 2>&1
sleep 1
"$wlrctl_bin" pointer move 1813 72 >> "$chevron_dispatch_path" 2>&1
sleep 1
"$wlrctl_bin" pointer click left >> "$chevron_dispatch_path" 2>&1
sleep 3
"$qs_bin" ipc -p "$shell_path" call panel state > "$chevron_panel_state_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_status_child_path" 2>&1
"$grim_bin" "$chevron_child_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call panel close > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call bar chevron collapse > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_status_closed_again_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

# One statistic of one patch of a frame, 0..255. Read off the red channel
# rather than through a grayscale conversion, the reason --bar-adaptive
# gives: every colour here is grey and a colorspace conversion answers in
# numbers these expectations are not written in.
_chevron_patch() {
  local png="$1" patch="$2" stat="$3"
  $convert_bin "$png" -crop "$patch" +repage \
    -format "%[fx:int($stat.r*255+0.5)]" info: 2>/dev/null
}

# The ink claim, under --pantheon only (M66). Three parts: the band settled
# on the dark paint, so its cells really are carrying black ink; the patch
# inside the card is on the card, not on the bright wallpaper around it; and
# the words drawn on that card are light. The middle one is what makes the
# last one mean anything, since a patch that slid off the card would read the
# wallpaper's own 230 and pass on nothing.
_chevron_assert_ink() {
  local paint source screen mean max
  [ -s "$chevron_paint_path" ] || fail "no bar paint reply produced at $chevron_paint_path"
  paint=$("$jq_bin" -r '.[0].paint.paint // "none"' "$chevron_paint_path" 2>/dev/null)
  source=$("$jq_bin" -r '.[0].paint.source // ""' "$chevron_paint_path" 2>/dev/null)
  screen=$("$jq_bin" -r '.[0].screen // ""' "$chevron_paint_path" 2>/dev/null)
  echo "chevron ink: band paint=$paint read on '$source' (this output is '$screen')"
  if [ "$paint" != "dark" ]; then
    fail "the band over the bright wallpaper reports '$paint', not 'dark', so its cells are not carrying black ink: $(cat "$chevron_paint_path")"
  fi
  # One reading for the whole session, taken on the main display: this rig
  # has one output, so the band reports itself as its own source.
  if [ "$source" != "$screen" ] || [ -z "$source" ]; then
    fail "bar paint reports the reading from '$source' on an output called '$screen': $(cat "$chevron_paint_path")"
  fi

  [ -f "$chevron_open_path" ] || fail "no chevron-open screenshot to read the card's ink off"
  $convert_bin "$chevron_open_path" -crop "$chevron_card_patch" +repage \
    "$chevron_card_ink_path" > /dev/null 2>&1
  [ -f "$chevron_card_ink_path" ] && echo "SMOKE_CHEVRON_CARD_INK $chevron_card_ink_path"
  mean=$(_chevron_patch "$chevron_open_path" "$chevron_card_patch" mean)
  max=$(_chevron_patch "$chevron_open_path" "$chevron_card_patch" maxima)
  [ -n "$mean" ] && [ -n "$max" ] \
    || fail "could not read the patch $chevron_card_patch out of $chevron_open_path"
  echo "chevron ink: the card patch $chevron_card_patch reads mean=$mean max=$max"
  if [ "$mean" -gt 120 ]; then
    fail "the patch $chevron_card_patch reads mean $mean, too bright to be the card: it is on the wallpaper beside it, so the ink below is untested"
  fi
  if [ "$max" -lt 150 ]; then
    fail "the card's brightest pixel over $chevron_card_patch is $max: the second bar is drawing the band's black ink on its own dark plate"
  fi
}

leg_chevron_assert() {
  # The five names the fixture puts before the chevron. Order matters:
  # `collapses` reports them in layout order, so one grep asserts the whole
  # boundary rather than five independent membership checks.
  local chevron_hidden_names='"bluetooth","weather","tray","bell","indicators"'
  if [ ! -s "$chevron_status_shut_path" ]; then
    fail "no bar chevron status (shut) produced"
  fi
  cat "$chevron_status_shut_path"; echo
  # Named before the claims below, so a run that fails one still hands the
  # frames back to look at.
  if [ -f "$chevron_shut_path" ]; then
    echo "SMOKE_CHEVRON_SHUT $chevron_shut_path"
  fi
  if [ -f "$chevron_open_path" ]; then
    echo "SMOKE_CHEVRON_OPEN $chevron_open_path"
  fi
  if ! grep -q '"chevronRegions":\["right"\]' "$chevron_status_shut_path"; then
    fail "bar chevron status did not resolve exactly one chevron, in the right region. Got: $(cat "$chevron_status_shut_path")"
  fi
  # The group and the surface it lives in, in one line: those exact five
  # names, in layout order, and no bar up yet.
  if ! grep -q "\"collapses\":\[$chevron_hidden_names\],\"open\":false" "$chevron_status_shut_path"; then
    fail "bar chevron status does not govern the five names placed before it, with its bar shut. Got: $(cat "$chevron_status_shut_path")"
  fi
  if [ ! -f "$chevron_shut_path" ]; then
    fail "no chevron-shut screenshot produced"
  fi
  if ! grep -q '^ok$' "$chevron_expand_reply_path" 2>/dev/null; then
    fail "bar chevron expand was refused. Got: $(cat "$chevron_expand_reply_path" 2>/dev/null)"
  fi
  if [ ! -s "$chevron_status_open_path" ]; then
    fail "no bar chevron status (open) produced"
  fi
  cat "$chevron_status_open_path"; echo
  # Same five names, still governed, now with their bar up. An empty
  # `collapses` here would mean the layout changed under the run rather than
  # the surface.
  if ! grep -q "\"collapses\":\[$chevron_hidden_names\],\"open\":true" "$chevron_status_open_path"; then
    fail "bar chevron expand did not open the group's own bar while keeping the same governed names. Got: $(cat "$chevron_status_open_path")"
  fi
  if [ ! -f "$chevron_open_path" ]; then
    fail "no chevron-open screenshot produced"
  fi
  if cmp -s "$chevron_shut_path" "$chevron_open_path"; then
    fail "chevron-shut and chevron-open screenshots are byte-identical: the second bar opened and rendered nothing"
  fi
  # The click's own claim, in three parts: the panel opened, the card it was
  # clicked in is still up, and the frame shows both. A popout that replaced
  # the card would leave `panel state` right and `open` false.
  if ! grep -q '^weather$' "$chevron_panel_state_path" 2>/dev/null; then
    fail "clicking the card's middle cell did not open its panel. Got: $(cat "$chevron_panel_state_path" 2>/dev/null), pointer: $(cat "$chevron_dispatch_path" 2>/dev/null)"
  fi
  if ! grep -q '"open":true' "$chevron_status_child_path" 2>/dev/null; then
    fail "opening a panel from the card closed the card. Got: $(cat "$chevron_status_child_path" 2>/dev/null)"
  fi
  if [ ! -f "$chevron_child_path" ]; then
    fail "no chevron-child screenshot produced"
  fi
  echo "SMOKE_CHEVRON_CHILD $chevron_child_path"
  if [ ! -s "$chevron_status_closed_again_path" ]; then
    fail "no bar chevron status (closed again) produced"
  fi
  if ! grep -q '"open":false' "$chevron_status_closed_again_path"; then
    fail "bar chevron collapse left the group's bar open. Got: $(cat "$chevron_status_closed_again_path")"
  fi
  if leg_on pantheon; then
    _chevron_assert_ink
  fi
}
