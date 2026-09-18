# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --switcher-keys: the switcher driven by the compositor's own binds and real
# keys rather than over IPC (M64). --switcher proves the surface; this proves
# the way in, which is where it was broken: on a pantheon host a held Alt
# with two taps of Tab left the card up and the release did nothing (owner,
# 2026-09-18).
#
# The cause, and why a leg exists for it. Hyprland marks a bind SHADOWED
# whenever another bind consumes a press while that bind's own key is held
# (`CKeybindManager::shadowKeybinds`), and `handleKeybinds` skips a shadowed
# bind. Holding Alt and pressing Tab consumes Tab, so the Alt_L release bind
# is shadowed from that moment, and nothing clears it before the release is
# handled: the Alt_L release runs `handleKeybinds` first and `shadowKeybinds`
# after. A plain `bindr` therefore fires on a bare Alt tap and never once
# Alt+Tab has been pressed, which is the only time it is wanted. The `t`
# flag is the fix: `shadowKeybinds` skips a transparent bind outright.
#
# This session registers the shipped binds in their fixed form plus three
# probes, two of them on the same Alt_L (Hyprland's `addKeybind` appends
# rather than replacing, so binds on one key all get their turn):
#   bindrt ALT  Alt_L  the shipped commit, has to fire
#   bindr  ALT  Alt_L  the form that shipped before, must NOT fire
#   bindrt ,    Alt_L  a bind with no mods, must NOT fire either, which is
#                      what says the modifier is still held as far as the
#                      bind table is concerned when Alt_L comes up
#   bindr  ,    F13    an ordinary key's release bind, the floor
# and the run opens with F13 and a bare Alt tap, both of which HAVE to leave
# their markers: an absent `plain` after Alt+Tab then means shadowed, not a
# bind that was never registered or keys that never arrived.
#
# wtype is the keyboard, one process for the whole hold: `-M alt` sets the
# modifier state, `-P Alt_L` is the real key event the bind matches on, and
# `-s` sleeps between them so the run can read `switcher state` mid-hold. Two
# places this differs from a physical Alt, neither of them near the shadowing
# this leg is about. `modmaskAtPressTime`: a real keyboard has not folded ALT
# into the mask yet when Alt_L goes down and wtype has, because it sets the
# mask itself, and `handleKeybinds`' release path reaches the same answer
# from either. And keysym resolution, which needs the one config line the
# drive writes; the comment beside it says why.
leg_switcher_keys_flag="--switcher-keys"
leg_switcher_keys_order=104
leg_switcher_keys_needs="foot jq wtype"
# A fourth window sits on workspace 2 throughout and must not reach the card
# (M64): the owner's quick Alt+Tab was landing on a window elsewhere and
# taking the compositor to its workspace, and Gala lists the active
# workspace's windows alone. The compositor's own client list is read beside
# `switcher state`, so a run where that window never spawned cannot pass by
# having nothing to exclude.
#
# The base run's fixture window is the third of the three and the one the
# commit lands on, exactly as in --switcher.
leg_switcher_keys_fixture_window=keep
#
# Three fast taps after that (M64 addendum, owner 2026-09-18): "alt+tab
# doesn't work when i hit it fast, it just glitches, i have to wait for the
# fade in to finish". Each is one wtype process holding Alt, tapping Tab
# once and releasing straight back out with no sleep between any of them,
# which is the one gap `Switcher.qml`'s `_commitPending` exists for: the
# compositor spawns `switcher next` and `switcher commit` as two
# independent processes, and nothing orders their arrival at the ipc
# socket, so a fast enough tap can have the release win that race. The
# active window has to alternate between the two windows on every one of
# the three, never repeat or sit still.

