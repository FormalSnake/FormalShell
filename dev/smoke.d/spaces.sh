# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, iso_home, the *_bin paths and fail()
# --spaces (M74): the Spaces cell's own reads, off one session with windows
# on two workspaces. A sibling of --workspaces rather than more of it: that
# leg photographs the pill's travel on a burst clock, and everything here
# waits on herdr polls and a real pointer instead, so the two timelines
# would only get in each other's way.
#
# Fixture: the base window plus two windows of one foot server on
# workspace 1, sharing its pid the way every ghostty window does: one
# carries `herdr --remote fakehost` under the title herdr's default
# window_title renders for it, the other a plain shell. Two foots on
# workspace 2, one
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
# - `workspaces status`: every window listed under its own chip with its
#   icon resolved and shown (icons on every occupied chip, not just the
#   one on screen), every chip labelled with its ordinal, the blocked and
#   working agents on the right icons, the plain window with none, and the
#   chip on screen wider than a bare one.
# - `debug dump`'s herdr block agreeing: both windows in stateByWindow,
#   both client keys in stateByKey.
# - The frame: the blocked icon's badge, read as the difference between the
#   chip with herdr answering blocked and the same chip once it answers
#   idle, red-dominant and inside that icon's own box (the icon's rect out
#   of `workspaces status`). The idle dump drops the window from
#   stateByWindow, which is the "nothing for idle" half.
# - A wheel notch over workspace 1's slot (wlrctl, a real axis event) moving
#   focus to workspace 2 and a notch back returning it, off hyprctl. A
#   notch is `scroll 15`: Qt reads wlrctl's continuous axis at 8 per unit,
#   so the 10 wheel.sh sends is an angleDelta of 80, short of the 120 the
#   cell sums to before it steps.
# - `workspaces peek 2` opening the preview on workspace 2 with both of its
#   windows drawn live (the thumbnails' ScreencopyViews holding a frame),
#   taking the keyboard as any panel does; photographed, then closed.
# - A real pointer parked on workspace 2's chip opening the same preview
#   after the hover delay without taking the keyboard, and staying open
#   while the pointer keeps moving over the chip, which is what a hand on a
#   real mouse does and what a card that primes Exclusive focus fails:
#   Hyprland pulls the pointer onto a layer that maps Exclusive and hands
#   it back on the next motion. Moving off it closes it again.
# - A window of workspace 2 floated and moved mostly past the output's right
#   edge (`movewindowpixel exact`), the case a scrolling layout produces on
#   its own: the peeked card's miniature opens scrolled to the output's own
#   region, lays that window out at its real size and place beyond the
#   viewport (its thumbnail as wide as the window's rect at the miniature's
#   scale, not a clamped sliver), and a real wheel notch over the card
#   scrolls the strip along x, then a notch the other way scrolls it back.
leg_spaces_flag="--spaces"
leg_spaces_order=196
leg_spaces_needs="foot jq convert wlrctl"
leg_spaces_fixture_window=keep

spaces_shim_dir="$shot_dir/spaces-shim"
spaces_ssh_calls_path="$shot_dir/spaces-ssh-calls.txt"
spaces_herdr_calls_path="$shot_dir/spaces-herdr-calls.txt"
spaces_remote_state_path="$shot_dir/spaces-remote-state"
spaces_dispatch_path="$shot_dir/spaces-dispatch.txt"
spaces_foot_socket="$shot_dir/formalshell-spaces-foot.sock"
spaces_done_path="$shot_dir/spaces-done"
spaces_status_one_path="$shot_dir/spaces-status-one.json"
spaces_status_two_path="$shot_dir/spaces-status-two.json"
spaces_status_peek_path="$shot_dir/spaces-status-peek.json"
spaces_status_hover_path="$shot_dir/spaces-status-hover.json"
spaces_status_left_path="$shot_dir/spaces-status-left.json"
spaces_status_moved_path="$shot_dir/spaces-status-moved.json"
spaces_status_pad_path="$shot_dir/spaces-status-pad.json"
spaces_status_pad_back_path="$shot_dir/spaces-status-pad-back.json"
spaces_status_wheel_path="$shot_dir/spaces-status-wheel.json"
spaces_status_wheel_back_path="$shot_dir/spaces-status-wheel-back.json"
spaces_dump_path="$shot_dir/spaces-dump.json"
spaces_dump_idle_path="$shot_dir/spaces-dump-idle.json"
spaces_peek_reply_path="$shot_dir/spaces-peek-reply.txt"
spaces_ws_down_path="$shot_dir/spaces-ws-down.txt"
spaces_ws_up_path="$shot_dir/spaces-ws-up.txt"
spaces_blocked_png="$shot_dir/spaces-blocked.png"
spaces_idle_png="$shot_dir/spaces-idle.png"
spaces_two_png="$shot_dir/spaces-two.png"
spaces_peek_png="$shot_dir/spaces-peek.png"
spaces_wheel_png="$shot_dir/spaces-wheel.png"
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
if [ "\${1:-}" = workspace ]; then
  printf '%s\n' '{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[{"label":"rig","number":1}]}}'
  exit 0
