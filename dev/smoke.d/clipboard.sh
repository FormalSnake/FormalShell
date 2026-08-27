# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --clipboard drives both directions: wl-copy seeds the ledger, wl-paste
# reads the system clipboard back to prove what the shell put there.
#
# The head is one copy, one settle, one read, and it is an assertion of its
# own: the ledger has to hold something copied before anything had read it.
# ClipboardService owns the two `wl-paste --watch` children and is built at
# startup (shell.qml's `_startupServices`), not by its first reader. It is
# cleared afterwards so the fixture sequence starts from the same empty
# state the count assertions expect. Polling the ledger here instead would
# construct the service itself and prove nothing.
#
# Two list dumps prove capture, newest-first order, and that re-copying an
# existing entry moves it to the front rather than duplicating it. Then the
# leg that matters: a sentinel is copied, the route is summoned, `menu
# filter` narrows it to one known row, `menu activate 0` (the rig's Enter
# stand-in) fires, and the clipboard is read back. It has to hold the ROW's
# entry, not the sentinel: row activation is in-process
# (`@ipc:clipboard.copy:<id>`), and a spawned `qs ipc` would be a silent
# exit 127 on any install that does not put `qs` on PATH.
#
# The image fixture is copied last so the cursor lands on it when the route
# is resummoned, which is what puts the split pane's framed image preview in
# this run's own screenshot.
#
# A capture of copied markup rides in just before it. Row labels and the
# split pane both take provider data verbatim, and a Text left on AutoText
# parses anything the rich-text heuristic accepts, so the row would show
# bold "clipboard smoke markup" with its tags eaten and its font no longer
# the row's. The ledger dump asserts the markup survived capture; the frame
# is where the row is read back with its angle brackets intact.
leg_clipboard_flag="--clipboard"
leg_clipboard_order=130
leg_clipboard_needs="wl-copy wl-paste convert"

clip_list1_path="$shot_dir/clipboard-list1.json"
clip_list2_path="$shot_dir/clipboard-list2.json"
clip_list3_path="$shot_dir/clipboard-list3.json"
clip_copy_path="$shot_dir/clipboard-copy.txt"
clip_paste_path="$shot_dir/clipboard-paste.txt"
clip_activate_path="$shot_dir/clipboard-activate.txt"
clip_activate_paste_path="$shot_dir/clipboard-activate-paste.txt"
clip_image_fixture_path="$shot_dir/clip-image.png"
clip_route_png="$shot_dir/clipboard-route.png"
clip_thumb_cache_path="$shot_dir/clipboard-thumb-cache.txt"
clip_warmup_path="$shot_dir/clipboard-warmup.json"

leg_clipboard_fixture() {
  # The ledger's image entry: a small solid PNG copied last, so the route's
  # newest row is the image one and the split pane's screenshot shows the
  # framed preview rather than the text one.
  $convert_bin -size 320x180 xc:'#3fae2a' "$clip_image_fixture_path"
}

leg_clipboard_timing() {
  # The head costs a fixed 4s and every frame after it stacks on top. The
  # end state (the route summoned over the image entry) is stable, so a
  # generous delay only ever lands on it.
  leg_timing 42 70
  # Sharing the launcher surface with --picker costs this leg the whole
  # picker timeline before its own route can be summoned.
  if leg_on picker; then leg_timing 50 85; fi
}

leg_clipboard_drive() {
  local script="$shot_dir/clipboard-drive.sh" picker_wait=""
  if leg_on picker; then
    picker_wait="for _ in \$(seq 1 60); do [ -f \"$picker_done_path\" ] && break; sleep 1; done"
  fi
  write_script "$script" <<EOF
#!/usr/bin/env bash
"$wl_copy_bin" "clipboard smoke warmup"
sleep 3
"$qs_bin" ipc -p "$shell_path" call clipboard list > "$clip_warmup_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call clipboard clear > /dev/null 2>&1
sleep 1
"$wl_copy_bin" "clipboard smoke one"
sleep 1
"$wl_copy_bin" "clipboard smoke two"
sleep 1
"$wl_copy_bin" "clipboard smoke three"
sleep 1
"$qs_bin" ipc -p "$shell_path" call clipboard list > "$clip_list1_path" 2>&1
sleep 1
"$wl_copy_bin" "clipboard smoke three"
sleep 1
"$qs_bin" ipc -p "$shell_path" call clipboard list > "$clip_list2_path" 2>&1
copy_id=\$(grep -o '"id":"[^"]*"' "$clip_list2_path" | sed -n '2p' | cut -d'"' -f4)
"$qs_bin" ipc -p "$shell_path" call clipboard copy "\$copy_id" > "$clip_copy_path" 2>&1
sleep 1
"$wl_paste_bin" --no-newline > "$clip_paste_path" 2>&1
sleep 1
"$wl_copy_bin" "clipboard smoke sentinel"
sleep 1
$picker_wait
"$qs_bin" ipc -p "$shell_path" call menu summon clipboard > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu filter "clipboard smoke one" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu activate 0 > "$clip_activate_path" 2>&1
sleep 2
"$wl_paste_bin" --no-newline > "$clip_activate_paste_path" 2>&1
sleep 1
"$wl_copy_bin" '<b>clipboard smoke markup</b>'
sleep 1
"$wl_copy_bin" --type image/png < "$clip_image_fixture_path"
sleep 2
"$qs_bin" ipc -p "$shell_path" call clipboard list > "$clip_list3_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu summon clipboard > /dev/null 2>&1
sleep 3
"$grim_bin" "$clip_route_png" > /dev/null 2>&1
ls -1 "$iso_home/.cache/formalshell/thumbnails" > "$clip_thumb_cache_path" 2>&1
EOF
  echo "exec-once = bash $script"
}

