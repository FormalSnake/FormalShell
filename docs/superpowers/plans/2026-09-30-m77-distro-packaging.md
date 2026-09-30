# M77: install anywhere Hyprland runs

Goal: a new user on NixOS, Arch or a Debian/Ubuntu system goes from nothing
to a running shell with no hand-edited paths, and CI proves each path.

Facts this plan rests on (checked 2026-09-30):

- The pinned quickshell rev `43d4fa9` is v0.3.0 plus 19 commits and 12
  commits behind v0.3.1, so v0.3.1 carries everything the shell uses.
- Arch `extra` ships `quickshell 0.3.1`. Debian ships 0.3.1 in forky
  (testing) and sid, and 0.3.0 in trixie-backports (missing the lock
  surface fixes in those 19 commits).
- The shell is pure QML/JS. Native installs use the distro's quickshell and
  Qt; the only build step is compiling `*.frag` to `.qsb` with `qsb`.

## Task 1: IPC without a store path, Nix module polish

- Ship a `formalshell-ipc` command (or `formalshell ipc ...`, whichever
  quickshell's CLI allows without re-adding `-p`; check with the built `qs`)
  that resolves the installed shell path itself. The Hyprland Lua file,
  `docs/USAGE.md` and the README use it; no `<store-path>` left anywhere
  (`rg '<store-path>'` returns nothing).
- `programs.formalshell.package` and `services.formalshell-greeter.package`
  default to this flake's own package for the host system (modules become
  functions closing over `self`).
- `programs.formalshell.hyprland.enable` (default true) writes
  `~/.config/hypr/formalshell.lua`; the user adds one `dofile` line.
- Verify: `just vm-build`, `just lint` (or `vm-lint`), one `just vm-smoke
  --menu` run proving binds still reach the shell, eval of the HM module.

## Task 2: CI for the Nix path

- CI builds `.#formalshell` and `.#formalshell-greeter` on x86_64-linux.
- A flake check evaluates a minimal NixOS config importing
  `nixosModules.formalshell`, `formalshell-greeter` and home-manager with
  `homeModules.default`, using only README-documented options and no
  explicit `package`.
- `release.yml` on `v*` tags attaches the Arch and Debian packages from
  Tasks 4 and 5 to a GitHub release. No tag is created by this milestone.

## Task 3: native install layout

`packaging/Makefile` with `install DESTDIR= PREFIX=/usr`, shared by both
distro packages:

- `/usr/share/formalshell` (shell tree, compiled `.qsb`, branding,
  examples), `/usr/share/formalshell/hyprland/formalshell.lua`.
- `/usr/bin/formalshell` wrapper setting the env `nix/package.nix` sets
  (`QSG_RENDER_LOOP`, `QT_FFMPEG_DECODING_HW_DEVICE_TYPES`), plus
  `formalshell-ipc`, `formalshell-watchdog`, `formalshell-lock-before-sleep`.
- systemd user units matching `nix/hm-module.nix`.
- PAM service `formalshell-lock`, geoclue app config, polkit and power
  poller pieces matching `nix/nixos-module.nix` defaults.
- Lucide font installed into the system font dir.

## Task 4: Arch package

`packaging/arch/PKGBUILD` (AUR-ready, builds from a tag tarball or the local
tree). Distro packages as `depends`/`optdepends`; the tools the flake builds
itself (`formalshell-eds`, `ttfx`, `tensaku`, `clipssh`, `localsend-cli`,
`iphone-bridge`) are built as split packages where upstream source allows,
otherwise left as optdepends whose absence hits the shell's existing honest
unavailable states. Verify in an `archlinux` container: `makepkg`, `pacman
-U`, `namcap`, qmllint of the installed tree against the system quickshell.

## Task 5: Debian/Ubuntu package

`packaging/debian/` built with `dpkg-buildpackage` in `debian:testing`,
`debian:trixie` and the newest Ubuntu. Depends on `quickshell (>= 0.3.1)`.
Where the distro lacks it, the release also ships a quickshell 0.3.1 deb
rebuilt from Debian's own source for that suite, if the shell runs on that
suite's Qt; otherwise that suite is documented as unsupported. Same
verification shape as Task 4 plus `lintian`.

## Task 6: runtime proof of a native install

Inside the test VM, a Debian and an Arch container with the built package
installed connect to the nested Hyprland session's Wayland and Hyprland
sockets and run `/usr/bin/formalshell`. Screenshot read, `formalshell-ipc
menu toggle` answered. Committed as `dev/native-check.sh`.

## Task 7: docs

README install section for NixOS, Arch and Debian/Ubuntu; USAGE updated;
CLAUDE.md's "Everything ships in the flake" rule extended to the native
packages. Humanizer pass.
