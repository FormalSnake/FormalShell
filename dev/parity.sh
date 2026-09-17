#!/usr/bin/env bash
# Diffs one dev/smoke.sh leg combination between this worktree's branch and
# a worktree at origin/main (../FormalShell-main, sibling to this one), so a
# theme migration can be checked pixel-for-pixel instead of by eye alone.
#
#   dev/parity.sh --gallery
#   dev/parity.sh --panel network --notify --tooltip
#
# Runs `just vm-smoke <flags>` once per side, each through dev/vm-lock.sh so
# the two never share the VM concurrently, with that side's directory as
# cwd (dev/vm.sh sync rsyncs the cwd's own working tree). dev/vm.sh smoke
# already copies every frame it produces into that directory's own
# artifacts/ and echoes "pulled screenshot: <path>" for each; this script
# reads those lines rather than re-deriving paths from the VM-side
# SMOKE_OK/SMOKE_<NAME> lines. The primary SMOKE_OK frame's local name
# carries a run timestamp (dev/vm.sh's own naming), so it is renamed to
# primary.png here to pair across the two runs; every other frame's
# basename is already stable leg to leg.
#
# compare -metric AE (ImageMagick 7) then diffs every frame present on both
# sides into artifacts/parity/diff/<tag>/, printing one
# "PARITY <tag> <name> <ae-count>" line per frame. A frame missing from one
# side, or whose two sides differ in geometry, prints a FAIL line instead
# of a count. Nothing outside artifacts/parity/ is ever removed.
set -euo pipefail
cd "$(dirname "$0")/.."
repo_root="$(pwd)"
main_dir="$repo_root/../FormalShell-main"

if [ $# -eq 0 ]; then
  echo "usage: $0 <smoke flags...>" >&2
  exit 1
fi

if [ ! -d "$main_dir" ]; then
  echo "parity: no worktree at $main_dir" >&2
  exit 1
fi

tag_parts=()
for flag in "$@"; do
  tag_parts+=("${flag#--}")
done
tag=$(IFS=-; echo "${tag_parts[*]}")

main_out="$repo_root/artifacts/parity/main/$tag"
branch_out="$repo_root/artifacts/parity/branch/$tag"
diff_out="$repo_root/artifacts/parity/diff/$tag"
rm -rf "$main_out" "$branch_out" "$diff_out"
mkdir -p "$main_out" "$branch_out" "$diff_out"

# Runs the leg from worktree $1, copying its frames into directory $2.
run_side() {
  local dir="$1" out="$2"
  shift 2
  local log status=0
  log=$(cd "$dir" && dev/vm-lock.sh just vm-smoke "$@" 2>&1) || status=$?
  printf '%s\n' "$log"
  if [ "$status" -ne 0 ]; then
    echo "parity: smoke run failed in $dir (exit $status)" >&2
    exit "$status"
  fi
  local line path base
  while IFS= read -r line; do
    case "$line" in
      "pulled screenshot: "*)
        path="${line#pulled screenshot: }"
        base="$(basename "$path")"
        case "$base" in
          smoke-*.png) base="primary.png" ;;
        esac
        cp "$path" "$out/$base"
        ;;
    esac
  done <<< "$log"
}

run_side "$main_dir" "$main_out" "$@"
run_side "$repo_root" "$branch_out" "$@"

shopt -s nullglob
for main_png in "$main_out"/*.png; do
  name=$(basename "$main_png" .png)
  branch_png="$branch_out/$name.png"
  if [ ! -e "$branch_png" ]; then
    echo "PARITY $tag $name FAIL missing-on-branch"
    continue
  fi
  main_size=$(magick identify -format '%wx%h' "$main_png")
  branch_size=$(magick identify -format '%wx%h' "$branch_png")
  if [ "$main_size" != "$branch_size" ]; then
    echo "PARITY $tag $name FAIL size $main_size-vs-$branch_size"
    continue
  fi
  ae_status=0
  ae=$(compare -metric AE "$main_png" "$branch_png" "$diff_out/$name.png" 2>&1) || ae_status=$?
  if [ "$ae_status" -gt 1 ]; then
    echo "PARITY $tag $name FAIL compare-exit-$ae_status: $ae"
    continue
  fi
  echo "PARITY $tag $name $ae"
done

for branch_png in "$branch_out"/*.png; do
  name=$(basename "$branch_png" .png)
  if [ ! -e "$main_out/$name.png" ]; then
    echo "PARITY $tag $name FAIL missing-on-main"
  fi
done
shopt -u nullglob
