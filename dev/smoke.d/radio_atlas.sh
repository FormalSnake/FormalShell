# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --radio-atlas opens Radio Atlas with `panel open radio` over a world cache
# the fixture writes: one station, served on loopback the way --radio serves
# its favourite, placed in the South Atlantic so no real station Radio Browser
# adds behind it sits under the same pixel. Enter on a real key plays the
# list's first station, which turns the globe from its starting pose to
# centre it: the globe's own box has to differ between the open frame and
# that one. After `radio stop`, a real pointer
# click on the globe's centre (where the playing station now sits) picks the
# station off the globe and plays it again, read back off `radio status`.
# Then dev/vpointer.py holds the button across the globe: a drag that
# stops for 250 ms before its release must leave `radio status`'s
# atlas.globe.longitude where the release left it, and the same drag let
# go while moving must coast, less than 2.5 times the drag's own turn.
# Escape closes the atlas, read back off `panel state`. Before that, the
# pointer parks on the header's close button, and the formalshell:tooltip
# layer has to be absent before and present after, the way --tooltip reads a
# panel header. The example Hyprland config has to carry a layer rule for
# formalshell:radio (this rig runs with blur off, so a frame cannot show it).
#
# The globe's centre is worked out from the panel's own layout and the
# spacing tokens (panelPadding 12, controlHeight 32, lg 8, a 16px caption
# line), since nothing over IPC reports it.
leg_radio_atlas_flag="--radio-atlas"
leg_radio_atlas_order=176
leg_radio_atlas_needs="ffmpeg wtype wlrctl convert jq python3"

radio_atlas_track_path="$shot_dir/radio-atlas-station.mp3"
radio_atlas_open_png="$shot_dir/radio-atlas-open.png"
radio_atlas_turned_png="$shot_dir/radio-atlas-turned.png"
radio_atlas_picked_png="$shot_dir/radio-atlas-picked.png"
radio_atlas_open_path="$shot_dir/radio-atlas-open.txt"
radio_atlas_state_path="$shot_dir/radio-atlas-state.txt"
radio_atlas_played_path="$shot_dir/radio-atlas-played.json"
radio_atlas_stopped_path="$shot_dir/radio-atlas-stopped.json"
radio_atlas_picked_path="$shot_dir/radio-atlas-picked.json"
radio_atlas_closed_path="$shot_dir/radio-atlas-closed.txt"
radio_atlas_globe_path="$shot_dir/radio-atlas-globe.txt"
radio_atlas_tip_before_path="$shot_dir/radio-atlas-tip-before.json"
radio_atlas_tip_after_path="$shot_dir/radio-atlas-tip-after.json"
radio_atlas_tip_png="$shot_dir/radio-atlas-tooltip.png"
radio_atlas_loop_pid_path="$shot_dir/radio-atlas-loop.pid"
radio_atlas_drag_before_path="$shot_dir/radio-atlas-drag-before.json"
radio_atlas_drag_released_path="$shot_dir/radio-atlas-drag-released.json"
radio_atlas_drag_settled_path="$shot_dir/radio-atlas-drag-settled.json"
radio_atlas_fling_released_path="$shot_dir/radio-atlas-fling-released.json"
radio_atlas_fling_settled_path="$shot_dir/radio-atlas-fling-settled.json"
radio_atlas_vpointer="$PWD/dev/vpointer.py"
# Twelve 15px steps a frame apart, about 940 px/s.
radio_atlas_steps=$(for _ in $(seq 12); do printf 'move 15 0 wait 16 '; done)
radio_atlas_name="FormalShell Atlas Radio"
radio_atlas_port=18098

leg_radio_atlas_timing() {
  leg_timing 40 70
}

leg_radio_atlas_fixture() {
  local cache_dir="$iso_home/.cache/formalshell/radio-atlas"
  mkdir -p "$cache_dir"
  local now_ms
  now_ms=$(($(date +%s) * 1000))
  cat > "$cache_dir/world.json" <<EOF
{"fetchedAt":$now_ms,"stations":[{"uuid":"smoke-atlas-1","name":"$radio_atlas_name","url":"http://127.0.0.1:$radio_atlas_port/station.mp3","homepage":"","favicon":"","country":"France","countryCode":"FR","state":"","language":"","tags":"","codec":"MP3","bitrate":128,"votes":0,"clicks":0,"latitude":-30.5,"longitude":-21.25}]}
EOF
  "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "sine=frequency=440:sample_rate=44100" -t 60 \
    -c:a libmp3lame -b:a 128k -y "$radio_atlas_track_path"
}

