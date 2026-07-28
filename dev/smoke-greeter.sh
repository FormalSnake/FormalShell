#!/usr/bin/env bash
# greetd smoke (M8 Task 2): drives the real greetd instance's default_session
# (the formalshell-greeter compositor nix/testvm.nix declares) through a full
# login — typed via wtype into the greeter's own Wayland session, not an IPC
# shortcut, since Quickshell.Services.Greetd exposes no such thing (see
# greeter/greeter.qml's own header comment; same "verify the action, not the
# input method" idiom dev/smoke-niri.sh's --lock mode already uses). Prints
# the pre-auth (clock + input cell) and post-auth screenshots plus the
# session log, proving the real create_session/auth_message/start_session
# exchange happened rather than just "it renders".
#
# Unlike dev/smoke-niri.sh's own ephemeral nested compositor (composed fresh
# every run by that script), greetd's default_session is a persistent system
# service declared once in nix/testvm.nix — driving it means finding the
# ALREADY-RUNNING greeter session rather than spawning a new one, and
# reaching from this script's own "test" account into the separate `greeter`
# system account's Wayland session. Root (passwordless sudo, already wired
# for --lock's own wtype use) bypasses the greeter runtime dir's 0700 mode
# outright, the same way it bypasses any other user's file permissions, so
# grim/wtype run via `sudo env ...` here rather than as the `greeter` user
# itself.
#
# `sudo systemctl restart greetd` up front makes every run idempotent: once
# a login succeeds, greetd moves on to the authenticated user's own session
# and the default_session compositor this script talks to is gone — the
# restart forces a fresh greeter back up regardless of what a previous run
# (or a fresh boot) left running.
set -euo pipefail
cd "$(dirname "$0")/.."

runtime_dir=/run/formalshell-greeter
wayland_display=wayland-1
session_log=/tmp/formalshell-greeter-session.log
post_auth_src=/tmp/formalshell-greeter-post-auth.png

out_dir="artifacts/greeter"
mkdir -p "$out_dir"
pre_auth_png="$out_dir/greeter-pre-auth.png"
post_auth_png="$out_dir/greeter-post-auth.png"
session_log_out="$out_dir/greeter-session.log"
journal_out="$out_dir/greetd-journal.txt"

greeter_env=(sudo env "XDG_RUNTIME_DIR=$runtime_dir" "WAYLAND_DISPLAY=$wayland_display")
# wtype connects to the compositor fresh on every invocation; the virtual
# keyboard's keymap upload needs one round trip to land before the first
# key event is safe to send, or that first character is silently dropped
# (reproduced directly: `wtype "12345"` into an empty field landed "2345").
# `-s <ms>` sleeps before interpreting the text/key that follows, giving
# that round trip time to complete — confirmed reliable up to a 16-char
# string across this same cross-user path.
wtype_settle_ms=300

sudo rm -f "$post_auth_src" "$session_log"
sudo systemctl restart greetd

for _ in $(seq 1 60); do
  sudo test -S "$runtime_dir/$wayland_display" && break
  sleep 2
done
if ! sudo test -S "$runtime_dir/$wayland_display"; then
  echo "SMOKE_FAIL: greeter compositor socket never appeared at $runtime_dir/$wayland_display" >&2
  sudo cat "$session_log" >&2 || true
  exit 1
fi

# formalshell-greeter needs a moment after connecting to map its PanelWindow
# surfaces and pull the first Greetd.state — matches the fixed post-connect
# settle windows dev/smoke-niri.sh's own modes use before their first shot.
sleep 3
"${greeter_env[@]}" grim "$pre_auth_png"

"${greeter_env[@]}" wtype -s "$wtype_settle_ms" "test"
"${greeter_env[@]}" wtype -s "$wtype_settle_ms" -k Return
# The create_session -> auth_message round trip (real PAM conversation)
# measured comparably slow to --lock's own PAM round trip in
# dev/smoke-niri.sh; 3s margin before typing the password avoids racing the
# prompt switching from "USER" to the password step.
sleep 3
"${greeter_env[@]}" wtype -s "$wtype_settle_ms" "formalshell-test"
"${greeter_env[@]}" wtype -s "$wtype_settle_ms" -k Return

for _ in $(seq 1 30); do
  sudo test -f "$post_auth_src" && break
  sleep 2
done
if ! sudo test -f "$post_auth_src"; then
  echo "SMOKE_FAIL: no post-auth screenshot — greeter never reached Greetd.launch(); session log:" >&2
  sudo cat "$session_log" >&2 || true
  exit 1
fi
sudo cp "$post_auth_src" "$post_auth_png"
sudo chmod 644 "$post_auth_png"

sudo cp "$session_log" "$session_log_out" 2>/dev/null || true
sudo chmod 644 "$session_log_out" 2>/dev/null || true
sudo journalctl -u greetd --no-pager -n 300 > "$journal_out" 2>&1 || true

if ! grep -q "Authentication complete." "$session_log_out"; then
  echo "SMOKE_FAIL: session log has no 'Authentication complete.' line — got:" >&2
  cat "$session_log_out" >&2
  exit 1
fi
if ! grep -q "Quitting." "$session_log_out"; then
  echo "SMOKE_FAIL: session log has no 'Quitting.' line (Greetd.launch's exit-after-launch never fired) — got:" >&2
  cat "$session_log_out" >&2
  exit 1
fi

echo "SMOKE_GREETER_PRE $pre_auth_png"
echo "SMOKE_GREETER_POST $post_auth_png"
echo "SMOKE_GREETER_OK"
