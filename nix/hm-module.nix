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
  };
}
