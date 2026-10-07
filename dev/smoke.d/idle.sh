# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --idle: the rust rewrite spec's idle and cold start budgets, read under
# whatever settings the scaffold writes (the default bar, every cell it
# ships). Cold start is the launch stamp to the bar's first commit, with
# the shell's own `phase` lines between. Idle is 60 s with nothing driven,
# 20 s after the launch: CPU ticks and context switches of every thread
# (a voluntary switch is a sleep, so each one is a wakeup), the frame
# callbacks the shell asked for, and the commits it made. Under FS_CPU_QUOTA
# this is the e1504g power saver stand-in.
#
# Rust only: the QML shell logs neither phases nor commits.
leg_idle_flag="--idle"
leg_idle_order=901
leg_idle_needs=""

idle_results_path="$shot_dir/idle-results.txt"
idle_start_path="$shot_dir/shell-start.ns"
idle_done_path="$shot_dir/idle-done"

leg_idle_shell() {
  local software=""
  if [ "$session_mode" = vkms ]; then software="export LIBGL_ALWAYS_SOFTWARE=1"; fi
  write_script "$1" <<EOF
#!/usr/bin/env bash
$software
date '+%s%N' > "$idle_start_path"
$shell_prefix "$shell_bin" > "$shell_log_path" 2>&1 &
echo \$! > "$shot_dir/shell.pid"
wait
EOF
}

leg_idle_timing() {
  leg_timing 115 150
}

leg_idle_drive() {
  local script="$shot_dir/idle-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
# Per thread: name, utime+stime ticks, voluntary and involuntary switches.
sample() {
  for t in /proc/\$pid/task/*; do
    name=\$(cat "\$t/comm" 2>/dev/null) || continue
    ticks=\$(sed 's/.*) //' "\$t/stat" | awk '{print \$12 + \$13}')
    vol=\$(awk '/^voluntary_ctxt_switches/{print \$2}' "\$t/status")
    inv=\$(awk '/^nonvoluntary_ctxt_switches/{print \$2}' "\$t/status")
    echo "\${t##*/} \$name \$ticks \$vol \$inv"
  done
}
for _ in \$(seq 100); do
  pid=\$(cat "$shot_dir/shell.pid" 2>/dev/null) && [ -r "/proc/\$pid/stat" ] && break
  sleep 0.1
done
sleep 20
sample > "$shot_dir/idle-before.txt"
c0=\$(grep -c '^commit ' "$shell_log_path")
echo "idle-start \$(date +%s%N)" > "$shot_dir/idle-marks.txt"
sleep 60
sample > "$shot_dir/idle-after.txt"
c1=\$(grep -c '^commit ' "$shell_log_path")
echo "idle-end \$(date +%s%N)" >> "$shot_dir/idle-marks.txt"
awk 'NR == FNR { t[\$1] = \$3; v[\$1] = \$4; i[\$1] = \$5; next }
  { dt = \$3 - t[\$1]; dv = \$4 - v[\$1]; di = \$5 - i[\$1]; tt += dt; tv += dv
    printf "thread %s %s ticks=%d wakeups=%d preempted=%d\n", \$1, \$2, dt, dv, di }
  END { printf "total ticks=%d wakeups=%d clk_tck=%d\n", tt, tv, '"\$(getconf CLK_TCK)"' }' \
  "$shot_dir/idle-before.txt" "$shot_dir/idle-after.txt" > "$idle_results_path"
echo "commits \$((c1 - c0))" >> "$idle_results_path"
# Then 20 s under strace, after the sample so its cost is not counted: the
# syscall each wakeup came back from names its waker.
if command -v strace > /dev/null; then
  st=strace; [ "\$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null)" = 0 ] || st="sudo -n strace"
  timeout -s INT 20 \$st -f -tt -T -p "\$pid" -o "$shot_dir/idle-strace.log" > /dev/null 2>&1 || true
fi
touch "$idle_done_path"
EOF
  hypr_exec_once "bash $script"
}

leg_idle_assert() {
  [ -f "$idle_done_path" ] || fail "--idle: the drive never finished its sample"
  local start first
  start=$(cat "$idle_start_path")
  first=$(awk '/^commit surface=bar n=1 /{match($0, /t=[0-9]+ms/); print substr($0, RSTART + 2, RLENGTH - 4); exit}' "$shell_log_path")
  awk -v start="$start" '/^start epoch_us=/{ split($2, a, "="); printf "SMOKE_IDLE launch_to_zero_ms=%d\n", (a[2] * 1000 - start) / 1000000 }' "$shell_log_path"
  grep -E '^phase ' "$shell_log_path" | sed 's/^/SMOKE_IDLE /'
  echo "SMOKE_IDLE first_bar_commit_ms=${first:-none}"
  sed 's/^/SMOKE_IDLE /' "$idle_results_path"
  echo "SMOKE_IDLE_LOG $shell_log_path"
  if [ -s "$shot_dir/idle-strace.log" ]; then echo "SMOKE_IDLE_STRACE $shot_dir/idle-strace.log"; fi
}
