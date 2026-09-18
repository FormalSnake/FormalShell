# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, iso_home, the *_bin paths and fail()
# --frame-adaptive: the screen frame's ring wearing the wingpanel band's own
# paint (M62). With `frame.thickness` set the bar hands its band to
# FrameRing, so the habit is only visible at all if the ring reads the same
# sampler; this is the owner's own layout, a left bar inside a frame, and it
# reads the ring's TOP edge, which no bar ever touches.
#
# Four wallpapers driven into one session, and a fifth case that changes no
# wallpaper at all:
#   a flat #e6e6e6 field (mean 230, no spread)  -> dark, nothing drawn
#   a flat #1e1e1e field (mean 30, no spread)   -> light, nothing drawn
#   top half white, bottom half black           -> translucentDark, black 0.3
#   the dark field with the fixture window full -> maximized, solid
#   the busy field again with bar.paint pinned  -> light, nothing drawn
# The fourth ring is not in its frame, for the reason --bar-adaptive gives:
# Hyprland draws a fullscreen window above the layer the bar is on, so that
# case is asserted off `bar paint` and the whole-state dump alone.
#
# The fifth is the point of the key. The owner's wallpaper is a dark forest
# edge whose spread trips wingpanel's busy rule, so the rule fills the band
# black at 0.3 and the frame with it; `bar.paint: "transparent"` keeps the
# rule for the ink and drops the fill, which is what elementary shows over a
# calm sky. It is driven by moving a second settings.json over the first, the
# write config_reload.sh's header names as the one a file watch has always
# seen, so the only thing that changes between the third case and this one is
# that key.
#
# It owns `theme`, `bar` and `frame`, so it combines with none of the legs
# that write them.
leg_frame_adaptive_flag="--frame-adaptive"
leg_frame_adaptive_order=191
leg_frame_adaptive_needs="convert jq"
# The base run's own focused window is what goes fullscreen for the fourth
# case, the same way --fullscreen takes it over.
leg_frame_adaptive_fixture_window=keep

frame_adaptive_bright_wp="$shot_dir/frame-adaptive-bright.png"
frame_adaptive_dark_wp="$shot_dir/frame-adaptive-dark.png"
frame_adaptive_busy_wp="$shot_dir/frame-adaptive-busy.png"

frame_adaptive_bright_png="$shot_dir/frame-adaptive-bright-ring.png"
frame_adaptive_dark_png="$shot_dir/frame-adaptive-dark-ring.png"
frame_adaptive_busy_png="$shot_dir/frame-adaptive-busy-ring.png"
frame_adaptive_max_png="$shot_dir/frame-adaptive-maximized-ring.png"
frame_adaptive_pin_png="$shot_dir/frame-adaptive-pinned-ring.png"

frame_adaptive_bright_json="$shot_dir/frame-adaptive-bright.json"
frame_adaptive_dark_json="$shot_dir/frame-adaptive-dark.json"
frame_adaptive_busy_json="$shot_dir/frame-adaptive-busy.json"
frame_adaptive_max_json="$shot_dir/frame-adaptive-maximized.json"
frame_adaptive_pin_json="$shot_dir/frame-adaptive-pinned.json"
frame_adaptive_max_dump="$shot_dir/frame-adaptive-maximized-dump.json"
frame_adaptive_max_clients="$shot_dir/frame-adaptive-maximized-clients.json"
frame_adaptive_pin_dump="$shot_dir/frame-adaptive-pinned-dump.json"
frame_adaptive_layers="$shot_dir/frame-adaptive-layers.json"
frame_adaptive_monitors="$shot_dir/frame-adaptive-monitors.json"
frame_adaptive_pin_settings="$shot_dir/frame-adaptive-settings-pinned.json"

# The ring's own rows along the TOP edge, which a left bar never reaches: the
# band is 24px deep, so rows 4 to 11 are ring and nothing else. The busy
# wallpaper's white half is the top one, so black at 0.3 lands at 178 there
# and is telling apart from the bare 255 the pin leaves.
frame_adaptive_patch="40x8+1200+4"

