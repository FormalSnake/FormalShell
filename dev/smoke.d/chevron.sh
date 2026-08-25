# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --chevron points bar.layout at today's exact default right region reordered
# around one `chevron` name: the five governed cells lead the region, then the
# chevron, then battery/audio/network sit outboard against the screen edge. A
# right-region chevron governs what PRECEDES it, so the group opens inward
# into empty bar and everything outboard of the chevron keeps its x, which is
# as much what the two frames are read for as which cells appeared.
#
# The bar boots collapsed, which is the shipped default and the claim itself.
# `bar chevron expand` then stands in for a click on the cell (no synthetic
# pointer here), deliberately with no region argument, since a single-chevron
# layout is meant to infer it. The two PNGs are asserted to differ: M24
# shipped a correct IPC contract over a bar that rendered nothing, and these
# two frames were byte-identical the whole time with every dump passing.
leg_chevron_flag="--chevron"
leg_chevron_order=180

chevron_status_collapsed_path="$shot_dir/chevron-status-collapsed.json"
chevron_status_expanded_path="$shot_dir/chevron-status-expanded.json"
chevron_expand_reply_path="$shot_dir/chevron-expand-reply.txt"
chevron_collapsed_path="$shot_dir/chevron-collapsed.png"
chevron_expanded_path="$shot_dir/chevron-expanded.png"

leg_chevron_fixture() {
  settings_fragment ', "bar": {"layout": {"right": ["bluetooth", "weather", "tray", "bell", "indicators", "chevron", "battery", "audio", "network"]}}'
}

leg_chevron_timing() {
  # chevron-drive.sh's own last step lands ~10s in; the run's own frame is
  # taken past that, so it shows the bar left expanded.
  leg_timing 14 40
}

leg_chevron_drive() {
  local script="$shot_dir/chevron-drive.sh"
  # The expanded shot sits three seconds behind the expand call: an order of
  # magnitude past the reveal's own animation (Theme.motion.standard, 130ms),
  # which is what makes it a picture of the end state rather than of a frame
  # somewhere inside it.
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 5
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_status_collapsed_path" 2>&1
sleep 1
"$grim_bin" "$chevron_collapsed_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call bar chevron expand > "$chevron_expand_reply_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_status_expanded_path" 2>&1
sleep 1
"$grim_bin" "$chevron_expanded_path" > /dev/null 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_chevron_assert() {
  # The five names the fixture puts before the chevron. Order matters:
  # `collapses` reports them in layout order, so one grep asserts the whole
  # boundary rather than five independent membership checks.
  local chevron_hidden_names='"bluetooth","weather","tray","bell","indicators"'
  if [ ! -s "$chevron_status_collapsed_path" ]; then
    fail "no bar chevron status (collapsed) produced"
  fi
  cat "$chevron_status_collapsed_path"; echo
  if ! grep -q '"chevronRegions":\["right"\]' "$chevron_status_collapsed_path"; then
    fail "bar chevron status did not resolve exactly one chevron, in the right region. Got: $(cat "$chevron_status_collapsed_path")"
  fi
  if ! grep -q "\"collapses\":\[$chevron_hidden_names\]" "$chevron_status_collapsed_path"; then
    fail "bar chevron status does not govern the five names placed before it. Got: $(cat "$chevron_status_collapsed_path")"
  fi
  # The claim the screenshot alone cannot make: collapsed means those exact
  # names are hidden right now, not merely that the chevron knows about them.
  if ! grep -q "\"collapsed\":true,\"collapses\":\[$chevron_hidden_names\],\"hidden\":\[$chevron_hidden_names\]" "$chevron_status_collapsed_path"; then
    fail "bar chevron status did not report the governed names as hidden while collapsed. Got: $(cat "$chevron_status_collapsed_path")"
  fi
  if [ ! -f "$chevron_collapsed_path" ]; then
    fail "no chevron-collapsed screenshot produced"
  fi
  # Named-artifact marker: dev/vm.sh pulls every "SMOKE_<NAME> <path>.png"
  # line back to the mac, and without one the shot only ever exists in the VM.
  echo "SMOKE_CHEVRON_COLLAPSED $chevron_collapsed_path"
  if ! grep -q '^ok$' "$chevron_expand_reply_path" 2>/dev/null; then
    fail "bar chevron expand was refused. Got: $(cat "$chevron_expand_reply_path" 2>/dev/null)"
  fi
  if [ ! -s "$chevron_status_expanded_path" ]; then
    fail "no bar chevron status (expanded) produced"
  fi
  cat "$chevron_status_expanded_path"; echo
  # Same five names, still governed, none of them hidden any more. An empty
  # `collapses` here would mean the layout changed under the run rather than
  # the state.
  if ! grep -q "\"collapsed\":false,\"collapses\":\[$chevron_hidden_names\],\"hidden\":\[\]" "$chevron_status_expanded_path"; then
    fail "bar chevron expand did not clear the hidden set while keeping the same governed names. Got: $(cat "$chevron_status_expanded_path")"
  fi
  if [ ! -f "$chevron_expanded_path" ]; then
    fail "no chevron-expanded screenshot produced"
  fi
  echo "SMOKE_CHEVRON_EXPANDED $chevron_expanded_path"
  if cmp -s "$chevron_collapsed_path" "$chevron_expanded_path"; then
    fail "chevron-collapsed and chevron-expanded screenshots are byte-identical: the expand changed the state but rendered nothing"
  fi
}
