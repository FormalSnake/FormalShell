# Headless aarch64-linux NixOS VM, darwin-runnable — the runtime layer of the
# mac e2e rig (docs/superpowers/plans/2026-07-28-mac-e2e-rig.md). Boots via
# HVF under packages.aarch64-darwin.testvm, driven by dev/vm.sh.
#
# virtualisation.host.pkgs is the same wiring pkgs.darwin.linux-builder uses
# (nixos/modules/profiles/nix-builder-vm.nix, pkgs/top-level/darwin-packages.nix
# in the pinned nixpkgs) to make config.system.build.vm a script that runs
# directly on the mac while the guest system itself stays aarch64-linux.
#
# additionalPaths pre-stages this flake's own inputs (not just its package
# outputs) into the guest's Nix store image: nix's flake fetcher resolves a
# locked github/git input to a deterministic store path from its narHash
# alone, and skips the network entirely when that exact path is already
# valid in the local store. Combined with the formalshell/quickshell
# packages also being staged below, `nix build .#formalshell` inside the VM
# needs neither the network nor a shared store to be a no-op.
{ self, nixpkgs, quickshell }:

nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  modules = [
    # Not part of the default module list (nixos/modules/module-list.nix only
    # wires it into documentation.nixos.extraModules) — nix-builder-vm.nix
    # imports it explicitly for the same reason.
    (nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
    ({ pkgs, ... }:
      let
        quickshellPkg = quickshell.packages.aarch64-linux.default;

        # Only job: get WAYLAND_DISPLAY into the systemd --user environment,
        # the exact lookup dev/smoke-niri.sh falls back to
        # (`systemctl --user show-environment`). Mirrors the
        # nixos/modules/programs/wayland/sway.nix upstream module's own
        # generated /etc/sway/config.d/nixos.conf (import-environment then a
        # belt-and-suspenders set-environment), minus the parts of that
        # module (session target, XDG portals, display-manager wiring) that
        # assume an interactive seat we don't have here.
        swayHeadlessConfig = pkgs.writeText "sway-headless-testhost.conf" ''
          exec "systemctl --user import-environment WAYLAND_DISPLAY DISPLAY; systemctl --user set-environment WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
        '';
      in
      {
        virtualisation = {
          host.pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          graphics = false;
          cores = 6;
          memorySize = 8192;
          diskSize = 40960;
          useNixStoreImage = true;
          writableStore = true;
          writableStoreUseTmpfs = false;
          useHostCerts = true;
          forwardPorts = [
            { from = "host"; host.address = "127.0.0.1"; host.port = 2222; guest.port = 22; }
          ];
          additionalPaths = [ nixpkgs.outPath quickshell.outPath ];

          # Populated at boot from the $KEYS env var, same mechanism
          # nix-builder-vm.nix uses for its own authorized_keys — dev/vm.sh
          # points it at a keypair generated into the gitignored
          # dev/.testvm/, so the flake carries no secret and no host path.
          sharedDirectories.keys = {
            source = "\"$KEYS\"";
            target = "/var/keys";
          };
        };

        # QEMU SLiRP's own DNS is broken on macOS; cache.nixos.org otherwise
        # unreachable from the guest.
        networking.nameservers = [ "8.8.8.8" ];
        networking.hostName = "formalshell-testvm";

        users.users.test = {
          isNormalUser = true;
          uid = 1000;
          extraGroups = [ "wheel" ];
          # Without lingering, the systemd --user instance (and the
          # compositor service below) only exists while "test" is logged
          # in; ssh command sessions don't count as a login for this
          # purpose the way the getty autologin does.
          linger = true;
        };
        security.sudo.wheelNeedsPassword = false;
        services.getty.autologinUser = "test";

        # Headless wlroots parent compositor — the Wayland "host session"
        # dev/smoke-*.sh nests its own niri/Hyprland inside, same role
        # niri-session plays on the real Linux hosts. graphics = false
        # above means no DRM device in the guest, so this runs on
        # wlroots' headless backend with the pixman software renderer.
        systemd.user.services.testhost-compositor = {
          description = "headless wlroots parent session for e2e smoke tests";
          wantedBy = [ "default.target" ];
          # sway's `exec` forks and calls execlp("sh", "sh", "-c", cmd, …) —
          # a PATH search, not an absolute path. NixOS units otherwise only
          # get a minimal PATH (coreutils/findutils/grep/sed/systemd); add
          # bash so the config's `exec "…"` line (below) has an `sh` to run.
          path = [ pkgs.bash ];
          environment = {
            WLR_BACKENDS = "headless";
            WLR_RENDERER = "pixman";
            WLR_LIBINPUT_NO_DEVICES = "1";
          };
          serviceConfig = {
            ExecStart = "${pkgs.sway}/bin/sway --config ${swayHeadlessConfig}";
            Restart = "on-failure";
          };
        };

        services.openssh = {
          enable = true;
          authorizedKeysFiles = [ "/var/keys/%u_ed25519.pub" ];
          # StrictModes stays at its default (on): the driver must pass
          # $KEYS through `nix-store --add` before boot (same as
          # nix-builder-vm.nix's run-builder), so the 9p mapped-xattr share
          # reports /var/keys/*.pub owned by root instead of the host uid
          # that ran ssh-keygen — sshd's AuthorizedKeysFile ownership check
          # accepts root-owned files unconditionally.
        };

        environment.systemPackages = [
          self.packages.aarch64-linux.formalshell
          quickshellPkg
          pkgs.qt6.qtdeclarative
          pkgs.matugen
          # niri's system-deps constraint on this pinned rev is
          # libdisplay-info >= 0.1.0, < 0.4.0; nixpkgs bumped the default
          # libdisplay-info to 0.4.0 out from under it, so pin niri to the
          # 0.2.0 branch nixpkgs kept around for exactly this skew.
          (pkgs.niri.override { libdisplay-info = pkgs.libdisplay-info_0_2; })
          pkgs.sway
          pkgs.imagemagick
          pkgs.libnotify
          pkgs.brightnessctl
          pkgs.wireplumber
          pkgs.git
          pkgs.just
          pkgs.iproute2
          pkgs.jq
          pkgs.bash
        ];

        # No hardware sink exists in a headless VM, so AudioService.available
        # would stay false forever and the OSD's volume/mute path would be
        # unexercisable. A pipewire "adapter" node with the support.null-
        # audio-sink factory (documented at the Virtual-Devices wiki linked
        # from this very option's description) creates a real Audio/Sink
        # node with no backing hardware — wireplumber then picks it as the
        # default sink since it's the only one, and AudioService's
        # Pipewire.defaultAudioSink binds it exactly as it would a real card.
        services.pipewire = {
          enable = true;
          pulse.enable = true;
          extraConfig.pipewire."10-virtual-sink" = {
            "context.objects" = [
              {
                factory = "adapter";
                args = {
                  "factory.name" = "support.null-audio-sink";
                  "node.name" = "virtual-sink";
                  "node.description" = "Virtual Sink";
                  "media.class" = "Audio/Sink";
                  "audio.position" = "FL,FR";
                };
              }
            ];
          };
        };

        hardware.graphics.enable = true;
        security.polkit.enable = true;

        fonts = {
          packages = [ pkgs.nerd-fonts.jetbrains-mono ];
          fontconfig.enable = true;
        };

        nix.settings = {
          experimental-features = [ "nix-command" "flakes" ];
          trusted-users = [ "test" ];
        };

        system.stateVersion = "24.05";
      })
  ];
}
