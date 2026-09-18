# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, iso_home, the *_bin paths and fail()
# --lyrics (M56 P3/P5/P9/P11/P14): three real MPRIS players. Since P14, a
# lookup starts a second after ANY key change, panel open or closed, so all
# three cache files (two `.json`, one `.miss`) are written straight into the
# isolated XDG_CACHE_HOME in `leg_lyrics_fixture`, off the fixture's own
# known ffmpeg duration, before the session (and any player in it) even
# exists: there is never a moment where a key is live with no file behind
# it, which a select-then-write ordering could no longer promise once the
# wait was no longer gated on the panel being closed. `dev/smoke.d/README.md`
# still calls this the file contract; nothing here needs a leg of its own to
# know when another one is done, since the marker chain below only has to
# serialise the player-specific waits, not the seeding.
#
# Track1 carries a syllable line, a background line whose own end runs
# ridiculously past the next main line's start, and a duet turn (spec
# P1/P4/P5): seeding the other two tracks below has no fixed duration (each
# select waits on the real player's own MPRIS registration), so the overlap
# the duet-lit poll waits for is built to still be true minutes later rather
# than sized to a guessed setup time. Track2's
# cache has line timing only and no `words`, so `LyricsService.lines`
# synthesises them client-side (P4): the same four-word line repeats every
# 20s for the length of the file, so whichever repeat happens to be active
# once this leg gets around to selecting it, `position` minus that line's
# own `time` is what the poll below reads, not a wall-clock guess. Track3
# gets an empty `.miss` marker, the seven-day fresh-miss path, never asked
# of a provider at all.
#
# The claims: `media lyrics` reaches `synced`/`quality:2`/`estimated:false`
# for track1, its `active`/`secondary` moving to the exact pair kopuz's rule
# produces once the duet line starts while the background line is still
# running (P5's own worked example, not a made-up one: see the fixture's own
# comment below); a real wlrctl wheel notch over the pane's own on-screen
# rect (found the same way the panel-width check already does, a pixel diff
# between a bare frame and one with the panel open) takes `follow` to false,
# and selecting track2 re-arms it; track2 reaches `quality:1` with every
# line `estimated:true` and its wipe visibly partway in a frame, read off
# the row's own left/right halves rather than trusted from IPC alone;
# track3 reaches `none` with the panel narrower, as M55 already proved;
# selecting track1 back grows the panel again across a burst of frames that
# all share the narrow card's own centre, which is the centre of the bar
# cell that opened it (the growth travels both edges); and that burst's
# settled frame carries the lit line broken inside a chunk wider than the
# pane, read as the brightest ink stopping short of the viewport's clip.
#
# Two more since M69. The reopen claim: a wheel takes `follow` off, the panel
# is closed with the track still playing and opened again with no track
# change between, and the column is back on the song. Closing is the one way
# out of the wheel takeover that leaves none of spec P9's own re-arms
# reachable (they all live inside an open panel), which is what left a
# reopened pane parked where the wheel had put it minutes earlier, reading as
# the song having run ahead of the lyrics (owner, 2026-09-18).
#
# The line-change claim: track1 carries an mpv IPC socket, so the tail of the
# run seeks it back over its own chained boundaries and photographs two
# consecutive line changes, one into a line that fits on a row (15s) and one
# into the line that wraps (25s). Each frame's ink is read as a column of row
# means down the pane, and the two things that hold are that the pane never
# empties out while a change is in flight, and that the brightest row, which
# is the lit line, is on one place across the tail of each burst rather than
# still drifting. A row that resized itself as it lit moved every row under
# it and the scroll's own target with them, so the column was still chasing
# a line seconds after it had started singing (owner, 2026-09-18).
leg_lyrics_flag="--lyrics"
leg_lyrics_order=175
leg_lyrics_needs="mpv ffmpeg convert jq wlrctl"

lyrics_track1_path="$shot_dir/lyrics-track1.flac"
lyrics_track2_path="$shot_dir/lyrics-track2.flac"
lyrics_track3_path="$shot_dir/lyrics-track3.flac"
lyrics_pid1_path="$shot_dir/lyrics-mpv1.pid"
lyrics_pid2_path="$shot_dir/lyrics-mpv2.pid"
lyrics_pid3_path="$shot_dir/lyrics-mpv3.pid"
lyrics_id1_path="$shot_dir/lyrics-id1.txt"
lyrics_id2_path="$shot_dir/lyrics-id2.txt"
lyrics_id3_path="$shot_dir/lyrics-id3.txt"
lyrics_seed_log_path="$shot_dir/lyrics-seed.log"
lyrics_bare_path="$shot_dir/lyrics-bare.png"
lyrics_synced_png_path="$shot_dir/lyrics-synced.png"
lyrics_estimated_png_path="$shot_dir/lyrics-estimated.png"
lyrics_none_png_path="$shot_dir/lyrics-none.png"
lyrics_status_preopen_path="$shot_dir/lyrics-status-preopen.json"
lyrics_status_synced_path="$shot_dir/lyrics-status-synced.json"
lyrics_status_later_path="$shot_dir/lyrics-status-later.json"
lyrics_status_duet_path="$shot_dir/lyrics-status-duet.json"
lyrics_status_prewheel_path="$shot_dir/lyrics-status-prewheel.json"
lyrics_status_postwheel_path="$shot_dir/lyrics-status-postwheel.json"
lyrics_status_estimated_path="$shot_dir/lyrics-status-estimated.json"
lyrics_status_none_path="$shot_dir/lyrics-status-none.json"
lyrics_status_return_path="$shot_dir/lyrics-status-return.json"
lyrics_panel_synced_json_path="$shot_dir/lyrics-panel-synced.json"
lyrics_panel_none_json_path="$shot_dir/lyrics-panel-none.json"
lyrics_wheel_dispatch_path="$shot_dir/lyrics-wheel-dispatch.txt"
lyrics_wheel_target_path="$shot_dir/lyrics-wheel-target.txt"
lyrics_return_rects_path="$shot_dir/lyrics-return-rects.txt"
lyrics_return_narrow_path="$shot_dir/lyrics-return-narrow.png"
lyrics_edge_rects_path="$shot_dir/lyrics-edge-rects.txt"
lyrics_status_reopen_path="$shot_dir/lyrics-status-reopen.json"
lyrics_reopen_png_path="$shot_dir/lyrics-reopen.png"
lyrics_burst_index_path="$shot_dir/lyrics-burst-index.txt"
lyrics_burst_profile_path="$shot_dir/lyrics-burst-profile.txt"
lyrics_sock1_path="$shot_dir/lyrics-mpv1.sock"
lyrics_lib_path="$shot_dir/lyrics-lib.sh"
lyrics_marker_seeded="$shot_dir/lyrics-marker-seeded"
lyrics_marker_open1="$shot_dir/lyrics-marker-open1"
lyrics_marker_track1="$shot_dir/lyrics-marker-track1"
lyrics_marker_track2="$shot_dir/lyrics-marker-track2"
lyrics_marker_track3="$shot_dir/lyrics-marker-track3"

