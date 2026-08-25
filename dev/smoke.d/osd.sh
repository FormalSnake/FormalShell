# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --osd drives the bottom-centre pill three ways off one timeline: a manual
# `osd volume` (osd-manual.png), a real `wpctl set-volume` (the
# AudioService.changed auto-show trigger, this run's own SMOKE_OK frame),
# then `osd brightness` (osd-brightness.png). The VM has a pipewire null
# sink but no backlight device, so the brightness frame proves the surface
# renders that kind honestly (0%, empty track), not that hardware exists.
# The sink is set to a second value first, because pipewire outlives the
# session: re-setting an already-30% sink changes nothing, `changed` never
# fires, and the auto-show leg would photograph an empty screen.
leg_osd_flag="--osd"
leg_osd_order=50
leg_osd_needs="wpctl"

osd_manual_path="$shot_dir/osd-manual.png"
osd_brightness_path="$shot_dir/osd-brightness.png"

leg_osd_timing() {
  # The auto-show trigger lands at 9, and this run's own SMOKE_OK frame is
  # the one it produces. The brightness frame lands at 14.
  leg_timing 10 0 5
}

leg_osd_drive() {
  # Each trigger is screenshotted a second later, well inside the pill's
  # 1.6s auto-hide window, with enough gap between them that the previous
  # card is long gone before the next fires. The sleep-7 set is not
  # photographed: it exists so the sleep-9 one is always a real change.
  local script="$shot_dir/osd-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 4
"$qs_bin" ipc -p "$shell_path" call osd volume > /dev/null 2>&1
sleep 1
"$grim_bin" "$osd_manual_path" > /dev/null 2>&1
sleep 2
"$wpctl_bin" set-volume @DEFAULT_AUDIO_SINK@ 80% > /dev/null 2>&1
sleep 2
"$wpctl_bin" set-volume @DEFAULT_AUDIO_SINK@ 30% > /dev/null 2>&1
sleep 4
"$qs_bin" ipc -p "$shell_path" call osd brightness > /dev/null 2>&1
sleep 1
"$grim_bin" "$osd_brightness_path" > /dev/null 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_osd_assert() {
  if [ ! -f "$osd_manual_path" ]; then
    fail "no osd-manual screenshot produced"
  fi
  echo "SMOKE_OSD_MANUAL $osd_manual_path"
  if [ ! -f "$osd_brightness_path" ]; then
    fail "no osd-brightness screenshot produced"
  fi
  echo "SMOKE_OSD_BRIGHTNESS $osd_brightness_path"
}
