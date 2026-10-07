# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --hotcorner-relock drives the one hot corner sequence a layer dump cannot
# reach: fire the bottom-right corner, unlock, and leave the cursor exactly
# where it was. Unlocking puts the corner surface back under a pointer that
# never moved, and firing on the enter that comes with it relocked the
# session on the spot (owner report, 2026-08-26).
#
# The proof is the pause in the middle: three seconds of `lock isLocked`
# reading false with no pointer event of any kind in between. The leg then
# moves the pointer out, waits past the re-arm cooldown and moves back in,
# which has to lock again, so the fix is not just "the corner stopped
# working".
#
# The corner surfaces are destroyed and rebuilt under the plate, which is
# what makes this leg fail on the old rule rather than merely pass on the new
# one. Instrumenting the corner here showed the compositor sending it an
# enter 51ms after the unlock under a cursor that had not moved since the
# lock: real, but harmless to a surface that remembered firing. The surfaces
# do not always live that long. `Corners.windows` is resolved from the output
# list and the config, so an output leaving and coming back rebuilds every
# corner, which on a laptop is what closing and opening the lid does while
# the session is locked, and a rebuilt corner has nothing to remember. The
# rig has one head and no lid, so `hotCorners.enabled` is written false and
# then true instead: same model going empty and refilling, same fresh
# surfaces, and it can be made to happen on cue. The lock plate is above the
# Top layer throughout, so the new surfaces get no pointer of their own until
# the unlock hands it over.
#
# wlrctl and wtype, not any IPC shortcut: the whole claim is about real
# pointer enter/leave and a real unlock, and LockIpc deliberately has no
# "type this password" verb (see its header). wlrctl's protocol is relative
# only, so every move starts by slamming the pointer into the top-left
# corner, which the compositor clamps, and travels from there. Top-left is
# `none` by default, so that origin fires nothing.
#
# The same sequence then runs on the bottom-left corner's screensaver: fired,
# dismissed with `screensaver stop` while the cursor stays parked in the
# corner, and three seconds with no pointer event in which it must not come
# back. The screensaver's overlay covers the corner through its exit fade,
# so the hand-back enter arrives when the overlay unmaps, after any cooldown
# counted from the dismiss itself has run out.
#
# A shell that serves no `lock` target yet (FS_IMPL=rust before the lock
# lands) runs the screensaver half alone.
leg_hotcorner_relock_flag="--hotcorner-relock"
leg_hotcorner_relock_rust=1
leg_hotcorner_relock_order=161
leg_hotcorner_relock_needs="wlrctl wtype jq"
# The frames here are the ordinary desktop and the lock plate over it, so
# the base run's fixture window stays where it is.
leg_hotcorner_relock_fixture_window=keep

# The bottom-right corner surface is `hotCorners.size` (4) square against the
# far edge of the rig's pinned 1920x1080 output, so 1917x1077 is inside it
# with a pixel to spare on both edges.
hotcorner_relock_x=1917
hotcorner_relock_y=1077

hotcorner_relock_locked_path="$shot_dir/hotcorner-relock-locked.png"
hotcorner_relock_unlocked_path="$shot_dir/hotcorner-relock-unlocked.png"
hotcorner_relock_parked_path="$shot_dir/hotcorner-relock-parked.png"
hotcorner_relock_again_path="$shot_dir/hotcorner-relock-again.png"
hotcorner_relock_s1_path="$shot_dir/hotcorner-relock-1-locked.txt"
hotcorner_relock_s2_path="$shot_dir/hotcorner-relock-2-unlocked.txt"
hotcorner_relock_s3_path="$shot_dir/hotcorner-relock-3-parked.txt"
hotcorner_relock_s4_path="$shot_dir/hotcorner-relock-4-again.txt"
hotcorner_relock_s5_path="$shot_dir/hotcorner-relock-5-final.txt"
hotcorner_relock_moves_path="$shot_dir/hotcorner-relock-moves.txt"
hotcorner_relock_nolock_path="$shot_dir/hotcorner-relock-nolock.txt"
hotcorner_relock_saver_on_path="$shot_dir/hotcorner-relock-6-saver-on.json"
hotcorner_relock_saver_parked_path="$shot_dir/hotcorner-relock-7-saver-parked.json"
hotcorner_relock_saver_again_path="$shot_dir/hotcorner-relock-8-saver-again.json"
hotcorner_relock_saver_final_path="$shot_dir/hotcorner-relock-9-saver-final.json"
hotcorner_relock_saver_shot_path="$shot_dir/hotcorner-relock-saver.png"
hotcorner_relock_saver_parked_shot_path="$shot_dir/hotcorner-relock-saver-parked.png"
hotcorner_relock_settings_path="$iso_home/.config/formalshell/settings.json"

