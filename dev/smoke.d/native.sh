# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --native <pkgdir>: the Arch, Debian or Ubuntu packages in <pkgdir>,
# installed with pacman or apt into a rootless podman image of the release
# they were built for, and the /usr/bin/formalshell they install run in
# place of the Nix package. A Debian release is read off the formalshell
# package's version suffix (0.1.0-1+trixie), which packaging/debian/build.sh
# writes. Arch on aarch64 is Arch Linux ARM, which has no official image.
# dev/native-check.sh builds the packages on the mac and runs this per
# release.
#
# The container sees the session through its own XDG_RUNTIME_DIR holding
# the session's Wayland socket and Hyprland instance directory, and nothing
# else of the host's: it runs the shell under its own dbus-run-session, so
# neither the host bus nor the rig's is reachable from it. It runs as the
# host uid (keep-id), which the image also gives an account whose password
# is the VM's, so the lock round trip goes through the package's own
# /etc/pam.d/formalshell-lock and the release's own pam_unix.
#
# What it proves, all over the package's own formalshell-ipc inside the
# container: a debug dump reporting a connected hyprland backend, the bar
# drawn, `menu toggle` opening the launcher, and a lock that a wrong
# password answers with "Wrong password" (a missing or broken PAM service
# reads "PAM error") and the real one unlocks.
leg_native_flag="--native <pkgdir>"
leg_native_order=5
leg_native_needs="wtype jq convert"

native_home=$HOME
native_container=formalshell-native
native_dump_path="$shot_dir/native-dump.json"
native_menu_path="$shot_dir/native-menu-status.json"
native_lock_rc_path="$shot_dir/native-lock-rc.txt"
native_islocked1_path="$shot_dir/native-islocked-1.txt"
native_islocked2_path="$shot_dir/native-islocked-2.txt"
native_wrong_path="$shot_dir/native-lock-wrong.json"
native_status_path="$shot_dir/native-lock-status.json"
native_done_path="$shot_dir/native-done"
native_bar_png="$shot_dir/native-bar.png"
native_menu_png="$shot_dir/native-menu.png"
native_locked_png="$shot_dir/native-locked.png"
native_error_png="$shot_dir/native-error.png"
native_unlocked_png="$shot_dir/native-unlocked.png"

# Podman's own store and config live under the real HOME: every script the
# session runs sees the rig's isolated one, and the private bus in
# DBUS_SESSION_BUS_ADDRESS has no systemd on it to place the container.
native_podman_fn() {
  cat <<EOF
pm() {
  env -u DBUS_SESSION_BUS_ADDRESS -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
    HOME="$native_home" podman "\$@"
}
EOF
}

