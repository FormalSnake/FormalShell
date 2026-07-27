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
        };
        security.sudo.wheelNeedsPassword = false;
        services.getty.autologinUser = "test";

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

        services.pipewire = {
          enable = true;
          pulse.enable = true;
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