switcher_keys_probe_dir="$shot_dir/switcher-keys-probes"
switcher_keys_binds_path="$shot_dir/switcher-keys-binds.txt"
switcher_keys_wtype_log="$shot_dir/switcher-keys-wtype.log"
switcher_keys_control_path="$shot_dir/switcher-keys-control.txt"
switcher_keys_after_path="$shot_dir/switcher-keys-after.txt"
switcher_keys_held_json="$shot_dir/switcher-keys-held.json"
switcher_keys_closed_json="$shot_dir/switcher-keys-closed.json"
switcher_keys_layers_held="$shot_dir/switcher-keys-layers-held.json"
switcher_keys_layers_closed="$shot_dir/switcher-keys-layers-closed.json"
switcher_keys_active_json="$shot_dir/switcher-keys-active.json"
switcher_keys_clients_json="$shot_dir/switcher-keys-clients.json"
switcher_keys_held_png="$shot_dir/switcher-keys-held.png"
switcher_keys_closed_png="$shot_dir/switcher-keys-closed.png"
switcher_keys_fast_before_json="$shot_dir/switcher-keys-fast-before.json"
switcher_keys_fast_1_json="$shot_dir/switcher-keys-fast-1.json"
switcher_keys_fast_2_json="$shot_dir/switcher-keys-fast-2.json"
switcher_keys_fast_3_json="$shot_dir/switcher-keys-fast-3.json"
switcher_keys_fast_state_json="$shot_dir/switcher-keys-fast-state.json"

leg_switcher_keys_fixture() {
  # --pantheon pins the same preset; two "theme" keys in one settings.json
  # would be one object silently winning over the other.
  if ! leg_on pantheon; then
    settings_fragment ', "theme": {"preset": "pantheon"}'
  fi
}

leg_switcher_keys_validate() {
  local other
  for other in switcher switcher_off retro; do
    if leg_on "$other"; then
      echo "usage: --switcher-keys drives the same surface under its own preset, so it cannot combine with --${other//_/-}" >&2
      exit 1
    fi
  done
}

leg_switcher_keys_timing() {
  leg_timing 50 128
}

