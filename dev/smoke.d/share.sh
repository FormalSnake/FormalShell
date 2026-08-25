# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --share proves the menu's share route in both directions.
#
# Present: a fixture string is copied, `debug query "share"` shows the
# `when`-gated node resolved, `menu summon share` is screenshotted
# (share-menu.png, the CLIPBOARD/PICK FROM HISTORY/RECEIVE rows), and `menu
# activate 0` fires the CLIPBOARD row. What has to come out of that is a real
# `localsend_app <path>` process: upstream's own arg parser drops dash-flags
# and non-path text alike (LoadSelectionFromArgsAction keeps only args that
# pass File(arg).existsSync()), so the copied text can only reach LocalSend
# as a real file. Its final argv element is read off /proc, the file it names
# is read off disk before the process is killed, and its contents must be the
# exact fixture text: proof the text travelled as a file, not that some
# string was passed on argv.
#
# Absent: the honest no-binary state, proven rather than inferred. A shim
# directory mirrors the session's own PATH one level minus any entry named
# localsend_app (every other binary still resolves), and a SECOND formalshell
# is launched with PATH scoped to it, taking the instance lock off the first
# the same way --instance proves the handoff. Two more `debug query "share"`
# passes against the survivor must come back empty, and `menu summon` plus a
# frame (share-menu-absent.png) must show the root menu with no SHARE row.
leg_share_flag="--share"
leg_share_order=230
leg_share_needs="wl-copy"

share_query1_path="$shot_dir/share-query-1.json"
share_query2_path="$shot_dir/share-query-2.json"
share_menu_path="$shot_dir/share-menu.png"
share_pgrep_path="$shot_dir/share-pgrep.txt"
share_cmdline_path="$shot_dir/share-cmdline.txt"
share_tmpfile_path="$shot_dir/share-tmpfile.txt"
share_second_log_path="$shot_dir/share-second.log"
share_instance_status_path="$shot_dir/share-instance-status.json"
share_absent_query1_path="$shot_dir/share-absent-query-1.json"
share_absent_query2_path="$shot_dir/share-absent-query-2.json"
share_menu_absent_path="$shot_dir/share-menu-absent.png"
share_noshare_dir="$shot_dir/share-noshare-shim"

# This leg's own clock: the menu covers the whole output, so under
# --wallpaper it starts past that leg's last frame.
share_t0() {
  if leg_on wallpaper; then echo 14; else echo 2; fi
}

