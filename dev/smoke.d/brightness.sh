# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --brightness: bursts of brightness steps against PATH-shimmed `ddcutil` and
# `brightnessctl`, each one asserted to move one way only. The rig has no
# backlight and no DDC monitor, so the shims stand in for g815's pair: an
# internal backlight and an HDMI-A-1 monitor on I2C bus 12, both starting at
# 30%.
#
# The ddcutil shim behaves like the real one where it matters: every getvcp
# and setvcp takes the bus's flock, waits for it the way ddcutil retries it
# (and gives up after 2s, logging a dropped write), and holds it for 100 to
# 300ms, a real monitor's setvcp. A call that found the lock held logs an
# overlap. The brightnessctl shim answers each read after 20 to 150ms, the
# spread a loaded laptop puts on a spawn, and applies writes under a lock in
# whatever order they reach it.
#
# Three bursts, each eight steps 40ms apart (a held key's repeat):
#  1. the keybind path (`brightnessctl set 5%+ && osd brightness`, each one
#     in the background as Hyprland spawns them), `osd state`'s brightness
#     sampled every 20ms: never a step back, and 70 at the end.
#  2. Right eight times on the display panel's HDMI-A-1 row: the monitor's
#     setvcp values in the order they landed only ever rise, end at 70, and
#     no write overlapped another or was dropped.
#  3. Left eight times on the panel's backlight row, from 70: the values the
#     backlight was set to only ever fall, and end at 30.
#  4. Two headless outputs named HDMI-A-1 and eDP-1, the shim's monitor
#     found by the detection their arrival starts, then `display
#     brightnessStep` the way the keys now call it, each call in the
#     background: -5 eight times focused on HDMI-A-1 (70 to 30 over DDC),
#     then +5 eight times focused on eDP-1 (30 to 70 on the backlight). The
#     first call of each burst is followed by `osd state`, which has to show
#     the value asked for already, and the pill's layer sits on the focused
#     output (the rig's headless outputs grab as the same picture, so the
#     layer list is the proof); the samples never step back and end on
#     the target, the device's own writes only move one way and end there,
#     and the eight DDC steps reach the monitor in fewer than eight setvcp
#     calls, none overlapping another.
#
# The shell's wrapper puts its own brightnessctl and ddcutil first on PATH,
# so this leg starts the wrapped binary itself, with the wrapper's own
# environment read out of the makeCWrapper call it embeds and the shims in
# front of its PATH.
leg_brightness_flag="--brightness"
leg_brightness_order=217
leg_brightness_needs="wtype jq"

brightness_shim_dir="$shot_dir/brightness-shim"
brightness_dev_dir="$shot_dir/brightness-dev"
brightness_ddc_log="$shot_dir/brightness-ddc.log"
brightness_bl_log="$shot_dir/brightness-backlight.log"
brightness_osd_samples="$shot_dir/brightness-osd.txt"
brightness_stops_path="$shot_dir/brightness-stops.txt"
brightness_panel_png="$shot_dir/brightness-panel.png"
brightness_step_ddc="$shot_dir/brightness-step-ddc.txt"
brightness_step_bl="$shot_dir/brightness-step-backlight.txt"
brightness_step_first="$shot_dir/brightness-step-first.txt"
brightness_step_monitors="$shot_dir/brightness-step-monitors"
brightness_step_layers="$shot_dir/brightness-step-layers"

leg_brightness_fixture() {
  mkdir -p "$brightness_shim_dir" "$brightness_dev_dir"
  echo 30 > "$brightness_dev_dir/ddc"
  echo 30 > "$brightness_dev_dir/backlight"
  : > "$brightness_ddc_log"
  : > "$brightness_bl_log"

  cat > "$brightness_shim_dir/ddcutil" <<EOF
#!/usr/bin/env bash
d="$brightness_dev_dir"
log="$brightness_ddc_log"
case " \$* " in
  *" detect "*)
    printf 'Display 1\n   I2C bus:  /dev/i2c-12\n   DRM connector:           card1-HDMI-A-1\n   Monitor:                 AUS:PA278CGV:shim\n\n'
    exit 0 ;;
esac
exec 9> "\$d/i2c-12.lock"
if ! flock -n 9; then
  echo "overlap \$*" >> "\$log"
  flock -w 2 9 || { echo "dropped \$*" >> "\$log"; exit 1; }
