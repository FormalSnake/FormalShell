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
leg_chevron_flag="--chevron"
leg_chevron_order=180
leg_chevron_needs="wlrctl"

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

leg_chevron_fixture() {
  settings_fragment ', "bar": {"layout": {"right": ["bluetooth", "weather", "tray", "bell", "indicators", "chevron", "battery", "audio", "network"]}}'
}

leg_chevron_timing() {
  # chevron-drive.sh's own last step lands ~19s in; the run's own frame is
  # taken past that, so it shows the bar left with the group's card shut.
  leg_timing 22 50
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
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 5
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
}