fi
# "{hostname}: {workspace}" as fakehost's server would render it. The VM's
# own bashrc titles every prompt user@host: cwd, so this client's bash gets
# a home whose .bashrc, read last, puts herdr's title back each prompt.
if [ "\$*" = "--remote fakehost" ]; then
  export HOME="$spaces_shim_dir/remote-client-home"
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
# A real remote whose bash, run by sshd, sources a ~/.bashrc that starts
# an interactive fish on the channel's stdin. Short of -n or --norc that fish
# waits for an EOF the shell's open stdin pipe never sends.
case " \$* " in
  *" -n "*|*" bash --norc "*) ;;
  *) cat > /dev/null ;;
esac
# One line the size and shape herdr 0.9.1 really prints for eight agents
# (~4.5KB, a non-ASCII title glyph in each), only the first one's status
# driven.
agent() {
  printf '{"agent":"claude","agent_session":{"agent":"claude","kind":"id","source":"herdr:claude","value":"764b8a38-bc42-4d6b-8c85-73ca5a24831%s"},"agent_status":"%s","cwd":"/home/rig/src/project-%s","focused":false,"foreground_cwd":"/home/rig/src/project-%s","pane_id":"w65215ab3bb4281:p%s","revision":11,"state_change_seq":856,"tab_id":"w65215ab3bb4281:t%s","terminal_id":"term_65c177d9ebde6%s","terminal_title":"◑ Fixture agent %s on a long running task","terminal_title_stripped":"Fixture agent %s on a long running task","workspace_id":"w65215ab3bb4281"}' "\$1" "\$2" "\$1" "\$1" "\$1" "\$1" "\$1" "\$1" "\$1"
}
echo "hostname fakehost-server"
while :; do
  state=\$(cat "$spaces_remote_state_path" 2>/dev/null)
  agents=\$(agent 1 "\${state:-idle}")
  for i in 2 3 4 5 6 7 8; do agents="\$agents,\$(agent "\$i" idle)"; done
  printf '{"id":"cli:agent:list","result":{"type":"agent_list","agents":[%s]}}\n' "\$agents"
  printf '%s\n' '{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[{"label":"other","number":1},{"label":"rig","number":2}]}}'
  sleep 2
done
EOF
  mkdir -p "$spaces_shim_dir/remote-client-home"
  cat > "$spaces_shim_dir/remote-client-home/.bashrc" <<'EOF'
PS1='$ '
PROMPT_COMMAND='printf "\033]2;fakehost-server: rig\007"'
EOF
  chmod +x "$spaces_shim_dir/herdr" "$spaces_shim_dir/ssh"
  # clipssh.sh's route onto the shell's PATH: the rig's own environment is
  # what Hyprland, the foots and the shell's pollers all inherit.
  export PATH="$spaces_shim_dir:$PATH"

  # One entry and one flat icon per fixture app id, so every window has an
  # icon of its own and none of them is red, which the badge read relies on.
  mkdir -p "$iso_home/.local/share/applications" "$iso_home/.local/share/icons/hicolor/48x48/apps"
  for name in blocked:'#3A7BD5' sibling:'#9A6AD5' working:'#3AAA5D' plain:'#8A8A8A'; do
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
  # The base run writes the same index only when every leg keeps its
  # fixture window, which a rider like --frame does not, and QIconLoader
  # enumerates nothing under hicolor without one.
  cat > "$iso_home/.local/share/icons/hicolor/index.theme" <<'EOF'
[Icon Theme]
Name=Hicolor
Comment=Fallback icon theme
Directories=48x48/apps

[48x48/apps]
Size=48
Context=Applications
Type=Threshold
EOF
}