fi
sleep "\$(printf '0.%03d' \$((100 + RANDOM % 200)))"
case " \$* " in
  *" getvcp 10 "*) echo "VCP 10 C \$(cat "\$d/ddc") 100" ;;
  *" setvcp 10 "*)
    v="\${*: -1}"
    echo "\$v" > "\$d/ddc"
    echo "set \$v" >> "\$log" ;;
  *) exit 1 ;;
esac
EOF

  cat > "$brightness_shim_dir/brightnessctl" <<EOF
#!/usr/bin/env bash
d="$brightness_dev_dir"
log="$brightness_bl_log"
sleep "\$(printf '0.%03d' \$((20 + RANDOM % 130)))"
machine=0 arg=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -m) machine=1 ;;
    -d|-c) shift ;;
    set) arg="\$2"; shift ;;
  esac
  shift
done
exec 9> "\$d/backlight.lock"
flock 9
v=\$(cat "\$d/backlight")
case "\$arg" in
  "") ;;
  *%+) v=\$((v + \${arg%%%+})); echo "step \$((v > 100 ? 100 : v))" >> "\$log" ;;
  *%-) v=\$((v - \${arg%%%-})); echo "step \$((v < 0 ? 0 : v))" >> "\$log" ;;
  *%) v=\${arg%%%}; echo "set \$v" >> "\$log" ;;
esac
v=\$((v > 100 ? 100 : v < 0 ? 0 : v))
echo "\$v" > "\$d/backlight"
[ "\$machine" = 1 ] && echo "shim_backlight,backlight,\$v,\$v%,100"
exit 0
EOF
  chmod +x "$brightness_shim_dir/ddcutil" "$brightness_shim_dir/brightnessctl"
}

leg_brightness_shell() {
  local doc wrapped env_lines
  doc=$(grep -a -A20 "^makeCWrapper '" "$shell_bin")
  wrapped=$(sed -n "s/^makeCWrapper '\([^']*\)'.*/\1/p" <<< "$doc" | head -n1)
  [ -x "$wrapped" ] || fail "cannot read the wrapped binary out of $shell_bin"
  env_lines=$(sed -n \
    -e "s/^ *--set-default '\([A-Z_]*\)' '\([^']*\)'.*/export \1=\"\${\1:-\2}\"/p" \
    -e "s/^ *--prefix 'PATH' ':' '\([^']*\)'.*/export PATH=\"\1:\$PATH\"/p" \
    -e "s/^ *--suffix 'PATH' ':' '\([^']*\)'.*/export PATH=\"\$PATH:\1\"/p" <<< "$doc")
  write_script "$1" <<EOF
#!/usr/bin/env bash
export LIBGL_ALWAYS_SOFTWARE=1
$env_lines
export PATH="$brightness_shim_dir:\$PATH"
$wayland_debug_line
$shell_prefix "$wrapped" > "$shell_log_path" 2>&1 &
echo \$! > "$shot_dir/shell.pid"
wait
EOF
}

leg_brightness_timing() {
  leg_timing 40 80
}

