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
# default) pass.
set -euo pipefail
cd "$(dirname "$0")/.."
repo_root="$(pwd)"

work_dir="dev/.testvm"
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

  local keys_store_path
  keys_store_path=$(nix-store --add "$repo_root/$keys_dir")

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
  rsync -az --delete \
    --exclude 'result*' \
    --exclude '.git/index.lock' \
    --exclude 'artifacts/' \
    --exclude '/dev/.linux-builder/' \
    --exclude '/dev/.testvm/' \
    -e "ssh ${ssh_opts[*]}" \
    "$repo_root/" test@localhost:formalshell/
}

cmd_run() {
  if [ $# -eq 0 ]; then
    echo "usage: $0 run <cmd...>" >&2
    exit 1
  fi
  vm_run "$@"
}

# sync, run dev/smoke-niri.sh with the given flags, then pull the SMOKE_OK
# screenshot plus any other stdout (the dump/status/query JSON the smoke
# script cats inline) back to ./artifacts/ on the mac.
cmd_smoke() {
  cmd_sync
  local out status=0
  out=$(vm_run "./dev/smoke-niri.sh $*" 2>&1) || status=$?
  echo "$out"
  if [ "$status" -ne 0 ]; then
    echo "testvm: smoke run failed (exit $status)" >&2
    exit "$status"
  fi

  local remote_png
  remote_png=$(printf '%s\n' "$out" | sed -n 's/^SMOKE_OK //p' | tail -1)
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

  local rest
  rest=$(printf '%s\n' "$out" | grep -v '^SMOKE_OK ' || true)
  if [ -n "$(printf '%s' "$rest" | tr -d '[:space:]')" ]; then
    local local_json="$repo_root/artifacts/smoke-${ts}.json"
    printf '%s\n' "$rest" > "$local_json"
    echo "pulled dump/status output: $local_json"
  fi
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
    echo "usage: $0 {start|stop|status|sync|run <cmd...>|smoke [flags...]|shell}" >&2
    exit 1
    ;;
esac
