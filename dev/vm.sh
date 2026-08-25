#!/usr/bin/env bash
# Driver for the runtime layer of the mac e2e rig
# (docs/superpowers/plans/2026-07-28-mac-e2e-rig.md): boots
# packages.aarch64-darwin.testvm (nix/testvm.nix) in the background, syncs
# the working tree into it, and runs commands/smoke tests inside with the
# nested-niri session env wired up.
#
# The working tree — not a commit — is what gets tested: `sync` rsyncs it
# straight into the VM over the ssh port-forward.
#
# KEYS follows the same pattern nix-builder-vm.nix uses for its own
# authorized_keys share: `nix-store --add` before boot so the 9p mapped-xattr
# share reports the pubkey as root-owned, which is what lets sshd's
# AuthorizedKeysFile ownership check (StrictModes, left at its secure
# default) pass. Only the .pub is added — the store is world-readable and
# the private key never needs to leave dev/.testvm/keys.
set -euo pipefail
cd "$(dirname "$0")/.."
repo_root="$(pwd)"

# One VM per repository, not per checkout: a git worktree resolves its
# common dir to the main checkout's .git, so every worktree shares that
# checkout's dev/.testvm instead of building and booting a second VM.
work_dir="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/dev/.testvm"
keys_dir="$work_dir/keys"
disk_image="$work_dir/formalshell-testvm.qcow2"
log_file="$work_dir/vm.log"
pid_file="$work_dir/vm.pid"
priv_key="$keys_dir/test_ed25519"

