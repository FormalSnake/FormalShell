# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, iso_home, the *_bin paths and fail()
# --lyrics: two real MPRIS players (media.sh's own idiom, reused rather than
# rerun alongside --media), each with its own generated track, so the leg
# does not depend on --media running in the same session. The cache key for
# each track is worked out in shell the same way Lyrics.cacheKey does it
# (shell/Lyrics/model.js), off the tags the leg itself set and the duration
# `media status` reports back for that player, so a mismatch there is the
# assert failing rather than a silent miss. A word-timed LRC is seeded under
# the first track's key BEFORE the panel opens (D2: a cache hit costs one
# `cat`, never a real lrclib request), and an empty `.none` marker under the
# second's, reproducing the seven-day-fresh miss path with no network at
# all.
#
# The claim: `media lyrics` reaches `synced`, `source: "cache"`, `words:
# true` (the fixture LRC carries inline word stamps) and its own `index`
# moves with playback; switching the active player to the untimed track
# reaches `none`; the panel itself is visibly narrower with no lyrics pane
# to draw beside the now-playing column (M55 A1: `popupWidthMenuSplit`
# synced, `popupWidthWide` once it drops to `none`), measured as a
# pixel-diff rect against a bare frame taken before either open
# (panel_emerge.sh's own trick), since neither `panel state` nor `debug
# dump` carries panel geometry.
leg_lyrics_flag="--lyrics"
leg_lyrics_order=175
leg_lyrics_needs="mpv ffmpeg convert jq"

lyrics_track1_path="$shot_dir/lyrics-track1.flac"
lyrics_track2_path="$shot_dir/lyrics-track2.flac"
lyrics_pid1_path="$shot_dir/lyrics-mpv1.pid"
lyrics_pid2_path="$shot_dir/lyrics-mpv2.pid"
lyrics_status1_path="$shot_dir/lyrics-status1.json"
lyrics_status2_path="$shot_dir/lyrics-status2.json"
lyrics_key1_path="$shot_dir/lyrics-key1.txt"
lyrics_key2_path="$shot_dir/lyrics-key2.txt"
lyrics_id2_path="$shot_dir/lyrics-id2.txt"
lyrics_bare_path="$shot_dir/lyrics-bare.png"
lyrics_synced_png_path="$shot_dir/lyrics-synced.png"
lyrics_none_png_path="$shot_dir/lyrics-none.png"
lyrics_status_synced_path="$shot_dir/lyrics-status-synced.json"
lyrics_status_later_path="$shot_dir/lyrics-status-later.json"
lyrics_status_none_path="$shot_dir/lyrics-status-none.json"
lyrics_panel_synced_json_path="$shot_dir/lyrics-panel-synced.json"
lyrics_panel_none_json_path="$shot_dir/lyrics-panel-none.json"
lyrics_lib_path="$shot_dir/lyrics-lib.sh"

lyrics_track1_title="FormalShell Lyrics Smoke Track"
lyrics_track1_artist="FormalShell Lyrics Artist"
lyrics_track1_album="FormalShell Lyrics Album"
lyrics_track2_title="FormalShell Lyrics Miss Track"
lyrics_track2_artist="FormalShell Lyrics Artist Two"
lyrics_track2_album="FormalShell Lyrics Album Two"

leg_lyrics_timing() {
  # Two players staggered to keep both MPRIS registrations unambiguous
  # (media.sh's own reasoning), a synced poll, a 3s gap, then a select and a
  # none poll: worst case lands ~70s in. Both tracks are generated well past
  # that (80s/70s): mpv quits and drops off MPRIS entirely once a track
  # ends, which reads as an empty title/artist (LyricsService.state stuck
  # on "idle") rather than as any lyrics failure of its own.
  leg_timing 75 100
}

