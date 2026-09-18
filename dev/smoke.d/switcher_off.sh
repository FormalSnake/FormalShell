# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --switcher-off: the other half of --switcher (M60 T6). The switcher is a
# habit, and a preset without it never instantiates the surface at all, so
# the claim here is that the IPC target says so rather than accepting a call
# and doing nothing. A leg of its own because a preset is read at startup and
# one session carries one settings.json: the shipped default (metamorphosis)
# is what this runs on, which is why it pins no fixture.
#
# All five verbs, not just one: `state` returning the error string is what a
# rig or a keybind sees, and `commit` is bound to the release of a modifier
# on a pantheon host, so on any other preset it is the verb that would fire
# most often of all.
leg_switcher_off_flag="--switcher-off"
leg_switcher_off_order=103
leg_switcher_off_needs="jq"

switcher_off_dir="$shot_dir/switcher-off"
switcher_off_png="$shot_dir/switcher-off.png"
switcher_off_layers="$shot_dir/switcher-off-layers.json"

leg_switcher_off_validate() {
  local other
  for other in pantheon retro; do
    if leg_on "$other"; then
      echo "usage: --switcher-off reads the target under the shipped preset, so it cannot combine with --${other}" >&2
      exit 1
    fi
  done
}

leg_switcher_off_timing() {
  leg_timing 16 50
}

leg_switcher_off_drive() {
  local script="$shot_dir/switcher-off-drive.sh"
  write_script "$script" <<EOS
#!/usr/bin/env bash
mkdir -p "$switcher_off_dir"
sleep 5
for verb in next prev commit cancel state; do
  "$qs_bin" ipc -p "$shell_path" call switcher "\$verb" > "$switcher_off_dir/\$verb.txt" 2>&1
done
sleep 1
"$hyprctl_bin" -j layers > "$switcher_off_layers" 2>&1
"$grim_bin" "$switcher_off_png" > /dev/null 2>&1
EOS
  echo "exec-once = bash $script"
}

leg_switcher_off_assert() {
  local verb reply want="error: switcher is off under this theme"
  for verb in next prev commit cancel state; do
    local path="$switcher_off_dir/$verb.txt"
    [ -s "$path" ] || fail "no reply produced for switcher $verb at $path"
    reply=$(tr -d '\r\n' < "$path")
    echo "switcher $verb: $reply"
    [ "$reply" = "$want" ] || fail "switcher $verb answered '$reply', not '$want'"
  done

  # And nothing was drawn for it: a surface that was never instantiated
  # carries no layer surface to find.
  local mapped
  [ -s "$switcher_off_layers" ] || fail "no layer dump produced at $switcher_off_layers"
  mapped=$("$jq_bin" -r '[.[] | .levels[] | .[] | select(.namespace == "formalshell:switcher")] | length' \
    "$switcher_off_layers" 2>/dev/null)
  echo "layers: formalshell:switcher=$mapped"
  [ "${mapped:-0}" -eq 0 ] || fail "a switcher surface is mapped under a theme whose habit is off ($mapped)"

  echo "SMOKE_SWITCHER_OFF ok five verbs refused"
  echo "SMOKE_SWITCHER_OFF_FRAME $switcher_off_png"
}