leg_share_fixture() {
  # Not a shim with a fake binary ahead of the real one: the session's real
  # PATH minus that one entry, so every OTHER process the shell spawns (sh
  # for the `when` check itself, wl-paste, matugen) still resolves normally.
  # PATH order is preserved, first directory wins, so this is a faithful
  # mirror rather than a guess at what else needs to be on it.
  local saved_ifs="$IFS" path_dir path_entry entry_name
  mkdir -p "$share_noshare_dir"
  IFS=':'
  for path_dir in $PATH; do
    IFS="$saved_ifs"
    [ -d "$path_dir" ] || continue
    for path_entry in "$path_dir"/*; do
      [ -e "$path_entry" ] || continue
      entry_name=$(basename "$path_entry")
      [ "$entry_name" = "localsend_app" ] && continue
      [ -e "$share_noshare_dir/$entry_name" ] && continue
      ln -s "$path_entry" "$share_noshare_dir/$entry_name"
    done
    IFS=':'
  done
  IFS="$saved_ifs"
}

leg_share_timing() {
  local t0
  t0=$(share_t0)
  # The drive's worst case: ~12s through the present-case kill (the
  # localsend_app pgrep polls up to 6s, Flutter startup is not instant) plus
  # a 15s takeover ceiling for the absent-case handoff plus the closing
  # query/frame round trip.
  leg_timing $((36 + t0 - 2)) $((70 + t0 - 2))
  # Sharing the launcher surface with --menu costs this leg that leg's whole
  # timeline before it may touch the route at all.
  if leg_on menu; then leg_timing 72 105 3; fi
}

leg_share_drive() {
  local t0 script="$shot_dir/share-drive.sh" menu_wait=""
  t0=$(share_t0)
  if leg_on menu; then
    # menu-finish.sh's own last action writes the selection file, and its
    # pending select() would otherwise still be armed when `menu activate 0`
    # lands here, picking the select list's index 0 instead of the SHARE row.
    menu_wait="for _ in \$(seq 1 90); do [ -f \"$selection_path\" ] && break; sleep 0.5; done"
  fi
  write_script "$script" <<EOF
#!/usr/bin/env bash
$menu_wait
sleep $t0
"$wl_copy_bin" "share smoke fixture"
sleep 1
"$qs_bin" ipc -p "$shell_path" call debug query "share" > "$share_query1_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call debug query "share" > "$share_query2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu summon share > /dev/null 2>&1
sleep 1
# grim, not a compositor-side capture: the frame has to leave the clipboard
# alone. A compositor-side screenshot action that copies the image too would
# supersede the fixture text the row is about to share.
"$grim_bin" "$share_menu_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu activate 0 > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 6 ]; do
  pgrep -f -- "localsend_app" > "$share_pgrep_path" 2>&1 || true
  [ -s "$share_pgrep_path" ] && break
  sleep 1
done
share_pid=\$(head -n1 "$share_pgrep_path")
if [ -n "\$share_pid" ]; then
  tr '\\0' '\\n' < /proc/\$share_pid/cmdline > "$share_cmdline_path" 2>&1
  share_tmp_arg=\$(tail -n1 "$share_cmdline_path")
  [ -f "\$share_tmp_arg" ] && cat "\$share_tmp_arg" > "$share_tmpfile_path" 2>&1
  kill "\$share_pid" 2>/dev/null || true
fi
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
sleep 1
# argv[1]=="-p" tells the real daemon apart from this script's own
# "qs ipc ... call" clients, which carry the same -p path further along.
find_daemon_pids() {
  for pid in \$(pgrep -f -- "-p $shell_path"); do
    if [ "\$(tr '\\0' '\\n' < /proc/\$pid/cmdline 2>/dev/null | sed -n '2p')" = "-p" ]; then
      echo "\$pid"
    fi
  done
}
old_pid=\$(find_daemon_pids | head -n1)
# LIBGL_ALWAYS_SOFTWARE for the same reason dev/smoke.sh exports it for the
# primary: on the vkms card Qt's EGL init takes the shell down otherwise.
LIBGL_ALWAYS_SOFTWARE=1 PATH="$share_noshare_dir" "$PWD/result/bin/formalshell" > "$share_second_log_path" 2>&1 &
new_pid=\$!
waited=0
count=0
while [ "\$waited" -lt 15000 ]; do
  sleep 0.5
  waited=\$((waited + 500))
  count=\$(find_daemon_pids | wc -l | tr -d ' ')
  if [ "\$count" = "1" ]; then
    break
  fi
done
survivor=\$(find_daemon_pids | head -n1)
printf '{"oldPid":%s,"newPid":%s,"survivorPid":%s,"waitedMs":%s,"finalCount":%s}\n' \\
  "\${old_pid:-null}" "\${new_pid:-null}" "\${survivor:-null}" "\$waited" "\${count:-0}" \\
  > "$share_instance_status_path"
"$qs_bin" ipc -p "$shell_path" call debug query "share" > "$share_absent_query1_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call debug query "share" > "$share_absent_query2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu summon "" > /dev/null 2>&1
sleep 1
"$grim_bin" "$share_menu_absent_path" > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_share_assert() {
  local f share_pid share_old share_new share_survivor share_final_count
  # Both passes are expected to show "share" already resolved: Menu.qml's
  # defaultMenuFile.onLoaded runs _evalConditions() at shell startup, long
  # before this drive script's first sleep. The second pass is redundant
  # confirmation, not a race with a still-pending first.
  for f in "$share_query1_path" "$share_query2_path"; do
    if [ ! -s "$f" ]; then
      fail "no debug query produced at $f"
    fi
  done
  cat "$share_query1_path"; echo
  cat "$share_query2_path"; echo
  if ! grep -qF '"id":"share"' "$share_query1_path"; then
    fail "first debug query never saw the share node present. Got: $(cat "$share_query1_path")"
  fi
  if ! grep -qF '"id":"share"' "$share_query2_path"; then
    fail "second debug query never saw the share node present. Got: $(cat "$share_query2_path")"
  fi
  if [ ! -f "$share_menu_path" ]; then
    fail "no share-menu screenshot produced"
  fi
  echo "SMOKE_SHARE_MENU $share_menu_path"

  share_pid=$(head -n1 "$share_pgrep_path" 2>/dev/null)
  if [ -z "$share_pid" ]; then
    fail "no localsend_app process ever appeared, pgrep output: $(cat "$share_pgrep_path" 2>/dev/null)"
  fi
  echo "SMOKE_SHARE_PID $share_pid"
  if [ ! -s "$share_cmdline_path" ]; then
    fail "could not read the launched process's /proc cmdline"
  fi
  cat "$share_cmdline_path"; echo
  if ! tail -n1 "$share_cmdline_path" | grep -qE '\.txt$'; then
    fail "launched process argv did not end in a mktemp .txt path. Got: $(tr '\n' ' ' < "$share_cmdline_path")"
  fi
  if [ ! -s "$share_tmpfile_path" ]; then
    fail "could not read the shared temp file's contents off disk"
  fi
  cat "$share_tmpfile_path"; echo
  if ! grep -qF "share smoke fixture" "$share_tmpfile_path"; then
    fail "shared temp file did not contain the fixture text. Got: $(tr '\n' ' ' < "$share_tmpfile_path")"
  fi

  # The absent case, through a second instance whose PATH is genuinely
  # scoped away from localsend_app.
  if [ ! -s "$share_instance_status_path" ]; then
    fail "no share-instance-status.json produced, the second daemon may never have launched"
  fi
  cat "$share_instance_status_path"
  share_old=$(grep -o '"oldPid":[A-Za-z0-9]*' "$share_instance_status_path" | cut -d: -f2)
  share_new=$(grep -o '"newPid":[A-Za-z0-9]*' "$share_instance_status_path" | cut -d: -f2)
  share_survivor=$(grep -o '"survivorPid":[A-Za-z0-9]*' "$share_instance_status_path" | cut -d: -f2)
  share_final_count=$(grep -o '"finalCount":[0-9]*' "$share_instance_status_path" | cut -d: -f2)
  echo "-- primary shell log (instance lock lines) --"
  grep "instance lock" "$shell_log_path" 2>/dev/null || echo "(none found)"
  echo "-- share-second.log (instance lock lines) --"
  grep "instance lock" "$share_second_log_path" 2>/dev/null || echo "(none found)"
  if [ "$share_old" = "null" ] || [ -z "$share_old" ]; then
    fail "no live primary share instance was found before the second launch"
  fi
  if [ "$share_final_count" != "1" ] || [ "$share_survivor" != "$share_new" ]; then
    fail "the shadowed-PATH instance did not win the takeover (finalCount=$share_final_count survivor=$share_survivor new=$share_new)"
  fi
  if ! grep -q "being replaced" "$shell_log_path" 2>/dev/null; then
    fail "the primary instance's log never logged being replaced"
  fi
  for f in "$share_absent_query1_path" "$share_absent_query2_path"; do
    if [ ! -s "$f" ]; then
      fail "no debug query produced at $f"
    fi
  done
  cat "$share_absent_query1_path"; echo
  cat "$share_absent_query2_path"; echo
  # The exact "share" id AND the "share." prefix a leaked child row would
  # carry: a summoned route used to render its actionable children even with
  # its own `when` gate false.
  if grep -qF '"id":"share"' "$share_absent_query1_path" || grep -qF '"id":"share"' "$share_absent_query2_path" \
    || grep -qF '"id":"share.' "$share_absent_query1_path" || grep -qF '"id":"share.' "$share_absent_query2_path"; then
    fail "share node (or one of its children) was still visible with localsend_app shadowed off PATH"
  fi
  if [ ! -f "$share_menu_absent_path" ]; then
    fail "no share-menu-absent screenshot produced"
  fi
  echo "SMOKE_SHARE_MENU_ABSENT $share_menu_absent_path"
}