leg_clipboard_assert() {
  local f count1 count2
  for f in "$clip_list1_path" "$clip_list2_path" "$clip_list3_path"; do
    if [ ! -s "$f" ]; then
      fail "no clipboard list produced at $f"
    fi
  done
  # A copy made before anything read the ledger. It fails if the two
  # `wl-paste --watch` children only start when something first reads
  # ClipboardService, which is what the poll this replaced was papering over.
  cat "$clip_warmup_path"; echo
  if ! grep -qF 'clipboard smoke warmup' "$clip_warmup_path"; then
    fail "a copy made before anything read the ledger was never captured: $(cat "$clip_warmup_path" 2>/dev/null)"
  fi
  cat "$clip_list1_path"; echo
  cat "$clip_list2_path"; echo
  if ! grep -qF 'clipboard smoke three' "$clip_list1_path"; then
    fail "the clipboard ledger never captured the fixture strings: $(cat "$clip_list1_path")"
  fi
  # The count has to stay 3 across the re-copy: a fourth entry would mean
  # the dedup-to-front path inserted a duplicate instead of moving the
  # existing "clipboard smoke three" entry.
  count1=$(grep -o '"id":' "$clip_list1_path" | wc -l | tr -d ' ')
  count2=$(grep -o '"id":' "$clip_list2_path" | wc -l | tr -d ' ')
  if [ "$count1" != "3" ] || [ "$count2" != "3" ]; then
    fail "clipboard list item count drifted (before=$count1 after-recopy=$count2, want 3/3)"
  fi
  if ! grep -q '^ok$' "$clip_copy_path" 2>/dev/null; then
    fail "clipboard copy did not answer ok, got: $(cat "$clip_copy_path" 2>/dev/null)"
  fi
  # ThumbnailService's `fit` half. The ledger's image row draws a
  # prerendered letterboxed copy rather than decoding the capture itself,
  # and a warmed row and a fallback row paint the same pixels, so the frame
  # cannot tell them apart. The cache filename can: `fit` rather than the
  # picker's `cover`, which is the mode this route asks for.
  if [ ! -s "$clip_thumb_cache_path" ]; then
    fail "no thumbnail cache directory produced for the clipboard route"
  fi
  cat "$clip_thumb_cache_path"
  if ! grep -q 'fit[0-9]*\.jpg$' "$clip_thumb_cache_path"; then
    fail "the clipboard capture was never prerendered in fit mode, cache holds: $(cat "$clip_thumb_cache_path")"
  fi
  if grep -q '\.part\.jpg$' "$clip_thumb_cache_path"; then
    fail "the thumbnail warm left partial files behind: $(cat "$clip_thumb_cache_path")"
  fi
  # wl-paste --no-newline leaves this file without one of its own, so the
  # explicit echo keeps the next line from landing appended to it.
  cat "$clip_paste_path"; echo
  if ! grep -q 'clipboard smoke two' "$clip_paste_path"; then
    fail "the system clipboard did not flip to the copied entry, got: $(cat "$clip_paste_path")"
  fi
  # Row activation, the Enter stand-in. The sentinel copied right before it
  # is what makes this a real assertion rather than a tautology: the system
  # clipboard held "clipboard smoke sentinel" when the row was activated, so
  # reading "clipboard smoke one" back can only have come from the row's own
  # in-process action running.
  if ! grep -q '^ok$' "$clip_activate_path" 2>/dev/null; then
    fail "menu activate on the clipboard row did not answer ok, got: $(cat "$clip_activate_path" 2>/dev/null)"
  fi
  cat "$clip_activate_paste_path"; echo
  if ! grep -q 'clipboard smoke one' "$clip_activate_paste_path"; then
    fail "activating the clipboard row left the clipboard at $(cat "$clip_activate_paste_path"), not the row's own entry"
  fi
  # The image entry is what the split pane's preview frame is read against.
  if ! grep -qF '"kind":"image"' "$clip_list3_path"; then
    fail "the image fixture never reached the ledger: $(cat "$clip_list3_path")"
  fi
  cat "$clip_list3_path"; echo
  if ! grep -qF '<b>clipboard smoke markup</b>' "$clip_list3_path"; then
    fail "the markup capture never reached the ledger: $(cat "$clip_list3_path")"
  fi
  if [ ! -f "$clip_route_png" ]; then
    fail "no clipboard-route screenshot produced"
  fi
  echo "SMOKE_CLIPBOARD_ROUTE $clip_route_png"
}