leg_native_validate() {
  local dir pkg
  dir=$(leg_arg native)
  command -v podman >/dev/null 2>&1 || { echo "--native needs podman on PATH" >&2; exit 1; }
  if pkg=$(find "$dir" -maxdepth 1 -name 'formalshell_*_all.deb' 2>/dev/null | grep .); then
    native_suite=$(basename "$pkg" | sed -n 's/^formalshell_[^+]*+\([a-z]*\)_all\.deb$/\1/p')
  elif pkg=$(find "$dir" -maxdepth 1 -name 'formalshell-[0-9]*-any.pkg.tar.*' 2>/dev/null | grep .); then
    native_suite=arch
  else
    echo "--native: no formalshell package in $dir" >&2
    exit 1
  fi
  case $native_suite/$(uname -m) in
    trixie/*) native_base=docker.io/library/debian:trixie ;;
    forky/*) native_base=docker.io/library/debian:forky ;;
    sid/*) native_base=docker.io/library/debian:sid ;;
    resolute/*) native_base=docker.io/library/ubuntu:26.04 ;;
    arch/x86_64) native_base=docker.io/library/archlinux:latest ;;
    arch/aarch64) native_base=docker.io/menci/archlinuxarm:latest ;;
    *) echo "--native: no base image for '$native_suite' on $(uname -m) ($pkg)" >&2; exit 1 ;;
  esac
  native_pkgdir=$(cd "$dir" && pwd)
  native_image=localhost/formalshell-native:$native_suite
}

leg_native_fixture() {
  local containerfile="$shot_dir/native.Containerfile"
  # pacman's download sandbox needs Landlock, which a rootless container is
  # refused. Ubuntu's image already holds uid 1000 as `ubuntu`.
  if [ "$native_suite" = arch ]; then
    cat > "$containerfile" <<EOF
FROM $native_base
ARG UID
COPY . /pkgs/
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf \
 && pacman-key --init && pacman-key --populate \
 && pacman -Syu --noconfirm && pacman -U --noconfirm /pkgs/*.pkg.tar.* \
 && useradd -u \$UID -m test && echo test:formalshell-test | chpasswd \
 && pacman -Scc --noconfirm
EOF
  else
    cat > "$containerfile" <<EOF
FROM $native_base
ARG UID
COPY . /pkgs/
RUN if getent passwd \$UID >/dev/null; then userdel -r "\$(getent passwd \$UID | cut -d: -f1)"; fi \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y /pkgs/*.deb dbus \
 && useradd -u \$UID -m test && echo test:formalshell-test | chpasswd \
 && rm -rf /var/lib/apt/lists/*
EOF
  fi
  echo "native: $native_suite on $native_base from $native_pkgdir"
  HOME=$native_home podman build -q --build-arg UID="$(id -u)" -t "$native_image" \
    -f "$containerfile" "$native_pkgdir"
  mkdir -p -m 700 "$shot_dir/native-runtime"
}

leg_native_shell() {
  local uid rt
  uid=$(id -u)
  rt=/run/user/$uid
  write_script "$1" <<EOF
#!/usr/bin/env bash
$(native_podman_fn)
pm rm -f $native_container > /dev/null 2>&1
pm run --rm --name $native_container --userns=keep-id --network none \\
  -v "$shot_dir/native-runtime:$rt" \\
  -v "\$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY:$rt/\$WAYLAND_DISPLAY" \\
  -v "\$XDG_RUNTIME_DIR/hypr/\$HYPRLAND_INSTANCE_SIGNATURE:$rt/hypr/\$HYPRLAND_INSTANCE_SIGNATURE" \\
  -v "$iso_home:$iso_home" \\
  -e XDG_RUNTIME_DIR=$rt -e WAYLAND_DISPLAY -e HYPRLAND_INSTANCE_SIGNATURE \\
  -e XDG_CURRENT_DESKTOP=Hyprland -e XDG_SESSION_TYPE=wayland \\
  -e HOME="$iso_home" -e XDG_CONFIG_HOME="$iso_home/.config" \\
  -e XDG_STATE_HOME="$iso_home/.local/state" -e XDG_DATA_HOME="$iso_home/.local/share" \\
  -e XDG_CACHE_HOME="$iso_home/.cache" \\
  -e XDG_DATA_DIRS="$iso_home/.local/share:/usr/local/share:/usr/share" \\
  -e LIBGL_ALWAYS_SOFTWARE=1 -e LANG=C.UTF-8 \\
  "$native_image" dbus-run-session -- formalshell > "$shell_log_path" 2>&1 &
for _ in \$(seq 60); do
  pid=\$(pgrep -n -u $uid -f '^/usr/bin/quickshell -p /usr/share/formalshell\$') && break
  sleep 1
done
[ -n "\${pid:-}" ] && echo "\$pid" > "$shot_dir/shell.pid"
wait
EOF
}

leg_native_timing() {
  leg_timing 95 140
}

leg_native_drive() {
  local script="$shot_dir/native-drive.sh" stop="$shot_dir/native-stop.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
$(native_podman_fn)
ipc() { pm exec $native_container formalshell-ipc call "\$@"; }
for _ in \$(seq 60); do
  ipc debug dump > "$native_dump_path" 2>/dev/null && grep -qF '"compositor":"hyprland","available":true' "$native_dump_path" && break
  sleep 1
done
sleep 3
"$grim_bin" "$native_bar_png" > /dev/null 2>&1
ipc menu toggle > /dev/null 2>&1
sleep 2
ipc menu status > "$native_menu_path" 2>&1
"$grim_bin" "$native_menu_png" > /dev/null 2>&1
ipc menu toggle > /dev/null 2>&1
sleep 1
ipc lock lock > /dev/null 2>&1
echo \$? > "$native_lock_rc_path"
sleep 1
ipc lock isLocked > "$native_islocked1_path" 2>&1
sleep 3
"$grim_bin" "$native_locked_png" > /dev/null 2>&1
"$wtype_bin" "wrong-password"
"$wtype_bin" -k Return
sleep 5
"$grim_bin" "$native_error_png" > /dev/null 2>&1
ipc lock status > "$native_wrong_path" 2>&1
"$wtype_bin" "formalshell-test"
"$wtype_bin" -k Return
sleep 3
"$grim_bin" "$native_unlocked_png" > /dev/null 2>&1
ipc lock isLocked > "$native_islocked2_path" 2>&1
ipc lock status > "$native_status_path" 2>&1
touch "$native_done_path"
EOF
  write_script "$stop" <<EOF
#!/usr/bin/env bash
$(native_podman_fn)
pm stop -t 3 $native_container > /dev/null 2>&1 || true
EOF
  add_cleanup "bash $stop"
  hypr_exec_once "bash $script"
}

leg_native_assert() {
  local f top_sd
  [ -f "$native_done_path" ] || fail "native: the drive script never finished"
  for f in "$native_bar_png" "$native_menu_png" "$native_locked_png" "$native_error_png" "$native_unlocked_png"; do
    [ -f "$f" ] || fail "native: no screenshot at $f"
  done
  echo "SMOKE_NATIVE_BAR $native_bar_png"
  echo "SMOKE_NATIVE_MENU $native_menu_png"
  echo "SMOKE_NATIVE_LOCKED $native_locked_png"
  echo "SMOKE_NATIVE_ERROR $native_error_png"
  echo "SMOKE_NATIVE_UNLOCKED $native_unlocked_png"
  cat "$native_dump_path"; echo
  grep -qF '"compositor":"hyprland","available":true' "$native_dump_path" \
    || fail "native: the dump does not report a connected hyprland backend: $(cat "$native_dump_path")"
  # The strip's own band: a bare desktop there is one flat colour.
  top_sd=$($convert_bin "$native_bar_png" -crop 1920x40+0+0 +repage -colorspace gray -format '%[fx:standard_deviation]' info:)
  echo "native: bar band stddev $top_sd"
  awk -v s="$top_sd" 'BEGIN { exit !(s > 0.02) }' || fail "native: nothing drawn in the bar's band"
  $jq_bin -e '.isOpen == true' "$native_menu_path" > /dev/null \
    || fail "native: menu toggle did not open the launcher: $(cat "$native_menu_path")"
  cmp -s "$native_bar_png" "$native_menu_png" && fail "native: the launcher frame is the bar frame"
  grep -q '^0$' "$native_lock_rc_path" || fail "native: lock lock exited $(cat "$native_lock_rc_path")"
  grep -q '^true$' "$native_islocked1_path" || fail "native: isLocked after lock: $(cat "$native_islocked1_path")"
  $jq_bin -e '.authError == "Wrong password"' "$native_wrong_path" > /dev/null \
    || fail "native: a wrong password did not read as one through formalshell-lock: $(cat "$native_wrong_path")"
  grep -q '^false$' "$native_islocked2_path" \
    || fail "native: the real password did not unlock: $(cat "$native_islocked2_path") $(cat "$native_status_path")"
  cmp -s "$native_locked_png" "$native_unlocked_png" && fail "native: the locked frame is the unlocked frame"
  echo "NATIVE_OK $native_suite"
}