leg_radio_atlas_drive() {
  local script="$shot_dir/radio-atlas-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
# ffmpeg's listener takes one client and exits; the station is played twice.
# The loop closes every inherited fd above stderr first (the caller's flock
# fd among them) and its pid is recorded so cleanup can stop the respawning.
( for fd in /proc/\$BASHPID/fd/*; do n=\${fd##*/}; [ "\$n" -gt 2 ] && eval "exec \$n>&-"; done 2>/dev/null
  while true; do
  "$ffmpeg_bin" -nostdin -loglevel error -re -i "$radio_atlas_track_path" -c copy -f mp3 \
    -listen 1 "http://127.0.0.1:$radio_atlas_port/station.mp3"
done ) &
echo \$! > "$radio_atlas_loop_pid_path"
sleep 5
$ipc call panel open radio > "$radio_atlas_open_path" 2>&1
sleep 4
$ipc call panel state > "$radio_atlas_state_path" 2>&1
"$grim_bin" "$radio_atlas_open_png" > /dev/null 2>&1
"$wtype_bin" -k Return
SECONDS=0
while [ "\$SECONDS" -lt 12 ]; do
  $ipc call radio status > "$radio_atlas_played_path" 2>&1
  grep -q '"loaded":true' "$radio_atlas_played_path" && break
  sleep 1
done
sleep 1
"$grim_bin" "$radio_atlas_turned_png" > /dev/null 2>&1
$ipc call radio stop > /dev/null 2>&1
sleep 3
$ipc call radio status > "$radio_atlas_stopped_path" 2>&1
read -r out_w out_h < <($convert_bin "$radio_atlas_open_png" -format '%w %h' info:)
cw=\$(( out_w * 85 / 100 < 1180 ? out_w * 85 / 100 : 1180 ))
ch=\$(( out_h * 85 / 100 < 760 ? out_h * 85 / 100 : 760 ))
ox=\$(( (out_w - cw - 24) / 2 + 12 ))
oy=\$(( (out_h - ch - 24) / 2 + 12 ))
side=\$(( cw * 39 / 100 < 390 ? cw * 39 / 100 : 390 ))
gl=\$ox
gr=\$(( ox + cw - side - 12 - 1 - 12 ))
gt=\$(( oy + 32 + 12 + 1 + 12 ))
gb=\$(( oy + ch - 16 - 8 ))
gx=\$(( (gl + gr) / 2 ))
gy=\$(( (gt + gb) / 2 ))
echo "\$gl \$gt \$gr \$gb \$gx \$gy" > "$radio_atlas_globe_path"
"$wlrctl_bin" pointer move -4000 -4000
sleep 0.3
"$wlrctl_bin" pointer move \$gx \$gy
sleep 1
"$wlrctl_bin" pointer click left
SECONDS=0
while [ "\$SECONDS" -lt 12 ]; do
  $ipc call radio status > "$radio_atlas_picked_path" 2>&1
  grep -q '"loaded":true' "$radio_atlas_picked_path" && break
  sleep 1
done
sleep 1
"$grim_bin" "$radio_atlas_picked_png" > /dev/null 2>&1
# A held drag across the globe that stops, holds still, then lets go: read
# the pose before, just after the release and once a coast would be over.
$ipc call radio status > "$radio_atlas_drag_before_path" 2>&1
"$python3_bin" "$radio_atlas_vpointer" down $radio_atlas_steps wait 250 up
sleep 0.1
$ipc call radio status > "$radio_atlas_drag_released_path" 2>&1
sleep 1.5
$ipc call radio status > "$radio_atlas_drag_settled_path" 2>&1
# The same drag let go while still moving: it coasts, carrying only its
# own speed.
"$python3_bin" "$radio_atlas_vpointer" down $radio_atlas_steps up
$ipc call radio status > "$radio_atlas_fling_released_path" 2>&1
sleep 2.5
$ipc call radio status > "$radio_atlas_fling_settled_path" 2>&1
"$hyprctl_bin" -j layers > "$radio_atlas_tip_before_path" 2>&1
"$wlrctl_bin" pointer move -4000 -4000
sleep 0.5
"$wlrctl_bin" pointer move \$(( ox + cw - 16 )) \$(( oy + 16 ))
sleep 2
"$hyprctl_bin" -j layers > "$radio_atlas_tip_after_path" 2>&1
"$grim_bin" -c "$radio_atlas_tip_png" > /dev/null 2>&1
"$wtype_bin" -k Escape
sleep 2
$ipc call panel state > "$radio_atlas_closed_path" 2>&1
$ipc call radio stop > /dev/null 2>&1
EOF
  add_cleanup "kill \$(cat '$radio_atlas_loop_pid_path' 2>/dev/null) 2>/dev/null || true"
  add_cleanup "pkill -f 'listen 1 http://127.0.0.1:$radio_atlas_port' 2>/dev/null || true"
  add_cleanup "pkill -f 'radio-atlas-drive.sh' 2>/dev/null || true"
  hypr_exec_once "bash $script"
}

