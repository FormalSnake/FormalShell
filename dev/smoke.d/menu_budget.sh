# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # dev/smoke.sh reads leg_* and supplies shot_dir, the *_bin paths and fail()
# --menu-budget: the rust rewrite spec's launcher budget, read off the
# shell's own commit log. The bar's badge spins throughout (`debug
# r0Spinner`, the herdr badge's spinner) while the launcher opens and
# closes five times over `menu toggle`. Two numbers per open: the time from
# the toggle reaching the shell to the launcher surface's first commit
# (budget 50 ms), and the longest gap between two bar commits from the
# toggle to a second after it (budget 33 ms, two frames at 60 Hz). Then
# five seconds with the launcher open at rest, which must commit nothing.
#
# Only the rust shell logs its commits, so under QML the leg prints its
# numbers as skipped.
leg_menu_budget_flag="--menu-budget"
leg_menu_budget_order=22
leg_menu_budget_needs=""
leg_menu_budget_rust=1

leg_menu_budget_timing() {
  leg_timing 30 60
}

leg_menu_budget_drive() {
  local script="$shot_dir/menu-budget-drive.sh"
  write_script "$script" <<EOF
#!/usr/bin/env bash
sleep 4
$ipc call debug r0Spinner true > /dev/null 2>&1
sleep 1
for i in 1 2 3 4 5; do
  $ipc call menu toggle > /dev/null 2>&1
  sleep 1.5
  $ipc call menu toggle > /dev/null 2>&1
  sleep 1
done
$ipc call debug r0Spinner false > /dev/null 2>&1
sleep 1
$ipc call menu toggle > /dev/null 2>&1
sleep 2
echo rest-start > "$shot_dir/menu-budget-rest"
sleep 5
echo rest-end >> "$shot_dir/menu-budget-rest"
$ipc call menu toggle > /dev/null 2>&1
EOF
  hypr_exec_once "bash $script"
}

leg_menu_budget_assert() {
  if [ "$fs_impl" != rust ]; then
    echo "SMOKE_MENU_BUDGET skipped: only the rust shell logs its commits"
    return 0
  fi
  local out
  out=$(awk '
    function t(line) { match(line, /t=[0-9]+ms/); return substr(line, RSTART + 2, RLENGTH - 4) + 0 }
    /^ipc t=.*function: "toggle"/ && /target: "menu"/ { n++; if (n % 2 == 1 && n <= 10) { open[++o] = t($0) } ; if (n == 11) rest = t($0) }
    /^commit surface=menu / { mc[++m] = t($0) }
    /^commit surface=bar / { bc[++b] = t($0) }
    END {
      worst_first = 0; worst_gap = 0
      for (i = 1; i <= o; i++) {
        first = -1
        for (j = 1; j <= m; j++) if (mc[j] >= open[i]) { first = mc[j] - open[i]; break }
        gap = 0; last = -1
        for (j = 1; j <= b; j++) {
          if (bc[j] < open[i]) { last = bc[j]; continue }
          if (bc[j] > open[i] + 1000) break
          if (last >= 0 && bc[j] - last > gap) gap = bc[j] - last
          last = bc[j]
        }
        printf "open %d first_commit_ms=%d bar_gap_ms=%d\n", i, first, gap
        if (first < 0 || first > worst_first) worst_first = (first < 0 ? 99999 : first)
        if (gap > worst_gap) worst_gap = gap
      }
      # The frame interval of the session itself while the badge spins and nothing
      # else moves: the mean bar gap in the second before the first open.
      k = 0; sum = 0
      for (j = 2; j <= b; j++) if (bc[j] < open[1] && bc[j-1] > open[1] - 1000) { k++; sum += bc[j] - bc[j-1] }
      base = k ? sum / k : 0
      quiet = 0
      for (j = 1; j <= m; j++) if (mc[j] > rest + 2000 && mc[j] < rest + 7000) quiet++
      printf "worst first_commit_ms=%d bar_gap_ms=%d rest_commits=%d opens=%d frame_ms=%d\n", worst_first, worst_gap, quiet, o, base
    }' "$shell_log_path")
  echo "$out" | sed 's/^/SMOKE_MENU_BUDGET /'
  local worst
  worst=$(echo "$out" | tail -1)
  local first gap quiet opens
  first=$(echo "$worst" | sed -n 's/.*first_commit_ms=\([0-9]*\).*/\1/p')
  gap=$(echo "$worst" | sed -n 's/.*bar_gap_ms=\([0-9]*\).*/\1/p')
  quiet=$(echo "$worst" | sed -n 's/.*rest_commits=\([0-9]*\).*/\1/p')
  opens=$(echo "$worst" | sed -n 's/.*opens=\([0-9]*\).*/\1/p')
  [ "${opens:-0}" -eq 5 ] || fail "menu budget: saw ${opens:-0} launcher opens in the shell log, wanted 5"
  [ "$first" -le 50 ] || fail "menu budget: a launcher open took ${first}ms to its first commit (budget 50)"
  local frame
  frame=$(echo "$worst" | sed -n 's/.*frame_ms=\([0-9]*\).*/\1/p')
  # A compositor pacing frames at 30 Hz (the VM's vkms card) puts every
  # gap at 33 ms already: the budget is only readable on a 60 Hz output.
  if [ "${frame:-0}" -gt 20 ]; then
    echo "SMOKE_MENU_BUDGET bar gap unreadable here: this session's own frame interval is ${frame}ms"
  else
    [ "$gap" -le 33 ] || fail "menu budget: the bar went ${gap}ms without a frame across an open (budget 33)"
  fi
  [ "$quiet" -eq 0 ] || fail "menu budget: the launcher committed $quiet times while open at rest"
}
