# g815 HEAD re-sweep — real-hardware verification, 2026-07-29

Context: the owner spotted a large left/top-only gutter on published bar
screenshots. Root cause is stale images, not a live bug — all
`docs/screenshots/*.png` were committed at `98d1493` (2026-07-28 18:08)
while the padding fix `ca56dfc` landed at 20:43, ~2.5h later. This sweep
recaptures every niri smoke mode from real hardware (g815) at HEAD
`52e2db0` to confirm the fix and close the hardware-evidence gap
`docs/SWITCHOVER.md` names.

Host: g815, 24 cores, real battery/Wi-Fi (`wlp129s0f0`)/Bluetooth/backlight
(`nvidia_wmi_ec_backlight`)/multiple audio sinks. Repo at
`~/Developer/FormalShell`, confirmed `git rev-parse HEAD` = `52e2db0` before
this sweep started. `nix build .#formalshell` already complete on g815
(`/nix/store/wqpb8smxwf3jyxz43wjw15wdz3518267-formalshell-0.1.0-dev`) — no
warm-up build run here.

This is half A of 2: covers the 8 modes below. Half B covers the remaining
`--panel <name>` variants, `--lock`, `--screensaver`, `--picker`, `--media`,
and the Hyprland backend.

Screenshots copied to `artifacts/g815-head/<mode-slug>.png` on the mac
(gitignored, not committed).

## Results

(filled in as each mode runs)