leg_lyrics_fixture() {
  "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 80 \
    -metadata "title=$lyrics_track1_title" -metadata "artist=$lyrics_track1_artist" \
    -metadata "album=$lyrics_track1_album" -c:a flac -y "$lyrics_track1_path"
  "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 70 \
    -metadata "title=$lyrics_track2_title" -metadata "artist=$lyrics_track2_artist" \
    -metadata "album=$lyrics_track2_album" -c:a flac -y "$lyrics_track2_path"

  # Mirrors Lyrics.cacheKey (shell/Lyrics/model.js) exactly: artist, title,
  # album joined with spaces, lowercased, every run of non-alphanumerics
  # collapsed to one "-", the edges stripped, the rounded duration appended.
  write_script "$lyrics_lib_path" <<'EOF'
#!/usr/bin/env bash
lyrics_cache_key() {
  local artist="$1" title="$2" album="$3" duration="$4"
  local raw lower slug seconds
  raw="$artist $title $album"
  lower=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  slug=$(printf '%s' "$lower" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  seconds=$(awk -v v="$duration" 'BEGIN { if (v < 0) v = 0; printf "%d", (v - int(v) >= 0.5) ? int(v) + 1 : int(v) }')
  printf '%s-%s' "$slug" "$seconds"
}
EOF
}

leg_lyrics_drive() {
  local play1_script="$shot_dir/lyrics-play1.sh"
  local key1_script="$shot_dir/lyrics-key1.sh"
  local play2_script="$shot_dir/lyrics-play2.sh"
  local key2_script="$shot_dir/lyrics-key2.sh"
  local open_script="$shot_dir/lyrics-open.sh"
  local switch_script="$shot_dir/lyrics-switch.sh"
  local kill_script="$shot_dir/lyrics-kill.sh"
  local cache_dir="\$HOME/.cache/formalshell/lyrics"

  write_script "$play1_script" <<EOF
#!/usr/bin/env bash
sleep 2
echo \$\$ > "$lyrics_pid1_path"
exec "$mpv_bin" --no-video --really-quiet "$lyrics_track1_path"
EOF

  # A word-timed LRC over the first 25s (spec D5/D9, plan Task 6): a leading
  # [ar:...] metadata line (skipped, not a stamp), a first cue at 6s so the
  # panel opens on an interlude row, three word-stamped lines and one line
  # with two leading time stamps (a shared refrain repeated at 15s and 23s,
  # kopuz's merge case), nine timed entries in total.
  write_script "$key1_script" <<EOF
#!/usr/bin/env bash
. "$lyrics_lib_path"
sleep 6
SECONDS=0
while [ "\$SECONDS" -lt 8 ]; do
  "$qs_bin" ipc -p "$shell_path" call media status > "$lyrics_status1_path" 2>&1
  grep -qF "\"title\":\"$lyrics_track1_title\"" "$lyrics_status1_path" && break
  sleep 1
done
duration=\$("$jq_bin" -r '.length // 0' "$lyrics_status1_path" 2>/dev/null)
key1=\$(lyrics_cache_key "$lyrics_track1_artist" "$lyrics_track1_title" "$lyrics_track1_album" "\${duration:-0}")
echo "\$key1" > "$lyrics_key1_path"
mkdir -p "$cache_dir"
cat > "$cache_dir/\$key1.lrc" <<'LRC'
[ar:FormalShell Lyrics Artist]
[00:06.00]<00:06.00>Interlude <00:06.30>ends <00:06.60>here
[00:09.00]<00:09.00>Second <00:09.35>line <00:09.70>begins
[00:12.00]Third line plain text
[00:15.00][00:23.00]Shared refrain returns
[00:16.50]Fifth line continues
[00:18.50]<00:18.50>Sixth <00:18.80>line <00:19.10>word <00:19.40>by <00:19.70>word
[00:21.00]Seventh line here
[00:24.50]Eighth line closes it out
LRC
EOF

  write_script "$play2_script" <<EOF
#!/usr/bin/env bash
sleep 16
echo \$\$ > "$lyrics_pid2_path"
exec "$mpv_bin" --no-video --really-quiet "$lyrics_track2_path"
EOF

  # The second track's own key, read the same way: selected explicitly
  # (media.sh's "other" pattern) so its tags and duration are the real
  # player answering rather than the fixture's own ffmpeg -t. An empty
  # ".none" marker is a fresh miss (LyricsService.qml's find -mtime -7),
  # never asked of lrclib at all. Track1 is reselected before the panel
  # opens so the open below lands on the synced half first.
  write_script "$key2_script" <<EOF
#!/usr/bin/env bash
. "$lyrics_lib_path"
sleep 20
SECONDS=0
players=""
while [ "\$SECONDS" -lt 8 ]; do
  players=\$("$qs_bin" ipc -p "$shell_path" call media players 2>&1)
  [ "\$(printf '%s' "\$players" | grep -o '"id":"[^"]*"' | wc -l)" -ge 2 ] && break
  sleep 1
done
id1=\$("$jq_bin" -r '.id' "$lyrics_status1_path" 2>/dev/null)
# -x, whole-line match: mpv's first instance often claims the bare
# "org.mpris.MediaPlayer2.mpv" name and the second falls back to
# "org.mpris.MediaPlayer2.mpv.instance-<id>", so a plain substring
# exclusion (-F alone) drops both, id1 being a prefix of id2.
id2=\$(printf '%s' "\$players" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | grep -vFx "\$id1" | head -1)
echo "\$id2" > "$lyrics_id2_path"
"$qs_bin" ipc -p "$shell_path" call media select "\$id2" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call media status > "$lyrics_status2_path" 2>&1
duration=\$("$jq_bin" -r '.length // 0' "$lyrics_status2_path" 2>/dev/null)
key2=\$(lyrics_cache_key "$lyrics_track2_artist" "$lyrics_track2_title" "$lyrics_track2_album" "\${duration:-0}")
echo "\$key2" > "$lyrics_key2_path"
mkdir -p "$cache_dir"
: > "$cache_dir/\$key2.none"
"$qs_bin" ipc -p "$shell_path" call media select "\$id1" > /dev/null 2>&1
EOF

  write_script "$open_script" <<EOF
#!/usr/bin/env bash
sleep 36
"$grim_bin" "$lyrics_bare_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call panel open media > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 10 ]; do
  "$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_synced_path" 2>&1
  grep -qF '"state":"synced"' "$lyrics_status_synced_path" && break
  sleep 1
done
sleep 2
"$grim_bin" "$lyrics_synced_png_path" > /dev/null 2>&1
sleep 3
"$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_later_path" 2>&1
EOF

  write_script "$switch_script" <<EOF
#!/usr/bin/env bash
sleep 54
id2=\$(cat "$lyrics_id2_path" 2>/dev/null)
"$qs_bin" ipc -p "$shell_path" call media select "\$id2" > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 10 ]; do
  "$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_none_path" 2>&1
  grep -qF '"state":"none"' "$lyrics_status_none_path" && break
  sleep 1
done
sleep 2
"$grim_bin" "$lyrics_none_png_path" > /dev/null 2>&1
EOF

  write_script "$kill_script" <<EOF
#!/usr/bin/env bash
for pidfile in "$lyrics_pid1_path" "$lyrics_pid2_path"; do
  [ -f "\$pidfile" ] && kill "\$(cat "\$pidfile")" 2>/dev/null
done
true
EOF
  add_cleanup "bash $kill_script"

  echo "exec-once = bash $play1_script"
  echo "exec-once = bash $key1_script"
  echo "exec-once = bash $play2_script"
  echo "exec-once = bash $key2_script"
  echo "exec-once = bash $open_script"
  echo "exec-once = bash $switch_script"
}

# The card's own rect off a bare/open pair, panel_emerge.sh's own trick:
# the bounding box of the pixel difference between a frame with the panel
# closed and one with it open, cropped below the bar first so the cell's
# panel mark is not counted in it. Written as a small JSON file rather than
# left as a bare rect string, so the assert step (and anyone reading
# artifacts/ later) can read it with jq like every other leg's evidence.
# Width is the claim now (M55 Task 9/10): the panel changed from a fixed
# height (a shorter card with no LYRICS block) to a fixed WIDTH
# (`popupWidthMenuSplit`/`popupWidthWide`, the two-column layout), so height
# is no longer what tells the two states apart.
lyrics_panel_rect() {
  local open_frame="$1" out_json="$2" body_h=$((1080 - 60)) bare_body open_body rect w h
  bare_body="$shot_dir/lyrics-body-bare.png"
  open_body="$shot_dir/lyrics-body-$(basename "$open_frame").png"
  $convert_bin "$lyrics_bare_path" -crop "1920x${body_h}+0+60" +repage "$bare_body" > /dev/null 2>&1
  $convert_bin "$open_frame" -crop "1920x${body_h}+0+60" +repage "$open_body" > /dev/null 2>&1
  rect=$($convert_bin "$bare_body" "$open_body" -compose difference -composite \
    -threshold 8% -format "%@" info: 2>/dev/null)
  w=${rect%%x*}; h=${rect#*x}; h=${h%%+*}
  printf '{"rect": "%s", "width": %s, "height": %s}\n' "$rect" "${w:-0}" "${h:-0}" > "$out_json"
}

leg_lyrics_assert() {
  local index_synced index_later pos_synced pos_later width_synced width_none

  [ -s "$lyrics_status1_path" ] || fail "no media status produced for the first lyrics track"
  grep -qF "\"title\":\"$lyrics_track1_title\"" "$lyrics_status1_path" \
    || fail "media status never showed the first lyrics track, got: $(cat "$lyrics_status1_path" 2>/dev/null)"
  [ -s "$lyrics_key1_path" ] || fail "no cache key computed for the first lyrics track"
  [ -s "$lyrics_key2_path" ] || fail "no cache key computed for the second lyrics track"
  [ -s "$lyrics_id2_path" ] || fail "the second lyrics track never registered a distinct player id"

  [ -f "$lyrics_bare_path" ] || fail "no bare (panel closed) screenshot produced"

  if [ ! -s "$lyrics_status_synced_path" ]; then
    fail "no media lyrics status produced"
  fi
  cat "$lyrics_status_synced_path"; echo
  echo "SMOKE_LYRICS_STATUS $lyrics_status_synced_path"
  if ! grep -qF '"state":"synced"' "$lyrics_status_synced_path"; then
    fail "media lyrics never reached synced for the cached track, got: $(cat "$lyrics_status_synced_path")"
  fi
  if ! grep -qF '"source":"cache"' "$lyrics_status_synced_path"; then
    fail "media lyrics did not read the seeded LRC from cache, got: $(cat "$lyrics_status_synced_path")"
  fi
  if ! grep -qF '"words":true' "$lyrics_status_synced_path"; then
    fail "media lyrics does not report word timing, got: $(cat "$lyrics_status_synced_path")"
  fi
  [ -f "$lyrics_synced_png_path" ] || fail "no lyrics-synced screenshot produced"
  echo "SMOKE_LYRICS_SYNCED $lyrics_synced_png_path"

  if [ ! -s "$lyrics_status_later_path" ]; then
    fail "no later media lyrics status produced"
  fi
  cat "$lyrics_status_later_path"; echo
  echo "SMOKE_LYRICS_STATUS_LATER $lyrics_status_later_path"
  index_synced=$("$jq_bin" -r '.index' "$lyrics_status_synced_path" 2>/dev/null)
  index_later=$("$jq_bin" -r '.index' "$lyrics_status_later_path" 2>/dev/null)
  pos_synced=$("$jq_bin" -r '.position' "$lyrics_status_synced_path" 2>/dev/null)
  pos_later=$("$jq_bin" -r '.position' "$lyrics_status_later_path" 2>/dev/null)
  if ! awk -v a="${index_later:--1}" -v b="${index_synced:--1}" -v pl="${pos_later:-0}" -v ps="${pos_synced:-0}" \
    'BEGIN { exit !((a > b) || (pl > ps && a >= 0)) }'; then
    fail "neither the lyrics index nor the playback position advanced over the 3s wait (synced: index=$index_synced position=$pos_synced, later: index=$index_later position=$pos_later)"
  fi

  lyrics_panel_rect "$lyrics_synced_png_path" "$lyrics_panel_synced_json_path"
  echo "SMOKE_LYRICS_PANEL_SYNCED $lyrics_panel_synced_json_path"
  cat "$lyrics_panel_synced_json_path"; echo

  if [ ! -s "$lyrics_status_none_path" ]; then
    fail "no media lyrics status produced after switching to the untimed track"
  fi
  cat "$lyrics_status_none_path"; echo
  echo "SMOKE_LYRICS_NONE $lyrics_status_none_path"
  if ! grep -qF '"state":"none"' "$lyrics_status_none_path"; then
    fail "media lyrics did not reach none for the untimed track, got: $(cat "$lyrics_status_none_path")"
  fi
  [ -f "$lyrics_none_png_path" ] || fail "no lyrics-none screenshot produced"

  lyrics_panel_rect "$lyrics_none_png_path" "$lyrics_panel_none_json_path"
  echo "SMOKE_LYRICS_PANEL_NONE $lyrics_panel_none_json_path"
  cat "$lyrics_panel_none_json_path"; echo

  # M55 A1: `popupWidthMenuSplit` (840) synced, the two-column layout;
  # `popupWidthWide` (480) once lyrics drop to `none` and only the
  # now-playing column remains. A generous tolerance for the diff rect's
  # own edge antialiasing rather than the exact token value.
  width_synced=$("$jq_bin" -r '.width' "$lyrics_panel_synced_json_path" 2>/dev/null)
  width_none=$("$jq_bin" -r '.width' "$lyrics_panel_none_json_path" 2>/dev/null)
  if ! awk -v w="${width_synced:-0}" -v want=840 -v tol=30 'BEGIN { exit !(w > want - tol && w < want + tol) }'; then
    fail "the synced panel is not popupWidthMenuSplit wide (want ~840, got width=$width_synced)"
  fi
  if ! awk -v w="${width_none:-0}" -v want=480 -v tol=30 'BEGIN { exit !(w > want - tol && w < want + tol) }'; then
    fail "the untimed panel is not popupWidthWide wide (want ~480, got width=$width_none)"
  fi
}