leg_hotcorner_relock_timing() {
  leg_timing 52 85
}

leg_hotcorner_relock_drive() {
  local script="$shot_dir/hotcorner-relock-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
ipc() { $ipc call lock isLocked > "\$1" 2>&1; }
corner() {
  "$wlrctl_bin" pointer move -4000 -4000 >> "$hotcorner_relock_moves_path" 2>&1
  sleep 1
  "$wlrctl_bin" pointer move $hotcorner_relock_x $hotcorner_relock_y >> "$hotcorner_relock_moves_path" 2>&1
}
# Merged into whatever settings fixture the run already wrote rather than
# overwriting it, and written back through the same inode so the shell's own
# FileView watch survives the change.
corners() {
  "$jq_bin" ". + {hotCorners: {enabled: \$1, size: 4, delayMs: 400, topLeft: \"none\", topRight: \"none\", bottomLeft: \"screensaver\", bottomRight: \"lock\"}}" \\
    "$hotcorner_relock_settings_path" > "$shot_dir/hotcorner-relock-settings.json" 2>&1
  cat "$shot_dir/hotcorner-relock-settings.json" > "$hotcorner_relock_settings_path"
}
saver() { $ipc call screensaver status > "\$1" 2>&1; }
# The bottom-left corner, a pixel in from both edges.
saver_corner() {
  "$wlrctl_bin" pointer move -4000 -4000 >> "$hotcorner_relock_moves_path" 2>&1
  sleep 1
  "$wlrctl_bin" pointer move 2 $hotcorner_relock_y >> "$hotcorner_relock_moves_path" 2>&1
}
sleep 6
if $ipc call lock isLocked 2>&1 | grep -q '^Target not found'; then
  echo "no lock target" > "$hotcorner_relock_nolock_path"
else
corner
# 400ms of dwell, then the lock plate.
sleep 2
ipc "$hotcorner_relock_s1_path"
"$grim_bin" "$hotcorner_relock_locked_path" > /dev/null 2>&1
corners false
sleep 2
corners true
sleep 2
"$wtype_bin" "formalshell-test"
"$wtype_bin" -k Return
# Polled rather than slept: PAM's own round trip varies here, and a corner
# that re-arms too eagerly locks again 400ms after the unlock, so a fixed
# sample lands on the relock and blames the password for it. The first
# \`false\` is what proves the password worked; whether it holds is the next
# assertion's job.
for i in \$(seq 1 40); do
  ipc "$hotcorner_relock_s2_path"
  grep -q '^false\$' "$hotcorner_relock_s2_path" && break
  sleep 0.25
done
"$grim_bin" "$hotcorner_relock_unlocked_path" > /dev/null 2>&1
# Nothing below this line until the next \`corner\` touches the pointer. Any
# lock in this window came from the unlock's own hand-back.
sleep 3
ipc "$hotcorner_relock_s3_path"
"$grim_bin" "$hotcorner_relock_parked_path" > /dev/null 2>&1
# Out of the corner, past the cooldown, and back in: an ordinary approach,
# which still has to lock.
corner
sleep 2
ipc "$hotcorner_relock_s4_path"
"$grim_bin" "$hotcorner_relock_again_path" > /dev/null 2>&1
sleep 1
"$wtype_bin" "formalshell-test"
"$wtype_bin" -k Return
sleep 4
ipc "$hotcorner_relock_s5_path"
fi
corners true
sleep 2
saver_corner
sleep 2
saver "$hotcorner_relock_saver_on_path"
"$grim_bin" "$hotcorner_relock_saver_shot_path" > /dev/null 2>&1
$ipc call screensaver stop > /dev/null 2>&1
# Nothing touches the pointer until the next saver_corner: the overlay fades
# and unmaps over a cursor that never left.
sleep 3
saver "$hotcorner_relock_saver_parked_path"
"$grim_bin" "$hotcorner_relock_saver_parked_shot_path" > /dev/null 2>&1
saver_corner
sleep 2
saver "$hotcorner_relock_saver_again_path"
$ipc call screensaver stop > /dev/null 2>&1
sleep 2
saver "$hotcorner_relock_saver_final_path"
EOF
  hypr_exec_once "bash $script"
}

