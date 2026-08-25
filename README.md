```

  ▄▄▄▄▄▄▄                       ▄▄   ▄▄▄▄▄              ▄▄ ▄▄
 █▀██▀▀▀                         ██ ██▀▀▀▀█▄ █▄          ██ ██
   ██        ▄    ▄              ██ ▀██▄  ▄▀ ██          ██ ██
   ███▀▄███▄ ████▄███▄███▄ ▄▀▀█▄ ██   ▀██▄▄  ████▄ ▄█▀█▄ ██ ██
 ▄ ██  ██ ██ ██   ██ ██ ██ ▄█▀██ ██ ▄   ▀██▄ ██ ██ ██▄█▀ ██ ██
 ▀██▀ ▄▀███▀▄█▀  ▄██ ██ ▀█▄▀█▄██▄██ ▀██████▀▄██ ██▄▀█▄▄▄▄██▄██
```

[![CI](https://img.shields.io/github/actions/workflow/status/FormalSnake/FormalShell/ci.yml?branch=main&style=for-the-badge&labelColor=161616&color=4a9eda&logo=githubactions&logoColor=white&label=CI)](https://github.com/FormalSnake/FormalShell/actions/workflows/ci.yml)
[![Nix flake](https://img.shields.io/badge/nix-flake-4a9eda?style=for-the-badge&labelColor=161616&logo=nixos&logoColor=white)](flake.nix)
[![QuickShell](https://img.shields.io/badge/quickshell-QML-4a9eda?style=for-the-badge&labelColor=161616&logo=qt&logoColor=white)](https://quickshell.org/)
[![Wayland](https://img.shields.io/badge/wayland-hyprland-4a9eda?style=for-the-badge&labelColor=161616&logo=wayland&logoColor=white)](#install)
[![Status](https://img.shields.io/badge/status-pre--alpha-d35f5f?style=for-the-badge&labelColor=161616)](docs/SWITCHOVER.md)
[![License](https://img.shields.io/badge/license-MIT-cccccc?style=for-the-badge&labelColor=161616)](LICENSE)
[![Stars](https://img.shields.io/github/stars/FormalSnake/FormalShell?style=for-the-badge&labelColor=161616&color=161616&logo=github&logoColor=white)](https://github.com/FormalSnake/FormalShell/stargazers)

A Wayland desktop shell for [Hyprland](https://hypr.land), written in QML on
top of [QuickShell](https://quickshell.org/).
One process draws the bar, the launcher, the notifications, the lock screen
and the rest of it, and every color on screen is pulled out of your wallpaper
by matugen.

It looks like this:

![The FormalShell launcher over a wallpaper-derived palette](docs/screenshots/menu-hyprland.png)

Radius 10, one-pixel borders, sans for words and mono for values, Lucide
icons instead of Nerd Font glyphs. Surfaces sit at 85% opacity and Hyprland
does the blurring behind them; the shell draws no shadow and no gradient of
its own. The wallpaper used to come through a six-colour ordered dither, and
that is still there behind `wallpaper.dither`, off by default.

**Pre-alpha.** It boots, it is nice to use, and it will still surprise you.
[`docs/SWITCHOVER.md`](docs/SWITCHOVER.md) tracks what has been proven on
real hardware versus what has only ever run in a VM. Read it before you put
this on the laptop you need tomorrow morning.

## A tour

The launcher is the front door. Apps, clipboard history, a calculator, an
emoji picker that types the emoji for you, `nix run` for anything in nixpkgs,
your own compositor keybinds, wallpapers, toggles, and a `select`/`input`
mode that stands in for dmenu. Everything is one fuzzy search away and there
is a bar at the bottom telling you what Enter is about to do.

| | |
| :---: | :---: |
| <img src="docs/screenshots/notifications-center-hyprland.png" width="420"><br>Notification center, with DND and a real history | <img src="docs/screenshots/media-hyprland.png" width="420"><br>Now playing, over MPRIS |

Sixteen panels hang off the bar cells (audio, network, bluetooth, calendar,
weather, power, displays, system monitor, AirPods, and friends). A panel with
nothing to say prints `NO ADAPTER` rather than inventing a device, which is a
rule the whole shell follows: no faked values anywhere, including in the
screenshots above.

There is a full system monitor inside the launcher (per-core CPU, memory,
temps, disks, network rates, GPU where the driver will talk, plus a process
table you can kill things from), a screenshot and screen recording suite with
its own region picker, OCR, a color picker, and reminders that survive the
shell being restarted.

<img src="docs/screenshots/lock-hyprland.png" width="420"> <img src="docs/media/screensaver-decrypt.gif" width="360">

The lock screen is a real `WlSessionLock` with PAM behind it, and the greeter
is its twin at the login prompt. The screensaver runs
[ttfx](https://github.com/omacom-io/ttfx) and rerolls through its 37
effects until you touch something. Yes, that is what the idle timeout on your
machine should have been doing all along.

Everything above is driven over IPC, so any of it can be bound to a key:

```sh
qs ipc --any-display -p <store-path>/share/formalshell call menu summon
```

[`docs/USAGE.md`](docs/USAGE.md) has the full set of verbs, config keys, and
copy-paste binds for both compositors.

## Install

FormalShell is a Nix flake, and it installs as a system rather than as one
user program: a home-manager module for the shell, plus NixOS modules for the
things home-manager cannot reach (a PAM service for the lock screen, geoclue
for weather, greetd for the greeter).

```nix
{
  inputs.formalshell.url = "github:FormalSnake/FormalShell";

  outputs = { nixpkgs, home-manager, formalshell, ... }: {
    nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        formalshell.nixosModules.formalshell
        { services.formalshell.enable = true; }

        home-manager.nixosModules.home-manager
        {
          home-manager.users.me = {
            imports = [ formalshell.homeModules.default ];
            programs.formalshell = {
              enable = true;
              package = formalshell.packages.x86_64-linux.default;
            };
          };
        }
      ];
    };
  };
}
```

`services.formalshell.enable` switches on PAM, geoclue, NetworkManager,
bluez, upower, power-profiles-daemon and pipewire, each one behind its own
option and each defaulted with `mkDefault` so your existing config wins.
Without at least the PAM service the lock screen has nothing to authenticate
against, so do not skip the NixOS module.

For the login screen, add `formalshell.nixosModules.formalshell-greeter` and
point it at your session:

```nix
services.formalshell-greeter = {
  enable = true;
  package = formalshell.packages.x86_64-linux.formalshell-greeter;
  sessionCommand = [ "Hyprland" ];
};
```

The package wraps its own PATH, so matugen, grim, slurp, wf-recorder,
tesseract, ttfx and the rest ride along. The tools that have to match
something already running on your system (`nmcli`, `bluetoothctl`, `pactl`,
`wlsunset`) are deliberately left out.

Config lives in `~/.config/formalshell/settings.json`, which the shell only
ever reads. Anything it needs to remember goes to
`$XDG_STATE_HOME/formalshell/state.json` instead, so your config file is
yours.

## Hacking on it

```bash
nix develop   # qs, qmllint, qmltestrunner, qmlls, matugen, just
just build
just test     # headless qmltestrunner over tests/
just lint     # nix flake check (qml-tests + qmllint)
just smoke    # the good one
```

`just smoke` builds the shell, boots it inside a throwaway **nested**
Hyprland session, screenshots that session, and tears it down. Your real session is
never a test target, which means you can run the lock screen and the
notification server over and over without locking yourself out or stealing
the D-Bus name from your actual desktop. Flags drive individual surfaces
(`--menu`, `--notify`, `--lock`, `--tray`, `--media`, `--panel <name>`, and
forty more); each one is a file under `dev/smoke.d/` whose header says what
it proves. There is a
matching rig for developing on a Mac, where the whole thing runs in a headless
aarch64 NixOS VM and hands the screenshots back.

`qs ipc call gallery open` opens a dev gallery of every shared component on
one sheet, so a regression in the design system shows up in a single frame.

## License

MIT. See [`LICENSE`](LICENSE).

## Credits

Built on [QuickShell](https://quickshell.org/). The single-process
architecture and a lot of the interaction language come from
[Omarchy](https://github.com/basecamp/omarchy)'s `quattro` branch. The
multi-compositor backend borrows service patterns from
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (MIT,
with attribution in each ported file).
