# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, iso_home, the *_bin paths and fail()
# --spaces (M74): the Spaces cell's own reads, off one session with windows
# on two workspaces. A sibling of --workspaces rather than more of it: that
# leg photographs the pill's travel on a burst clock, and everything here
# waits on herdr polls and a real pointer instead, so the two timelines
# would only get in each other's way.
#
# Fixture: the base window plus a foot on workspace 1 whose process tree
# carries `herdr --remote fakehost`, and two foots on workspace 2, one
# carrying a bare `herdr` and one carrying nothing. `herdr` is a PATH shim:
# as a client it execs an interactive bash under the argv a real client has
# (the script itself reads as `bash .../herdr` in ps, which is not a
# client, and `cat` will not do: the VM's coreutils is one multi-call
# binary that picks its applet off argv[0]),
# and as `herdr agent list` it answers one `working` agent, which is the
# local poll. `ssh` is a PATH shim too, and the only ssh this session can
# reach: the wrapper suffixes openssh for exactly this, so the remote poll
# lands here, answers `blocked` (or `idle` once the drive says so) for
# fakehost every two seconds, and refuses any other host without ever
# handing it on. Every invocation is logged, which is the proof the remote
# path was taken at all.
#
# What is read, in order:
# - `workspaces status`: every window listed under its own slot with its
#   icon resolved, the blocked and working agents on the right icons, the
#   plain window with none, and the slot on screen wider than a bare one.
# - `debug dump`'s herdr block agreeing: both windows in stateByWindow,
#   both client keys in stateByKey.
# - The frame: the blocked icon's badge, read as the difference between the
#   slot with herdr answering blocked and the same slot once it answers
#   idle, red-dominant and inside that icon's own box. The idle dump drops
#   the window from stateByWindow, which is the "nothing for idle" half.
# - A wheel notch over workspace 1's slot (wlrctl, a real axis event) moving
#   focus to workspace 2 and a notch back returning it, off hyprctl. A
#   notch is `scroll 15`: Qt reads wlrctl's continuous axis at 8 per unit,
#   so the 10 wheel.sh sends is an angleDelta of 80, short of the 120 the
#   cell sums to before it steps.
# - `workspaces peek 2` opening the preview on workspace 2 with two window
#   boxes, photographed, then closed.
# - A real pointer parked on workspace 2's slot opening the same preview
#   after the hover delay, and moving off it closing it again.
leg_spaces_flag="--spaces"
leg_spaces_order=196
leg_spaces_needs="foot jq convert wlrctl"
leg_spaces_fixture_window=keep

spaces_shim_dir="$shot_dir/spaces-shim"
spaces_ssh_calls_path="$shot_dir/spaces-ssh-calls.txt"
spaces_herdr_calls_path="$shot_dir/spaces-herdr-calls.txt"
spaces_remote_state_path="$shot_dir/spaces-remote-state"
spaces_dispatch_path="$shot_dir/spaces-dispatch.txt"
spaces_done_path="$shot_dir/spaces-done"
spaces_status_one_path="$shot_dir/spaces-status-one.json"
spaces_status_two_path="$shot_dir/spaces-status-two.json"
spaces_status_peek_path="$shot_dir/spaces-status-peek.json"
spaces_status_hover_path="$shot_dir/spaces-status-hover.json"
spaces_status_left_path="$shot_dir/spaces-status-left.json"
spaces_dump_path="$shot_dir/spaces-dump.json"
spaces_dump_idle_path="$shot_dir/spaces-dump-idle.json"
spaces_peek_reply_path="$shot_dir/spaces-peek-reply.txt"
spaces_ws_down_path="$shot_dir/spaces-ws-down.txt"
spaces_ws_up_path="$shot_dir/spaces-ws-up.txt"
spaces_blocked_png="$shot_dir/spaces-blocked.png"
spaces_idle_png="$shot_dir/spaces-idle.png"
spaces_two_png="$shot_dir/spaces-two.png"
spaces_peek_png="$shot_dir/spaces-peek.png"
spaces_hover_png="$shot_dir/spaces-hover.png"
spaces_left_png="$shot_dir/spaces-left.png"
spaces_crop_dir="$shot_dir/spaces-crops"

leg_spaces_validate() {
  local other
  for other in workspaces wheel switcher switcher_keys tooltip tooltip_travel notify_close hotcorner_relock; do
    if leg_on "$other"; then
      echo "usage: --spaces drives the pointer and the focused workspace and cannot combine with --${other//_/-}" >&2
      exit 1
    fi
  done
}

