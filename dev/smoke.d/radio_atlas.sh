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
# Escape closes the atlas, read back off `panel state`.
#
# The globe's centre is worked out from RadioAtlas.qml's own layout and the
# spacing tokens (panelPadding 12, controlHeight 32, lg 8, a 16px caption
# line), since nothing over IPC reports it.
leg_radio_atlas_flag="--radio-atlas"
leg_radio_atlas_order=176
leg_radio_atlas_needs="ffmpeg wtype wlrctl convert"

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
( while true; do
  "$ffmpeg_bin" -nostdin -loglevel error -re -i "$radio_atlas_track_path" -c copy -f mp3 \
    -listen 1 "http://127.0.0.1:$radio_atlas_port/station.mp3"
done ) &
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
"$wtype_bin" -k Escape
sleep 2
$ipc call panel state > "$radio_atlas_closed_path" 2>&1
$ipc call radio stop > /dev/null 2>&1
EOF
  add_cleanup "pkill -f 'listen 1 http://127.0.0.1:$radio_atlas_port' 2>/dev/null || true"
  add_cleanup "pkill -f 'radio-atlas-drive.sh' 2>/dev/null || true"
  hypr_exec_once "bash $script"
}

leg_radio_atlas_assert() {
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
  echo "SMOKE_RADIO_ATLAS_OPEN $radio_atlas_open_png"
  echo "SMOKE_RADIO_ATLAS_TURNED $radio_atlas_turned_png"
  echo "SMOKE_RADIO_ATLAS_PICKED $radio_atlas_picked_png"
}
