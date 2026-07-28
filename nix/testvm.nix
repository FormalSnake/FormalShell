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
    self.nixosModules.formalshell
    ({ pkgs, ... }:
      let
        quickshellPkg = quickshell.packages.aarch64-linux.default;
        greeterPkg = self.packages.aarch64-linux.formalshell-greeter;

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

        # M8 Task 2: greetd's own default_session compositor. No `exec` line
        # at all (unlike swayHeadlessConfig above) — greeterSessionScript
        # below runs formalshell-greeter itself in the foreground so it
        # knows the exact moment the greeter quits and can screenshot the
        # torn-down surface before killing sway, which an async sway `exec`
        # can't give us.
        swayGreeterConfig = pkgs.writeText "sway-greeter-testhost.conf" ''
          # intentionally empty — greeterSessionScript below drives everything
        '';

        # greetd's session/worker.rs execs default_session.command through
        # `/bin/sh -c` with an environment reset to PAM's own envlist (only
        # XDG_SEAT/XDG_SESSION_CLASS/USER/LOGNAME/HOME/SHELL/TERM plus
        # GREETD_SOCK — confirmed by reading greetd's own worker.rs, not
        # nixpkgs' module), so nothing this VM's systemd units export
        # (WLR_BACKENDS and friends) reaches this script for free — it has
        # to set them up itself, same as swayHeadlessConfig's own unit does.
        # HOME in that PAM envlist is the `greeter` user's real passwd entry
        # (/var/empty, unwritable) — overridden here to a tmpfiles-owned
        # scratch dir so Qt has somewhere to put its cache. Absolute paths
        # everywhere below rather than bare names: PATH isn't part of that
        # reset envlist either.
        greeterRuntimeDir = "/run/formalshell-greeter";
        greeterHome = "/var/lib/formalshell-greeter";
        greeterSessionScript = pkgs.writeShellScript "formalshell-greeter-session" ''
          # Append, not truncate: greetd falls back to this same
          # default_session almost immediately after a successful login's
          # own session command exits (observed ~1s later in this VM, since
          # the authenticated session has no seat/backend to run "niri"
          # against and exits right back out) — a truncating `exec >` would
          # very likely race dev/smoke-greeter.sh's own read of this file
          # and wipe the very "Authentication complete."/"Quitting." lines
          # it's checking for. dev/smoke-greeter.sh rm -f's this path itself
          # before every run, so append-mode still starts each smoke run
          # from an empty file.
          exec >>/tmp/formalshell-greeter-session.log 2>&1
          set -x
          export XDG_RUNTIME_DIR="${greeterRuntimeDir}"
          export HOME="${greeterHome}"
          export WAYLAND_DISPLAY=wayland-1
          export WLR_BACKENDS=headless
          export WLR_RENDERER=pixman
          export WLR_LIBINPUT_NO_DEVICES=1
          # Surfaces Greetd's own qCDebug trail (Connected/Sending
          # request/Received response/Authentication complete/Quitting) in
          # this log — dev/smoke-greeter.sh's evidence for the auth
          # exchange, since greetd(1) itself barely logs beyond errors
          # (confirmed by reading greetd/src/context.rs).
          export QT_LOGGING_RULES="quickshell.service.greetd.debug=true"

          "${pkgs.sway}/bin/sway" --config "${swayGreeterConfig}" &
          sway_pid=$!
          for _ in $(seq 1 100); do
            [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && break
            sleep 0.1
          done

          # Blocks until Greetd.launch(...,true) (see greeter/greeter.qml's
          # onReadyToLaunch) quits this process — greetd starts the
          # authenticated session only once this whole default_session
          # command has terminated (greetd-ipc(7)'s "start_session" docs),
          # so the grim call below runs against the torn-down-greeter,
          # still-live compositor before sway itself is killed.
          "${greeterPkg}/bin/formalshell-greeter"
          "${pkgs.grim}/bin/grim" /tmp/formalshell-greeter-post-auth.png

          kill "$sway_pid" 2>/dev/null || true
          wait "$sway_pid" 2>/dev/null || true
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
          # M7 Task 3: PamContext needs a real password to authenticate
          # against for --lock's round trip — the account otherwise has none
          # (locked). Plaintext `password` is a throwaway, world-readable-
          # in-the-store credential NixOS itself warns is test-only; this VM
          # never carries anything else worth protecting.
          password = "formalshell-test";
        };
        security.sudo.wheelNeedsPassword = false;
        services.getty.autologinUser = "test";
        # M8 Task 3: nixosModules.formalshell declares the
        # "formalshell-lock" PAM service Lock.qml's PamContext authenticates
        # against (console-specific checks like pam_securetty that a lock
        # screen has no business inheriting are why it's a dedicated service
        # rather than reusing "login"), plus geoclue2/NetworkManager/
        # bluez/UPower/power-profiles-daemon/pipewire below — see
        # nix/nixos-module.nix for the per-service rationale.
        services.formalshell.enable = true;

        # M8 Task 2: a real greetd instance, hand-declared here the same way
        # formalshell-lock's PAM service is above — Task 3/4's NixOS modules
        # are where a real deployment gets this instead. terminal.vt/switch
        # are left at the upstream module's defaults (vt=1, switch=true):
        # greetd only calls VT_ACTIVATE when the current VT differs from the
        # target one (greetd/src/session/worker.rs), and tty1 is already the
        # kernel's default foreground VT on this serial-console VM, so the
        # ioctl is a no-op in practice rather than something that needs a
        # real framebuffer console behind it.
        services.greetd = {
          enable = true;
          settings.default_session.command = "${greeterSessionScript}";
        };
        systemd.tmpfiles.rules = [
          "d ${greeterRuntimeDir} 0700 greeter greeter -"
          "d ${greeterHome} 0700 greeter greeter -"
        ];

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
          pkgs.wl-clipboard
          pkgs.wireplumber
          pkgs.git
          pkgs.just
          pkgs.iproute2
          pkgs.jq
          pkgs.bash
          # M7 Task 1: MediaService needs a real MPRIS player registered on
          # the (isolated, per-run) D-Bus session bus to exercise the
          # now-playing bar cell/panel headlessly — mpv's own mpris.lua
          # script is the standard way to get that without a compiled
          # helper. mpvScripts.mpris is baked into the wrapper's
          # --script= flags via mpv's own `scripts` override argument (see
          # nixpkgs' pkgs/by-name/mp/mpv/package.nix), so plain `mpv` on
          # PATH already announces itself over MPRIS. ffmpeg-headless
          # generates the smoke script's silent fixture track at run time
          # (dev/smoke-niri.sh --media) rather than shipping a committed
          # binary asset.
          (pkgs.mpv.override { scripts = [ pkgs.mpvScripts.mpris ]; })
          pkgs.ffmpeg-headless
          # M7 Task 3: --lock's round-trip proof types the real test
          # password into the real password TextInput via a genuine
          # virtual-keyboard-unstable-v1 client rather than a headless IPC
          # shortcut (see LockIpc.qml's header comment for why one doesn't
          # exist) — wtype is the standard tool for that on wlroots-family
          # compositors, which niri implements support for.
          pkgs.wtype
          # M7 Task 3: niri's own `screenshot-screen` msg action is
          # deliberately refused while the session lock is engaged
          # (niri-wm/niri discussion #2384) — grim talks wlr-screencopy
          # directly as an ordinary client, which niri does not gate, so
          # it's what --lock actually screenshots the locked/unlocked
          # surfaces with.
          pkgs.grim
          # M7 Task 2: AppleMusicArtService's own curl calls reach the VM's
          # real DNS/network unwrapped, via nix/package.nix's PATH prefix on
          # the formalshell binary itself — this entry is only so `curl` is
          # also on an interactive ssh session's PATH for ad hoc
          # verification of the iTunes/amp-api chain from the VM directly.
          pkgs.curl
        ];

        # No hardware sink exists in a headless VM, so AudioService.available
        # would stay false forever and the OSD's volume/mute path would be
        # unexercisable. A pipewire "adapter" node with the support.null-
        # audio-sink factory (documented at the Virtual-Devices wiki linked
        # from this very option's description) creates a real Audio/Sink
        # node with no backing hardware — wireplumber then picks it as the
        # default sink since it's the only one, and AudioService's
        # Pipewire.defaultAudioSink binds it exactly as it would a real card.
        # (enable itself now comes from services.formalshell.pipewire — M8
        # Task 3 — this block only adds the virtual sink the enable pulls in.)
        services.pipewire = {
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

        # M6 Task 6 (enable now via services.formalshell.networkmanager/
        # bluetooth — M8 Task 3): the network panel needs a real
        # NetworkManager-managed device to enumerate (the virtio NIC gives a
        # genuine wired connection); the bluetooth panel needs bluez running
        # even though QEMU's aarch64 "virt" machine has no adapter at all —
        # its honest "NO ADAPTER" state is the expected, passing screenshot.

        # M6 Task 7 (enable now via services.formalshell.powerProfiles/
        # upower — M8 Task 3): the power panel needs a real
        # power-profiles-daemon to drive its profile picker; upower backs
        # UPower.displayDevice, which QEMU's aarch64 "virt" machine reports
        # as AC-only (no battery at all) — the panel's honest "AC POWER"
        # state is the expected, passing screenshot, same as bluetooth's
        # "NO ADAPTER".

        # M6 Task 8 (enable now via services.formalshell.geoclue — M8 Task
        # 3): LocationService's PositionSource wants a genuine geoclue2
        # D-Bus backend to talk to (not a fake fix) — this VM's virtio NIC
        # has no Wi-Fi radio to associate with, so geoclue never actually
        # produces a position and the panel's honest "NO LOCATION" state is
        # what the smoke screenshot shows; the manual settings.json lat/lon
        # override is the actually-exercised path.

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
