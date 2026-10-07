# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --motion-art proves the animated album cover with no
# network: `media.appleMusicArt` on, a track tagged with an artist and album
# whose motion art is already in the cache the lookup would have filled
# (`$XDG_CACHE_HOME/formalshell/applemusic-art/<key>.mp4`), so the decode is
# the only thing under test. That mp4 alternates flat red and flat blue every
# half second; the track's own static art is flat green, so which picture the
# cover slot is drawing is read off three colour counts.
#
#   playing  frames taken while the media panel is open carry red in some and
#            blue in others: the cover is moving, not the static art, and an
#            ffmpeg child is decoding it.
#   paused   after `media playPause`, two frames apart carry the same counts
#            and one of red or blue: the held frame, not the static art.
#   closed   with the panel shut no decoder is left running.
leg_motion_art_flag="--motion-art"
leg_motion_art_order=36
leg_motion_art_needs="mpv ffmpeg convert"

motion_art_artist="FormalShell Motion Artist"
motion_art_album="Motion Album"
motion_art_key="formalshell-motion-artist-motion-album"
motion_art_dir="$iso_home/.cache/formalshell/applemusic-art"
motion_art_track_path="$shot_dir/motion-art-track.flac"
motion_art_cover_path="$shot_dir/motion-art-cover.png"
motion_art_frames=8
motion_art_pgrep_open_path="$shot_dir/motion-art-pgrep-open.txt"
motion_art_pgrep_closed_path="$shot_dir/motion-art-pgrep-closed.txt"

leg_motion_art_timing() {
  leg_timing 26 60
}

leg_motion_art_fixture() {
  settings_fragment ', "media": {"appleMusicArt": true}'
  mkdir -p "$motion_art_dir"
  "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "nullsrc=s=128x128:r=25:d=2" \
    -vf "geq=r='if(lt(mod(T,1),0.5),255,0)':g=0:b='if(lt(mod(T,1),0.5),0,255)',format=yuv420p" \
    -c:v mpeg4 -q:v 2 -y "$motion_art_dir/$motion_art_key.mp4"
  $convert_bin -size 64x64 "xc:#00C000" "$motion_art_cover_path"
  "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" \
    -i "$motion_art_cover_path" -map 0:a -map 1:0 -c:v png -disposition:v attached_pic -t 60 \
    -metadata "title=Motion" -metadata "artist=$motion_art_artist" -metadata "album=$motion_art_album" \
    -c:a flac -y "$motion_art_track_path"
}

leg_motion_art_drive() {
  local play="$shot_dir/motion-art-play.sh" drive="$shot_dir/motion-art-drive.sh"
  write_script "$play" <<EOF
#!/usr/bin/env bash
sleep 2
exec "$mpv_bin" --no-video --really-quiet --loop-file=inf "$motion_art_track_path"
EOF
  write_script "$drive" <<EOF
#!/usr/bin/env bash
call() { $ipc call "\$@"; }
sleep 5
call panel open media > /dev/null 2>&1
sleep 4
for i in \$(seq 1 $motion_art_frames); do
  "$grim_bin" "$shot_dir/motion-art-play-\$i.png" > /dev/null 2>&1
  sleep 0.15
done
pgrep -fc 'applemusic-art' > "$motion_art_pgrep_open_path"
call media playPause > /dev/null 2>&1
sleep 1.5
"$grim_bin" "$shot_dir/motion-art-paused-1.png" > /dev/null 2>&1
sleep 0.8
"$grim_bin" "$shot_dir/motion-art-paused-2.png" > /dev/null 2>&1
call panel close > /dev/null 2>&1
sleep 1.5
pgrep -fc 'applemusic-art' > "$motion_art_pgrep_closed_path"
EOF
  hypr_exec_once "bash $play"
  hypr_exec_once "bash $drive"
}

# Pixels within 20% of one flat colour, over the whole frame. White ones
# (every label on screen) count toward each, so only differences between
# the three counts mean anything.
motion_art_count() {
  $convert_bin "$1" -alpha off -fuzz 20% -fill white -opaque "$2" -fill black +opaque white \
    -format '%[fx:round(mean*w*h)]' info: 2>/dev/null
}

motion_art_counts() {
  echo "$(motion_art_count "$1" '#FF0000') $(motion_art_count "$1" '#0000FF') $(motion_art_count "$1" '#00C000')"
}

leg_motion_art_assert() {
  local i f r b g reds=0 blues=0 trail=""
  for i in $(seq 1 $motion_art_frames); do
    f="$shot_dir/motion-art-play-$i.png"
    [ -f "$f" ] || fail "no screenshot produced at $f"
    read -r r b g <<< "$(motion_art_counts "$f")"
    trail+=" $r/$b/$g"
    [ $((r - b)) -gt 4000 ] && reds=$((reds + 1))
    [ $((b - r)) -gt 4000 ] && blues=$((blues + 1))
  done
  echo "SMOKE_MOTION_ART_PLAY_FRAME $shot_dir/motion-art-play-1.png"
  echo "SMOKE_MOTION_ART_PLAYING red/blue/green$trail"
  [ "$reds" -gt 0 ] && [ "$blues" -gt 0 ] \
    || fail "the cover did not move between red and blue frames while playing (red/blue/green$trail)"
  [ "$(cat "$motion_art_pgrep_open_path" 2>/dev/null)" -ge 1 ] || fail "no decoder running while the panel showed the cover"

  local p1 p2
  p1=$(motion_art_counts "$shot_dir/motion-art-paused-1.png")
  p2=$(motion_art_counts "$shot_dir/motion-art-paused-2.png")
  echo "SMOKE_MOTION_ART_PAUSED $p1 | $p2"
  echo "SMOKE_MOTION_ART_PAUSED_FRAME $shot_dir/motion-art-paused-2.png"
  [ "$p1" = "$p2" ] || fail "the cover kept moving after the track paused ($p1 then $p2)"
  read -r r b g <<< "$p2"
  [ $((r - g)) -gt 4000 ] || [ $((b - g)) -gt 4000 ] || fail "the paused cover fell back to the static art ($p2)"

  local left
  left=$(cat "$motion_art_pgrep_closed_path" 2>/dev/null)
  echo "SMOKE_MOTION_ART_CLOSED decoders=$left"
  [ "${left:-1}" -eq 0 ] || fail "a decoder was still running with the panel shut ($left)"
}