leg_spaces_timing() {
  leg_timing 80 120
}

leg_spaces_drive() {
  local script="$shot_dir/spaces-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
call() { $ipc call "\$@"; }
centre() { "$jq_bin" -r ".slots[\$1].rect | \"\\(.x + (.width / 2) | floor) \\(.y + (.height / 2) | floor)\"" "\$2"; }
card_centre() { "$jq_bin" -r ".preview.rect | \"\\(.x + (.width / 2) | floor) \\(.y + (.height / 2) | floor)\"" "\$1"; }
park() {
  "$wlrctl_bin" pointer move -4000 -4000 >> "$spaces_dispatch_path" 2>&1
  sleep 0.5
  "$wlrctl_bin" pointer move "\$1" "\$2" >> "$spaces_dispatch_path" 2>&1
}
sleep 4
"$hyprctl_bin" dispatch "hl.dsp.exec_cmd([==[$foot_bin --server=$spaces_foot_socket]==])" > "$spaces_dispatch_path" 2>&1
sleep 1
"$hyprctl_bin" dispatch "hl.dsp.exec_cmd([==[${foot_bin%/*}/footclient --server-socket=$spaces_foot_socket --app-id=formalshell-spaces-blocked herdr --remote fakehost]==])" >> "$spaces_dispatch_path" 2>&1
"$hyprctl_bin" dispatch "hl.dsp.exec_cmd([==[${foot_bin%/*}/footclient --server-socket=$spaces_foot_socket --app-id=formalshell-spaces-sibling sh -c 'sleep 300']==])" >> "$spaces_dispatch_path" 2>&1
"$hyprctl_bin" dispatch "hl.dsp.exec_cmd([==[$foot_bin --app-id=formalshell-spaces-working herdr]==], { workspace = '2 silent' })" >> "$spaces_dispatch_path" 2>&1
sleep 2
"$hyprctl_bin" dispatch "hl.dsp.exec_cmd([==[$foot_bin --app-id=formalshell-spaces-plain sh -c 'sleep 300']==], { workspace = '2 silent' })" >> "$spaces_dispatch_path" 2>&1
sleep 2
# Workspace 2's plain window floated and put mostly past the output's right
# edge, its real rect kept as it is. Fully past it Hyprland exports no
# frames for it and the capture count below would drop.
out_w=\$("$hyprctl_bin" monitors -j | "$jq_bin" -r '.[0] | (.width / .scale) | floor')
"$hyprctl_bin" dispatch "hl.dsp.window.float({ window = 'class:^(formalshell-spaces-plain)\$', action = 'toggle' })" >> "$spaces_dispatch_path" 2>&1
"$hyprctl_bin" dispatch "hl.dsp.window.resize({ x = 640, y = 400, window = 'class:^(formalshell-spaces-plain)\$' })" >> "$spaces_dispatch_path" 2>&1
"$hyprctl_bin" dispatch "hl.dsp.window.move({ x = \$((out_w - 200)), y = 150, window = 'class:^(formalshell-spaces-plain)\$' })" >> "$spaces_dispatch_path" 2>&1
# A footclient window belongs to the server's pid, which exec's window rules
# never see, so both are moved by class instead.
"$hyprctl_bin" dispatch "hl.dsp.window.move({ workspace = 1, follow = false, window = 'class:^(formalshell-spaces-blocked)\$' })" >> "$spaces_dispatch_path" 2>&1
"$hyprctl_bin" dispatch "hl.dsp.window.move({ workspace = 1, follow = false, window = 'class:^(formalshell-spaces-sibling)\$' })" >> "$spaces_dispatch_path" 2>&1
sleep 6
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
park \$(card_centre "$spaces_status_peek_path")
sleep 1
"$wlrctl_bin" pointer scroll 15 0 >> "$spaces_dispatch_path" 2>&1
sleep 1
call workspaces status > "$spaces_status_wheel_path" 2>&1
"$grim_bin" "$spaces_wheel_png" > /dev/null 2>&1
"$wlrctl_bin" pointer scroll -15 0 >> "$spaces_dispatch_path" 2>&1
sleep 1
call workspaces status > "$spaces_status_wheel_back_path" 2>&1
call workspaces close >> "$spaces_peek_reply_path" 2>&1
sleep 2
park \$(centre 1 "$spaces_status_one_path")
sleep 2
call workspaces status > "$spaces_status_hover_path" 2>&1
"$grim_bin" "$spaces_hover_png" > /dev/null 2>&1
for step in 3 -3 3 -3 3 -3 3 -3 3 -3; do
  "$wlrctl_bin" pointer move "\$step" 0 >> "$spaces_dispatch_path" 2>&1
  sleep 0.15
done
sleep 0.5
call workspaces status > "$spaces_status_moved_path" 2>&1
# Still the hover-opened card, no keyboard: the pointer crosses onto it and a
# horizontal axis event (what a trackpad's sideways swipe sends) scrolls the
# strip without the card closing.
read -r chip_x chip_y <<< "\$(centre 1 "$spaces_status_one_path")"
read -r card_x card_y <<< "\$(card_centre "$spaces_status_moved_path")"
"$wlrctl_bin" pointer move \$((card_x - chip_x)) \$((card_y - chip_y)) >> "$spaces_dispatch_path" 2>&1
sleep 1
"$wlrctl_bin" pointer scroll 0 15 >> "$spaces_dispatch_path" 2>&1
sleep 1
call workspaces status > "$spaces_status_pad_path" 2>&1
"$wlrctl_bin" pointer scroll 0 -15 >> "$spaces_dispatch_path" 2>&1
sleep 1
call workspaces status > "$spaces_status_pad_back_path" 2>&1
park 960 900
sleep 2
call workspaces status > "$spaces_status_left_path" 2>&1
"$grim_bin" "$spaces_left_png" > /dev/null 2>&1
touch "$spaces_done_path"
EOF
  add_cleanup "pkill -f formalshell-spaces- 2>/dev/null || true"
  hypr_exec_once "bash $script"
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
    "$spaces_status_two_path" "$spaces_status_peek_path" "$spaces_status_hover_path" \
    "$spaces_status_moved_path" "$spaces_status_left_path" \
    "$spaces_status_pad_path" "$spaces_status_pad_back_path" \
    "$spaces_status_wheel_path" "$spaces_status_wheel_back_path"; do
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

  # Chips: the ordinal on every one, whatever the compositor names it.
  "$jq_bin" -e '.slots | all(.label == (.idx | tostring))' "$spaces_status_one_path" > /dev/null \
    || fail "a chip is labelled with something other than its ordinal: $("$jq_bin" -c '[.slots[] | .label]' "$spaces_status_one_path")"

  # Icons: every fixture window under its own chip, each resolved, and
  # shown on every chip that holds a window, not only the one on screen.
  blocked=$(spaces_icon "$spaces_status_one_path" blocked)
  working=$(spaces_icon "$spaces_status_one_path" working)
  plain=$(spaces_icon "$spaces_status_one_path" plain)
  sibling=$(spaces_icon "$spaces_status_one_path" sibling)
  echo "blocked: $blocked"; echo "sibling: $sibling"; echo "working: $working"; echo "plain: $plain"
  echo "herdr in debug dump: $("$jq_bin" -c .herdr "$spaces_dump_path")"
  "$jq_bin" -c '.windows[] | select(.appId | startswith("formalshell-spaces-")) | {appId, pid, title}' "$spaces_dump_path"
  [ "$(echo "$blocked" | "$jq_bin" -r .slot)" = 0 ] || fail "the blocked window is not under workspace 1's slot: $blocked"
  [ "$(echo "$working" | "$jq_bin" -r .slot)" = 1 ] || fail "the working window is not under workspace 2's slot: $working"
  [ "$(echo "$plain" | "$jq_bin" -r .slot)" = 1 ] || fail "the plain window is not under workspace 2's slot: $plain"
  [ "$(echo "$sibling" | "$jq_bin" -r .slot)" = 0 ] || fail "the sibling window is not under workspace 1's slot: $sibling"
  for f in "$blocked" "$sibling" "$working" "$plain"; do
    [ "$(echo "$f" | "$jq_bin" -r .icon)" = true ] || fail "a fixture window resolved no icon: $f"
  done
  "$jq_bin" -e '[.slots[] | select(.icons | length > 0) | .appsShown] | all' "$spaces_status_one_path" > /dev/null \
    || fail "an occupied chip hides its icons: $("$jq_bin" -c '[.slots[] | {idx, appsShown}]' "$spaces_status_one_path")"
  # Only there when every leg in the run keeps the base fixture window.
  if $fixture_window_mode; then
    "$jq_bin" -e '.slots[0].icons | map(select(.appId == "formalshell-smoke-iconic")) | length == 1' "$spaces_status_one_path" > /dev/null \
      || fail "the base fixture window is not under workspace 1's slot"
  fi

  # Badges in status, then the same answer in the service itself.
  [ "$(echo "$blocked" | "$jq_bin" -r .agent)" = blocked ] || fail "the remote client's window carries no blocked badge: $blocked"
  [ "$(echo "$working" | "$jq_bin" -r .agent)" = working ] || fail "the local client's window carries no working badge: $working"
  [ "$(echo "$plain" | "$jq_bin" -r .agent)" = "" ] || fail "a window with no herdr in its tree carries a badge: $plain"
  [ "$(echo "$sibling" | "$jq_bin" -r .agent)" = "" ] \
    || fail "the plain window sharing the herdr window's pid carries its badge: $sibling"
  blocked_id=$(echo "$blocked" | "$jq_bin" -r .id)
  sibling_id=$(echo "$sibling" | "$jq_bin" -r .id)
  pids=$("$jq_bin" -r --arg a "$blocked_id" --arg b "$sibling_id" '[.windows[] | select(.id == $a or .id == $b) | .pid] | unique | map(tostring) | join(" ")' "$spaces_dump_path")
  echo "blocked and sibling pids: $pids"
  case "$pids" in ""|*" "*) fail "the blocked and sibling windows do not share one pid: '$pids'" ;; esac
  [ "$("$jq_bin" -r --arg id "$sibling_id" '.herdr.stateByWindow[$id] // ""' "$spaces_dump_path")" = "" ] \
    || fail "debug dump's stateByWindow badges the sibling $sibling_id"
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

  # The badge in the frame: what changed in workspace 1's chip when herdr
  # went from blocked to idle, which has to sit on the blocked icon and be
  # red. The icon's own rect comes out of the status read.
  local geo sx sy sw sh icon_left icon_width diff_box dx dw red_on red_off
  read -r sx sy sw sh < <("$jq_bin" -r '.slots[0].rect | "\(.x) \(.y) \(.width) \(.height)"' "$spaces_status_one_path")
  icon_left=$(echo "$blocked" | "$jq_bin" -r .rect.x)
  icon_width=$(echo "$blocked" | "$jq_bin" -r .rect.width)
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
  if [ "$dx" -lt $((icon_left - 3)) ] || [ $((dx + dw)) -gt $((icon_left + icon_width + 4)) ]; then
    fail "the badge change spans x=$dx..$((dx + dw)), outside the blocked icon at $icon_left..$((icon_left + icon_width))"
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
  "$jq_bin" -c .preview "$spaces_status_peek_path" "$spaces_status_hover_path" "$spaces_status_moved_path" "$spaces_status_left_path"
  grep -q '^ok$' "$spaces_peek_reply_path" || fail "workspaces peek 2 did not answer ok: $(cat "$spaces_peek_reply_path")"
  "$jq_bin" -e '.preview.open and .preview.idx == 2 and .preview.windows == 2 and .preview.keyboard' "$spaces_status_peek_path" > /dev/null \
    || fail "peek 2 did not open workspace 2's preview with two windows and the keyboard: $("$jq_bin" -c .preview "$spaces_status_peek_path")"
  "$jq_bin" -e '.preview.captured == 2' "$spaces_status_peek_path" > /dev/null \
    || fail "peek 2's thumbnails are not both live window captures: $("$jq_bin" -c .preview "$spaces_status_peek_path")"
  "$jq_bin" -e '.preview.open and .preview.idx == 2 and .preview.captured == 2 and (.preview.keyboard | not)' "$spaces_status_hover_path" > /dev/null \
    || fail "a pointer parked on workspace 2's chip did not open its live preview without the keyboard: $("$jq_bin" -c .preview "$spaces_status_hover_path")"
  "$jq_bin" -e '.preview.open and .preview.idx == 2' "$spaces_status_moved_path" > /dev/null \
    || fail "the preview closed while the pointer kept moving over workspace 2's chip: $("$jq_bin" -c .preview "$spaces_status_moved_path")"

  # The window parked past the right edge: the miniature opened on the
  # output's own region over a strip wider than itself, drew that window
  # whole beyond the viewport, and a wheel notch scrolls the strip along x.
  local mini before after back
  mini=$("$jq_bin" -c .preview.miniature "$spaces_status_peek_path")
  echo "miniature at peek: $mini"
  "$jq_bin" -e '.content.width > .view.width and .scroll == .home' <<< "$mini" > /dev/null \
    || fail "the miniature did not open on the output's own region over a wider strip: $mini"
  "$jq_bin" -e '
    .scale as $k | .inset as $i
    | (.thumbs | max_by(.rect.x)) as $t
    | ($t.x + $t.width) > .view.width
      and (($t.width - ($t.rect.width * $k - 2 * $i)) | fabs) <= 2
      and (($t.height - ($t.rect.height * $k - 2 * $i)) | fabs) <= 2' <<< "$mini" > /dev/null \
    || fail "the window past the output's edge is not drawn whole beyond the viewport: $mini"
  before=$("$jq_bin" -r .preview.miniature.scroll.x "$spaces_status_peek_path")
  after=$("$jq_bin" -r .preview.miniature.scroll.x "$spaces_status_wheel_path")
  back=$("$jq_bin" -r .preview.miniature.scroll.x "$spaces_status_wheel_back_path")
  echo "miniature scroll x: peek $before, after a notch $after, after the reverse notch $back"
  [ "$after" -gt "$before" ] || fail "a wheel notch over the preview did not scroll the miniature right: $before -> $after"
  [ "$back" -lt "$after" ] || fail "the reverse wheel notch did not scroll the miniature back: $after -> $back"
  local pad pad_back
  pad=$("$jq_bin" -r .preview.miniature.scroll.x "$spaces_status_pad_path")
  pad_back=$("$jq_bin" -r .preview.miniature.scroll.x "$spaces_status_pad_back_path")
  echo "hover-opened card, horizontal axis: after a sideways notch $pad, back $pad_back"
  "$jq_bin" -e '.preview.open and .preview.idx == 2 and (.preview.keyboard | not)' "$spaces_status_pad_path" > /dev/null \
    || fail "the hover-opened preview closed under a horizontal scroll: $("$jq_bin" -c .preview "$spaces_status_pad_path")"
  [ "$pad" -gt 0 ] || fail "a horizontal axis event over the hover-opened preview did not scroll the miniature: $pad"
  [ "$pad_back" -lt "$pad" ] || fail "the reverse horizontal event did not scroll the miniature back: $pad -> $pad_back"
  [ -f "$spaces_wheel_png" ] || fail "no spaces screenshot produced at $spaces_wheel_png"
  echo "SMOKE_SPACES_WHEEL $spaces_wheel_png"

  # The card and the chip row, cropped for reading.
  local card chips
  card=$("$jq_bin" -r '.preview.rect | "\(.width)x\(.height)+\(.x)+\(.y)"' "$spaces_status_peek_path")
  chips=$("$jq_bin" -r '[.slots[].rect] | "\((map(.x + .width) | max) - (map(.x) | min) + 8)x\((map(.y + .height) | max) - (map(.y) | min) + 8)+\((map(.x) | min) - 4)+\((map(.y) | min) - 4)"' "$spaces_status_one_path")
  $convert_bin "$spaces_peek_png" -crop "$card" +repage "$spaces_crop_dir/peek-card.png" \
    || fail "could not crop the preview card at $card"
  $convert_bin "$spaces_wheel_png" -crop "$card" +repage "$spaces_crop_dir/wheel-card.png" || true
  echo "SMOKE_SPACES_WHEEL_CARD $spaces_crop_dir/wheel-card.png"
  $convert_bin "$spaces_hover_png" -crop "$card" +repage "$spaces_crop_dir/hover-card.png" || true
  $convert_bin "$spaces_blocked_png" -crop "$chips" +repage -scale 300% "$spaces_crop_dir/chips.png" \
    || fail "could not crop the chip row at $chips"
  echo "SMOKE_SPACES_PEEK_CARD $spaces_crop_dir/peek-card.png"
  echo "SMOKE_SPACES_HOVER_CARD $spaces_crop_dir/hover-card.png"
  echo "SMOKE_SPACES_CHIPS $spaces_crop_dir/chips.png"
  "$jq_bin" -e '.preview.open | not' "$spaces_status_left_path" > /dev/null \
    || fail "moving the pointer off the slot left the preview open: $("$jq_bin" -c .preview "$spaces_status_left_path")"
}