leg_radio_atlas_assert() {
  grep -q 'formalshell:radio' "$radio_atlas_tip_before_path" \
    || fail "no formalshell:radio layer in the layer dump with the atlas open"
  grep -q 'formalshell:tooltip' "$radio_atlas_tip_before_path" \
    && fail "a tooltip layer was mapped before the pointer parked on a button"
  grep -q 'formalshell:tooltip' "$radio_atlas_tip_after_path" \
    || fail "no tooltip layer after the pointer parked on the close button"
  grep -q 'namespace = "formalshell:radio"' "docs/examples/hyprland/formalshell.lua" \
    || fail "the example Hyprland config has no layer rule for formalshell:radio"
  echo "SMOKE_RADIO_ATLAS_TOOLTIP $radio_atlas_tip_png"
  grep -q "^ok$" "$radio_atlas_open_path" 2>/dev/null \
    || fail "panel open radio did not answer ok, got: $(cat "$radio_atlas_open_path" 2>/dev/null)"
  grep -q "^radio$" "$radio_atlas_state_path" 2>/dev/null \
    || fail "panel state is not radio with the atlas open, got: $(cat "$radio_atlas_state_path" 2>/dev/null)"
  cat "$radio_atlas_played_path"; echo
  grep -q '"loaded":true' "$radio_atlas_played_path" && grep -qF "\"station\":\"$radio_atlas_name\"" "$radio_atlas_played_path" \
    || fail "Enter on the list did not play the loopback station"
  grep -q '"running":false' "$radio_atlas_stopped_path" \
    || fail "radio stop left the station running: $(cat "$radio_atlas_stopped_path")"
  cat "$radio_atlas_picked_path"; echo
  grep -q '"loaded":true' "$radio_atlas_picked_path" && grep -qF "\"station\":\"$radio_atlas_name\"" "$radio_atlas_picked_path" \
    || fail "a click on the globe's centre did not pick the station ($(cat "$radio_atlas_globe_path" 2>/dev/null))"
  [ -z "$(tr -d '[:space:]' < "$radio_atlas_closed_path" 2>/dev/null)" ] \
    || fail "Escape left a panel open: $(cat "$radio_atlas_closed_path")"
  for png in "$radio_atlas_open_png" "$radio_atlas_turned_png" "$radio_atlas_picked_png"; do
    [ -s "$png" ] || fail "no frame at $png"
  done
  local gl gt gr gb box diff
  read -r gl gt gr gb _ _ < "$radio_atlas_globe_path"
  box="$((gr - gl))x$((gb - gt))+$gl+$gt"
  $convert_bin "$radio_atlas_open_png" -crop "$box" +repage -strip "$shot_dir/radio-atlas-globe-open.png" > /dev/null 2>&1
  $convert_bin "$radio_atlas_turned_png" -crop "$box" +repage -strip "$shot_dir/radio-atlas-globe-turned.png" > /dev/null 2>&1
  diff=$($convert_bin "$shot_dir/radio-atlas-globe-open.png" "$shot_dir/radio-atlas-globe-turned.png" -compose difference -composite -colorspace gray -format '%[fx:mean*100]' info: 2>/dev/null)
  echo "globe box $box, mean difference after the turn: ${diff}%"
  awk -v d="${diff:-0}" 'BEGIN { exit !(d > 1.0) }' || fail "the globe did not turn to the station (mean difference ${diff}%)"
  local before released settled fling_released fling_settled coasting
  read -r before released settled fling_released fling_settled <<< "$(for f in "$radio_atlas_drag_before_path" "$radio_atlas_drag_released_path" \
    "$radio_atlas_drag_settled_path" "$radio_atlas_fling_released_path" "$radio_atlas_fling_settled_path"; do
    "$jq_bin" -r '.atlas.globe.longitude // "none"' "$f" 2>/dev/null || echo none
  done | tr '\n' ' ')"
  coasting=$("$jq_bin" -r '.atlas.globe.coasting' "$radio_atlas_drag_settled_path" 2>/dev/null)
  echo "drag longitudes: before $before, released $released, settled $settled; fling released $fling_released, settled $fling_settled"
  awk -v a="$before" -v b="$released" 'function d(x, y) { x = y - x; while (x > 180) x -= 360; while (x < -180) x += 360; return x < 0 ? -x : x }
    BEGIN { exit !(a != "none" && b != "none" && d(a, b) > 1) }' \
    || fail "the held drag did not turn the globe (longitude $before to $released)"
  [ "$released" = "$settled" ] && [ "$coasting" = "false" ] \
    || fail "a drag that stopped before its release coasted on (longitude $released to $settled, coasting $coasting)"
  awk -v a="$before" -v b="$released" -v c="$fling_released" -v e="$fling_settled" \
    'function d(x, y) { x = y - x; while (x > 180) x -= 360; while (x < -180) x += 360; return x < 0 ? -x : x }
    BEGIN { drag = d(a, b); coast = d(c, e); printf "drag turned %.2f deg, the moving release coasted %.2f deg after it\n", drag, coast
      exit !(coast > 0 && coast < drag * 2.5) }' \
    || fail "a release while moving coasted out of proportion to the drag (or not at all)"
  echo "SMOKE_RADIO_ATLAS_OPEN $radio_atlas_open_png"
  echo "SMOKE_RADIO_ATLAS_TURNED $radio_atlas_turned_png"
  echo "SMOKE_RADIO_ATLAS_PICKED $radio_atlas_picked_png"
}
