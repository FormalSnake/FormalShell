# Switching a real machine over

FormalShell is pre-alpha. This is the honesty check to read before you put
it on a machine you depend on: what has been proven on real hardware, what
has only ever run in a VM, and what the host has to provide before a given
surface can work at all. The install mechanics live in
[`README.md`](../README.md#install); this document is the risk.

Two things shape everything below. First, the verification rig is a nested
compositor under software rendering, so it proves that a surface works, not
that it works against your hardware. Second, every real-hardware sweep so
far has been niri only. The Hyprland backend implements the same contract
and passes its own checks, but it has never run on a real machine.

## Host prerequisites

Each of these is something the shell cannot install for you. Where one is
missing the surface says so honestly rather than failing silently, but it
still doesn't work.

| Surface | Needs |
| --- | --- |
| Lock screen | `security.pam.services.formalshell-lock`, which `nixosModules.formalshell` declares for you. Without it PAM has nothing to authenticate against |
| Weather | geoclue2 and its agent, also from that module |
| External monitor brightness | `hardware.i2c.enable = true` (or `modprobe i2c-dev`) and your user in the `i2c` group. Without both, `ddcutil detect` finds nothing and the panel shows backlight rows only |
| Polkit prompts | your existing polkit agent dropped from the host config. Only one agent can register per session, and this one never fights for the name |
| Menu share | `localsend` installed, plus inbound 53317/tcp and 53317/udp for peer discovery |
| AirPods panel | the `omarchy-pods` fork of the `librepods` daemon running as `librepods --headless`. The stock librepods tray app is write-only and cannot feed this panel |
| DualSense panel | `hid-playstation` bound, and your own udev LED rule if you want lightbar and player LEDs readable |
| Tailscale toggle | `sudo tailscale set --operator=$USER`, once per host. Status polling needs no grant; only up and down do |
| Calendar via online accounts | `services.gnome.evolution-data-server.enable` and `services.gnome.gnome-online-accounts.enable` |

The shell's own wrapper carries matugen, grim, slurp, wl-clipboard,
wf-recorder, tesseract, ffmpeg, ttfx, cava, ddcutil, qrencode,
brightnessctl and wtype, so none of those are host prerequisites. The
daemon-paired CLIs (`nmcli`, `bluetoothctl`, `pactl`) stay off it on
purpose, since they have to match the NetworkManager, bluez and PipeWire
your system is actually running.

## What has run on real hardware

Swept on two niri machines, e1504g and g815, most recently at commit
`52e2db0`:

Bar, menu, notifications, clipboard, picker, screensaver, now playing,
theming through matugen, the OSD, and the network, audio, bluetooth, power
and calendar panels (local `.ics` path only).

Those sweeps found five defects the VM structurally could not surface, all
in populated-state paths: Wi-Fi signal scaled 0..1 as 0..100, UPower
strings title-cased wrong, the OSD's auto-show signal, an audio panel
elision bug, and a Bluetooth title-case bug. All five are fixed and
visually reconfirmed on hardware, and the last full sweep found no new
ones. That is one dry well, not a guarantee: anywhere a real string or
number from hardware gets formatted for display is the same class of risk.

## What has only run in a VM

Everything else, which is most of the newer surfaces: the greeter, the
lock screen's real-PAM success and failure paths, the SNI tray, the
indicators slot, settings-driven bar layout and custom modules, the bar
chevron, the notification bell, card density and repeat collapse, the
weather, github, usage, tailscale, AirPods and DualSense cells and panels,
the opt-in microphone, keyboard-layout and system-update cells, EDS and
RRULE calendar events, day selection, the menu's calculator, emoji, nix
runner, keybinds, share and toggle routes, app names and icons,
launch-or-focus, the region picker, OCR and color pick, reminders, plugins,
polkit, night light, the no-wallpaper theme toggle, and continuous
screensaver cycling.

Surfaces added after that sweep have no entry at all: the quake console,
the display panel, the system monitor and its process table, and the
launcher's view routes. Treat them as VM-only.

Two of those deserve calling out. **The GOA OAuth path has never run
anywhere**, since the VM's evidence is a local EDS calendar; a real Google
or Nextcloud account through GNOME Online Accounts is exactly what a real
host has to prove. **Screen recording has no evidence of any kind**: nested
niri under llvmpipe advertises `zwp_linux_dmabuf_v1` version 3 and
wf-recorder binds version 4 unconditionally, so the bind is rejected before
a recording can start. That is an environment limit with no workaround
inside this repo, so the recorder child, both audio modes, the GIF
transcode and the bar's recording cell all reach a real host unproven.

## Rough edges to know about

**The Hyprland backend is flaky in the sandboxed dev loop** and has never
run on real hardware. Both backends implement the same `CompositorBackend`
contract, but only niri has mileage.

**The greeter has no session or user picker**, and that is greetd's wire
protocol rather than a gap here: it has no enumeration call anywhere in it.
The session launched on a successful login is the fixed `sessionCommand`
from your Nix config, and the username is free-text entry.

**Window capture looks different on niri.** niri reports a pixel box only
for floating windows, so a tiled window has no rectangle to highlight. The
picker names those windows in a card instead and captures through niri's
own server-side crop. Selection works on both backends; only the
affordance differs, and the branch is on whether a rectangle exists rather
than on a compositor name.

**A `menu.jsonc` written before the toggle hub goes inert silently.**
`theme` became `toggles`, `theme.mode-toggle` became `toggles.dark-mode`,
and `system.stay-awake` became `toggles.stay-awake`. An override naming an
id that no longer exists is not an error: it matches nothing, so your
customization disappears and the default row renders instead.

## What "ready" would mean

1. Every VM-only surface above verified on at least one real machine,
   starting with the greeter and the lock screen's real-PAM paths, since
   switching over is itself the first real test of both.
2. Screen recording proven at all, from a standing start.
3. A daily-drive stretch on a machine that is not the primary one.
4. One full sweep cycle with no new hardware-only defect class.
