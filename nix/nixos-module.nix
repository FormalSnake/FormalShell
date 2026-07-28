# System-side prerequisites for FormalShell that home-manager cannot provide
# (spec docs/superpowers/specs/2026-07-27-formalshell-design.md §Nix): a
# dedicated PAM service for the lock screen's PamContext, geoclue2 (+ its
# agent) for LocationService's default position source, and the system D-Bus
# services the bar/panels bind directly and have no other way to acquire.
#
# Each toggle below traces to a specific QML file reading a specific
# Quickshell service module — audited from nix/testvm.nix's own hand-added
# services (M8 Task 3):
#   - NetworkManager: the only backend Quickshell.Networking talks to
#     (confirmed from quickshell's src/network/qml.cpp) — NetworkPanel.qml.
#   - bluez: the backend Quickshell.Bluetooth talks to — BluetoothPanel.qml.
#   - UPower: the backend Quickshell.Services.UPower talks to — the bar's
#     Battery.qml cell and PowerPanel.qml.
#   - power-profiles-daemon: provides the net.hadess.PowerProfiles D-Bus
#     service UPower's PowerProfiles binding talks to — PowerPanel.qml's
#     profile picker.
#   - pipewire: the backend Quickshell.Services.Pipewire talks to —
#     AudioService.qml (bar cell, audio panel, volume OSD).
# All five are genuine FormalShell prerequisites, not test-rig artifacts —
# nix/testvm.nix's *other* hand-added bits (the null-audio-sink virtual
# node, wtype/grim/mpv, getty autologin, …) stay in the VM config because
# they only exist to give the smoke rig something to screenshot, not
# something a real install needs.
#
# Every option defaults to true but is set with lib.mkDefault, so a consumer
# who already manages one of these services their own way (a different
# network stack, an existing pipewire config, …) can still override it
# without a definition conflict.
{ config, lib, ... }:
let
  cfg = config.services.formalshell;
in
{
  options.services.formalshell = {
    enable = lib.mkEnableOption "FormalShell system-side prerequisites";

    pam.enable = lib.mkEnableOption ''
      the "formalshell-lock" PAM service Lock.qml's PamContext authenticates
      against (shell/Surfaces/Lock/Lock.qml: `PamContext { config:
      "formalshell-lock" }` — a literal string, not a setting, so this only
      toggles whether the service exists, never its name)
    '' // { default = true; };

    geoclue.enable = lib.mkEnableOption ''
      geoclue2 (+ its demo agent) for LocationService.qml's default
      QtPositioning position source. FormalShell ships no compiled agent of
      its own (pure QML/JS, spec's hard rule) — the upstream demo agent is
      what actually authorizes the request, same role services.geoclue2's
      own enableDemoAgent default already plays
    '' // { default = true; };

    networkmanager.enable = lib.mkEnableOption "NetworkManager, the network panel's only backend" // { default = true; };
    bluetooth.enable = lib.mkEnableOption "bluez, the bluetooth panel's backend" // { default = true; };
    upower.enable = lib.mkEnableOption "UPower, backing the battery bar cell and power panel" // { default = true; };
    powerProfiles.enable = lib.mkEnableOption "power-profiles-daemon, backing the power panel's profile picker" // { default = true; };
    pipewire.enable = lib.mkEnableOption "pipewire, backing the audio bar cell, audio panel, and volume OSD" // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    security.pam.services."formalshell-lock" = lib.mkIf cfg.pam.enable (lib.mkDefault { });

    services.geoclue2 = lib.mkIf cfg.geoclue.enable {
      enable = lib.mkDefault true;
      enableDemoAgent = lib.mkDefault true;
    };

    networking.networkmanager.enable = lib.mkIf cfg.networkmanager.enable (lib.mkDefault true);
    hardware.bluetooth.enable = lib.mkIf cfg.bluetooth.enable (lib.mkDefault true);
    services.upower.enable = lib.mkIf cfg.upower.enable (lib.mkDefault true);
    services.power-profiles-daemon.enable = lib.mkIf cfg.powerProfiles.enable (lib.mkDefault true);
    services.pipewire.enable = lib.mkIf cfg.pipewire.enable (lib.mkDefault true);
  };
}