leg_switcher_keys_drive() {
  local script="$shot_dir/switcher-keys-drive.sh"
  local probe="$shot_dir/switcher-keys-probe.sh"
  write_script "$probe" <<EOS
#!/usr/bin/env bash
mkdir -p "$switcher_keys_probe_dir"
touch "$switcher_keys_probe_dir/\$1"
EOS
  # The one accommodation this rig needs, and the reason it is not a cheat:
  # hyprland resolves a bind's keysym by running the event's KEYCODE through
  # the COMPOSITOR's own layout (`CKeybindManager::onKeyEvent`'s
  # `m_xkbTranslationState`), and wtype is a virtual-keyboard client that
  # ships a keymap of its own with keycodes allocated in the order it first
  # uses a keysym. Those two disagree about what every keycode means, so
  # without this a synthetic Alt_L arrives as some unrelated key and no bind
  # matches at all. `resolve_binds_by_sym` is hyprland's own switch for
  # resolving through the keyboard's own layout instead, which for wtype is
  # its keymap and for a real keyboard on this rig's single us layout is the
  # same answer either way. Nothing else about the bind table changes: the
  # modifier mask, the shadowing and the release path are what this leg
  # reads, and none of them go near keysym resolution.
  echo "input {"
  echo "    resolve_binds_by_sym = true"
  echo "}"
  # Real binds in this session's real hyprland.conf, the shipped example's
  # three plus the probes, so what is exercised is hyprland's own bind table
  # rather than anything this rig invented.
  echo "bind = ALT, Tab, exec, $qs_bin ipc -p $shell_path call switcher next"
  echo "bind = ALT SHIFT, Tab, exec, $qs_bin ipc -p $shell_path call switcher prev"
  echo "bindrt = ALT, Alt_L, exec, $qs_bin ipc -p $shell_path call switcher commit"
  echo "bindr = ALT, Alt_L, exec, bash $probe plain"
  echo "bindrt = , Alt_L, exec, bash $probe nomods"
  # An ordinary key, as the floor under every claim below: a release bind on
  # something that is not a modifier, fired by the same wtype.
  echo "bindr = , F13, exec, bash $probe f13"
  write_script "$script" <<EOS
#!/usr/bin/env bash
mkdir -p "$switcher_keys_probe_dir"
sleep 4
"$hyprctl_bin" binds > "$switcher_keys_binds_path" 2>&1
# Two more windows of the same app id as the base fixture's, spawned through
# the compositor so they are tracked from the moment they map.
"$hyprctl_bin" dispatch exec "$foot_bin --app-id=formalshell-smoke-iconic --title='formalshell smoke two' sh -c 'sleep 300'"
sleep 2
"$hyprctl_bin" dispatch exec "$foot_bin --app-id=formalshell-smoke-iconic --title='formalshell smoke three' sh -c 'sleep 300'"
sleep 3
# And one the card must not hold, moved off silently so the monitor stays on
# the workspace the other three are on.
"$hyprctl_bin" dispatch exec "$foot_bin --app-id=formalshell-smoke-elsewhere --title='formalshell smoke elsewhere' sh -c 'sleep 300'"
sleep 3
"$hyprctl_bin" dispatch movetoworkspacesilent "2,class:formalshell-smoke-elsewhere"
sleep 3
"$hyprctl_bin" -j clients > "$switcher_keys_clients_json" 2>&1

# The control: an ordinary key's release bind, then Alt down and straight
# back up with no Tab in between, which is the one shape a plain release bind
# on a held modifier does fire on.
"$wtype_bin" -k F13 >> "$switcher_keys_wtype_log" 2>&1
sleep 1
"$wtype_bin" -M alt -P Alt_L -s 300 -p Alt_L -m alt >> "$switcher_keys_wtype_log" 2>&1
sleep 2
ls -1 "$switcher_keys_probe_dir" > "$switcher_keys_control_path" 2>&1
rm -f "$switcher_keys_probe_dir"/* 2>/dev/null
sleep 1

# The hold itself, in the background so the card can be read while Alt is
# still down.
"$wtype_bin" -M alt -P Alt_L -s 800 -k Tab -s 1500 -k Tab -s 2200 -p Alt_L -m alt \
  > /dev/null 2>&1 &
sleep 3.4
"$qs_bin" ipc -p "$shell_path" call switcher state > "$switcher_keys_held_json" 2>&1
"$hyprctl_bin" -j layers > "$switcher_keys_layers_held" 2>&1
"$grim_bin" "$switcher_keys_held_png" > /dev/null 2>&1
wait
sleep 3
"$qs_bin" ipc -p "$shell_path" call switcher state > "$switcher_keys_closed_json" 2>&1
"$hyprctl_bin" -j layers > "$switcher_keys_layers_closed" 2>&1
"$hyprctl_bin" -j activewindow > "$switcher_keys_active_json" 2>&1
ls -1 "$switcher_keys_probe_dir" > "$switcher_keys_after_path" 2>&1
"$grim_bin" "$switcher_keys_closed_png" > /dev/null 2>&1

# Three fast taps, no sleep inside any of them: one wtype process per tap
# presses the Alt key, taps Tab once and releases Alt straight back out.
"$hyprctl_bin" -j activewindow > "$switcher_keys_fast_before_json" 2>&1
"$wtype_bin" -M alt -P Alt_L -k Tab -p Alt_L -m alt >> "$switcher_keys_wtype_log" 2>&1
sleep 1
"$hyprctl_bin" -j activewindow > "$switcher_keys_fast_1_json" 2>&1
"$wtype_bin" -M alt -P Alt_L -k Tab -p Alt_L -m alt >> "$switcher_keys_wtype_log" 2>&1
sleep 1
"$hyprctl_bin" -j activewindow > "$switcher_keys_fast_2_json" 2>&1
"$wtype_bin" -M alt -P Alt_L -k Tab -p Alt_L -m alt >> "$switcher_keys_wtype_log" 2>&1
sleep 1
"$hyprctl_bin" -j activewindow > "$switcher_keys_fast_3_json" 2>&1
"$qs_bin" ipc -p "$shell_path" call switcher state > "$switcher_keys_fast_state_json" 2>&1
EOS
  echo "exec-once = bash $script"
}

_switcher_keys_layers() {
  "$jq_bin" -r '[.[] | .levels[] | .[] | select(.namespace == "formalshell:switcher")] | length' \
    "$1" 2>/dev/null
}

# Hyprland's own address for a window and the shell's id for it differ by the
# prefix alone (HyprlandBackend: ids are the hex address verbatim).
_switcher_keys_bare_address() {
  echo "${1#0x}"
}

leg_switcher_keys_assert() {
  local f
  for f in "$switcher_keys_binds_path" \
    "$switcher_keys_control_path" "$switcher_keys_after_path" \
    "$switcher_keys_held_json" "$switcher_keys_closed_json" \
    "$switcher_keys_layers_held" "$switcher_keys_layers_closed" \
    "$switcher_keys_active_json" "$switcher_keys_clients_json" \
    "$switcher_keys_fast_before_json" "$switcher_keys_fast_1_json" \
    "$switcher_keys_fast_2_json" "$switcher_keys_fast_3_json" \
    "$switcher_keys_fast_state_json"; do
    [ -f "$f" ] || fail "no switcher-keys artifact produced at $f"
  done
  for f in "$switcher_keys_held_png" "$switcher_keys_closed_png"; do
    [ -f "$f" ] || fail "no frame produced at $f"
  done

  # Hyprland's own bind table and the two controls first: nothing below means
  # anything until the binds are shown to be registered and a bare Alt tap is
  # shown to reach them through this rig's keyboard.
  echo "--- hyprland's own bind table ---"
  cat "$switcher_keys_binds_path"
  echo "--- wtype ---"
  cat "$switcher_keys_wtype_log" 2>/dev/null
  echo "after F13 and a bare Alt tap: [$(tr '\n' ' ' < "$switcher_keys_control_path")]"
  grep -qx 'f13' "$switcher_keys_control_path" \
    || fail "a release bind on an ordinary key left no marker: wtype's keys are not reaching hyprland's bind table at all"
  grep -qx 'plain' "$switcher_keys_control_path" \
    || fail "a bare Alt press and release left no marker while F13's did: the modifier bind is the part that never fires"

  # Two taps of Tab with Alt held: the card is up and the cursor has walked
  # to the third entry.
  local open count index selected_id selected_title mapped
  open=$("$jq_bin" -r '.open' "$switcher_keys_held_json")
  count=$("$jq_bin" -r '.count' "$switcher_keys_held_json")
  index=$("$jq_bin" -r '.index' "$switcher_keys_held_json")
  selected_id=$("$jq_bin" -r '.id' "$switcher_keys_held_json")
  selected_title=$("$jq_bin" -r '.title' "$switcher_keys_held_json")
  echo "alt held, two tabs: open=$open index=$index count=$count title='$selected_title'"
  [ "$open" = "true" ] || fail "Alt+Tab did not open the card: $(cat "$switcher_keys_held_json")"
  [ "$index" = "2" ] || fail "two taps of Tab left the cursor on entry $index, not the third"
  [ -n "$selected_id" ] || fail "the switcher reports no window under the cursor"

  # Four windows in the session, three on the card: the fourth is on
  # workspace 2, and a held Alt walks the workspace being looked at.
  local mapped_windows elsewhere_workspace
  mapped_windows=$("$jq_bin" -r 'length' "$switcher_keys_clients_json")
  elsewhere_workspace=$("$jq_bin" -r \
    '[.[] | select(.class == "formalshell-smoke-elsewhere") | .workspace.id] | first' \
    "$switcher_keys_clients_json")
  echo "session: $mapped_windows windows mapped, one on workspace $elsewhere_workspace"
  [ "${mapped_windows:-0}" -ge 4 ] \
    || fail "the session holds $mapped_windows windows, so the one for another workspace never spawned and there was nothing to exclude"
  [ "$elsewhere_workspace" = "2" ] \
    || fail "the fourth window is on workspace $elsewhere_workspace, not the 2 it was moved to"
  [ "$count" = "3" ] \
    || fail "the switcher offers $count windows, not the three on this workspace: a window from somewhere else reached the card"
  mapped=$(_switcher_keys_layers "$switcher_keys_layers_held")
  echo "layers while held: formalshell:switcher=$mapped"
  [ "${mapped:-0}" -ge 1 ] || fail "no formalshell:switcher layer surface while Alt is held"

  # The release, which is the whole leg: the card closes and focus lands on
  # the window the cursor named.
  local closed_open closed_layers active_address
  closed_open=$("$jq_bin" -r '.open' "$switcher_keys_closed_json")
  closed_layers=$(_switcher_keys_layers "$switcher_keys_layers_closed")
  active_address=$("$jq_bin" -r '.address' "$switcher_keys_active_json")
  echo "alt released: open=$closed_open layers=$closed_layers active=$active_address want=$selected_id"
  [ "$closed_open" = "false" ] \
    || fail "releasing Alt left the card open: $(cat "$switcher_keys_closed_json")"
  [ "${closed_layers:-0}" -eq 0 ] \
    || fail "the switcher's layer surface stayed mapped after the release ($closed_layers)"
  [ -n "$active_address" ] || fail "hyprctl reports no active window after the release"
  [ "$(_switcher_keys_bare_address "$active_address")" = "$(_switcher_keys_bare_address "$selected_id")" ] \
    || fail "focus landed on $active_address, not on the window under the cursor, $selected_id"

  # And the two Alt_L probes, which say WHY the shipped bind needs its flag.
  echo "after the hold: [$(tr '\n' ' ' < "$switcher_keys_after_path")]"
  if grep -qx 'plain' "$switcher_keys_after_path"; then
    fail "the plain 'bindr' fired after an Alt+Tab: hyprland no longer shadows a held key's release bind, so the shipped 'bindrt' and this leg both want revisiting"
  fi
  if grep -qx 'nomods' "$switcher_keys_after_path"; then
    fail "a release bind with no mods fired: the modifier is cleared before Alt_L's release reaches the bind table, so the shipped bind must drop its ALT"
  fi

  # Three fast taps, no sleep inside any of them: focus has to alternate
  # every time, never repeat or sit still, and the card is never left open.
  local fast_before fast_1 fast_2 fast_3 fast_open
  fast_before=$("$jq_bin" -r '.address' "$switcher_keys_fast_before_json")
  fast_1=$("$jq_bin" -r '.address' "$switcher_keys_fast_1_json")
  fast_2=$("$jq_bin" -r '.address' "$switcher_keys_fast_2_json")
  fast_3=$("$jq_bin" -r '.address' "$switcher_keys_fast_3_json")
  fast_open=$("$jq_bin" -r '.open' "$switcher_keys_fast_state_json")
  echo "fast taps: before=$fast_before 1=$fast_1 2=$fast_2 3=$fast_3 open=$fast_open"
  [ -n "$fast_1" ] || fail "no active window after the first fast tap"
  [ "$fast_1" != "$fast_before" ] \
    || fail "the first fast tap left focus on $fast_before: a commit that raced ahead of the next that opened the card was lost"
  [ "$fast_2" = "$fast_before" ] \
    || fail "the second fast tap landed on $fast_2, not back on $fast_before: focus is not alternating"
  [ "$fast_3" = "$fast_1" ] \
    || fail "the third fast tap landed on $fast_3, not back on $fast_1: focus is not alternating"
  [ "$fast_open" = "false" ] \
    || fail "the card is still open after three fast taps: $(cat "$switcher_keys_fast_state_json")"

  echo "SMOKE_SWITCHER_KEYS ok index=$index count=$count committed=$selected_id"
  echo "SMOKE_SWITCHER_KEYS_HELD $switcher_keys_held_png"
  echo "SMOKE_SWITCHER_KEYS_CLOSED $switcher_keys_closed_png"
}
