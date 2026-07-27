# FormalShell

A from-scratch Wayland desktop shell built on QuickShell (Qt/QML toolkit,
v0.3.x): one long-running process hosting bar, unified menu/launcher,
notifications, OSD, lock screen, screensaver, greeter, panels, clipboard
history, media, weather — compositor-agnostic behind a formal backend
interface (niri primary, Hyprland second), matugen-driven colors,
brutalist/terminal aesthetic, and first-party nix support designed so the
consuming config needs near-zero glue.

## Status

Pre-alpha. M1 (walking skeleton) and M2 (compositor layer) are done: a
themed, brutalist bar showing live workspaces and the active window, backed
by a formal `CompositorBackend` contract with working niri and Hyprland
implementations, CI (qmllint + headless qml-tests), and a nested-niri smoke
loop used as the visual verification tool for every UI change. Everything
past that — menu/launcher, notifications, OSD, lock/screensaver, greeter,
panels, matugen theming — is unbuilt; see
`docs/superpowers/specs/2026-07-27-formalshell-design.md` for the full design.

## Screenshots

Both screenshots below come from `dev/smoke-niri.sh`: it builds the package,
launches it inside an isolated **nested** niri session (not the host
desktop), screenshots that nested session, and tears it down. This is the
standard way UI changes get verified in this repo — see `CLAUDE.md`.

![Bar on niri](docs/screenshots/bar-niri.png)

The Hyprland backend is implemented and its `debug` IPC dump has been
verified against a live nested Hyprland session (workspaces, focused window,
`compositor: "hyprland"` all correct), but nested Hyprland does not reliably
reach a screenshot in this dev sandbox (its wlroots-in-Wayland backend either
fails to composite a frame for `grim` or hangs on exit) — no `bar-hyprland.png`
is published until that's fixed. `dev/smoke-hyprland.sh` is the script to
retry once the environment allows it.

## Install

Add the flake input and pull in the home-manager module:

```nix
{
  inputs.formalshell.url = "github:FormalSnake/FormalShell";
}
```

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

## Dev loop

```bash
nix develop            # qs, qt6.qtdeclarative (qmllint/qmltestrunner/qmlls), matugen, just
just build             # nix build .#formalshell
just test              # headless qmltestrunner over tests/
just lint              # nix flake check -L (qml-tests + qmllint)
just smoke             # nested niri + screenshot — the visual verification loop
./dev/smoke-hyprland.sh # nested Hyprland equivalent (see Screenshots above)
```

## License

MIT — see `LICENSE`.

## Credits

Built on [QuickShell](https://quickshell.org/). Architecture and UX
(single-process shell, unified surfaces, IPC contract) are generalized from
[Omarchy](https://github.com/basecamp/omarchy)'s `quattro` branch off
Hyprland. Service patterns for the multi-compositor backend layer are ported
with attribution from [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
(MIT).