leg_frame_adaptive_validate() {
  if leg_on frame || leg_on bar_adaptive || leg_on bar_position || leg_on config_reload; then
    echo "usage: --frame-adaptive writes theme, bar and frame itself and cannot combine with --frame, --bar-adaptive, --bar-position or --config-reload" >&2
    exit 1
  fi
}

leg_frame_adaptive_fixture() {
  # --pantheon pins the same preset; two "theme" keys in one settings.json
  # would be one object silently winning over the other.
  if ! leg_on pantheon; then
    settings_fragment ', "theme": {"preset": "pantheon"}'
  fi
  # The owner's own layout: the ring all round the output with the bar's band
  # down the left edge of it.
  settings_fragment ', "frame": {"thickness": 24, "radius": 20}'
  # The rule itself is the claim, and pantheon's own table pins the band
  # transparent, so the key puts the rule back; the pinned case sets it
  # again on its own.
  settings_fragment ', "bar": {"position": "left", "paint": "auto"}'
  settings_fragment ', "fullscreen": {"hideChrome": false}'
  $convert_bin -size 1920x1080 xc:'#e6e6e6' "$frame_adaptive_bright_wp"
  $convert_bin -size 1920x1080 xc:'#1e1e1e' "$frame_adaptive_dark_wp"
  # Split across the screen rather than down it: the band the sampler reads
  # is the bar's own edge, so a left bar reads a five-column strip of the
  # wallpaper and a vertical split would hand it one flat colour. Half white
  # over half black puts the spread in that strip and still leaves the ring's
  # top edge over the white half, where black at 0.3 is telling.
  $convert_bin -size 1920x1080 xc:black -fill white \
    -draw "rectangle 0,0 1919,539" "$frame_adaptive_busy_wp"
}

leg_frame_adaptive_timing() {
  leg_timing 58 115
}

leg_frame_adaptive_drive() {
  local script="$shot_dir/frame-adaptive-drive.sh"
  local settings_path="$iso_home/.config/formalshell/settings.json"
  write_script "$script" <<EOS
#!/usr/bin/env bash
# One case per block: set the wallpaper, let the retheme and the sampler
# settle, then read the shell's own answer and photograph the ring.
sleep 5
"$hyprctl_bin" -j layers > "$frame_adaptive_layers" 2>&1
"$hyprctl_bin" -j monitors > "$frame_adaptive_monitors" 2>&1

"$qs_bin" ipc -p "$shell_path" call wallpaper set "$frame_adaptive_bright_wp" > /dev/null 2>&1
sleep 6
"$qs_bin" ipc -p "$shell_path" call bar paint > "$frame_adaptive_bright_json" 2>&1
"$grim_bin" "$frame_adaptive_bright_png" > /dev/null 2>&1

"$qs_bin" ipc -p "$shell_path" call wallpaper set "$frame_adaptive_dark_wp" > /dev/null 2>&1
sleep 6
"$qs_bin" ipc -p "$shell_path" call bar paint > "$frame_adaptive_dark_json" 2>&1
"$grim_bin" "$frame_adaptive_dark_png" > /dev/null 2>&1

"$qs_bin" ipc -p "$shell_path" call wallpaper set "$frame_adaptive_busy_wp" > /dev/null 2>&1
sleep 6
"$qs_bin" ipc -p "$shell_path" call bar paint > "$frame_adaptive_busy_json" 2>&1
"$grim_bin" "$frame_adaptive_busy_png" > /dev/null 2>&1

# The window over the output, on the dark field, so the paint can only be the
# window's doing: the same wallpaper read \`light\` two cases earlier.
"$qs_bin" ipc -p "$shell_path" call wallpaper set "$frame_adaptive_dark_wp" > /dev/null 2>&1
sleep 5
"$hyprctl_bin" dispatch fullscreen 2 > /dev/null 2>&1
sleep 6
"$qs_bin" ipc -p "$shell_path" call bar paint > "$frame_adaptive_max_json" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug dump > "$frame_adaptive_max_dump" 2>&1
"$hyprctl_bin" -j clients > "$frame_adaptive_max_clients" 2>&1
"$grim_bin" "$frame_adaptive_max_png" > /dev/null 2>&1
"$hyprctl_bin" dispatch fullscreen 0 > /dev/null 2>&1
sleep 2

# The busy field back, unpinned, then the same field with bar.paint pinned:
# one key apart, so the fill going away is the key's doing and nothing else's.
"$qs_bin" ipc -p "$shell_path" call wallpaper set "$frame_adaptive_busy_wp" > /dev/null 2>&1
sleep 6
"$jq_bin" '.bar.paint = "transparent"' "$settings_path" > "$frame_adaptive_pin_settings" 2>&1
mv "$frame_adaptive_pin_settings" "$settings_path"
sleep 10
"$qs_bin" ipc -p "$shell_path" call bar paint > "$frame_adaptive_pin_json" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug dump > "$frame_adaptive_pin_dump" 2>&1
"$grim_bin" "$frame_adaptive_pin_png" > /dev/null 2>&1
EOS
  echo "exec-once = bash $script"
}