lyrics_track1_title="FormalShell Lyrics Smoke Track"
lyrics_track1_artist="FormalShell Lyrics Artist"
lyrics_track1_album="FormalShell Lyrics Album"
lyrics_track2_title="FormalShell Lyrics Estimated Track"
lyrics_track2_artist="FormalShell Lyrics Artist Two"
lyrics_track2_album="FormalShell Lyrics Album Two"
lyrics_track3_title="FormalShell Lyrics Miss Track"
lyrics_track3_artist="FormalShell Lyrics Artist Three"
lyrics_track3_album="FormalShell Lyrics Album Three"

leg_lyrics_timing() {
  # Every slow step below polls a condition rather than sleeping a guess, so
  # this only has to outlast the sum of their own timeouts once, not the
  # common case. Track1 stays on MPRIS through the whole thing (mpv drops
  # off MPRIS the moment a track ends), hence its file being far longer
  # than the session that plays it. The reopen check and the two line-change
  # bursts add about a minute on the tail.
  leg_timing 100 430 2
}

leg_lyrics_fixture() {
  "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 400 \
    -metadata "title=$lyrics_track1_title" -metadata "artist=$lyrics_track1_artist" \
    -metadata "album=$lyrics_track1_album" -c:a flac -y "$lyrics_track1_path"
  "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 400 \
    -metadata "title=$lyrics_track2_title" -metadata "artist=$lyrics_track2_artist" \
    -metadata "album=$lyrics_track2_album" -c:a flac -y "$lyrics_track2_path"
  "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 300 \
    -metadata "title=$lyrics_track3_title" -metadata "artist=$lyrics_track3_artist" \
    -metadata "album=$lyrics_track3_album" -c:a flac -y "$lyrics_track3_path"

  write_script "$lyrics_lib_path" <<'EOF'
#!/usr/bin/env bash
# Mirrors Lyrics.cacheKey (shell/Lyrics/model.js) exactly: artist, title,
# album joined with spaces, lowercased, every run of non-alphanumerics
# collapsed to one "-", the edges stripped, the rounded duration appended.
lyrics_cache_key() {
  local artist="$1" title="$2" album="$3" duration="$4"
  local raw lower slug seconds
  raw="$artist $title $album"
  lower=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  slug=$(printf '%s' "$lower" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  seconds=$(awk -v v="$duration" 'BEGIN { if (v < 0) v = 0; printf "%d", (v - int(v) >= 0.5) ? int(v) + 1 : int(v) }')
  printf '%s-%s' "$slug" "$seconds"
}

# Track1's own mpv, for the absolute seeks the line-change bursts need: MPRIS
# gives no verb for one and the shell's own seek would move the pane's state
# as well as the player's.
lyrics_mpv() {
  python3 - "$1" "$2" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
s.sendall(sys.argv[2].encode() + b"\n")
s.close()
PY
}

lyrics_wait_marker() {
  local marker="$1" timeout="$2" waited=0
  while [ ! -f "$marker" ] && [ "$waited" -lt "$timeout" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  [ -f "$marker" ]
}

# The panel's own on-screen rect, read off a pixel diff between a frame with
# no panel open and one with it open (panel_emerge.sh's own trick), so the
# wheel target and the wipe/return crops below never need a hardcoded screen
# coordinate. Crops away the bar first (its clock ticking between the two
# shots would otherwise stretch the box upward); the returned y is relative
# to that crop, so a caller driving the real pointer adds the 60 back and a
# caller only cropping further from the same body image does not. Echoes
# "x y w h bodyImagePath".
lyrics_pane_rect() {
  local bare="$1" open="$2" conv="$3"
  local body_h=$((1080 - 60)) bare_body open_body rect w h rest x y
  bare_body="${bare%.png}-body.png"
  open_body="${open%.png}-body.png"
  "$conv" "$bare" -crop "1920x${body_h}+0+60" +repage "$bare_body" > /dev/null 2>&1
  "$conv" "$open" -crop "1920x${body_h}+0+60" +repage "$open_body" > /dev/null 2>&1
  rect=$("$conv" "$bare_body" "$open_body" -compose difference -composite \
    -threshold 8% -format "%@" info: 2>/dev/null)
  w=${rect%%x*}
  rest=${rect#*x}
  h=${rest%%+*}
  rest=${rest#*+}
  x=${rest%%+*}
  y=${rest#*+}
  printf '%s %s %s %s %s\n' "${x:-0}" "${y:-0}" "${w:-0}" "${h:-0}" "$open_body"
}
EOF

  # Four lines chained edge to edge (line0 ends exactly where line1 starts,
  # so there is never a gap wide enough for `displayLines` to read as an
  # interlude, and never a moment with nothing active), the last two
  # carrying an end so far past the others that they are lit for practically
  # the rest of the run rather than one frame's worth: seeding all three
  # tracks below runs before the panel ever opens and takes as long as the
  # VM feels like taking, so the window this leg's duet-lit poll wants has
  # to survive whatever that turns out to be, not a wall-clock guess. Line0
  # carries eight word-level chunks (quality 2) and line1 is a plain short
  # main line, between them covering the moment the earlier "index moving"
  # check happens to land on. Line2 is the background line, `parent: 1`
  # (the raw index the service stores before `displayLines` remaps it), its
  # own end ridiculously past the point line3 (the duet turn) takes over as
  # the active main line at 25s: P5's rule judges a background line on its
  # own timing, so it stays lit into that next main line for effectively the
  # rest of the session, which is what the duet-lit poll below waits for.
  # Line3 ends on one word longer than the pane is wide, so the lit form has
  # to break inside a chunk the way the plain one does; the return burst's
  # own settled frame is where that line is read.
  cat > "$shot_dir/lyrics-track1-cache.json" <<'JSON'
{"source": "apple", "lines": [
{"time": 2.0, "end": 15.0, "text": "Paper lantern morning", "parent": null, "background": false, "oppositeTurn": false, "estimated": false, "words": [
  {"time": 2.0, "text": "Pa", "joinsNext": true}, {"time": 2.6, "text": "per", "joinsNext": false},
  {"time": 3.2, "text": "lan", "joinsNext": true}, {"time": 3.8, "text": "tern", "joinsNext": false},
  {"time": 4.4, "text": "morn", "joinsNext": true}, {"time": 5.0, "text": "ing", "joinsNext": false}]},
{"time": 15.0, "end": 25.0, "text": "Sundial over the harbour", "parent": null, "background": false, "oppositeTurn": false, "estimated": false, "words": [
  {"time": 15.0, "text": "Sun", "joinsNext": true}, {"time": 15.8, "text": "dial", "joinsNext": false},
  {"time": 16.8, "text": "over", "joinsNext": false}, {"time": 17.8, "text": "the", "joinsNext": false},
  {"time": 18.6, "text": "harbour", "joinsNext": false}]},
{"time": 16.0, "end": 100000.0, "text": "steady now", "parent": 1, "background": true, "oppositeTurn": false, "estimated": false, "words": [
  {"time": 16.0, "text": "stea", "joinsNext": true}, {"time": 16.8, "text": "dy", "joinsNext": false},
  {"time": 17.6, "text": "now", "joinsNext": false}]},
{"time": 25.0, "end": 100000.0, "text": "Answer from the other shore lanternlightacrossthewholeharbourmouth", "parent": null, "background": false, "oppositeTurn": true, "estimated": false, "words": [
  {"time": 25.0, "text": "Answer", "joinsNext": false}, {"time": 26.2, "text": "from", "joinsNext": false},
  {"time": 27.2, "text": "the", "joinsNext": false}, {"time": 28.2, "text": "other", "joinsNext": false},
  {"time": 29.2, "text": "shore", "joinsNext": false},
  {"time": 30.2, "text": "lanternlightacrossthewholeharbourmouth", "joinsNext": false}]}
]}
JSON

  # Line timing only, no `words`, so LyricsService synthesises them (P4).
  # The same four-word line ("Amber light falls low") repeats every 20s for
  # the length of the file: each repeat's own 16s span is wide enough that
  # "Amber"/"light" wipe fully (and their glow decays) by 5.64s in, while
  # "falls"/"low" have not started until 8.89s in, so [5.8, 8.7] relative to
  # whichever repeat is active is nearly three seconds of margin, not one
  # exact frame, and it holds regardless of which repeat this leg happens to
  # land on once it gets around to selecting this track.
  {
    printf '{"source": "lrclib", "lines": ['
    local i sep="" t
    for i in $(seq 0 18); do
      t=$((4 + i * 20))
      printf '%s{"time": %s.0, "end": %s.0, "text": "Amber light falls low", "parent": null, "background": false, "oppositeTurn": false, "estimated": false, "words": []}' \
        "$sep" "$t" "$((t + 16))"
      sep=","
    done
    printf ']}'
  } > "$shot_dir/lyrics-track2-cache.json"

  # spec P14: LyricsService starts a lookup a second after ANY key change,
  # panel open or closed, so a player selected for longer than that with no
  # cache file yet would otherwise start a real provider race. Every cache
  # file this leg needs is therefore written here, before the session (and
  # every mpv player in it) even exists, off the fixture's own known
  # duration rather than a real player's, so there is never a moment where
  # a key is live and its file is not: `ffmpeg -t 400` reports back within
  # a few milliseconds of 400 for plain silence, comfortably inside
  # `lyrics_cache_key`'s own half-second rounding.
  # shellcheck source=/dev/null
  . "$lyrics_lib_path"
  local cache_dir="$iso_home/.cache/formalshell/lyrics"
  mkdir -p "$cache_dir"
  local key1 key2 key3
  key1=$(lyrics_cache_key "$lyrics_track1_artist" "$lyrics_track1_title" "$lyrics_track1_album" 400)
  key2=$(lyrics_cache_key "$lyrics_track2_artist" "$lyrics_track2_title" "$lyrics_track2_album" 400)
  key3=$(lyrics_cache_key "$lyrics_track3_artist" "$lyrics_track3_title" "$lyrics_track3_album" 300)
  cp "$shot_dir/lyrics-track1-cache.json" "$cache_dir/$key1.json"
  cp "$shot_dir/lyrics-track2-cache.json" "$cache_dir/$key2.json"
  : > "$cache_dir/$key3.miss"
}

leg_lyrics_drive() {
  local play_all="$shot_dir/lyrics-p0-play.sh"
  local seed_all="$shot_dir/lyrics-p1-seed.sh"
  local open1="$shot_dir/lyrics-p2-open.sh"
  local duet_wheel="$shot_dir/lyrics-p3-duet-wheel.sh"
  local track2="$shot_dir/lyrics-p4-track2.sh"
  local track3="$shot_dir/lyrics-p5-track3.sh"
  local return_script="$shot_dir/lyrics-p6-return.sh"
  local kill_script="$shot_dir/lyrics-kill.sh"

  write_script "$play_all" <<EOF
#!/usr/bin/env bash
sleep 2
"$mpv_bin" --no-video --really-quiet --input-ipc-server="$lyrics_sock1_path" "$lyrics_track1_path" &
disown
echo \$! > "$lyrics_pid1_path"
sleep 2
"$mpv_bin" --no-video --really-quiet "$lyrics_track2_path" &
disown
echo \$! > "$lyrics_pid2_path"
sleep 2
"$mpv_bin" --no-video --really-quiet "$lyrics_track3_path" &
disown
echo \$! > "$lyrics_pid3_path"
EOF

  # Every cache file already exists (written in leg_lyrics_fixture, spec
  # P14's own comment there says why), so this only has to work out which
  # real MPRIS id is which fixture: each of the three players is selected
  # in turn and `media status`'s own title tells it apart from the other
  # two regardless of which one the compositor happened to register first.
  write_script "$seed_all" <<EOF
#!/usr/bin/env bash
. "$lyrics_lib_path"
: > "$lyrics_seed_log_path"
SECONDS=0
players=""
while [ "\$SECONDS" -lt 20 ]; do
  players=\$("$qs_bin" ipc -p "$shell_path" call media players 2>&1)
  count=\$(printf '%s' "\$players" | grep -o '"id":"[^"]*"' | wc -l)
  [ "\$count" -ge 3 ] && break
  sleep 1
done
echo "players: \$players" >> "$lyrics_seed_log_path"

for id in \$(printf '%s' "\$players" | grep -o '"id":"[^"]*"' | cut -d'"' -f4); do
  "$qs_bin" ipc -p "$shell_path" call media select "\$id" > /dev/null 2>&1
  status=""
  SECONDS=0
  # Waits for status's own "id" field (MediaService.activeId) to actually
  # be this id before trusting anything else in the same dump, rather than
  # matching on title text alone: a status call fired right after select
  # can still carry the PREVIOUS player's own title for a moment, and every
  # title here belongs to one of these three fixtures, so a stale read
  # would otherwise misassign it to the wrong one.
  while [ "\$SECONDS" -lt 6 ]; do
    status=\$("$qs_bin" ipc -p "$shell_path" call media status 2>&1)
    case "\$status" in *"\"id\":\"\$id\""*) break ;; esac
    sleep 1
  done
  echo "id=\$id status=\$status" >> "$lyrics_seed_log_path"
  case "\$status" in
    *"\"title\":\"$lyrics_track1_title\""*) echo "\$id" > "$lyrics_id1_path" ;;
    *"\"title\":\"$lyrics_track2_title\""*) echo "\$id" > "$lyrics_id2_path" ;;
    *"\"title\":\"$lyrics_track3_title\""*) echo "\$id" > "$lyrics_id3_path" ;;
  esac
done

id1=\$(cat "$lyrics_id1_path" 2>/dev/null)
"$qs_bin" ipc -p "$shell_path" call media select "\$id1" > /dev/null 2>&1
touch "$lyrics_marker_seeded"
EOF

  # spec P14: the lookup starts on the track change itself, so track1's
  # lyrics are polled to synced here with the panel still closed the whole
  # time (no `panel open` call yet), proving the pane never had to wait on
  # being opened at all. Opening it after that is the "no morph" half: the
  # settle sleep below is sized for the panel's own open transition, not
  # for lyrics to arrive (they already have), so the very first frame read
  # off it lands on popupWidthMenuSplit directly rather than growing into
  # it from popupWidthWide.
  write_script "$open1" <<EOF
#!/usr/bin/env bash
. "$lyrics_lib_path"
lyrics_wait_marker "$lyrics_marker_seeded" 30
"$grim_bin" "$lyrics_bare_path" > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 15 ]; do
  "$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_preopen_path" 2>&1
  grep -qF '"state":"synced"' "$lyrics_status_preopen_path" && break
  sleep 1
done
"$qs_bin" ipc -p "$shell_path" call panel open media > /dev/null 2>&1
sleep 1
"$grim_bin" "$lyrics_synced_png_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_synced_path" 2>&1
sleep 3
"$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_later_path" 2>&1
touch "$lyrics_marker_open1"
EOF

  # The duet-lit poll has no fixed duration (it is waiting for track1's own
  # playback position, not a shell reaction), so it is a real poll, at 0.5s
  # resolution against the fixture's own 3.5s-wide overlap window, rather
  # than a sleep tuned to it. The wheel target comes from `lyrics_pane_rect`
  # against the already-open synced frame, never a hardcoded coordinate:
  # `+ 480` is popupWidthMenuSplit's own leading column width (M55 A1/M56
  # P13), so the point lands in the middle of the trailing 360px the lyrics
  # pane owns.
  write_script "$duet_wheel" <<EOF
#!/usr/bin/env bash
. "$lyrics_lib_path"
lyrics_wait_marker "$lyrics_marker_open1" 60
SECONDS=0
while [ "\$SECONDS" -lt 50 ]; do
  "$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_duet_path" 2>&1
  active=\$("$jq_bin" -r '.active' "$lyrics_status_duet_path" 2>/dev/null)
  [ "\$active" = "3" ] && break
  sleep 0.5
done

read -r rx ry rw rh _ < <(lyrics_pane_rect "$lyrics_bare_path" "$lyrics_synced_png_path" "$convert_bin")
target_x=\$((rx + 480 + (rw - 480) / 2))
target_y=\$((ry + rh / 2 + 60))
echo "\$target_x \$target_y \$rx \$ry \$rw \$rh" > "$lyrics_wheel_target_path"

"$wlrctl_bin" pointer move -4000 -4000 > "$lyrics_wheel_dispatch_path" 2>&1
sleep 1
"$wlrctl_bin" pointer move "\$target_x" "\$target_y" >> "$lyrics_wheel_dispatch_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_prewheel_path" 2>&1
"$wlrctl_bin" pointer scroll 10 0 >> "$lyrics_wheel_dispatch_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_postwheel_path" 2>&1

# The reopen: the wheel has the column, the panel is shut with track1 still
# playing, and it comes back with no track change anywhere in between, so
# nothing but the open itself can have re-armed follow.
"$qs_bin" ipc -p "$shell_path" call panel close > /dev/null 2>&1
sleep 6
"$qs_bin" ipc -p "$shell_path" call panel open media > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_reopen_path" 2>&1
"$grim_bin" "$lyrics_reopen_png_path" > /dev/null 2>&1
touch "$lyrics_marker_track1"
EOF

  # Track2 is already playing (seeded in the pre-open phase), so selecting
  # it here is a plain cache hit; it is also the wheel takeover's other
  # half, since a new track re-arms `follow` (`LyricsService._resolve()`
  # does that on every key change), read back in the same status dump the
  # quality/estimated assertions use. The position poll below reads
  # `active` and that display line's own `time` back out of the same JSON
  # rather than assuming which of the 19 repeats is current.
  write_script "$track2" <<EOF
#!/usr/bin/env bash
. "$lyrics_lib_path"
lyrics_wait_marker "$lyrics_marker_track1" 120
id2=\$(cat "$lyrics_id2_path" 2>/dev/null)
"$qs_bin" ipc -p "$shell_path" call media select "\$id2" > /dev/null 2>&1
# The anchorless open rests against the screen's far padding, so this track
# change is the one where the width (the pane leaving while the new key
# loads, then coming back) has to carry the card's leading edge with it.
# Eight frames straight through it, read in verify: the far edge on the
# padding in every one, which a place animated on a clock of its own misses
# by hundreds of pixels for most of the burst.
for n in 1 2 3 4 5 6 7 8; do
  "$grim_bin" "$shot_dir/lyrics-edge-\${n}.png" > /dev/null 2>&1
done
SECONDS=0
while [ "\$SECONDS" -lt 15 ]; do
  "$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_estimated_path" 2>&1
  grep -qF '"state":"synced"' "$lyrics_status_estimated_path" && break
  sleep 1
done
# The pane arrives on the panel's own width morph. The position window below
# can already be open the moment the state flips, so without this the frame
# lands mid-morph and the pinned fractions read a card that is still moving.
sleep 1

SECONDS=0
while [ "\$SECONDS" -lt 30 ]; do
  "$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_estimated_path" 2>&1
  active=\$("$jq_bin" -r '.active' "$lyrics_status_estimated_path" 2>/dev/null)
  if [ -n "\$active" ] && [ "\$active" != "-1" ] && [ "\$active" != "null" ]; then
    pos=\$("$jq_bin" -r '.position' "$lyrics_status_estimated_path" 2>/dev/null)
    linetime=\$("$jq_bin" -r ".lines[\$active].time" "$lyrics_status_estimated_path" 2>/dev/null)
    if awk -v p="\${pos:--1}" -v t="\${linetime:--1}" 'BEGIN { r = p - t; exit !(r >= 5.8 && r <= 8.7) }'; then
      break
    fi
  fi
  sleep 0.5
done
"$grim_bin" "$lyrics_estimated_png_path" > /dev/null 2>&1
touch "$lyrics_marker_track2"
EOF

  write_script "$track3" <<EOF
#!/usr/bin/env bash
. "$lyrics_lib_path"
lyrics_wait_marker "$lyrics_marker_track2" 160
id3=\$(cat "$lyrics_id3_path" 2>/dev/null)
"$qs_bin" ipc -p "$shell_path" call media select "\$id3" > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 15 ]; do
  "$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_none_path" 2>&1
  grep -qF '"state":"none"' "$lyrics_status_none_path" && break
  sleep 1
