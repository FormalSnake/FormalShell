#!/usr/bin/env bash
# Builds a 300-icon theme once, then runs the stress shell N times each
# with async and sync image loads, printing the miss count per run.
set -u
theme="$HOME/.local/share/icons/stress"
if [ ! -f "$theme/index.theme" ]; then
  mkdir -p "$theme/scalable/apps"
  src=/run/current-system/sw/share/icons/hicolor/scalable/apps/foot.svg
  for i in $(seq 0 299); do cp "$src" "$theme/scalable/apps/stress-$i.svg"; done
  printf '[Icon Theme]\nName=stress\nInherits=hicolor\nDirectories=scalable/apps\n\n[scalable/apps]\nSize=48\nType=Scalable\n' > "$theme/index.theme"
fi
dir=$(cd "$(dirname "$0")" && pwd)
for mode in 1 0; do
  echo "== STRESS_ASYNC=$mode"
  for n in $(seq 1 ${RUNS:-12}); do
    STRESS_ASYNC=$mode QS_ICON_THEME=stress timeout 20 qs -p "$dir" 2>&1 | grep -o "MISSES [0-9]* of [0-9]*" || echo "MISSES (no output)"
  done
done