ssh_port=2222
ssh_opts=(-p "$ssh_port" -i "$priv_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes)
scp_opts=(-P "$ssh_port" -i "$priv_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes)

is_running() {
  [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

wait_for_ssh() {
  local tries=$1
  for ((i = 0; i < tries; i++)); do
    if ssh "${ssh_opts[@]}" test@localhost true 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  return 1
}

# Runs a command inside the VM with cwd at the synced repo and the nested
# smoke scripts' expected session env exported. WAYLAND_DISPLAY is read
# live from the systemd --user environment (same fallback dev/smoke-niri.sh
# itself uses) rather than hardcoded, since it is the parent compositor's
# own -- not guaranteed to be wayland-1 forever.
vm_run() {
  ssh "${ssh_opts[@]}" test@localhost \
    "cd formalshell && export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus WAYLAND_DISPLAY=\$(systemctl --user show-environment | sed -n 's/^WAYLAND_DISPLAY=//p') && $*"
}

cmd_start() {
  if is_running; then
    echo "testvm already running (pid $(cat "$pid_file"))"
    return 0
  fi
  mkdir -p "$keys_dir"
  if [ ! -f "$priv_key" ]; then
    ssh-keygen -t ed25519 -N "" -C "formalshell-testvm" -f "$priv_key" >/dev/null
    echo "generated ssh keypair: $priv_key"
  fi

  git -C "$repo_root" add -A >/dev/null 2>&1 || true  # flakes only see tracked files
  local vm_pkg
  vm_pkg=$(nix build --no-link --print-out-paths "$repo_root#testvm")
  echo "built $vm_pkg"

  # Copy just the pubkey into its own directory before adding to the
  # store — `nix-store --add` on $keys_dir would put the private key
  # (sshd never reads it; only the guest's authorized_keys .pub does)
  # into the world-readable store too.
  local pub_keys_dir="$work_dir/keys-pub"
  mkdir -p "$pub_keys_dir"
  cp "$priv_key.pub" "$pub_keys_dir/"
  local keys_store_path
  keys_store_path=$(nix-store --add "$repo_root/$pub_keys_dir")

  (
    cd "$work_dir"
    set -m
    KEYS="$keys_store_path" NIX_DISK_IMAGE="$repo_root/$disk_image" \
      nohup "$vm_pkg/bin/run-formalshell-testvm-vm" >vm.log 2>&1 &
    echo $! >vm.pid
  )
  echo "booting testvm (pid $(cat "$pid_file")), log: $log_file"

  if ! wait_for_ssh 60; then
    echo "testvm: ssh did not come up after 5 minutes; see $log_file" >&2
    exit 1
  fi
  echo "testvm ssh is up on 127.0.0.1:${ssh_port}"
}

cmd_stop() {
  if ! is_running; then
    echo "testvm not running"
    rm -f "$pid_file"
    return 0
  fi
  local pid
  pid=$(cat "$pid_file")
  echo "stopping testvm (pid $pid)"
  ssh "${ssh_opts[@]}" test@localhost 'sudo poweroff' 2>/dev/null || true
  for ((i = 0; i < 30; i++)); do
    is_running || break
    sleep 1
  done
  if is_running; then
    echo "testvm did not power off gracefully, sending SIGTERM"
    kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    for ((i = 0; i < 10; i++)); do
      is_running || break
      sleep 1
    done
    if is_running; then
      echo "testvm still up, sending SIGKILL"
      kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pid_file"
}

cmd_status() {
  if is_running; then
    echo "testvm running (pid $(cat "$pid_file"))"
    if ssh "${ssh_opts[@]}" test@localhost true 2>/dev/null; then
      echo "ssh reachable on 127.0.0.1:${ssh_port}"
    else
      echo "ssh not reachable"
    fi
  else
    echo "testvm not running"
  fi
}

cmd_sync() {
  # /.git stays out: in a worktree it is a gitdir file pointing at the mac,
  # which leaves the VM's copy dangling and every `git add -A` there
  # failing. The VM keeps its own repo instead (created below on first
  # sync); the flake only needs the files tracked, not the history.
  rsync -az --delete \
    --exclude 'result*' \
    --exclude '/.git' \
    --exclude 'artifacts/' \
    --exclude '/dev/.linux-builder/' \
    --exclude '/dev/.testvm/' \
    -e "ssh ${ssh_opts[*]}" \
    "$repo_root/" test@localhost:formalshell/
  vm_run 'cd ~/formalshell && { [ -d .git ] || git init -q; }'
}

cmd_run() {
  if [ $# -eq 0 ]; then
    echo "usage: $0 run <cmd...>" >&2
    exit 1
  fi
  vm_run "$@"
}

# sync, run the smoke rig with the given flags, then pull the SMOKE_OK
# screenshot plus any other stdout (the dump/status/query JSON the smoke
# script cats inline) back to ./artifacts/ on the mac.
#
# --compositor picks the rig: hyprland (dev/smoke.sh, the default and the
# backend M41 onwards ships) or niri (dev/smoke-niri.sh, still the richer
# script until M46 deletes that backend). It is consumed here, never passed
# through to the script.
cmd_smoke() {
  local script="./dev/smoke.sh"
  local flags=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --compositor)
        case "${2:-}" in
          hyprland) script="./dev/smoke.sh" ;;
          niri) script="./dev/smoke-niri.sh" ;;
          *) echo "usage: $0 smoke [--compositor hyprland|niri] [flags...]" >&2; exit 1 ;;
        esac
        shift 2
        ;;
      *) flags+=("$1"); shift ;;
    esac
  done
  set -- ${flags[@]+"${flags[@]}"}

  cmd_sync
  local out status=0
  out=$(vm_run "$script $*" 2>&1) || status=$?
  echo "$out"
  if [ "$status" -ne 0 ]; then
    echo "testvm: smoke run failed (exit $status)" >&2
    exit "$status"
  fi

  # `grep -oE`, not an anchored `^SMOKE_OK` sed: --menu's own last line is a
  # `cat` of selection.txt with no trailing newline, so the SMOKE_OK line
  # lands appended to that JSON instead of starting its own line.
  local remote_png
  remote_png=$(printf '%s\n' "$out" | grep -oE 'SMOKE_OK [^[:space:]]+' | tail -1 | awk '{print $2}')
  if [ -z "$remote_png" ]; then
    echo "testvm: no SMOKE_OK line in smoke output" >&2
    exit 1
  fi

  mkdir -p "$repo_root/artifacts"
  local ts local_png
  ts=$(date +%Y%m%d-%H%M%S)
  local_png="$repo_root/artifacts/smoke-${ts}.png"
  scp "${scp_opts[@]}" "test@localhost:$remote_png" "$local_png"
  echo "pulled screenshot: $local_png"

  # Strip the marker wherever it landed (its own line, or appended to the
  # last JSON line above) before saving whatever's left as the JSON sidecar.
  local rest
  rest=$(printf '%s\n' "$out" | sed -E 's/SMOKE_OK [^[:space:]]+//' | sed '/^[[:space:]]*$/d')
  if [ -n "$(printf '%s' "$rest" | tr -d '[:space:]')" ]; then
    local local_json="$repo_root/artifacts/smoke-${ts}.json"
    printf '%s\n' "$rest" > "$local_json"
    echo "pulled dump/status output: $local_json"
  fi

  # Named secondary screenshots (M14 Task 3's `SMOKE_WIFI_*` lines, same
  # convention --lock/--screensaver already print as SMOKE_LOCK_*/
  # SMOKE_SCREENSAVER_*): any "SMOKE_<NAME> <remote-path>.png" line beyond
  # the primary SMOKE_OK gets pulled too, under its own basename — a fixed
  # name, not timestamped, since these are the specific named artifacts a
  # task's own Verify step reads back (wifi-wrong.png, wifi-connected.png,
  # wifi-eap-connected.png, …), not the generic per-run screenshot.
  local extra_line remote_extra local_extra
  while IFS= read -r extra_line; do
    [ -z "$extra_line" ] && continue
    remote_extra=$(printf '%s\n' "$extra_line" | awk '{print $2}')
    case "$remote_extra" in
      *.png)
        local_extra="$repo_root/artifacts/$(basename "$remote_extra")"
        scp "${scp_opts[@]}" "test@localhost:$remote_extra" "$local_extra"
        echo "pulled screenshot: $local_extra"
        ;;
    esac
  done <<< "$(printf '%s\n' "$out" | grep -oE '^SMOKE_[A-Z0-9_]+ [^[:space:]]+' | grep -v '^SMOKE_OK ')"

  # --screensaver-gif writes its committed output straight into the synced
  # repo's docs/media/ inside the VM, not artifacts/ — pull those back into
  # the real repo so the command actually reproduces the tracked GIFs
  # instead of requiring a manual scp. The next cmd_sync's `rsync --delete`
  # would otherwise be a no-op here (the pulled files now exist on the mac
  # side too), so this can't regress into deleting what it just pulled.
  case " $* " in
    *" --screensaver-gif "*)
      mkdir -p "$repo_root/docs/media"
      rsync -az -e "ssh ${ssh_opts[*]}" \
        --include 'screensaver-*.gif' --exclude '*' \
        test@localhost:formalshell/docs/media/ "$repo_root/docs/media/"
      echo "pulled screensaver gifs: $repo_root/docs/media/screensaver-*.gif"
      ;;
  esac
}

cmd_shell() {
  exec ssh -t "${ssh_opts[@]}" test@localhost \
    "cd formalshell && export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus WAYLAND_DISPLAY=\$(systemctl --user show-environment | sed -n 's/^WAYLAND_DISPLAY=//p') && exec \$SHELL -l"
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  sync) cmd_sync ;;
  run) shift; cmd_run "$@" ;;
  smoke) shift; cmd_smoke "$@" ;;
  shell) cmd_shell ;;
  *)
    echo "usage: $0 {start|stop|status|sync|run <cmd...>|smoke [--compositor hyprland|niri] [flags...]|shell}" >&2
    exit 1
    ;;
esac