done
sleep 2
"$grim_bin" "$lyrics_none_png_path" > /dev/null 2>&1
touch "$lyrics_marker_track3"
EOF

  # The centring leg: the anchorless "panel open media" every other frame
  # in this leg uses rests on the screen's own far padding (840 wide
  # against a 1920 output wants x=1068, which is the clamp), so it can say
  # nothing about a cell, and this one part closes it and reopens through
  # `panel toggle media`, which anchors under the bar's own now-playing
  # cell. That cell is in the centre region, so both widths clear the
  # padding at either end and what places the card is the centring alone.
  # Track3 (none, narrow) is still active when it reopens, so the arrival
  # is the same key change `follow`'s other re-arm path already needs to
  # fire on (`LyricsService._resolve()` resets it on every key change, not
  # only the wheel-scroll leg's own path above). One frame of the narrow
  # card first, for the cell centre it rests on, then a burst through the
  # arrival, each read against the same bare frame `lyrics_pane_rect` uses
  # for the width checks (panel close leaves the desktop exactly as bare as
  # it started).
  write_script "$return_script" <<EOF
#!/usr/bin/env bash
. "$lyrics_lib_path"
lyrics_wait_marker "$lyrics_marker_track3" 200
id1=\$(cat "$lyrics_id1_path" 2>/dev/null)
"$qs_bin" ipc -p "$shell_path" call panel close > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call panel toggle media > /dev/null 2>&1
sleep 1
"$grim_bin" "$lyrics_return_narrow_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call media select "\$id1" > /dev/null 2>&1
: > "$lyrics_return_rects_path"
for delay in 0.1 0.4 0.8 1.2 1.6; do
  sleep "\$delay"
  frame="$shot_dir/lyrics-return-\${delay}.png"
  "$grim_bin" "\$frame" > /dev/null 2>&1
  read -r rx ry rw rh _ < <(lyrics_pane_rect "$lyrics_bare_path" "\$frame" "$convert_bin")
  echo "\$delay \$rx \$ry \$rw \$rh" >> "$lyrics_return_rects_path"
