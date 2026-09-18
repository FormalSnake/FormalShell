# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --app-grid: the launcher's app results drawn as a grid of icons with the
# app's name under each one (`menu.appGrid`), and the row list it still is
# with the key absent.
#
# The session's XDG_DATA_DIRS is the isolated HOME alone, so the installed-app
# list is exactly the six entries staged below and every count here is a real
# number rather than whatever the VM happens to ship. One of them carries a
# solid green icon nothing else in the palette comes near, which is how the
# frame is read: at 64px the cell's icon covers thousands of pixels of that
# colour, where the same entry in a row list covers a couple of hundred. That
# is the whole claim a screenshot can make about a grid, and `menu status`'s
# `view` and `columns` make the rest.
#
# Real keystrokes rather than IPC for the cursor: Right has to move it by one
# cell and Down by a column count, and only a Qt key event through the
# compositor proves the grid answers the arrows at all (the same reason
# --panel-keys exists). `cursor` on `menu status` is what reads the answer.
#
# The key's default is the other half of the leg, and it is the theme's
# rather than a constant (M60 P6): the row list under Omarchy's launcher
# habit, Slingshot's grid under pantheon's. Config.qml re-reads settings.json
# on a write, so the key is deleted underneath the running shell, the
# launcher resummoned, and the level has to come back as the habit's own
# route; then it is put back, which leaves the grid up for the run's own
# frame. Ridden by --pantheon it is the grid the deletion lands on, which is
# where that default is read.
leg_app_grid_flag="--app-grid"
leg_app_grid_order=26
leg_app_grid_needs="convert wtype jq"

# This leg's own clock: the launcher covers the whole output, so under
# --wallpaper it starts after that leg's last frame, the rule menu_t0 draws.
app_grid_t0() {
  if leg_on wallpaper; then echo 16; else echo 3; fi
}

app_grid_dir="$iso_home/.local/share/applications"
app_grid_icon_dir="$iso_home/.local/share/icons/hicolor"
app_grid_marker="$shot_dir/app-grid-launched.txt"
app_grid_settings="$iso_home/.config/formalshell/settings.json"
app_grid_settings_on="$shot_dir/app-grid-settings-on.json"
app_grid_settings_off="$shot_dir/app-grid-settings-off.json"

app_grid_png="$shot_dir/app-grid.png"
app_grid_mixed_png="$shot_dir/app-grid-mixed.png"
app_grid_rows_png="$shot_dir/app-grid-rows.png"
app_grid_open_path="$shot_dir/app-grid-status-open.json"
app_grid_right_path="$shot_dir/app-grid-status-right.json"
app_grid_down_path="$shot_dir/app-grid-status-down.json"
app_grid_narrow_path="$shot_dir/app-grid-status-narrow.json"
app_grid_mixed_path="$shot_dir/app-grid-status-mixed.json"
app_grid_off_path="$shot_dir/app-grid-status-off.json"
app_grid_probe_path="$shot_dir/app-grid-probe.json"
app_grid_mixed_query_path="$shot_dir/app-grid-mixed-query.json"

# The icon the frame is read by, and the one every other entry wears so the
# green count is one cell's worth and not five.
app_grid_mark="#2F9E44"
app_grid_other="#2A6FAE"

app_grid_entry() {
  local file="$1" name="$2" icon="$3" exec_line="$4"
  {
    echo "[Desktop Entry]"
    echo "Type=Application"
    echo "Name=$name"
    echo "Exec=$exec_line"
    if [ -n "$icon" ]; then echo "Icon=$icon"; fi
  } > "$app_grid_dir/$file"
}