leg_spaces_fixture() {
  local name colour
  mkdir -p "$spaces_shim_dir"
  echo blocked > "$spaces_remote_state_path"
  cat > "$spaces_shim_dir/herdr" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = agent ]; then
  printf '%s\n' "\$*" >> "$spaces_herdr_calls_path"
  printf '%s\n' '{"result":{"type":"agent_list","agents":[{"pane_id":"p1","agent":"claude","agent_status":"working"}]}}'
  exit 0
fi
exec -a "herdr\${*:+ \$*}" bash
EOF
  cat > "$spaces_shim_dir/ssh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$spaces_ssh_calls_path"
host=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) shift 2 ;;
    -*) shift ;;
    *) host="\$1"; break ;;
  esac
done
if [ "\$host" != fakehost ]; then
  printf 'refused %s\n' "\$host" >> "$spaces_ssh_calls_path"
  exit 255
fi
while :; do
  state=\$(cat "$spaces_remote_state_path" 2>/dev/null)
  printf '{"result":{"type":"agent_list","agents":[{"pane_id":"p1","agent":"claude","agent_status":"%s"}]}}\n' "\${state:-idle}"
  sleep 2
done
EOF
  chmod +x "$spaces_shim_dir/herdr" "$spaces_shim_dir/ssh"
  # clipssh.sh's route onto the shell's PATH: the rig's own environment is
  # what Hyprland, the foots and the shell's pollers all inherit.
  export PATH="$spaces_shim_dir:$PATH"

  # One entry and one flat icon per fixture app id, so every window has an
  # icon of its own and none of them is red, which the badge read relies on.
  mkdir -p "$iso_home/.local/share/applications" "$iso_home/.local/share/icons/hicolor/48x48/apps"
  for name in blocked:'#3A7BD5' working:'#3AAA5D' plain:'#8A8A8A'; do
    colour=${name#*:}
    name=${name%%:*}
    cat > "$iso_home/.local/share/applications/formalshell-spaces-$name.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Spaces $name
Exec=true
Icon=formalshell-spaces-$name
EOF
    $convert_bin -size 48x48 "xc:$colour" "$iso_home/.local/share/icons/hicolor/48x48/apps/formalshell-spaces-$name.png"
  done
}

leg_spaces_timing() {
  leg_timing 80 120
}

leg_spaces_drive() {
  local script="$shot_dir/spaces-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
call() { "$qs_bin" ipc -p "$shell_path" call "\$@"; }
centre() { "$jq_bin" -r ".slots[\$1].rect | \"\\(.x + (.width / 2) | floor) \\(.y + (.height / 2) | floor)\"" "\$2"; }
park() {
  "$wlrctl_bin" pointer move -4000 -4000 >> "$spaces_dispatch_path" 2>&1
  sleep 0.5
  "$wlrctl_bin" pointer move "\$1" "\$2" >> "$spaces_dispatch_path" 2>&1
}
sleep 4
"$hyprctl_bin" dispatch exec "[workspace 1 silent] $foot_bin --app-id=formalshell-spaces-blocked herdr --remote fakehost" > "$spaces_dispatch_path" 2>&1
"$hyprctl_bin" dispatch exec "[workspace 2 silent] $foot_bin --app-id=formalshell-spaces-working herdr" >> "$spaces_dispatch_path" 2>&1
sleep 2
"$hyprctl_bin" dispatch exec "[workspace 2 silent] $foot_bin --app-id=formalshell-spaces-plain sh -c 'sleep 300'" >> "$spaces_dispatch_path" 2>&1
sleep 8
call workspaces status > "$spaces_status_one_path" 2>&1
call debug dump > "$spaces_dump_path" 2>&1
"$grim_bin" "$spaces_blocked_png" > /dev/null 2>&1
echo idle > "$spaces_remote_state_path"
sleep 5
call debug dump > "$spaces_dump_idle_path" 2>&1
"$grim_bin" "$spaces_idle_png" > /dev/null 2>&1
echo blocked > "$spaces_remote_state_path"
sleep 4
park \$(centre 0 "$spaces_status_one_path")
sleep 1
"$wlrctl_bin" pointer scroll 15 0 >> "$spaces_dispatch_path" 2>&1
sleep 2
"$hyprctl_bin" activeworkspace -j > "$spaces_ws_down_path" 2>&1
call workspaces status > "$spaces_status_two_path" 2>&1
"$grim_bin" "$spaces_two_png" > /dev/null 2>&1
"$wlrctl_bin" pointer scroll -15 0 >> "$spaces_dispatch_path" 2>&1
sleep 2
"$hyprctl_bin" activeworkspace -j > "$spaces_ws_up_path" 2>&1
park 960 900
sleep 1
call workspaces peek 2 > "$spaces_peek_reply_path" 2>&1
sleep 2
call workspaces status > "$spaces_status_peek_path" 2>&1
"$grim_bin" "$spaces_peek_png" > /dev/null 2>&1
call workspaces close >> "$spaces_peek_reply_path" 2>&1
sleep 2
park \$(centre 1 "$spaces_status_one_path")
sleep 2
call workspaces status > "$spaces_status_hover_path" 2>&1
"$grim_bin" "$spaces_hover_png" > /dev/null 2>&1
park 960 900
sleep 2
call workspaces status > "$spaces_status_left_path" 2>&1
"$grim_bin" "$spaces_left_png" > /dev/null 2>&1
touch "$spaces_done_path"
EOF
  add_cleanup "pkill -f formalshell-spaces- 2>/dev/null || true"
  echo "exec-once = bash $script"
}