done
"$qs_bin" ipc -p "$shell_path" call media lyrics > "$lyrics_status_return_path" 2>&1

# The two line changes, photographed. Track1's own boundaries are at 15s
# (line0 into line1, both a row tall) and 25s (line1 into line3, the one that
# wraps), and both are chained edge to edge, so there is a lit line in every
# frame of both bursts. The seeks are mpv's own: a shell seek would move the
# pane's state along with the player's, and the run is well past 25s by now.
: > "$lyrics_burst_index_path"
for phase in a b; do
  case "\$phase" in
    a) lyrics_mpv "$lyrics_sock1_path" '{"command":["seek",12,"absolute"]}' ;;
    b) lyrics_mpv "$lyrics_sock1_path" '{"command":["seek",22,"absolute"]}' ;;
  esac
  sleep 2
  for n in 1 2 3 4 5 6 7 8 9 10; do
    "$grim_bin" "$shot_dir/lyrics-burst-\${phase}-\${n}.png" > /dev/null 2>&1
    echo "\${phase}-\${n}" >> "$lyrics_burst_index_path"
    sleep 0.3
  done
done
EOF

  write_script "$kill_script" <<EOF
#!/usr/bin/env bash
for pidfile in "$lyrics_pid1_path" "$lyrics_pid2_path" "$lyrics_pid3_path"; do
  [ -f "\$pidfile" ] && kill "\$(cat "\$pidfile")" 2>/dev/null