leg_brightness_drive() {
  local script="$shot_dir/brightness-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
call() { $ipc call "\$@"; }
sleep 4
# 1. The keybind path, sampled.
( end=\$((SECONDS + 4)); while [ \$SECONDS -lt \$end ]; do
    call osd state | "$jq_bin" -r '.brightness // "none"' 2>/dev/null
    sleep 0.02
  done ) > "$brightness_osd_samples" &
sampler=\$!
sleep 0.3
for _ in 1 2 3 4 5 6 7 8; do
  ( "$brightness_shim_dir/brightnessctl" -q set 5%+ && call osd brightness > /dev/null 2>&1 ) &
  sleep 0.04
done
wait \$sampler
# 2 and 3. The panel's cursor walks one stop per output, then the backlight
# row, then HDMI-A-1; the first Down only lands it on the first stop.
outputs=\$("$hyprctl_bin" -j monitors all | "$jq_bin" length)
echo "\$outputs" > "$brightness_stops_path"
call panel open display > /dev/null 2>&1
# Past the panel's DDC detection and its first getvcp.
sleep 3
for _ in \$(seq \$((outputs + 2))); do "$wtype_bin" -k Down; sleep 0.1; done
for _ in 1 2 3 4 5 6 7 8; do "$wtype_bin" -k Right; sleep 0.04; done
sleep 4
"$grim_bin" "$brightness_panel_png" > /dev/null 2>&1
"$wtype_bin" -k Up
sleep 0.2
for _ in 1 2 3 4 5 6 7 8; do "$wtype_bin" -k Left; sleep 0.04; done
sleep 3
call panel close > /dev/null 2>&1
sleep 1
# 4. The step verb, one burst per device kind.
"$hyprctl_bin" output create headless HDMI-A-1 > /dev/null 2>&1
"$hyprctl_bin" output create headless eDP-1 > /dev/null 2>&1
sleep 3
step_burst() {
  local output=\$1 delta=\$2 samples=\$3 sampler
  "$hyprctl_bin" dispatch "hl.dsp.focus({ monitor = '\$output' })" > /dev/null 2>&1
  sleep 0.5
  "$hyprctl_bin" -j monitors all > "$brightness_step_monitors-\$output.json"
  echo "--- \$output" >> "$brightness_ddc_log"
  echo "--- \$output" >> "$brightness_bl_log"
  ( end=\$((SECONDS + 3)); while [ \$SECONDS -lt \$end ]; do
      call osd state | "$jq_bin" -r '.brightness // "none"' 2>/dev/null
      sleep 0.02
    done ) > "\$samples" &
  sampler=\$!
  sleep 0.2
  call display brightnessStep "\$delta" >> "$brightness_step_first"
  echo "\$output \$(call osd state | "$jq_bin" -r .brightness)" >> "$brightness_step_first"
  for _ in 1 2 3 4 5 6 7; do
    sleep 0.04
    call display brightnessStep "\$delta" > /dev/null 2>&1 &
  done
  # Inside the pill's hold, the burst's writes done.
  sleep 0.8
  "$hyprctl_bin" -j layers > "$brightness_step_layers-\$output.json"
  wait \$sampler
}
step_burst HDMI-A-1 -5 "$brightness_step_ddc"
sleep 2
step_burst eDP-1 5 "$brightness_step_bl"
sleep 2
"$hyprctl_bin" output remove eDP-1 > /dev/null 2>&1
"$hyprctl_bin" output remove HDMI-A-1 > /dev/null 2>&1
EOF
  hypr_exec_once "bash $script"
}

# Prints the first pair of numbers in stdin that steps against $1 (up|down).
brightness_backstep() {
  awk -v dir="$1" '$1 ~ /^[0-9.]+$/ { if (seen && ((dir == "up" && $1 < last) || (dir == "down" && $1 > last))) { print last " then " $1; exit } last = $1; seen = 1 }'
}

leg_brightness_assert() {
  local back last
  [ -s "$brightness_osd_samples" ] || fail "no osd state samples"
  echo "SMOKE_BRIGHTNESS_OSD $brightness_osd_samples"
  echo "SMOKE_BRIGHTNESS_DDC $brightness_ddc_log"
  echo "SMOKE_BRIGHTNESS_BACKLIGHT $brightness_bl_log"
  [ -f "$brightness_panel_png" ] && echo "SMOKE_BRIGHTNESS_PANEL $brightness_panel_png"
  echo "osd samples: $(tr '\n' ' ' < "$brightness_osd_samples")"
  echo "ddc log: $(tr '\n' ' ' < "$brightness_ddc_log")"
  echo "backlight log: $(tr '\n' ' ' < "$brightness_bl_log")"

  grep -q 'none' "$brightness_osd_samples" && fail "osd state carries no brightness"
  back=$(brightness_backstep up < "$brightness_osd_samples")
  [ -z "$back" ] || fail "the OSD stepped back during the key burst: $back"
  last=$(tail -n1 "$brightness_osd_samples")
  [ "$last" = 70 ] || fail "the OSD ended the key burst on $last, not 70"
  back=$(grep '^step ' "$brightness_bl_log" | cut -d' ' -f2 | brightness_backstep up)
  [ -z "$back" ] || fail "the backlight itself stepped back during the key burst: $back"

  grep -E '^(overlap|dropped) .*setvcp' "$brightness_ddc_log" && fail "a setvcp ran while another held the bus"
  back=$(brightness_panel_sets "$brightness_ddc_log" | brightness_backstep up)
  [ -z "$back" ] || fail "HDMI-A-1 stepped back during the panel burst: $back"
  last=$(brightness_panel_sets "$brightness_ddc_log" | tail -n1)
  [ "$last" = 70 ] || fail "HDMI-A-1 ended the panel burst on ${last:-nothing}, not 70"

  back=$(brightness_panel_sets "$brightness_bl_log" | brightness_backstep down)
  [ -z "$back" ] || fail "the backlight stepped back up during the panel burst: $back"
  last=$(brightness_panel_sets "$brightness_bl_log" | tail -n1)
  [ "$last" = 30 ] || fail "the backlight ended the panel burst on ${last:-nothing}, not 30"

  brightness_step_assert
}

