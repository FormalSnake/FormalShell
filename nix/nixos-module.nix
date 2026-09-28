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
#   - polkit: PolkitService.qml registers the shell as the session's
#     authentication agent, which needs polkitd to register with. The
#     setuid pkexec wrapper is its own opt-in on current nixpkgs; without it
#     pkexec refuses to run ("pkexec must be setuid root").
# All six are genuine FormalShell prerequisites, not test-rig artifacts —
# nix/testvm.nix's *other* hand-added bits (the null-audio-sink virtual
# node, wtype/grim/mpv, getty autologin, …) stay in the VM config because
# they only exist to give the smoke rig something to screenshot, not
# something a real install needs.
#
# Every option defaults to true but is set with lib.mkDefault, so a consumer
# who already manages one of these services their own way (a different
# network stack, an existing pipewire config, …) can still override it
# without a definition conflict.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.formalshell;
  ancs4linux = pkgs.callPackage ./ancs4linux.nix { };
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
    polkit.enable = lib.mkEnableOption "polkit and the pkexec wrapper, backing the shell's authentication agent" // { default = true; };

    # M75: the iPhone ANCS/AMS bridge. Off by default and not folded into the
    # `enable` toggle above: ancs4linux.Observer and ancs4linux.Advertising
    # run as root on the system bus and start advertising over BLE, which is
    # not something a shell that merely wants a battery cell should turn on
    # by accident.
    iphone.enable = lib.mkEnableOption ''
      the iPhone integration's system side: ancs4linux's Observer and
      Advertising daemons (nix/ancs4linux.nix, pzmarzly/ancs4linux with the
      omarchy-iphone metadata patch), the D-Bus policy letting the
      "ancs4linux" group talk to them, that group itself, and Bluetooth
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
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
      security.polkit = lib.mkIf cfg.polkit.enable {
        enable = lib.mkDefault true;
        enablePkexecWrapper = lib.mkDefault true;
      };
    })

    (lib.mkIf cfg.iphone.enable {
      hardware.bluetooth.enable = lib.mkDefault true;

      users.groups.ancs4linux = { };

      # D-Bus policy and unit shape copied from ancs4linux's own autorun/ dir
      # (pzmarzly/ancs4linux @ b658546, autorun/ancs4linux-{observer,advertising}.xml):
      # root owns each bus name outright, the ancs4linux group gets send/receive.
      environment.etc."dbus-1/system.d/ancs4linux-observer.conf".text = ''
        <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
         "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
        <busconfig>
          <policy user="root">
            <allow own="ancs4linux.Observer"/>
            <allow send_destination="ancs4linux.Observer"/>
            <allow receive_sender="ancs4linux.Observer"/>
          </policy>
          <policy group="ancs4linux">
            <allow send_destination="ancs4linux.Observer"/>
            <allow receive_sender="ancs4linux.Observer"/>
          </policy>
        </busconfig>
      '';
      environment.etc."dbus-1/system.d/ancs4linux-advertising.conf".text = ''
        <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
         "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
        <busconfig>
          <policy user="root">
            <allow own="ancs4linux.Advertising"/>
            <allow send_destination="ancs4linux.Advertising"/>
            <allow receive_sender="ancs4linux.Advertising"/>
          </policy>
          <policy group="ancs4linux">
            <allow send_destination="ancs4linux.Advertising"/>
            <allow receive_sender="ancs4linux.Advertising"/>
          </policy>
        </busconfig>
      '';

      # Type=dbus units, same as upstream: systemd waits for the BusName to
      # appear on the system bus before treating the unit as started, which is
      # what lets ExecStartPost-less dependents (IphoneService's bridge child)
      # find the service already registered rather than racing its startup.
      systemd.services.ancs4linux-observer = {
        description = "ancs4linux Observer daemon (ANCS notifications over BLE)";
        requires = [ "bluetooth.service" ];
        after = [ "bluetooth.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "dbus";
          BusName = "ancs4linux.Observer";
          ExecStart = "${ancs4linux}/bin/ancs4linux-observer";
        };
      };

      systemd.services.ancs4linux-advertising = {
        description = "ancs4linux Advertising daemon (BLE pairing)";
        requires = [ "bluetooth.service" ];
        after = [ "bluetooth.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "dbus";
          BusName = "ancs4linux.Advertising";
          ExecStart = "${ancs4linux}/bin/ancs4linux-advertising";
        };
      };
    })
  ];
}