# The icon a fixture app id resolved to in one status read, as a jq object
# carrying its slot index and its place among that slot's icons.
spaces_icon() {
  "$jq_bin" -c --arg app "formalshell-spaces-$2" \
    '[.slots | to_entries[] | .key as $s | .value.icons | to_entries[] | select(.value.appId == $app) | .value + {slot: $s, at: .key}] | first' "$1"
}

leg_spaces_assert() {
  local f blocked working plain blocked_id working_id slot_one slot_bare
  [ -f "$spaces_done_path" ] || fail "the spaces drive never finished; last dispatch output: $(tail -n 5 "$spaces_dispatch_path" 2>/dev/null)"
  for f in "$spaces_status_one_path" "$spaces_dump_path" "$spaces_dump_idle_path" \
    "$spaces_status_two_path" "$spaces_status_peek_path" "$spaces_status_hover_path" "$spaces_status_left_path"; do
    [ -s "$f" ] || fail "no read produced at $f"
  done
  cat "$spaces_status_one_path"; echo
  cat "$spaces_dispatch_path" 2>/dev/null || true
  echo "ssh shim calls:"; cat "$spaces_ssh_calls_path" 2>/dev/null || true
  echo "herdr shim calls: $(wc -l < "$spaces_herdr_calls_path" 2>/dev/null || echo 0)"

  # The remote poll reached the shim, and only for fakehost.
  grep -q 'fakehost' "$spaces_ssh_calls_path" 2>/dev/null \
    || fail "no ssh call for fakehost: the remote herdr client was never polled"
  if grep -q '^refused' "$spaces_ssh_calls_path"; then
    fail "the shell asked ssh for a host other than fakehost: $(grep '^refused' "$spaces_ssh_calls_path")"
  fi
  [ -s "$spaces_herdr_calls_path" ] || fail "the local herdr client was never polled"

  # Icons: every fixture window under its own slot, each resolved.
  blocked=$(spaces_icon "$spaces_status_one_path" blocked)
  working=$(spaces_icon "$spaces_status_one_path" working)
  plain=$(spaces_icon "$spaces_status_one_path" plain)
  echo "blocked: $blocked"; echo "working: $working"; echo "plain: $plain"
  echo "herdr in debug dump: $("$jq_bin" -c .herdr "$spaces_dump_path")"
  [ "$(echo "$blocked" | "$jq_bin" -r .slot)" = 0 ] || fail "the blocked window is not under workspace 1's slot: $blocked"
  [ "$(echo "$working" | "$jq_bin" -r .slot)" = 1 ] || fail "the working window is not under workspace 2's slot: $working"
  [ "$(echo "$plain" | "$jq_bin" -r .slot)" = 1 ] || fail "the plain window is not under workspace 2's slot: $plain"
  for f in "$blocked" "$working" "$plain"; do
    [ "$(echo "$f" | "$jq_bin" -r .icon)" = true ] || fail "a fixture window resolved no icon: $f"
  done
  "$jq_bin" -e '.slots[0].icons | map(select(.appId == "formalshell-smoke-iconic")) | length == 1' "$spaces_status_one_path" > /dev/null \
    || fail "the base fixture window is not under workspace 1's slot"

  # Badges in status, then the same answer in the service itself.
  [ "$(echo "$blocked" | "$jq_bin" -r .agent)" = blocked ] || fail "the remote client's window carries no blocked badge: $blocked"
  [ "$(echo "$working" | "$jq_bin" -r .agent)" = working ] || fail "the local client's window carries no working badge: $working"
  [ "$(echo "$plain" | "$jq_bin" -r .agent)" = "" ] || fail "a window with no herdr in its tree carries a badge: $plain"
  blocked_id=$(echo "$blocked" | "$jq_bin" -r .id)
  working_id=$(echo "$working" | "$jq_bin" -r .id)
  [ "$("$jq_bin" -r --arg id "$blocked_id" '.herdr.stateByWindow[$id] // ""' "$spaces_dump_path")" = blocked ] \
    || fail "debug dump's stateByWindow has no blocked entry for $blocked_id"
  [ "$("$jq_bin" -r --arg id "$working_id" '.herdr.stateByWindow[$id] // ""' "$spaces_dump_path")" = working ] \
    || fail "debug dump's stateByWindow has no working entry for $working_id"
  [ "$("$jq_bin" -r '.herdr.stateByKey["remote:fakehost"] // ""' "$spaces_dump_path")" = blocked ] \
    || fail "debug dump's stateByKey has no blocked remote:fakehost"
  [ "$("$jq_bin" -r '.herdr.stateByKey.local // ""' "$spaces_dump_path")" = working ] \
    || fail "debug dump's stateByKey has no working local client"
  "$jq_bin" -c .herdr "$spaces_dump_idle_path"
  [ "$("$jq_bin" -r --arg id "$blocked_id" '.herdr.stateByWindow[$id] // ""' "$spaces_dump_idle_path")" = "" ] \
    || fail "herdr answering idle left $blocked_id in stateByWindow"

  # The slot on screen is wider than a bare one.
  slot_one=$("$jq_bin" -r '.slots[0].extent' "$spaces_status_one_path")
  slot_bare=$("$jq_bin" -r '[.slots[] | select(.icons | length == 0) | .extent] | first // 0' "$spaces_status_one_path")
  echo "workspace 1 slot $slot_one wide, a bare slot $slot_bare"
  "$jq_bin" -e '.slots[0].active and .slots[0].appsShown' "$spaces_status_one_path" > /dev/null \
    || fail "workspace 1's slot is not the active one showing its icons"
  [ "${slot_one%.*}" -gt "${slot_bare%.*}" ] || fail "the active slot ($slot_one) is no wider than a bare one ($slot_bare)"

  for f in "$spaces_blocked_png" "$spaces_idle_png" "$spaces_two_png" "$spaces_peek_png" "$spaces_hover_png" "$spaces_left_png"; do
    [ -f "$f" ] || fail "no spaces screenshot produced at $f"
  done
  echo "SMOKE_SPACES_BLOCKED $spaces_blocked_png"
  echo "SMOKE_SPACES_IDLE $spaces_idle_png"
  echo "SMOKE_SPACES_TWO $spaces_two_png"
  echo "SMOKE_SPACES_PEEK $spaces_peek_png"
  echo "SMOKE_SPACES_HOVER $spaces_hover_png"
  echo "SMOKE_SPACES_LEFT $spaces_left_png"

  # The badge in the frame: what changed in workspace 1's slot when herdr
  # went from blocked to idle, which has to sit on the blocked icon and be
  # red. Icons are right-aligned in the slot, `md` in from its end, 16 wide
  # with 2 between.
  local geo sx sy sw sh n at icon_left diff_box dx dw red_on red_off
  read -r sx sy sw sh < <("$jq_bin" -r '.slots[0].rect | "\(.x) \(.y) \(.width) \(.height)"' "$spaces_status_one_path")
  n=$("$jq_bin" -r '.slots[0].icons | length' "$spaces_status_one_path")
  at=$(echo "$blocked" | "$jq_bin" -r .at)
  icon_left=$((sx + sw - 6 - (n - at) * 16 - (n - 1 - at) * 2))
  geo="${sw}x${sh}+${sx}+${sy}"
  mkdir -p "$spaces_crop_dir"
  $convert_bin "$spaces_blocked_png" -crop "$geo" +repage "$spaces_crop_dir/slot-blocked.png" \
    || fail "could not crop workspace 1's slot at $geo"
  $convert_bin "$spaces_idle_png" -crop "$geo" +repage "$spaces_crop_dir/slot-idle.png"
  echo "SMOKE_SPACES_SLOT_BLOCKED $spaces_crop_dir/slot-blocked.png"
  echo "SMOKE_SPACES_SLOT_IDLE $spaces_crop_dir/slot-idle.png"
  diff_box=$($convert_bin "$spaces_crop_dir/slot-blocked.png" "$spaces_crop_dir/slot-idle.png" \
    -compose difference -composite -threshold 10% -format '%@' info: 2>/dev/null)
  echo "slot $geo, blocked icon from x=$icon_left, badge diff box $diff_box"
  dw=${diff_box%%x*}
  dx=$(echo "$diff_box" | sed -n 's/^[0-9]*x[0-9]*+\([0-9]*\)+[0-9]*$/\1/p')
  [ -n "$dx" ] && [ "${dw:-0}" -gt 0 ] && [ "$diff_box" != "0x0+0+0" ] \
    || fail "workspace 1's slot looks the same with herdr blocked and idle: no badge drawn"
  dx=$((dx + sx))
  if [ "$dx" -lt $((icon_left - 3)) ] || [ $((dx + dw)) -gt $((icon_left + 16 + 4)) ]; then
    fail "the badge change spans x=$dx..$((dx + dw)), outside the blocked icon at $icon_left..$((icon_left + 16))"
  fi
  # Redness as the mean of red over the other two, read off both frames in
  # the same box. The badge pulses between 0.4 and 1, so a fixed colour
  # match would depend on the phase a frame caught; the blocked frame only
  # has to be clearly redder than the idle one, whose box holds a blue icon.
  local red='%[fx:mean.r - (mean.g + mean.b) / 2]'
  red_on=$($convert_bin "$spaces_crop_dir/slot-blocked.png" -crop "$diff_box" +repage -format "$red" info: 2>/dev/null)
  red_off=$($convert_bin "$spaces_crop_dir/slot-idle.png" -crop "$diff_box" +repage -format "$red" info: 2>/dev/null)
  echo "redness in the badge box: blocked $red_on, idle $red_off"
  awk -v on="$red_on" -v off="$red_off" 'BEGIN { exit !(on != "" && off != "" && on > off + 0.1) }' \
    || fail "the blocked badge is not drawn in the destructive colour: redness $red_on against $red_off idle"

  # The wheel: one notch down to workspace 2, one back.
  echo "after notch down: $("$jq_bin" -c '{id, name}' "$spaces_ws_down_path" 2>/dev/null)"
  echo "after notch up: $("$jq_bin" -c '{id, name}' "$spaces_ws_up_path" 2>/dev/null)"
  [ "$("$jq_bin" -r .id "$spaces_ws_down_path")" = 2 ] || fail "a wheel notch over the cell did not move focus to workspace 2"
  [ "$("$jq_bin" -r .id "$spaces_ws_up_path")" = 1 ] || fail "a wheel notch back did not return focus to workspace 1"
  "$jq_bin" -e '.slots[1].active and (.slots[1].icons | map(.agent) | index("working") != null)' "$spaces_status_two_path" > /dev/null \
    || fail "workspace 2's slot is not active with its working badge after the notch: $(cat "$spaces_status_two_path")"

  # The preview, by IPC and by pointer.
  cat "$spaces_peek_reply_path"
  "$jq_bin" -c .preview "$spaces_status_peek_path" "$spaces_status_hover_path" "$spaces_status_left_path"
  grep -q '^ok$' "$spaces_peek_reply_path" || fail "workspaces peek 2 did not answer ok: $(cat "$spaces_peek_reply_path")"
  "$jq_bin" -e '.preview.open and .preview.idx == 2 and .preview.windows == 2' "$spaces_status_peek_path" > /dev/null \
    || fail "peek 2 did not open workspace 2's preview with two boxes: $("$jq_bin" -c .preview "$spaces_status_peek_path")"
  "$jq_bin" -e '.preview.open and .preview.idx == 2' "$spaces_status_hover_path" > /dev/null \
    || fail "a pointer parked on workspace 2's slot did not open its preview: $("$jq_bin" -c .preview "$spaces_status_hover_path")"
  "$jq_bin" -e '.preview.open | not' "$spaces_status_left_path" > /dev/null \
    || fail "moving the pointer off the slot left the preview open: $("$jq_bin" -c .preview "$spaces_status_left_path")"
}
