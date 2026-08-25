# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --gallery opens the dev gallery (Surfaces/Gallery/Gallery.qml), the sheet
# that renders the real shared components against the live theme, and leaves
# it up so the run's own smoke.png is that sheet.
#
# The route has no on-screen state anything else asserts, so `status` is the
# proof it ran: `gallery open` answering ok is not enough on its own, since
# `qs ipc call gallery show` used to resolve to qs's OWN `show` subcommand
# and print an interface listing while the surface never opened. isOpen read
# back afterwards is what caught that.
leg_gallery_flag="--gallery"
leg_gallery_order=220

gallery_log_path="$shot_dir/gallery.log"

# This leg's own clock: the sheet covers the whole output, so under
# --wallpaper it starts past that leg's last frame, the same rule menu_t0
# draws.
gallery_t0() {
  if leg_on wallpaper; then echo 16; else echo 3; fi
}

leg_gallery_timing() {
  local t0
  t0=$(gallery_t0)
  leg_timing $((8 + t0 - 3)) $((40 + t0 - 3))
}

leg_gallery_drive() {
  local t0 script="$shot_dir/gallery-drive.sh"
  t0=$(gallery_t0)
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep $t0
"$qs_bin" ipc -p "$shell_path" call gallery open > "$gallery_log_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call gallery status >> "$gallery_log_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_gallery_assert() {
  echo "SMOKE_GALLERY_IPC $(tr '\n' ' ' < "$gallery_log_path" 2>/dev/null || echo '(no reply)')"
  if ! grep -q '"isOpen":true' "$gallery_log_path" 2>/dev/null; then
    fail "gallery did not report isOpen after open: $(cat "$gallery_log_path" 2>/dev/null)"
  fi
}