_frame_adaptive_paint() {
  "$jq_bin" -r '.[0].paint.paint // "none"' "$1" 2>/dev/null
}

_frame_adaptive_numbers() {
  "$jq_bin" -r '.[0].paint | "mean=\(.mean | floor) std=\(.std | floor) pin=\(.pin) pinned=\(.pinned) fullscreen=\(.fullscreen)"' \
    "$1" 2>/dev/null
}

# The mean luminance of the ring patch, 0..255, off one channel: every
# expected ring here is grey over a grey wallpaper, and a colourspace
# conversion is one linearization away from answering in numbers these
# expectations are not written in.
_frame_adaptive_ring() {
  $convert_bin "$1" -crop "$frame_adaptive_patch" +repage \
    -format '%[fx:int(mean.r*255+0.5)]' info: 2>/dev/null
}

# One case: the reported paint, then the ring it drew. `unseen` reports the
# patch and asserts nothing about it, for the one case whose ring is behind a
# fullscreen window.
_frame_adaptive_case() {
  local label="$1" json="$2" png="$3" want="$4" want_ring="$5"
  local got numbers ring
  [ -s "$json" ] || fail "$label: no bar paint reply produced at $json"
  [ -f "$png" ] || fail "$label: no frame produced at $png"
  got=$(_frame_adaptive_paint "$json")
  numbers=$(_frame_adaptive_numbers "$json")
  ring=$(_frame_adaptive_ring "$png")
  echo "$label: paint=$got $numbers ring=$ring (want $want, ring ~$want_ring)"
  if [ "$got" != "$want" ]; then
    fail "$label: the band reports '$got', not '$want' ($numbers)"
  fi
  if [ -z "$ring" ]; then
    fail "$label: could not read the ring patch $frame_adaptive_patch out of $png"
  fi
  if [ "$want_ring" != "unseen" ]; then
    if [ "$ring" -lt "$((want_ring - 12))" ] || [ "$ring" -gt "$((want_ring + 12))" ]; then
      fail "$label: the ring drew $ring over the top patch, not ~$want_ring, so the $want paint is not what reached the frame"
    fi
  fi
  frame_adaptive_summary="$frame_adaptive_summary $label=$got/$ring"
}

