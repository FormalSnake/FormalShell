# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --clipssh-image: the two paths that send an image over ssh without anyone
# first putting it on the clipboard and then finding the Clipssh route.
# `clipssh.autoSendImages` sends every image the moment it lands in history,
# and Shift+Enter on a history row sends that row's file. Both resolve a host
# out of `clipssh.alias` rather than off a row under a cursor, which is the
# half `--clipssh` cannot reach: its rows carry their own alias.
#
# The shim stands in for the binary the same way `--clipssh`'s does, and adds
# the one claim no frame can make. clipssh reads the clipboard and nothing
# else, so on every invocation it records the sha256 of what the clipboard
# actually held next to the alias it was handed. A send that reached
# ClipsshService with the right name while the clipboard still held the last
# transfer's reply text (or nothing) looks exactly like a working one from
# the outside; the digest is what separates them.
#
# The two sends are sequential because ClipsshService takes one transfer at a
# time. The order is load-bearing too: the shim reproduces clipssh's last act
# of wl-copying the remote path back as TEXT, so by the time the row is
# activated the image is off the clipboard, and the second digest matching is
# what proves Shift+Enter put it back rather than riding what the auto-send
# left there. That text is also why the row is reached through `menu filter
# image` rather than by index: it lands in history as a row of its own, ahead
# of the image, and the image row is the only one whose label matches.
leg_clipssh_image_flag="--clipssh-image"
leg_clipssh_image_order=136
leg_clipssh_image_needs="wl-copy wl-paste convert"

clipssh_image_shim_dir="$shot_dir/clipssh-image-shim"
clipssh_image_calls_path="$shot_dir/clipssh-image-calls.txt"
clipssh_image_fixture_path="$shot_dir/clipssh-image.png"
clipssh_image_digest_path="$shot_dir/clipssh-image-digest.txt"
clipssh_image_summon_reply_path="$shot_dir/clipssh-image-summon-reply.txt"
clipssh_image_filter_reply_path="$shot_dir/clipssh-image-filter-reply.txt"
clipssh_image_alt_reply_path="$shot_dir/clipssh-image-alt-reply.txt"
clipssh_image_route_png="$shot_dir/clipssh-image-route.png"

leg_clipssh_image_fixture() {
  # One alias saved and one named, so neither path has anything to ask: the
  # "ask" branch is the launcher drilling into the route, which is
  # `--clipssh`'s own timeline.
  mkdir -p "$iso_home/.clipssh"
  printf '%s\n' 'box=test@10.255.255.7' > "$iso_home/.clipssh/aliases"
  settings_fragment ', "clipssh": {"alias": "box", "autoSendImages": true}'

  # A solid colour at a size nothing else in the run produces, so its digest
  # cannot collide with a screenshot or a thumbnail that happened to reach
  # the clipboard.
  $convert_bin -size 317x181 xc:'#2a6fae' "$clipssh_image_fixture_path"
  # The digest the shim's readings are checked against, taken here rather
  # than in the assert so it is the file that was actually copied.
  sha256sum "$clipssh_image_fixture_path" | cut -d ' ' -f1 > "$clipssh_image_digest_path"

  mkdir -p "$clipssh_image_shim_dir"
  # `<alias> <sha256 of the clipboard>` per invocation, and `none` where the
  # clipboard holds no image at all, which is the failure this leg exists to
  # catch. Fast (no sleep): the second send waits on the first having
  # finished, not on catching it mid-flight.
  cat > "$clipssh_image_shim_dir/clipssh" <<EOF
#!/usr/bin/env bash
digest=\$(wl-paste --no-newline --type image/png 2>/dev/null | sha256sum | cut -d ' ' -f1)
if ! wl-paste --list-types 2>/dev/null | grep -q '^image/png$'; then digest=none; fi
printf '%s %s\n' "\${1:-}" "\$digest" >> "$clipssh_image_calls_path"
printf '\033[0;32mUploaded: /tmp/clipboard-1755180000.png\033[0m\n'
EOF
  chmod +x "$clipssh_image_shim_dir/clipssh"
  # PATH is not in session_env, so this is what Hyprland and everything it
  # spawns inherit, the same route --clipssh's shim takes. wl-paste has to
  # stay reachable by name for the shim's own reading.
  export PATH="$clipssh_image_shim_dir:$(dirname "$wl_paste_bin"):$PATH"
}

leg_clipssh_image_timing() {
  leg_timing 28 65
}

leg_clipssh_image_drive() {
  local script="$shot_dir/clipssh-image-drive.sh"
  # The frame is taken inline rather than on a clock of its own, unlike
  # --clipssh's: the two states that leg photographs are six-second toasts,
  # while the launcher here sits open and unchanging between the filter and
  # the activation, and Shift+Enter closes it the moment it lands. A fixed
  # delay raced that close and photographed an empty desktop.
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 4
# The auto-send's own trigger: nothing here calls clipssh, or the shell. The
# image landing in history is the whole event.
"$wl_copy_bin" --type image/png < "$clipssh_image_fixture_path"
sleep 6
"$qs_bin" ipc -p "$shell_path" call menu summon clipboard > "$clipssh_image_summon_reply_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call menu filter image > "$clipssh_image_filter_reply_path" 2>&1
sleep 2
"$grim_bin" "$clipssh_image_route_png" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu activateAlternate 0 > "$clipssh_image_alt_reply_path" 2>&1
sleep 5
EOF
  echo "exec-once = bash $script"
}

leg_clipssh_image_assert() {
  local want lines
  want=$(cat "$clipssh_image_digest_path")

  if ! grep -q '^ok$' "$clipssh_image_summon_reply_path" 2>/dev/null; then
    fail "menu summon clipboard did not answer ok, got: $(cat "$clipssh_image_summon_reply_path" 2>/dev/null)"
  fi
  if ! grep -q '^ok$' "$clipssh_image_filter_reply_path" 2>/dev/null; then
    fail "menu filter image did not answer ok, got: $(cat "$clipssh_image_filter_reply_path" 2>/dev/null)"
  fi
  if ! grep -q '^ok$' "$clipssh_image_alt_reply_path" 2>/dev/null; then
    fail "menu activateAlternate on the image row did not answer ok, got: $(cat "$clipssh_image_alt_reply_path" 2>/dev/null)"
  fi

  if [ ! -s "$clipssh_image_calls_path" ]; then
    fail "clipssh was never invoked: neither clipssh.autoSendImages nor Shift+Enter reached ClipsshService"
  fi
  cat "$clipssh_image_calls_path"
  lines=$(wc -l < "$clipssh_image_calls_path")
  if [ "$lines" -ne 2 ]; then
    fail "clipssh ran $lines times, want 2 (the auto-send, then Shift+Enter): $(tr '\n' ' ' < "$clipssh_image_calls_path")"
  fi
  # Both invocations, same two claims: the alias came out of clipssh.alias
  # (no row carried it), and the clipboard held the fixture image when
  # clipssh read it.
  if [ "$(cat "$clipssh_image_calls_path")" != "box $want
box $want" ]; then
    fail "want two 'box $want' invocations, got: $(tr '\n' ' ' < "$clipssh_image_calls_path")"
  fi

  if [ ! -f "$clipssh_image_route_png" ]; then
    fail "no clipboard route screenshot produced at $clipssh_image_route_png"
  fi
  echo "SMOKE_CLIPSSH_IMAGE_ROUTE $clipssh_image_route_png"
}