# The values a shim log set before the first step burst marker.
brightness_panel_sets() {
  sed '/^--- /,$d' "$1" | grep '^set ' | cut -d' ' -f2
}

# The values a shim log set after the step burst marker for $2.
brightness_after() {
  sed -n "/^--- $2\$/,/^--- /p" "$1" | grep '^set ' | cut -d' ' -f2
}

brightness_step_assert() {
  local back last writes o
  [ -s "$brightness_step_ddc" ] && [ -s "$brightness_step_bl" ] || fail "no step burst samples"
  echo "SMOKE_BRIGHTNESS_STEP_FIRST $brightness_step_first"
  echo "step first calls: $(tr '\n' ' ' < "$brightness_step_first")"
  echo "step ddc samples: $(tr '\n' ' ' < "$brightness_step_ddc")"
  echo "step backlight samples: $(tr '\n' ' ' < "$brightness_step_bl")"
  for o in HDMI-A-1 eDP-1; do
    "$jq_bin" -e --arg o "$o" '.[] | select(.name == $o and .focused)' "$brightness_step_monitors-$o.json" > /dev/null \
      || fail "$o was not the focused output for its burst"
    "$jq_bin" -e --arg o "$o" '.[$o].levels[][]? | select(.namespace == "formalshell:osd")' "$brightness_step_layers-$o.json" > /dev/null \
      || fail "the OSD was not on $o during its burst"
  done
  [ "$(grep -c '^ok$' "$brightness_step_first")" = 2 ] || fail "brightnessStep did not answer ok: $(cat "$brightness_step_first")"
  grep -qx 'HDMI-A-1 65' "$brightness_step_first" || fail "the OSD did not show 65 right after the first DDC step"
  grep -qx 'eDP-1 35' "$brightness_step_first" || fail "the OSD did not show 35 right after the first backlight step"

  back=$(brightness_backstep down < "$brightness_step_ddc")
  [ -z "$back" ] || fail "the OSD stepped back up during the DDC step burst: $back"
  last=$(tail -n1 "$brightness_step_ddc")
  [ "$last" = 30 ] || fail "the OSD ended the DDC step burst on $last, not 30"
  back=$(brightness_after "$brightness_ddc_log" HDMI-A-1 | brightness_backstep down)
  [ -z "$back" ] || fail "HDMI-A-1 stepped back up during the step burst: $back"
  last=$(brightness_after "$brightness_ddc_log" HDMI-A-1 | tail -n1)
  [ "$last" = 30 ] || fail "HDMI-A-1 ended the step burst on ${last:-nothing}, not 30"
  writes=$(brightness_after "$brightness_ddc_log" HDMI-A-1 | wc -l)
  echo "step burst: 8 DDC steps in $writes setvcp calls"
  [ "$writes" -lt 8 ] || fail "the DDC step burst was not coalesced: $writes setvcp calls for 8 steps"

  back=$(brightness_backstep up < "$brightness_step_bl")
  [ -z "$back" ] || fail "the OSD stepped back during the backlight step burst: $back"
  last=$(tail -n1 "$brightness_step_bl")
  [ "$last" = 70 ] || fail "the OSD ended the backlight step burst on $last, not 70"
  back=$(brightness_after "$brightness_bl_log" eDP-1 | brightness_backstep up)
  [ -z "$back" ] || fail "the backlight stepped back during the step burst: $back"
  last=$(brightness_after "$brightness_bl_log" eDP-1 | tail -n1)
  [ "$last" = 70 ] || fail "the backlight ended the step burst on ${last:-nothing}, not 70"
  echo "step burst: 8 backlight steps in $(brightness_after "$brightness_bl_log" eDP-1 | wc -l) writes"
}