leg_app_grid_fixture() {
  settings_fragment ', "menu": {"appGrid": true}'

  mkdir -p "$app_grid_icon_dir/48x48/apps" "$app_grid_icon_dir/128x128/apps"
  local size
  for size in 48 128; do
    $convert_bin -size "${size}x${size}" "xc:$app_grid_mark" \
      "$app_grid_icon_dir/${size}x${size}/apps/formalshell-app-grid-mark.png"
    $convert_bin -size "${size}x${size}" "xc:$app_grid_other" \
      "$app_grid_icon_dir/${size}x${size}/apps/formalshell-app-grid-plain.png"
  done
  # QIconLoader enumerates no directories at all without an index.theme, so a
  # bare PNG in the right place still resolves to no icon.
  cat > "$app_grid_icon_dir/index.theme" <<'EOF'
[Icon Theme]
Name=Hicolor
Comment=Fallback icon theme
Directories=48x48/apps,128x128/apps

[48x48/apps]
Size=48
Context=Applications
Type=Threshold

[128x128/apps]
Size=128
Context=Applications
Type=Threshold
EOF

  # Six entries: the launch probe under a name nothing else here matches, four
  # ordinary ones so the grid wraps past its own column count, and one long
  # name with no icon at all, which is both the elision case and the honest
  # no-icon cell.
  app_grid_entry "formalshell-probe.desktop" "Grid Launch Probe" \
    "formalshell-app-grid-mark" "touch $app_grid_marker"
  app_grid_entry "formalshell-files.desktop" "Files Fixture" \
    "formalshell-app-grid-plain" "true"
  app_grid_entry "formalshell-mail.desktop" "Mail Fixture" \
    "formalshell-app-grid-plain" "true"
  app_grid_entry "formalshell-music.desktop" "Music Fixture" \
    "formalshell-app-grid-plain" "true"
  app_grid_entry "formalshell-photos.desktop" "Photos Fixture" \
    "formalshell-app-grid-plain" "true"
  app_grid_entry "formalshell-long.desktop" "A Very Long Fixture Application Name" \
    "" "true"
}

leg_app_grid_timing() {
  local t0
  t0=$(app_grid_t0)
  leg_timing $((t0 + 29)) $((t0 + 64))
}

leg_app_grid_drive() {
  local t0 script="$shot_dir/app-grid-drive.sh"
  t0=$(app_grid_t0)
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep $t0
cp "$app_grid_settings" "$app_grid_settings_on"
"$qs_bin" ipc -p "$shell_path" call menu summon apps > /dev/null 2>&1
sleep 2
"$grim_bin" "$app_grid_png" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$app_grid_open_path" 2>&1
"$wtype_bin" -k Right
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu status > "$app_grid_right_path" 2>&1
"$wtype_bin" -k Down
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu status > "$app_grid_down_path" 2>&1
# A token only the probe entry carries, so the narrowed grid is one cell and
# the cursor Enter lands on is unambiguous.
"$qs_bin" ipc -p "$shell_path" call menu filter probe > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call debug query probe > "$app_grid_probe_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$app_grid_narrow_path" 2>&1
"$wtype_bin" -k Return
sleep 2
# A root query that ranks an app alongside routes: the grid takes the apps
# and the rest draw as rows under it.
"$qs_bin" ipc -p "$shell_path" call menu summon "" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu filter app > /dev/null 2>&1
sleep 2
"$grim_bin" "$app_grid_mixed_png" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$app_grid_mixed_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug query app > "$app_grid_mixed_query_path" 2>&1
# Down onto the row under the grid queues its reveal for the next tick, and a
# new query inside that tick rebuilds the rows it was queued from. Verify reads
# the shell's own log for what a reveal evaluated after its row was gone says.
"$wtype_bin" -k Down
"$qs_bin" ipc -p "$shell_path" call menu filter ap > /dev/null 2>&1
"$wtype_bin" -k Down
"$qs_bin" ipc -p "$shell_path" call menu filter zzzz > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
# The key deleted underneath the running shell. Written back through the same
# inode rather than moved over, so the config watch sees a write and not a
# file it is no longer holding.
"$jq_bin" 'del(.menu.appGrid)' "$app_grid_settings" > "$app_grid_settings_off" 2>&1
cat "$app_grid_settings_off" > "$app_grid_settings"
sleep 2
"$qs_bin" ipc -p "$shell_path" call menu summon apps > /dev/null 2>&1
sleep 2
"$grim_bin" "$app_grid_rows_png" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$app_grid_off_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
cat "$app_grid_settings_on" > "$app_grid_settings"
sleep 2
"$qs_bin" ipc -p "$shell_path" call menu summon apps > /dev/null 2>&1
EOF
  echo "exec-once = bash $script"
}

