#!/usr/bin/env bash
# aarch64-linux build capability for the macbook: boots the `linux-builder`
# NixOS VM (nixpkgs' own macOS remote-builder profile,
# nixos/modules/profiles/nix-builder-vm.nix, pinned and resource-bumped as
# packages.aarch64-darwin.linux-builder in this repo's flake) in the
# background and registers it as a Nix distributed-build machine.
#
# Determinate Nix under nix-darwin (determinateNix.enable = true) disables
# nix-darwin's own nix.* management, so `nix.linux-builder.enable` — the
# module that would normally write /etc/nix/machines and the ssh client
# config for us — is unavailable. `register` reproduces exactly what that
# module writes (nix-darwin's modules/nix/linux-builder.nix), by hand, via
# sudo. /etc/nix/nix.conf already carries `builders = @/etc/nix/machines`,
# so the daemon picks this up with zero rebuild.
#
# `start`/`stop` manage the VM as a plain background job (no launchd unit —
# that would need a darwin-rebuild): create-builder is launched with job
# control enabled so it gets its own process group, and `stop` signals that
# whole group so the qemu descendant (reached via create-builder -> its
# run-builder wrapper -> the generated run-*-vm script, which execs qemu)
# dies too.
set -euo pipefail
cd "$(dirname "$0")/.."
repo_root="$(pwd)"

work_dir="dev/.linux-builder"
keys_dir="$work_dir/keys"
log_file="$work_dir/vm.log"
pid_file="$work_dir/vm.pid"
priv_key="$keys_dir/builder_ed25519"

ssh_port=31022
machines_line="ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 1 1 kvm,benchmark,big-parallel - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo="
ssh_client_conf="Host linux-builder
  User builder
  Hostname localhost
  HostKeyAlias linux-builder
  Port ${ssh_port}
  IdentityFile /etc/nix/builder_ed25519
"

ssh_opts=(-p "$ssh_port" -i "$priv_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes)

is_running() {
  [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

wait_for_ssh() {
  local tries=$1
  for ((i = 0; i < tries; i++)); do
    if ssh "${ssh_opts[@]}" builder@localhost true 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  return 1
}

cmd_start() {
  if is_running; then
    echo "linux-builder already running (pid $(cat "$pid_file"))"
    return 0
  fi
  mkdir -p "$keys_dir"

  local builder
  git -C "$repo_root" add -A >/dev/null 2>&1 || true  # flakes only see tracked files
  builder=$(nix build --no-link --print-out-paths "$repo_root#linux-builder")
  echo "built $builder"

  (
    cd "$work_dir"
    set -m
    KEYS="$repo_root/$keys_dir" nohup "$builder/bin/create-builder" >vm.log 2>&1 &
    echo $! >vm.pid
  )
  echo "booting linux-builder VM (pid $(cat "$pid_file")), log: $log_file"

  if ! wait_for_ssh 36; then
    echo "linux-builder: ssh did not come up after 3 minutes; see $log_file" >&2
    exit 1
  fi
  echo "linux-builder ssh is up on 127.0.0.1:${ssh_port}"
}

cmd_stop() {
  if ! is_running; then
    echo "linux-builder not running"
    rm -f "$pid_file"
    return 0
  fi
  local pid
  pid=$(cat "$pid_file")
  echo "stopping linux-builder (pid $pid)"
  kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  for ((i = 0; i < 20; i++)); do
    is_running || break
    sleep 1
  done
  if is_running; then
    echo "linux-builder still up, sending SIGKILL"
    kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
}

cmd_status() {
  if is_running; then
    echo "linux-builder running (pid $(cat "$pid_file"))"
  else
    echo "linux-builder not running"
  fi
  if [ -f /etc/nix/machines ] && grep -qF "linux-builder" /etc/nix/machines; then
    echo "registered: /etc/nix/machines has a linux-builder entry"
  else
    echo "not registered: run '$0 register'"
  fi
}

cmd_register() {
  if [ ! -f /etc/nix/machines ] || [ "$(cat /etc/nix/machines)" != "$machines_line" ]; then
    printf '%s\n' "$machines_line" | sudo tee /etc/nix/machines >/dev/null
    echo "wrote /etc/nix/machines"
  else
    echo "/etc/nix/machines already up to date"
  fi

  local ssh_conf_path=/etc/ssh/ssh_config.d/100-linux-builder.conf
  if [ ! -f "$ssh_conf_path" ] || [ "$(cat "$ssh_conf_path")" != "$ssh_client_conf" ]; then
    printf '%s' "$ssh_client_conf" | sudo tee "$ssh_conf_path" >/dev/null
    echo "wrote $ssh_conf_path"
  else
    echo "$ssh_conf_path already up to date"
  fi
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  register) cmd_register ;;
  *)
    echo "usage: $0 {start|stop|status|register}" >&2
    exit 1
    ;;
esac