done
true
EOF
  add_cleanup "bash $kill_script"

  echo "exec-once = bash $play_all"
  echo "exec-once = bash $seed_all"
  echo "exec-once = bash $open1"
  echo "exec-once = bash $duet_wheel"
  echo "exec-once = bash $track2"
  echo "exec-once = bash $track3"
  echo "exec-once = bash $return_script"
}

# A frame with the bar cropped off it, which is what every rect and crop in
# this leg is measured against (`lyrics_pane_rect` makes its own for the two
# frames it diffs; the burst reuses one rect over twenty frames and needs
# theirs).
lyrics_burst_body() {
  local frame="$1" body="${1%.png}-body.png"
  "$convert_bin" "$frame" -crop "1920x$((1080 - 60))+0+60" +repage "$body" > /dev/null 2>&1
  printf '%s' "$body"
}

# One frame's ink down the lyrics pane, as a column of row means: the crop is
# squeezed to a single pixel wide, so a row carrying text reads above the
# card's own fill and a row carrying none reads as the fill itself. The floor
# is taken from the frame rather than pinned, since the card's fill and the
# depth ramp both come off the live palette. Echoes "peakRow lastInkRow rows".
lyrics_ink_profile() {
  "$convert_bin" "$1" -crop "$2" +repage -colorspace Gray -resize 1x! -depth 8 txt:- 2>/dev/null \
    | python3 -c '
import re, sys
vals = []
for line in sys.stdin:
    m = re.match(r"0,(\d+): \((\d+)", line)
    if m:
        vals.append((int(m.group(1)), int(m.group(2))))
if not vals:
    print("-1 -1 0")
    raise SystemExit
lo = min(v for _, v in vals)
hi = max(v for _, v in vals)
floor = lo + (hi - lo) * 0.15
ink = [y for y, v in vals if v > floor]
peak = max(vals, key=lambda p: p[1])[0]
print("%d %d %d" % (peak, max(ink) if ink else -1, len(ink)))
'
}

# The panel's own width off a bare/open pair (panel_emerge.sh's own trick),
# kept here as the reader the two IPC-state assertions use; `lyrics_pane_rect`
# in the shared lib is the fuller version (also x/y) the wheel target and
# the return-burst check use.
lyrics_panel_rect() {
  local open_frame="$1" out_json="$2"
  # shellcheck source=/dev/null
  . "$lyrics_lib_path"
  read -r x y w h _ < <(lyrics_pane_rect "$lyrics_bare_path" "$open_frame" "$convert_bin")
  printf '{"width": %s, "height": %s, "x": %s, "y": %s}\n' "${w:-0}" "${h:-0}" "${x:-0}" "${y:-0}" > "$out_json"
}

