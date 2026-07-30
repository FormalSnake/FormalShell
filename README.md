# FormalShell

[![CI](https://github.com/FormalSnake/FormalShell/actions/workflows/ci.yml/badge.svg)](https://github.com/FormalSnake/FormalShell/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A from-scratch Wayland desktop shell for niri and Hyprland, built on
[QuickShell](https://quickshell.org/) (Qt/QML): one long-running process
hosting the bar, launcher, notifications, OSD, lock screen, screensaver,
panels, clipboard, and more, behind a compositor-agnostic backend. Colors are
wallpaper-derived end to end via matugen, and it ships as first-party Nix
modules so a consuming config needs almost no glue.

![FormalShell bar on niri](docs/screenshots/bar-niri.png)

**Status:** pre-alpha. M1 through M11 (walking skeleton through the greeter
and NixOS modules, bar completeness, screensaver effect gifs) are complete,
behind CI (qmllint + headless qml-tests) and nested-compositor smoke loops
for every change. M12 (DMS parity gaps + GOA/EDS calendar events,
`docs/superpowers/plans/2026-07-30-m12-dms-parity-and-eds.md`) is in
progress. See `docs/SWITCHOVER.md` for the current hardware-vs-VM
verification parity table before switching a real machine over, and
`docs/superpowers/specs/2026-07-27-formalshell-design.md` for the full
design.

## Screenshots

Every shot below comes from `dev/smoke-niri.sh`: it builds the package,
launches it inside an isolated **nested** niri session, screenshots that
session, and tears it down — safe to run against a live host by design.
Most were recaptured 2026-07-29 from **g815**, the owner's real niri
machine, showing genuinely populated hardware (real battery, Wi-Fi,
Bluetooth, audio, backlight) rather than the VM's empty state. The greeter
shot and the three M10 bar shots (tray, indicators, custom modules) are
VM-sourced — no greetd module on g815 yet, and g815 hasn't been re-swept
since M10 landed. Details on what each shot proves are in `CLAUDE.md`'s
verification loop section (the `dev/smoke-niri.sh` flag each was captured
with) and git history.

| | | |
| :---: | :---: | :---: |
| <img src="docs/screenshots/bar-niri.png" width="260"><br>**Bar** — g815 | <img src="docs/screenshots/menu-niri.png" width="260"><br>**Menu** — g815 | <img src="docs/screenshots/notifications-niri.png" width="260"><br>**Notifications** — g815 |
| <img src="docs/screenshots/osd-niri.png" width="260"><br>**OSD** — g815 | <img src="docs/screenshots/panels-niri.png" width="260"><br>**Panels** — g815 | <img src="docs/screenshots/calendar-niri.png" width="260"><br>**Calendar** — g815 |
| <img src="docs/screenshots/clipboard-niri.png" width="260"><br>**Clipboard** — g815 | <img src="docs/screenshots/media-niri.png" width="260"><br>**Now playing** — g815 | <img src="docs/screenshots/lock-niri.png" width="260"><br>**Lock screen** — g815 |
| <img src="docs/screenshots/screensaver-niri.png" width="260"><br>**Screensaver** — g815 | <img src="docs/screenshots/picker-niri.png" width="260"><br>**Picker** — g815 | <img src="docs/screenshots/greeter-niri.png" width="260"><br>**Greeter** — mac VM |
| <img src="docs/screenshots/tray-niri.png" width="260"><br>**Tray** — mac VM | <img src="docs/screenshots/indicators-niri.png" width="260"><br>**Indicators** — mac VM | <img src="docs/screenshots/bar-layout-niri.png" width="260"><br>**Custom bar modules** — mac VM |

The Hyprland backend is implemented and verified against a live nested
session's `debug` IPC dump, but nested Hyprland doesn't yet reliably reach a
screenshot in the dev sandbox, so no `bar-hyprland.png` is published until
that's fixed.

The screensaver's five convergence effects, frame-stepped and captured as
GIFs (`dev/smoke-niri.sh --screensaver-gif`, `CLAUDE.md`):

| | | | | |
| :---: | :---: | :---: | :---: | :---: |
| <img src="docs/media/screensaver-decrypt.gif" width="140"><br>**decrypt** | <img src="docs/media/screensaver-rain.gif" width="140"><br>**rain** | <img src="docs/media/screensaver-expand.gif" width="140"><br>**expand** | <img src="docs/media/screensaver-slide.gif" width="140"><br>**slide** | <img src="docs/media/screensaver-scatter.gif" width="140"><br>**scatter** |

## Features

Full per-surface reference (config keys, IPC targets, keybind examples) is
in **[`docs/USAGE.md`](docs/USAGE.md)**. In brief:

- **Bar** — three regions (left/center/right): workspaces, active window, an
  SNI tray with a grouped overflow drawer, DND/idle-inhibit indicators,
  clock, battery, audio, network/Bluetooth, weather, now playing — fully
  reorderable from `settings.json`, plus custom `command` and `qml` widget
  modules.
- **Menu** — one fuzzy-searchable, keyboard-driven surface doubling as app
  launcher, system/power menu, and a `select`/`input` dmenu replacement.
- **Notifications** — a mako-replacement stack: freedesktop server,
  independent card toasts, a summonable history center, a narrow DND bypass.
- **OSD** — one jitter-free bottom-center card for volume, brightness, and
  media.
- **Panels** — seven per-widget popouts (audio, calendar, network,
  bluetooth, power, weather, media) sharing one component and one IPC
  target.
- **Clipboard** — capped, deduplicated history surfaced through the menu.
- **Calendar** — month grid with a year/life-progress bar and local `.ics`
  event support.
- **Now playing** — an MPRIS-backed bar cell and panel, with optional Apple
  Music animated album art.
- **Lock screen** — a real `WlSessionLock` + PAM, with the design's one
  sanctioned blur exception.
- **Screensaver** — an idle-driven terminal-effect banner with five
  convergence effects.
- **Picker** — a ledger-grid wallpaper/image selector, also usable as a
  generic image-select IPC surface.
- **Greeter** — a greetd session rendering as the lock screen's visual twin,
  with real PAM authentication.
- **Theming** — wallpaper-driven matugen colors recolor every bar token and
  niri's window borders live, no restart required.
- **Compositor-agnostic** — a formal `CompositorBackend` contract, with
  working niri and Hyprland implementations.

## Install

FormalShell installs as a whole system, not just a user shell: one
home-manager module for the shell itself, and two NixOS modules for the
system-side pieces home-manager cannot provide (a PAM service, geoclue2 +
its agent, greetd). See `docs/SWITCHOVER.md` for the current readiness
report (a per-surface hardware-vs-VM-vs-unverified parity table and known
gaps) before switching a real machine over — this section is the mechanics,
that document is the honesty check. Add the flake input first:

```nix
{
  inputs.formalshell.url = "github:FormalSnake/FormalShell";
}
```

### `nixosModules.formalshell` — system-side prerequisites

`services.formalshell.enable = true;` turns on everything M6/M7 need from
the system side that home-manager has no access to. Each backend is its own
sub-option, defaulted on via `lib.mkDefault` so a config that already manages
one of these its own way can still override it without a definition conflict
— see `nix/nixos-module.nix` for the full rationale behind each entry:

| Sub-option | Backs | Default |
| --- | --- | --- |
| `pam.enable` | `security.pam.services.formalshell-lock` — the exact service name `Lock.qml`'s `PamContext` authenticates against | `true` |
| `geoclue.enable` | `services.geoclue2` + its demo agent — `LocationService`'s default position source | `true` |
| `networkmanager.enable` | `networking.networkmanager` — `NetworkPanel`'s only backend | `true` |
| `bluetooth.enable` | `hardware.bluetooth` — `BluetoothPanel`'s backend | `true` |
| `upower.enable` | `services.upower` — the battery bar cell and `PowerPanel` | `true` |
| `powerProfiles.enable` | `services.power-profiles-daemon` — `PowerPanel`'s profile picker | `true` |
| `pipewire.enable` | `services.pipewire` — the audio bar cell, audio panel, and volume OSD | `true` |

**Without this module (or an equivalent hand-written
`security.pam.services.formalshell-lock = { };`), the lock screen cannot
authenticate at all** — `PamContext` has nothing to talk to. **Without
`geoclue.enable`'s agent, geoclue never answers** `LocationService`'s
position requests either.

### `nixosModules.formalshell-greeter` — greetd wiring

`services.formalshell-greeter` wires `services.greetd` to run
`packages.<system>.formalshell-greeter` as the `default_session`, under a
wlroots compositor (`compositorPackage`, default `pkgs.sway`):

```nix
{
  services.formalshell-greeter = {
    enable = true;
    package = inputs.formalshell.packages.${pkgs.system}.formalshell-greeter;
    sessionCommand = [ "niri" ]; # argv a successful login launches
  };
}
```

`sessionCommand` is the one option a real deployment usually needs to set —
it's written into a static `settings.json` for the `greeter` system account
(whose own passwd `HOME` is unwritable, hence the module's own separate
`runtimeDir`/`stateDir`). `extraEnvironment`, `sessionLogFile`, and
`postGreeterCommand` exist for a nonstandard seat or verification tooling; a
normal login never touches them — see `nix/nixos-greeter-module.nix`.

### `homeModules.formalshell` — the shell itself

```nix
{
  imports = [ inputs.formalshell.homeModules.default ];
  programs.formalshell = {
    enable = true;
    package = inputs.formalshell.packages.${pkgs.system}.default;
  };
}
```

`programs.formalshell.settings` (JSON) is written once to
`~/.config/formalshell/settings.json` and only ever read by the shell — see
`nix/hm-module.nix`.

### Minimal working `flake.nix`

```nix
{
  inputs.formalshell.url = "github:FormalSnake/FormalShell";

  outputs = { self, nixpkgs, home-manager, formalshell, ... }: {
    nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        formalshell.nixosModules.formalshell
        formalshell.nixosModules.formalshell-greeter
        {
          services.formalshell.enable = true;
          services.formalshell-greeter = {
            enable = true;
            package = formalshell.packages.x86_64-linux.formalshell-greeter;
          };
        }
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

Wired into a NixOS host config as above (home-manager as a NixOS module,
not standalone), the one command that activates everything — the PAM
service, greetd, and the shell itself — is:

```sh
sudo nixos-rebuild switch --flake .#mymachine
```

## Dev loop

```bash
nix develop   # qs, qt6.qtdeclarative (qmllint/qmltestrunner/qmlls), matugen, just
just build    # nix build .#formalshell
just test     # headless qmltestrunner over tests/
just lint     # nix flake check -L (qml-tests + qmllint)
just smoke    # nested niri + screenshot, the visual verification loop
```

The full set of smoke-mode flags (`--wallpaper`, `--menu`, `--notify`,
`--panel <name>`, `--tray`, …), the Hyprland equivalent, and the mac-only
nested-VM rig for testing without a Linux box are documented in `CLAUDE.md`.

## License

MIT — see `LICENSE`.

## Credits

Built on [QuickShell](https://quickshell.org/). Architecture and UX
(single-process shell, unified surfaces, IPC contract) are generalized from
[Omarchy](https://github.com/basecamp/omarchy)'s `quattro` branch off
Hyprland. Service patterns for the multi-compositor backend layer are ported
with attribution from [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
(MIT).
