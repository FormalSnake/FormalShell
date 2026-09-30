self: { config, lib, pkgs, ... }:
let cfg = config.programs.formalshell; in
{
  options.programs.formalshell = {
    enable = lib.mkEnableOption "FormalShell";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.formalshell;
      defaultText = lib.literalExpression "formalshell.packages.\${pkgs.stdenv.hostPlatform.system}.formalshell";
      description = "FormalShell package. Defaults to this flake's build for the host system.";
    };
    hyprland.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Write ~/.config/hypr/formalshell.lua (binds and layer rules). Add `dofile(os.getenv(\"HOME\") .. \"/.config/hypr/formalshell.lua\")` to your hyprland.lua.";
    };
    settings = lib.mkOption {
      type = (pkgs.formats.json {}).type;
      default = {};
      description = "Contents of ~/.config/formalshell/settings.json. FormalShell only reads this file, so home-manager owns it fully.";
    };
    systemd = {
      enable = lib.mkEnableOption "systemd user service" // { default = true; };
      target = lib.mkOption { type = lib.types.str; default = "graphical-session.target"; };
      watchdog = lib.mkEnableOption "timer that restarts the shell when its IPC socket stops answering" // { default = true; };
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    xdg.configFile."formalshell/settings.json" = lib.mkIf (cfg.settings != {}) {
      source = (pkgs.formats.json {}).generate "formalshell-settings.json" cfg.settings;
    };
    xdg.configFile."hypr/formalshell.lua" = lib.mkIf cfg.hyprland.enable {
      source = "${cfg.package}/share/formalshell/examples/hyprland/formalshell.lua";
    };
    systemd.user.services.formalshell = lib.mkIf cfg.systemd.enable {
      Unit = { Description = "FormalShell"; PartOf = [ cfg.systemd.target ]; After = [ cfg.systemd.target ]; };
      Service = { ExecStart = lib.getExe cfg.package; Restart = "on-failure"; };
      Install = { WantedBy = [ cfg.systemd.target ]; };
    };
    # `formalshell-watchdog` (nix/package.nix) probes the shell over IPC
    # every 30s and restarts the service after two timeouts in a row. A
    # main thread hung on a render thread is a live process to systemd, so
    # Restart=on-failure alone never brings it back.
    systemd.user.services.formalshell-watchdog = lib.mkIf (cfg.systemd.enable && cfg.systemd.watchdog) {
      Unit = { Description = "FormalShell liveness probe"; PartOf = [ cfg.systemd.target ]; After = [ "formalshell.service" ]; };
      Service = { Type = "oneshot"; ExecStart = lib.getExe' cfg.package "formalshell-watchdog"; };
    };
    systemd.user.timers.formalshell-watchdog = lib.mkIf (cfg.systemd.enable && cfg.systemd.watchdog) {
      Unit = { Description = "FormalShell liveness probe"; PartOf = [ cfg.systemd.target ]; };
      Timer = { OnActiveSec = "30s"; OnUnitActiveSec = "30s"; AccuracySec = "5s"; Unit = "formalshell-watchdog.service"; };
      Install = { WantedBy = [ cfg.systemd.target ]; };
    };
  };
}