leg_lyrics_assert() {
  local index_synced index_later pos_synced pos_later width_synced width_none

  [ -s "$lyrics_id1_path" ] || fail "no player id resolved for the syllable track, seed log: $(cat "$lyrics_seed_log_path" 2>/dev/null)"
  [ -s "$lyrics_id2_path" ] || fail "no player id resolved for the estimated track, seed log: $(cat "$lyrics_seed_log_path" 2>/dev/null)"
  [ -s "$lyrics_id3_path" ] || fail "no player id resolved for the miss track, seed log: $(cat "$lyrics_seed_log_path" 2>/dev/null)"
  [ -f "$lyrics_bare_path" ] || fail "no bare (panel closed) screenshot produced"
  echo "SMOKE_LYRICS_BARE $lyrics_bare_path"

  # spec P14: the lookup ran on the track change itself, not on the panel
  # opening, so this reaches synced before "panel open media" is ever
  # called.
  if [ ! -s "$lyrics_status_preopen_path" ]; then
    fail "no media lyrics status produced before the panel ever opened"
  fi
  echo "SMOKE_LYRICS_PREOPEN $lyrics_status_preopen_path"
  cat "$lyrics_status_preopen_path"; echo
  if ! grep -qF '"state":"synced"' "$lyrics_status_preopen_path"; then
    fail "media lyrics did not reach synced before the panel opened (P14), got: $(cat "$lyrics_status_preopen_path")"
  fi

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
  if ! grep -qF '"quality":2' "$lyrics_status_synced_path"; then
    fail "the syllable track did not report quality 2, got: $(cat "$lyrics_status_synced_path")"
  fi
  [ -f "$lyrics_synced_png_path" ] || fail "no lyrics-synced screenshot produced"
  echo "SMOKE_LYRICS_SYNCED $lyrics_synced_png_path"

  if [ ! -s "$lyrics_status_later_path" ]; then
    fail "no later media lyrics status produced"
  fi
  cat "$lyrics_status_later_path"; echo
  echo "SMOKE_LYRICS_STATUS_LATER $lyrics_status_later_path"
  index_synced=$("$jq_bin" -r '.active' "$lyrics_status_synced_path" 2>/dev/null)
  index_later=$("$jq_bin" -r '.active' "$lyrics_status_later_path" 2>/dev/null)
  pos_synced=$("$jq_bin" -r '.position' "$lyrics_status_synced_path" 2>/dev/null)
  pos_later=$("$jq_bin" -r '.position' "$lyrics_status_later_path" 2>/dev/null)
  if ! awk -v a="${index_later:--1}" -v b="${index_synced:--1}" -v pl="${pos_later:-0}" -v ps="${pos_synced:-0}" \
    'BEGIN { exit !((a > b) || (pl > ps && a >= 0)) }'; then
    fail "neither the lyrics index nor the playback position advanced over the 3s wait (synced: index=$index_synced position=$pos_synced, later: index=$index_later position=$pos_later)"
  fi

  # This frame was taken one settle second after "panel open media", with
  # the lyrics already synced beforehand (P14 above): its width check below
  # is therefore also the "no morph" half of P14, the panel landing on
  # popupWidthMenuSplit directly rather than opening at popupWidthWide and
  # growing into it once the pane arrives.
  lyrics_panel_rect "$lyrics_synced_png_path" "$lyrics_panel_synced_json_path"
  echo "SMOKE_LYRICS_PANEL_SYNCED $lyrics_panel_synced_json_path"
  cat "$lyrics_panel_synced_json_path"; echo

  # P5's own worked example: the background line at raw index2 (display
  # index2 too, nothing here splices in an interlude) outlasts the main
  # line it rode in on (raw index1, `parent: 1`) and is still within its
  # own effectively-unbounded end once the duet turn (display index3)
  # becomes the active main line at 25s, so kopuz's rule keeps it lit into
  # the next main line rather than dropping it the instant its parent's row
  # changes.
  if [ ! -s "$lyrics_status_duet_path" ]; then
    fail "no media lyrics status produced for the duet-lit poll"
  fi
  cat "$lyrics_status_duet_path"; echo
  echo "SMOKE_LYRICS_DUET $lyrics_status_duet_path"
  if ! "$jq_bin" -e '.active == 3' "$lyrics_status_duet_path" > /dev/null 2>&1; then
    fail "active never reached the duet line (display index 3), got: $(cat "$lyrics_status_duet_path")"
  fi
  if ! "$jq_bin" -e '.secondary == [2]' "$lyrics_status_duet_path" > /dev/null 2>&1; then
    fail "secondary did not hold the overlapping background line (display index 2) into the duet line, got: $(cat "$lyrics_status_duet_path")"
  fi
  if ! "$jq_bin" -e '.lines[3].oppositeTurn == true' "$lyrics_status_duet_path" > /dev/null 2>&1; then
    fail "display line 3 is not marked oppositeTurn, got: $(cat "$lyrics_status_duet_path")"
  fi
  if ! "$jq_bin" -e '.lines[2].background == true and .lines[2].parent == 1' "$lyrics_status_duet_path" > /dev/null 2>&1; then
    fail "display line 2 lost its background/parent remap, got: $(cat "$lyrics_status_duet_path")"
  fi
  if ! "$jq_bin" -e '.lines[3].estimated == false' "$lyrics_status_duet_path" > /dev/null 2>&1; then
    fail "the syllable track's own line reported estimated:true, got: $(cat "$lyrics_status_duet_path")"
  fi

  # The wheel takeover: a real wlrctl scroll over the pane's own on-screen
  # rect, no IPC shortcut standing in for the pointer path.
  if [ ! -s "$lyrics_wheel_target_path" ]; then
    fail "no wheel target computed for the lyrics pane"
  fi
  cat "$lyrics_wheel_target_path"; echo
  if [ ! -s "$lyrics_status_prewheel_path" ] || [ ! -s "$lyrics_status_postwheel_path" ]; then
    fail "no pre/post-wheel media lyrics status produced"
  fi
  if ! "$jq_bin" -e '.follow == true' "$lyrics_status_prewheel_path" > /dev/null 2>&1; then
    fail "follow was already false before the wheel notch, got: $(cat "$lyrics_status_prewheel_path")"
  fi
  if ! "$jq_bin" -e '.follow == false' "$lyrics_status_postwheel_path" > /dev/null 2>&1; then
    fail "a wlrctl scroll over the pane did not take follow over, got: $(cat "$lyrics_status_postwheel_path")"
  fi
  echo "SMOKE_LYRICS_WHEEL follow true -> false over the pane at $(cat "$lyrics_wheel_target_path")"

  # Track2: line timing only, synthesised client-side (P4).
  if [ ! -s "$lyrics_status_estimated_path" ]; then
    fail "no media lyrics status produced for the estimated track"
  fi
  cat "$lyrics_status_estimated_path"; echo
  echo "SMOKE_LYRICS_ESTIMATED_STATUS $lyrics_status_estimated_path"
  if ! grep -qF '"state":"synced"' "$lyrics_status_estimated_path"; then
    fail "media lyrics never reached synced for the line-timing track, got: $(cat "$lyrics_status_estimated_path")"
  fi
  if ! grep -qF '"quality":1' "$lyrics_status_estimated_path"; then
    fail "the line-timing track did not report quality 1, got: $(cat "$lyrics_status_estimated_path")"
  fi
  if ! "$jq_bin" -e 'all(.lines[]; .estimated == true and (.words | length) > 0)' "$lyrics_status_estimated_path" > /dev/null 2>&1; then
    fail "not every line synthesised words and reported estimated:true, got: $(cat "$lyrics_status_estimated_path")"
  fi
  if ! "$jq_bin" -e '.follow == true' "$lyrics_status_estimated_path" > /dev/null 2>&1; then
    fail "selecting a new track did not re-arm follow, got: $(cat "$lyrics_status_estimated_path")"
  fi
  if ! "$jq_bin" -e '.active != -1' "$lyrics_status_estimated_path" > /dev/null 2>&1; then
    fail "the estimated track's poll never landed on an active line, got: $(cat "$lyrics_status_estimated_path")"
  fi
  [ -f "$lyrics_estimated_png_path" ] || fail "no lyrics-estimated screenshot produced"
  echo "SMOKE_LYRICS_ESTIMATED $lyrics_estimated_png_path"

  # The wipe read off the frame itself, not trusted from IPC alone: the
  # active line's own row, split left/right over "Amber light" (both fully
  # sung by the polled position) and "falls low" (neither started). The
  # fractions of the pane's own rect (measured once against a pulled frame
  # from this exact fixture and pinned here, since the row's exact position
  # depends on font metrics this leg has no other way to ask for) land
  # inside those two words with margin either side: x 53-62% for the sung
  # half, 63-74% for the unsung one, y 54-63% for the row itself, all three
  # players this leg always runs together (M55's own "PLAYERS (3)" line)
  # holding the card's own height stable between this check and track1's.
  read -r ex ey ew eh ebody < <(lyrics_pane_rect "$lyrics_bare_path" "$lyrics_estimated_png_path" "$convert_bin")
  local band_y=$((ey + eh * 54 / 100)) band_h=$((eh * 9 / 100))
  local left_x=$((ex + ew * 53 / 100)) left_w=$((ew * 9 / 100))
  local right_x=$((ex + ew * 63 / 100)) right_w=$((ew * 11 / 100))
  local left_mean right_mean
  left_mean=$("$convert_bin" "$ebody" -crop "${left_w}x${band_h}+${left_x}+${band_y}" +repage \
    -colorspace Gray -format '%[fx:mean]' info: 2>/dev/null)
  right_mean=$("$convert_bin" "$ebody" -crop "${right_w}x${band_h}+${right_x}+${band_y}" +repage \
    -colorspace Gray -format '%[fx:mean]' info: 2>/dev/null)
  echo "SMOKE_LYRICS_WIPE left=${left_mean:-0} right=${right_mean:-0} (rect: x=$ex y=$ey w=$ew h=$eh)"
  if ! awk -v l="${left_mean:-0}" -v r="${right_mean:-0}" 'BEGIN { exit !(l > r + 0.03) }'; then
    fail "the estimated track's wipe did not read brighter on its sung (left) half than its unsung (right) half: left=$left_mean right=$right_mean"
  fi

  # Measured here rather than in the session: eight diffs cost more time
  # than the run has left once the burst itself is done.
  local edge_n edge_x edge_w edge_y edge_h edge_far=$((1920 - 12)) edge_off
  : > "$lyrics_edge_rects_path"
  for edge_n in 1 2 3 4 5 6 7 8; do
    [ -f "$shot_dir/lyrics-edge-${edge_n}.png" ] || fail "edge-burst frame $edge_n was never taken"
    read -r edge_x edge_y edge_w edge_h _ < <(lyrics_pane_rect "$lyrics_bare_path" "$shot_dir/lyrics-edge-${edge_n}.png" "$convert_bin")
    echo "$edge_n $edge_x $edge_w" >> "$lyrics_edge_rects_path"
  done
  while read -r edge_n edge_x edge_w; do
    edge_off=$((edge_x + edge_w - edge_far))
    if [ "${edge_off#-}" -gt 4 ]; then
      fail "the card left the screen's far padding while its width morphed: frame $edge_n x=$edge_x w=$edge_w, far edge $((edge_x + edge_w)) against $edge_far"
    fi
  done < "$lyrics_edge_rects_path"
  echo "SMOKE_LYRICS_EDGE $(tr '\n' ';' < "$lyrics_edge_rects_path")"

  if [ ! -s "$lyrics_status_none_path" ]; then
    fail "no media lyrics status produced after switching to the untimed track"
  fi
  cat "$lyrics_status_none_path"; echo
  echo "SMOKE_LYRICS_NONE $lyrics_status_none_path"
  if ! grep -qF '"state":"none"' "$lyrics_status_none_path"; then
    fail "media lyrics did not reach none for the untimed track, got: $(cat "$lyrics_status_none_path")"
  fi
  [ -f "$lyrics_none_png_path" ] || fail "no lyrics-none screenshot produced"
  echo "SMOKE_LYRICS_NONE_PNG $lyrics_none_png_path"

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

  # Selecting track1 back re-arms follow (the other half of the wheel
  # takeover's re-arm claim) and grows the panel back to
  # popupWidthMenuSplit around the centre it already had, which is the
  # centre of the bar cell that opened it: the narrow card's own centre is
  # that number, since nothing clamps a 480-wide card under a centre-region
  # cell. The tolerance is the diff rect's own edge antialiasing; the place
  # this replaces moved the centre by half the growth, 180px.
  if [ ! -s "$lyrics_status_return_path" ]; then
    fail "no media lyrics status produced after returning to the syllable track"
  fi
  if ! "$jq_bin" -e '.follow == true' "$lyrics_status_return_path" > /dev/null 2>&1; then
    fail "selecting the syllable track back did not re-arm follow, got: $(cat "$lyrics_status_return_path")"
  fi
  [ -f "$lyrics_return_narrow_path" ] || fail "no narrow-card frame taken before the return arrival"
  local nx ny nw nh cell_centre
  read -r nx ny nw nh _ < <(lyrics_pane_rect "$lyrics_bare_path" "$lyrics_return_narrow_path" "$convert_bin")
  if ! awk -v w="${nw:-0}" -v want=480 -v tol=30 'BEGIN { exit !(w > want - tol && w < want + tol) }'; then
    fail "the reopened card is not popupWidthWide before the pane arrives (want ~480, got width=$nw)"
  fi
  cell_centre=$((nx + nw / 2))
  [ -s "$lyrics_return_rects_path" ] || fail "no return-burst rects recorded"
  echo "SMOKE_LYRICS_RETURN_RECTS $lyrics_return_rects_path"
  cat "$lyrics_return_rects_path"
  local delay rx ry rw rh last_w last_x centre off
  while read -r delay rx ry rw rh; do
    centre=$((rx + rw / 2))
    off=$((centre - cell_centre))
    if [ "${off#-}" -gt 8 ]; then
      fail "the card left its cell's centre during the return arrival: cell centre $cell_centre, card centre $centre at +${delay}s (x=$rx w=$rw)"
    fi
    last_w="$rw"
    last_x="$rx"
  done < "$lyrics_return_rects_path"
  [ -n "$last_w" ] || fail "no return-burst frame produced a panel rect at all"
  if ! awk -v w="${last_w:-0}" -v want=840 -v tol=30 'BEGIN { exit !(w > want - tol && w < want + tol) }'; then
    fail "the return burst never settled on popupWidthMenuSplit (want ~840, got width=$last_w)"
  fi
  # And the claim is about the centring rather than a clamp: both ends of
  # the settled card are clear of the screen's own padding.
  if [ "$last_x" -le 16 ] || [ $((last_x + last_w)) -ge $((1920 - 16)) ]; then
    fail "the settled card is against the screen's padding, so its place says nothing about its cell: x=$last_x w=$last_w"
  fi
  echo "SMOKE_LYRICS_CENTRE cell centre x=$cell_centre, card centre x=$((last_x + last_w / 2)) with the pane open (narrow width=$nw, settled width=$last_w)"
  [ -f "$shot_dir/lyrics-return-1.6.png" ] && echo "SMOKE_LYRICS_RETURN_SETTLED $shot_dir/lyrics-return-1.6.png"

  # The lit line's own fit (the fixture's line3 ends on one word wider than
  # the pane): the settled return frame is read for the brightest ink in the
  # pane below the header, which is the lit line and nothing else, since
  # every other row is drawn in `mutedForeground` under the depth ramp. A
  # chunk that could not break would run that ink to the viewport's own clip;
  # a broken one stops a `controlPaddingX` short of it. The band starts past
  # the header so the close button's own glyph is not the ink being measured.
  local sx sy sw sh sbody pane_x pane_w band_y band_h ink iw ih ix iy
  read -r sx sy sw sh sbody < <(lyrics_pane_rect "$lyrics_bare_path" "$shot_dir/lyrics-return-1.6.png" "$convert_bin")
  pane_x=$((sx + 480))
  pane_w=$((sw - 480 - 12))
  band_y=$((sy + 100))
  band_h=$((sh - 116))
  if [ "$pane_w" -lt 200 ] || [ "$band_h" -lt 80 ]; then
    fail "the settled return frame gave no lyrics pane to read: rect x=$sx y=$sy w=$sw h=$sh"
  fi
  ink=$("$convert_bin" "$sbody" -crop "${pane_w}x${band_h}+${pane_x}+${band_y}" +repage     -colorspace Gray -threshold 70% -format '%@' info: 2>/dev/null)
  [ -n "$ink" ] || fail "no lit line found in the settled return frame's lyrics pane"
  iw=${ink%%x*}
  ih=${ink#*x}; ih=${ih%%+*}
  ix=${ink#*+}; ix=${ix%%+*}
  iy=${ink##*+}
  echo "SMOKE_LYRICS_FIT lit ink ends at x=$((ix + iw)) of the pane's own $pane_w, over $ih rows of it (ink ${ink})"
  if [ $((ix + iw)) -gt $((pane_w - 14)) ]; then
    fail "the lit line ran to the pane's own clip: ink ends at $((ix + iw)) of $pane_w, so a chunk wider than the pane never broke"
  fi

  # The reopen (M69): the wheel had the column, the panel was shut with the
  # same track still playing and opened again, and nothing but the open
  # itself could have put follow back.
  if [ ! -s "$lyrics_status_reopen_path" ]; then
    fail "no media lyrics status produced after the panel was closed and reopened"
  fi
  cat "$lyrics_status_reopen_path"; echo
  echo "SMOKE_LYRICS_REOPEN $lyrics_status_reopen_path"
  [ -f "$lyrics_reopen_png_path" ] && echo "SMOKE_LYRICS_REOPEN_PNG $lyrics_reopen_png_path"
  if ! "$jq_bin" -e '.follow == true' "$lyrics_status_reopen_path" > /dev/null 2>&1; then
    fail "closing and reopening the panel left the column parked where the wheel put it, got: $(cat "$lyrics_status_reopen_path")"
  fi

  # The two line changes. The band starts past the header for the same reason
  # the fit check above does, and one rect serves every frame since the card
  # does not move through either burst.
  [ -s "$lyrics_burst_index_path" ] || fail "no line-change burst frames were taken"
  local burst_name burst_frame burst_body bx by bw bh
  burst_name=$(tail -1 "$lyrics_burst_index_path")
  read -r bx by bw bh burst_body < <(lyrics_pane_rect "$lyrics_bare_path" "$shot_dir/lyrics-burst-${burst_name}.png" "$convert_bin")
  local burst_crop="$((bw - 480 - 12))x$((bh - 116))+$((bx + 480))+$((by + 100))"
  if [ "$((bw - 480 - 12))" -lt 200 ] || [ "$((bh - 116))" -lt 80 ]; then
    fail "the line-change burst gave no lyrics pane to read: rect x=$bx y=$by w=$bw h=$bh"
  fi
  : > "$lyrics_burst_profile_path"
  local burst_failures="" peak_row last_row ink_rows
  while read -r burst_name; do
    burst_frame="$shot_dir/lyrics-burst-${burst_name}.png"
    [ -f "$burst_frame" ] || fail "line-change burst frame $burst_name was never taken"
    read -r peak_row last_row ink_rows < <(lyrics_ink_profile "$(lyrics_burst_body "$burst_frame")" "$burst_crop")
    printf '%s %s %s %s\n' "$burst_name" "$peak_row" "$last_row" "$ink_rows" >> "$lyrics_burst_profile_path"
    # Eight inked rows is a third of what any of these frames carries: it
    # separates a pane mid-change from one that has emptied out, and says
    # nothing about how many lines happen to be under the lit one, which the
    # fixture's own last line answers with none.
    if [ "${ink_rows:-0}" -lt 8 ]; then
      burst_failures="$burst_failures $burst_name(inkRows=$ink_rows)"
    fi
  done < "$lyrics_burst_index_path"
  echo "SMOKE_LYRICS_BURST $lyrics_burst_profile_path"
  cat "$lyrics_burst_profile_path"
  [ -f "$shot_dir/lyrics-burst-a-5.png" ] && echo "SMOKE_LYRICS_BURST_A $shot_dir/lyrics-burst-a-5.png"
  [ -f "$shot_dir/lyrics-burst-b-5.png" ] && echo "SMOKE_LYRICS_BURST_B $shot_dir/lyrics-burst-b-5.png"
  [ -z "$burst_failures" ] || fail "a line change emptied the pane out at:$burst_failures"

  # And the lit row is on one place across the tail of each burst: the last
  # five frames of a burst span a second and a half, well past the 500ms the
  # column's own travel takes, so a row still moving there is one whose own
  # box is still settling under it.
  local burst_phase tail_peaks first_peak
  for burst_phase in a b; do
    tail_peaks=$(grep "^${burst_phase}-" "$lyrics_burst_profile_path" | tail -5 | awk '{ print $2 }')
    first_peak=$(printf '%s\n' "$tail_peaks" | head -1)
    [ -n "$first_peak" ] || fail "burst $burst_phase produced no ink profile at all"
    while read -r peak_row; do
      if [ "$((peak_row - first_peak))" -gt 2 ] || [ "$((first_peak - peak_row))" -gt 2 ]; then
        fail "the lit row was still moving at the end of burst $burst_phase: peaks $(printf '%s' "$tail_peaks" | tr '\n' ' ')"
      fi
    done < <(printf '%s\n' "$tail_peaks")
  done
  echo "SMOKE_LYRICS_BURST_SETTLED a=$(grep '^a-' "$lyrics_burst_profile_path" | tail -5 | awk '{ print $2 }' | tr '\n' ' ')b=$(grep '^b-' "$lyrics_burst_profile_path" | tail -5 | awk '{ print $2 }' | tr '\n' ' ')"
}