# How many pixels of the probe entry's own colour the frame carries. Two
# passes rather than one: everything off that colour goes black first, so a
# palette that is already near-white somewhere else cannot be counted as a
# match by the second.
app_grid_mark_pixels() {
  $convert_bin "$1" -fuzz 12% -fill black +opaque "$app_grid_mark" \
    -fuzz 12% -fill white -opaque "$app_grid_mark" \
    -colorspace Gray -format '%[fx:int(mean*w*h+0.5)]' info: 2>/dev/null
}

app_grid_field() {
  "$jq_bin" -r ".$2 // empty" "$1" 2>/dev/null
}

leg_app_grid_assert() {
  local f
  for f in "$app_grid_open_path" "$app_grid_right_path" "$app_grid_down_path" \
    "$app_grid_narrow_path" "$app_grid_mixed_path" "$app_grid_off_path" \
    "$app_grid_probe_path" "$app_grid_mixed_query_path"; do
    [ -s "$f" ] || fail "no app-grid artifact produced at $f"
  done
  for f in "$app_grid_png" "$app_grid_mixed_png" "$app_grid_rows_png"; do
    [ -f "$f" ] || fail "no app-grid screenshot produced at $f"
  done

  cat "$app_grid_open_path"; echo
  local columns rows cursor
  if [ "$(app_grid_field "$app_grid_open_path" view)" != "appGrid" ]; then
    fail "the apps route did not report the grid, got: $(cat "$app_grid_open_path")"
  fi
  columns=$(app_grid_field "$app_grid_open_path" columns)
  rows=$(app_grid_field "$app_grid_open_path" rows)
  if [ -z "$columns" ] || [ "$columns" -le 1 ]; then
    fail "the app grid rendered ${columns:-0} column(s), so it is still a row list"
  fi
  if [ -z "$rows" ] || [ "$rows" -lt 6 ]; then
    fail "the apps route listed ${rows:-0} entries, fewer than the six staged: $(cat "$app_grid_open_path")"
  fi
  # A grid draws no group headings, so it must not report any either.
  if ! grep -q '"sections":\[\]' "$app_grid_open_path"; then
    fail "the app grid claimed group headings it cannot draw, got: $(cat "$app_grid_open_path")"
  fi
  echo "SMOKE_APP_GRID $app_grid_png ($rows apps in $columns columns)"

  # The icon at cell size. A row list draws the same entry at the body font's
  # own height, which is two orders of magnitude fewer pixels, so this number
  # is what says the frame is a grid of icons rather than a list carrying
  # them.
  local marked
  marked=$(app_grid_mark_pixels "$app_grid_png")
  if [ -z "$marked" ] || [ "$marked" -lt 2500 ]; then
    fail "the probe entry's icon covers ${marked:-0} pixels of the grid, too few to be a 64px cell icon"
  fi
  echo "SMOKE_APP_GRID_ICON ${marked}px of the probe entry's own colour"

  # The arrows: one cell right, then a whole row of cells down.
  cat "$app_grid_right_path"; echo
  cursor=$(app_grid_field "$app_grid_right_path" cursor)
  if [ "$cursor" != "1" ]; then
    fail "Right moved the grid cursor to ${cursor:-none}, not to the next cell"
  fi
  cat "$app_grid_down_path"; echo
  cursor=$(app_grid_field "$app_grid_down_path" cursor)
  if [ "$cursor" != "$((1 + columns))" ]; then
    fail "Down moved the grid cursor to ${cursor:-none}, not one row of $columns cells on from 1"
  fi

  # A typed query narrows the grid to the one entry that carries the token,
  # and the level is still a grid rather than falling back to rows.
  cat "$app_grid_narrow_path"; echo
  if [ "$(app_grid_field "$app_grid_narrow_path" view)" != "appGrid" ] \
    || [ "$(app_grid_field "$app_grid_narrow_path" rows)" != "1" ]; then
    fail "'probe' did not narrow the grid to the one entry, got: $(cat "$app_grid_narrow_path")"
  fi
  cat "$app_grid_probe_path"; echo
  if [ "$("$jq_bin" -r '.[0].label // ""' "$app_grid_probe_path")" != "Grid Launch Probe" ]; then
    fail "'probe' did not rank the probe entry first: $(cat "$app_grid_probe_path")"
  fi
  # Enter on the cell runs the entry's own Exec through the same path a row
  # takes, and the entry's Exec is the only thing that can write this file.
  if [ ! -f "$app_grid_marker" ]; then
    fail "Enter on the cursor cell did not launch the probe entry (no $app_grid_marker)"
  fi
  echo "SMOKE_APP_GRID_LAUNCH $app_grid_marker"

  # Mixed: the apps take the grid, everything else the query ranked draws as
  # rows under it.
  cat "$app_grid_mixed_path"; echo
  if grep -E 'AppGridView\.qml.*(ReferenceError|TypeError)' "$shell_log_path" > /dev/null 2>&1; then
    fail "the grid view threw in the shell's log: $(grep -E 'AppGridView\.qml.*(ReferenceError|TypeError)' "$shell_log_path" | head -2)"
  fi
  if [ "$(app_grid_field "$app_grid_mixed_path" view)" != "appGrid" ]; then
    fail "a root query ranking apps did not draw the grid, got: $(cat "$app_grid_mixed_path")"
  fi
  cat "$app_grid_mixed_query_path"; echo
  local app_hits other_hits
  app_hits=$("$jq_bin" '[.[] | select(.kind == "app")] | length' "$app_grid_mixed_query_path" 2>/dev/null)
  other_hits=$("$jq_bin" '[.[] | select(.kind != "app")] | length' "$app_grid_mixed_query_path" 2>/dev/null)
  if [ -z "$app_hits" ] || [ "$app_hits" -lt 1 ] || [ -z "$other_hits" ] || [ "$other_hits" -lt 1 ]; then
    fail "'app' ranked ${app_hits:-0} app(s) and ${other_hits:-0} other row(s), so nothing here is mixed"
  fi
  echo "SMOKE_APP_GRID_MIXED $app_grid_mixed_png ($app_hits in the grid, $other_hits as rows)"

  # The default: with the key gone the route is the one the live theme's
  # launcher habit asks for, and every entry the grid had is still on it.
  cat "$app_grid_off_path"; echo
  if [ "$(app_grid_field "$app_grid_off_path" rows)" != "$rows" ]; then
    fail "the default route lost entries the grid had, got: $(cat "$app_grid_off_path")"
  fi
  marked=$(app_grid_mark_pixels "$app_grid_rows_png")
  if leg_on pantheon; then
    # `menu status` alone here, no pixel read: a launcher reopened under the
    # popover emerge comes back with the grid scrolled off its own card
    # (`scrollTop` -391 against a two-row grid), so the frame says nothing
    # about which view drew it until that is fixed.
    if [ "$(app_grid_field "$app_grid_off_path" view)" != "appGrid" ] \
      || [ "$(app_grid_field "$app_grid_off_path" columns)" -le 1 ]; then
      fail "the apps route did not default to the grid under pantheon, got: $(cat "$app_grid_off_path")"
    fi
    echo "SMOKE_APP_GRID_DEFAULT $(app_grid_field "$app_grid_off_path" columns) columns by the launcher habit, no key set"
  else
    if [ "$(app_grid_field "$app_grid_off_path" view)" != "rows" ] \
      || [ "$(app_grid_field "$app_grid_off_path" columns)" != "1" ]; then
      fail "the apps route still drew a grid with menu.appGrid deleted, got: $(cat "$app_grid_off_path")"
    fi
    if [ -z "$marked" ] || [ "$marked" -gt 1000 ]; then
      fail "the row list drew the probe icon over ${marked:-0} pixels, which is still cell-sized"
    fi
    echo "SMOKE_APP_GRID_ROWS $app_grid_rows_png (${marked}px of the probe icon, a row's worth)"
  fi
}