leg_frame_adaptive_assert() {
  local box mw mh
  frame_adaptive_summary=""

  # The ring has to be up at all: with the frame on, the bar's window is the
  # whole output and the ring is what fills it. A window the size of a strip
  # would leave every patch below reading the bare wallpaper and every case
  # passing for the wrong reason.
  [ -s "$frame_adaptive_layers" ] || fail "no layer dump produced"
  [ -s "$frame_adaptive_monitors" ] || fail "no monitor dump produced"
  box=$("$jq_bin" -r '[.[] | .levels[] | .[] | select(.namespace == "formalshell:bar")] | first | "\(.x) \(.y) \(.w) \(.h)"' "$frame_adaptive_layers" 2>/dev/null)
  read -r mw mh <<< "$("$jq_bin" -r 'first | "\(.width / .scale | floor) \(.height / .scale | floor)"' "$frame_adaptive_monitors")"
  echo "framed bar window: $box on ${mw}x${mh}"
  [ "$box" = "0 0 $mw $mh" ] \
    || fail "the framed bar's window should span the whole output, so the ring is what the patches read; got: $box"

  # A flat bright field: nothing busy about it, so the ring draws no fill at
  # all and the patch is the wallpaper's own 230.
  _frame_adaptive_case bright "$frame_adaptive_bright_json" "$frame_adaptive_bright_png" dark 230
  # A flat dark one: the same bare ring, light ink on the bar, 30.
  _frame_adaptive_case dark "$frame_adaptive_dark_json" "$frame_adaptive_dark_png" light 30
  # Half white over half black: the left band carries the spread, so the ring
  # takes black at 0.3 over the white half of the top edge, which is 178.
  _frame_adaptive_case busy "$frame_adaptive_busy_json" "$frame_adaptive_busy_png" translucentDark 178
  # A window covering the output: solid black, whatever the wallpaper says.
  _frame_adaptive_case maximized "$frame_adaptive_max_json" "$frame_adaptive_max_png" maximized unseen
  # The same busy field with bar.paint pinned: the ink still follows the
  # band's own mean (127, under the bright threshold, so light ink) and the
  # fill is gone, leaving the white half at its own 255.
  _frame_adaptive_case pinned "$frame_adaptive_pin_json" "$frame_adaptive_pin_png" light 255

  local fs_windows
  [ -s "$frame_adaptive_max_clients" ] || fail "maximized: no client list produced"
  fs_windows=$("$jq_bin" -r '[.[] | select(.fullscreen != 0 and .fullscreen != false)] | length' \
    "$frame_adaptive_max_clients" 2>/dev/null)
  echo "maximized: fullscreen windows per hyprctl: $fs_windows"
  [ "${fs_windows:-0}" -ge 1 ] || fail "maximized: no window was actually fullscreen; the solid paint would be untested"
  "$jq_bin" -e '.bar[0].paint.paint == "maximized"' "$frame_adaptive_max_dump" > /dev/null 2>&1 \
    || fail "maximized: debug dump reports bar[0].paint of $("$jq_bin" -c '.bar[0].paint' "$frame_adaptive_max_dump")"

  # The pin is reported as a pin, on both routes, and the four cases before it
  # are reported as the rule: a key that silently became the default would
  # otherwise pass the pixel assert on a wallpaper that happened to agree.
  "$jq_bin" -e '.[0].paint.pinned == false and .[0].paint.pin == "auto"' "$frame_adaptive_busy_json" > /dev/null 2>&1 \
    || fail "busy: the band reports a pin it was never given: $("$jq_bin" -c '.[0].paint' "$frame_adaptive_busy_json")"
  "$jq_bin" -e '.[0].paint.pinned == true and .[0].paint.pin == "transparent"' "$frame_adaptive_pin_json" > /dev/null 2>&1 \
    || fail "pinned: the band does not report the pin: $("$jq_bin" -c '.[0].paint' "$frame_adaptive_pin_json")"
  "$jq_bin" -e '.bar[0].paint.pinned == true' "$frame_adaptive_pin_dump" > /dev/null 2>&1 \
    || fail "pinned: debug dump reports bar[0].paint of $("$jq_bin" -c '.bar[0].paint' "$frame_adaptive_pin_dump")"

  echo "SMOKE_FRAME_ADAPTIVE ok$frame_adaptive_summary"
  echo "SMOKE_FRAME_ADAPTIVE_BRIGHT $frame_adaptive_bright_png"
  echo "SMOKE_FRAME_ADAPTIVE_DARK $frame_adaptive_dark_png"
  echo "SMOKE_FRAME_ADAPTIVE_BUSY $frame_adaptive_busy_png"
  echo "SMOKE_FRAME_ADAPTIVE_MAXIMIZED $frame_adaptive_max_png"
  echo "SMOKE_FRAME_ADAPTIVE_PINNED $frame_adaptive_pin_png"
}
