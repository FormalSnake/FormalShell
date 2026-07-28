{ config, lib, pkgs, ... }:
let cfg = config.programs.formalshell; in
{
  options.programs.formalshell = {
    enable = lib.mkEnableOption "FormalShell";
    package = lib.mkOption { type = lib.types.package; description = "FormalShell package (from the flake's packages output)."; };
    settings = lib.mkOption {
      type = (pkgs.formats.json {}).type;
      default = {};
      description = "Contents of ~/.config/formalshell/settings.json. FormalShell only reads this file, so home-manager owns it fully.";
    };
    systemd = {
      enable = lib.mkEnableOption "systemd user service" // { default = true; };
      target = lib.mkOption { type = lib.types.str; default = "graphical-session.target"; };
      lockBeforeSleep = lib.mkEnableOption "lock-before-sleep systemd user unit" // { default = true; };
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    xdg.configFile."formalshell/settings.json" = lib.mkIf (cfg.settings != {}) {
      source = (pkgs.formats.json {}).generate "formalshell-settings.json" cfg.settings;
    };
    systemd.user.services.formalshell = lib.mkIf cfg.systemd.enable {
      Unit = { Description = "FormalShell"; PartOf = [ cfg.systemd.target ]; After = [ cfg.systemd.target ]; };
      Service = { ExecStart = lib.getExe cfg.package; Restart = "on-failure"; };
      Install = { WantedBy = [ cfg.systemd.target ]; };
    };
    # Spec §8's lock-before-sleep contract: `formalshell-lock-before-sleep`
    # (nix/package.nix) is the exit-0-always wrapper such a unit must call so
    # a lock failure never blocks suspend.
    systemd.user.services.formalshell-lock-before-sleep = lib.mkIf cfg.systemd.lockBeforeSleep {
      Unit = { Description = "Lock FormalShell before sleep"; Before = [ "sleep.target" ]; };
      Service = { Type = "oneshot"; ExecStart = lib.getExe' cfg.package "formalshell-lock-before-sleep"; };
      Install = { WantedBy = [ "sleep.target" ]; };
    };
  };
}
