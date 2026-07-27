# FormalShell

A from-scratch Wayland desktop shell built on QuickShell (Qt/QML toolkit,
v0.3.x): one long-running process hosting bar, unified menu/launcher,
notifications, OSD, lock screen, screensaver, greeter, panels, clipboard
history, media, weather — compositor-agnostic behind a formal backend
interface (niri primary, Hyprland second), matugen-driven colors,
brutalist/terminal aesthetic, and first-party nix support designed so the
consuming config needs near-zero glue.

## Status

Pre-alpha. M1 (walking skeleton), M2 (compositor layer), and M3 (matugen
theme engine) are done: a brutalist bar showing live workspaces and the
active window, backed by a formal `CompositorBackend` contract with working
niri and Hyprland implementations, and wallpaper-driven colors that recolor
every bar token live and sync niri's window borders (see Theming below). CI
(qmllint + headless qml-tests) and a nested-niri smoke loop are the
verification tools for every change. Everything past that —
menu/launcher, notifications, OSD, lock/screensaver, greeter, panels — is
unbuilt; see `docs/superpowers/specs/2026-07-27-formalshell-design.md` for
the full design.

## Screenshots

Both screenshots below come from `dev/smoke-niri.sh`: it builds the package,
launches it inside an isolated **nested** niri session (not the host
desktop), screenshots that nested session, and tears it down. This is the
standard way UI changes get verified in this repo — see `CLAUDE.md`.

![Bar on niri](docs/screenshots/bar-niri.png)

The screenshot above is from `dev/smoke-niri.sh --wallpaper`: a solid-color
test wallpaper is set over IPC before the shot, so the background layer and
the bar's colors are both matugen-derived rather than the static Flexoki
fallback.

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

## Theming

Colors are wallpaper-derived end to end, no restart required:

1. Setting a wallpaper (`wallpaper set`, below) persists it to
   `$XDG_STATE_HOME/formalshell/state.json` via the `State` singleton.
2. `ThemeEngine` notices the change, builds a merged matugen config in the
   spec's order — the user's own `~/.config/matugen/config.toml` `[config]`
   section, the shell's own `theme.json`/`niri-border.kdl` template
   registrations, the user's `[templates.*]` blocks, then any drop-in
   `*.toml` fragments from `~/.config/formalshell/matugen.d/` — and runs
   `matugen image <wallpaper> -m <mode> -c <merged-config>` (matugen runs are
   serialized; a wallpaper/mode change mid-run supersedes the pending run,
   never kills one in flight).
3. matugen's output is atomically published to
   `$XDG_STATE_HOME/formalshell/theme.json` and `niri-border.kdl`. `Theme`
   (the shell's color singleton) watches `theme.json` live, so every bar
   token recolors on the next paint. With no wallpaper set, `theme.json` is
   written straight from the static Flexoki fallback instead, so the
   pipeline is uniform from a fresh install.
4. A per-screen `Background` surface (background Wayland layer) shows the
   current wallpaper, or a flat `Theme.color.background` fill when none is
   set.
5. `ThemeEngine` reloads the compositor's running config
   (`CompositorService.applyThemeFragment()`) so niri's window borders pick
   up the new `niri-border.kdl` immediately.

Add this once to your niri config so window borders track the theme:

```kdl
include "~/.local/state/formalshell/niri-border.kdl"
```

(`ThemeEngine` creates the file empty at startup if it's missing yet, so the
`include` never errors on a fresh install.)

Wallpaper and theme are driven over the same IPC surface as everything else:

```bash
qs ipc --any-display -p <store-path>/share/formalshell call wallpaper set /path/to/image.jpg
qs ipc --any-display -p <store-path>/share/formalshell call theme mode toggle    # dark <-> light
qs ipc --any-display -p <store-path>/share/formalshell call theme status         # {"wallpaper":…,"mode":…,"themeJsonPresent":…}
```

## Dev loop

```bash
nix develop              # qs, qt6.qtdeclarative (qmllint/qmltestrunner/qmlls), matugen, just
just build               # nix build .#formalshell
just test                # headless qmltestrunner over tests/
just lint                # nix flake check -L (qml-tests + qmllint)
just smoke               # nested niri + screenshot — the visual verification loop
./dev/smoke-niri.sh --wallpaper # same, plus sets a test wallpaper over IPC first
./dev/smoke-hyprland.sh  # nested Hyprland equivalent (see Screenshots above)
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