hotcorner_relock_expect() {
  local path="$1" want="$2" what="$3"
  if [ ! -s "$path" ] || ! grep -q "^$want\$" "$path"; then
    echo "--- pointer moves ---" >&2
    cat "$hotcorner_relock_moves_path" >&2 2>/dev/null || true
    fail "$what (lock isLocked wanted $want, got: $(cat "$path" 2>/dev/null))"
  fi
  echo "SMOKE_HOTCORNER_RELOCK $what: isLocked=$want"
}

hotcorner_relock_saver_expect() {
  local path="$1" want="$2" what="$3"
  if [ ! -s "$path" ] || ! grep -q "\"active\":$want," "$path"; then
    echo "--- pointer moves ---" >&2
    cat "$hotcorner_relock_moves_path" >&2 2>/dev/null || true
    fail "$what (screensaver active wanted $want, got: $(cat "$path" 2>/dev/null))"
  fi
  echo "SMOKE_HOTCORNER_RELOCK $what: screensaver active=$want"
}

leg_hotcorner_relock_assert() {
  local f
  hotcorner_relock_saver_expect "$hotcorner_relock_saver_on_path" true \
    "the bottom-left corner started the screensaver"
  hotcorner_relock_saver_expect "$hotcorner_relock_saver_parked_path" false \
    "it stayed dismissed for 3s with the pointer parked in its corner"
  hotcorner_relock_saver_expect "$hotcorner_relock_saver_again_path" true \
    "leaving the corner and coming back started it again"
  hotcorner_relock_saver_expect "$hotcorner_relock_saver_final_path" false \
    "the screensaver was left stopped"
  [ -f "$hotcorner_relock_saver_shot_path" ] || fail "no screensaver corner frame produced"
  echo "SMOKE_HOTCORNER_RELOCK_SAVER $hotcorner_relock_saver_shot_path"
  echo "SMOKE_HOTCORNER_RELOCK_SAVER_PARKED $hotcorner_relock_saver_parked_shot_path"
  if [ -f "$hotcorner_relock_nolock_path" ]; then
    [ "$fs_impl" = rust ] || fail "the QML shell answered no lock target"
    echo "SMOKE_HOTCORNER_RELOCK lock half skipped: this shell serves no lock target yet"
    return 0
  fi
  hotcorner_relock_expect "$hotcorner_relock_s1_path" true \
    "the bottom-right corner locked the session"
  hotcorner_relock_expect "$hotcorner_relock_s2_path" false \
    "the typed password unlocked it"
  hotcorner_relock_expect "$hotcorner_relock_s3_path" false \
    "it stayed unlocked for 3s with the pointer parked in the rebuilt corner"
  hotcorner_relock_expect "$hotcorner_relock_s4_path" true \
    "leaving the corner and coming back past the cooldown locked it again"
  hotcorner_relock_expect "$hotcorner_relock_s5_path" false \
    "the session was left unlocked"
  for f in "$hotcorner_relock_locked_path" "$hotcorner_relock_unlocked_path" \
    "$hotcorner_relock_parked_path" "$hotcorner_relock_again_path"; do
    [ -f "$f" ] || fail "no hot corner relock screenshot produced at $f"
  done
  # A locked frame and an unlocked one cannot be the same picture: the
  # cheapest guard against a leg whose IPC answers all read right over a
  # session where no lock surface ever mapped.
  if cmp -s "$hotcorner_relock_locked_path" "$hotcorner_relock_unlocked_path"; then
    fail "the locked and unlocked hot corner frames are byte-identical: no lock surface ever mapped"
  fi
  echo "SMOKE_HOTCORNER_RELOCK_LOCKED $hotcorner_relock_locked_path"
  echo "SMOKE_HOTCORNER_RELOCK_UNLOCKED $hotcorner_relock_unlocked_path"
  echo "SMOKE_HOTCORNER_RELOCK_PARKED $hotcorner_relock_parked_path"
  echo "SMOKE_HOTCORNER_RELOCK_AGAIN $hotcorner_relock_again_path"
}
