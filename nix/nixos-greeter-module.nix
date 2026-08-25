# Greetd wiring (spec §Nix / §Surfaces 9: nixosModules.formalshell-greeter —
# "greetd wiring, system-side, can't be done from home-manager"). Generalizes
# the hand-rolled rig M8 Task 2 built directly in nix/testvm.nix into a
# module any consumer can enable; nix/testvm.nix now consumes this module
# itself rather than duplicating the declarations (same proof strategy as
# nix/nixos-module.nix).
#
# greetd's session/worker.rs execs default_session.command through
# `/bin/sh -c` with the environment reset to PAM's own envlist (confirmed by
# reading greetd's own source, not the nixpkgs module) — nothing this
# session's own systemd units would otherwise export reaches the script for
# free, so every env var the compositor or the greeter needs is set
# explicitly below. The `greeter` system user's real passwd entry has
# HOME=/var/empty (unwritable), hence stateDir/runtimeDir below and the
# tmpfiles rules that own them.
#
# The greeter binary runs in the script's *foreground*, not via the
# compositor's own `exec` line: greetd-ipc(7) only starts the authenticated
# session once this whole default_session command terminates, and running
# the greeter directly is what lets this script know the exact moment that
# happens (needed by postGreeterCommand below, and by M8 Task 2's smoke rig
# specifically) rather than racing an async compositor `exec`.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.formalshell-greeter;

  # greeter.sessionCommand (Core/Config.qml, read by greeter.qml as the argv
  # Greetd.launch() runs on successful auth) — a real deployment's version of
  # the settings.json key the shell would otherwise read from a real user's
  # $HOME the `greeter` account doesn't have. Written as a static store path
  # and pointed at via XDG_CONFIG_HOME rather than any settings.json write:
  # this is a NixOS module generating a file at build time, not the shell
  # itself writing to its own config at runtime (CLAUDE.md's read-only rule
  # is about the latter).
  settingsDir = pkgs.writeTextDir "formalshell/settings.json" (builtins.toJSON {
    greeter.sessionCommand = cfg.sessionCommand;
  });

  compositorConfigFile = pkgs.writeText "formalshell-greeter-compositor.conf" cfg.compositorConfigText;

  sessionScript = pkgs.writeShellScript "formalshell-greeter-session" ''
    ${lib.optionalString (cfg.sessionLogFile != null) ''
      exec >>${lib.escapeShellArg cfg.sessionLogFile} 2>&1
      set -x
    ''}
    export XDG_RUNTIME_DIR=${lib.escapeShellArg cfg.runtimeDir}
    export HOME=${lib.escapeShellArg cfg.stateDir}
    export XDG_CONFIG_HOME=${settingsDir}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (name: value: "export ${name}=${lib.escapeShellArg value}")
      cfg.extraEnvironment)}

    # WAYLAND_DISPLAY must stay unset going into this exec: wlr_backend_autocreate
    # checks getenv("WAYLAND_DISPLAY")/WAYLAND_SOCKET *before* trying DRM
    # (wlroots backend/backend.c) and, on a real seat with no WLR_BACKENDS
    # override, treats its mere presence as "we're nested inside another
    # Wayland session" — it then fails to connect to a socket nothing has
    # created yet and errors out instead of falling through to DRM
    # (confirmed by reproducing that exact failure directly). The compositor
    # picks its own socket name (wl_display_add_socket_auto), so discover
    # whichever one actually got created rather than assuming a fixed name.
    ${lib.getExe cfg.compositorPackage} --config ${compositorConfigFile} &
    compositor_pid=$!
    wayland_socket=""
    for _ in $(seq 1 100); do
      wayland_socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' -print -quit 2>/dev/null)
      [ -n "$wayland_socket" ] && break
      sleep 0.1
    done
    export WAYLAND_DISPLAY=$(basename "$wayland_socket")

    ${lib.getExe cfg.package}
    ${cfg.postGreeterCommand}

    kill "$compositor_pid" 2>/dev/null || true
    wait "$compositor_pid" 2>/dev/null || true
  '';
in
{
  options.services.formalshell-greeter = {
    enable = lib.mkEnableOption "the FormalShell greetd greeter";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The formalshell-greeter package (the packages.<system>.formalshell-greeter
        flake output).
      '';
    };

    compositorPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.sway;
      defaultText = lib.literalExpression "pkgs.sway";
      description = "Wlroots compositor the greeter surface runs under.";
    };

    compositorConfigText = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Extra config text for compositorPackage. Empty by default: the
        greeter binary is launched directly by this module's session
        script (see the header comment), not via the compositor's own
        `exec`, so a real deployment needs no config here at all — this
        exists for output/input quirks a particular seat might need.
      '';
    };

    sessionCommand = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Hyprland" ];
      description = ''
        Argv a successful login launches (greetd-ipc(7)'s start_session),
        written into a static settings.json for the `greeter` system
        account so a consumer who is not this repo's owner gets a proper
        option instead of hand-editing that key.
      '';
    };

    runtimeDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/formalshell-greeter";
      description = "Writable XDG_RUNTIME_DIR for the greeter's compositor and Qt process.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/formalshell-greeter";
      description = "Writable HOME for the greeter session (the `greeter` user's real passwd HOME is unwritable).";
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Additional environment variables exported before the compositor
        starts — e.g. WLR_BACKENDS/WLR_RENDERER overrides for a headless or
        otherwise nonstandard seat.
      '';
    };

    sessionLogFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "If set, the session script appends its own `set -x` trace (and both processes' stdout/stderr) here.";
    };

    postGreeterCommand = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Extra shell run after the greeter process exits but before the
        compositor is torn down — the only moment the compositor is up
        with no client attached. Ignored by a normal login; verification
        tooling (e.g. a post-auth screenshot) is the intended use.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.greetd = {
      enable = true;
      settings.default_session.command = "${sessionScript}";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.runtimeDir} 0700 greeter greeter -"
      "d ${cfg.stateDir} 0700 greeter greeter -"
    ];
  };
}
