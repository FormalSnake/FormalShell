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
    self.nixosModules.formalshell-greeter
    ({ pkgs, lib, ... }:
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

        # M14 Task 3: a throwaway self-signed TLS cert for hostapd's own
        # integrated EAP server (PEAP wraps a TLS tunnel in phase 1 before
        # MSCHAPv2 runs inside it — hostapd needs something to present).
        # wpa_supplicant/NM's own connectEap flow never sets a client-side
        # ca_cert (NetworkPanel.qml's _enterpriseScript), so nothing here
        # ever validates the chain — a bare self-signed leaf is enough to
        # complete the handshake. World-readable in the store, same
        # throwaway-test-credential tradeoff as users.users.test.password
        # below.
        # allowSubstitutes = false: a brand-new, never-cached derivation
        # otherwise triggers a cache.nixos.org narinfo lookup from whichever
        # machine builds it — on the linux-builder VM that lookup's TLS
        # handshake fails outright (broken guest CA trust store, the same
        # class of issue T1/T2 already hit on the testvm's own network
        # stack: `nix build .#testvm` reproducibly failed with "Problem with
        # the SSL CA cert ... error adding trust anchors from file:
        # /etc/ssl/certs/ca-certificates.crt" until this was set). `pkgs.
        # writeText` elsewhere in this file never needs this: writeTextFile
        # already defaults allowSubstitutes to false.
        eapTestCert = pkgs.runCommand "formaltest-eap-cert" {
          nativeBuildInputs = [ pkgs.openssl ];
          allowSubstitutes = false;
        } ''
          mkdir -p "$out"
          openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "$out/server.key" -out "$out/server.pem" \
            -days 3650 -subj "/CN=formaltest-eap"
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

        # M8 Task 4: a real greetd instance through
        # nixosModules.formalshell-greeter, the same proof strategy Task 3
        # used for services.formalshell — see nix/nixos-greeter-module.nix
        # for what each option does. terminal.vt/switch (the upstream
        # services.greetd module's own options, untouched by ours) are left
        # at their defaults (vt=1, switch=true): greetd only calls
        # VT_ACTIVATE when the current VT differs from the target one
        # (greetd/src/session/worker.rs), and tty1 is already the kernel's
        # default foreground VT on this serial-console VM, so the ioctl is a
        # no-op in practice rather than something that needs a real
        # framebuffer console behind it. extraEnvironment/sessionLogFile/
        # postGreeterCommand below are this VM's own headless-seat and
        # smoke-evidence needs (dev/smoke-greeter.sh reads sessionLogFile and
        # the grim screenshot postGreeterCommand produces) — a real
        # deployment on real hardware needs none of them.
        services.formalshell-greeter = {
          enable = true;
          package = greeterPkg;
          extraEnvironment = {
            WLR_BACKENDS = "headless";
            WLR_RENDERER = "pixman";
            WLR_LIBINPUT_NO_DEVICES = "1";
            # Surfaces Greetd's own qCDebug trail (Connected/Sending
            # request/Received response/Authentication complete/Quitting) in
            # sessionLogFile — dev/smoke-greeter.sh's evidence for the auth
            # exchange, since greetd(1) itself barely logs beyond errors
            # (confirmed by reading greetd/src/context.rs).
            QT_LOGGING_RULES = "quickshell.service.greetd.debug=true";
          };
          # Append, not truncate: greetd falls back to this same
          # default_session almost immediately after a successful login's
          # own session command exits (observed ~1s later in this VM, since
          # the authenticated session has no seat/backend to run "niri"
          # against and exits right back out) — a truncating `exec >` would
          # very likely race dev/smoke-greeter.sh's own read of this file
          # and wipe the very "Authentication complete."/"Quitting." lines
          # it's checking for. dev/smoke-greeter.sh rm -f's this path itself
          # before every run, so append-mode still starts each smoke run
          # from an empty file. (nix/nixos-greeter-module.nix's
          # sessionScript always appends with `>>`.)
          sessionLogFile = "/tmp/formalshell-greeter-session.log";
          postGreeterCommand = "${pkgs.grim}/bin/grim /tmp/formalshell-greeter-post-auth.png";
        };

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

        # M12 Task 2: restore what the EDS spike removed again after its
        # decision (docs/spikes/2026-07-28-eds-calendar-events.md "Cleanup")
        # — the shell now really consumes EDS through the formalshell-eds
        # CLI. The .service files delegate activation to systemd --user
        # (SystemdService=), so registering the bus names alone is not
        # enough: systemd.packages links the user units those names map to,
        # the same three-line wiring upstream's
        # services.gnome.evolution-data-server module does.
        services.dbus.packages = [ pkgs.evolution-data-server ];
        systemd.packages = [ pkgs.evolution-data-server ];

        environment.systemPackages = [
          self.packages.aarch64-linux.formalshell
          # M12 Task 2: the EDS companion CLI on the interactive PATH so the
          # smoke rig and ad hoc ssh sessions can seed/query calendars; the
          # shell's own wrapper carries it separately via nix/package.nix.
          self.packages.aarch64-linux.formalshell-eds
          pkgs.evolution-data-server
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
          # M10 Task 1: dev/sni-stub.py registers real StatusNotifierItems on
          # the session bus so the tray widget/grouped drawer has genuine
          # items to render — PyGObject is the "Python/GLib" producer the
          # plan sanctions, since nixpkgs ships nothing else that registers
          # a bare SNI item without dragging in a whole desktop applet
          # (nm-applet/blueman-applet) this headless VM has no backing
          # device for anyway.
          (pkgs.python3.withPackages (ps: [ ps.pygobject3 ]))
          # M14 Task 5: dev/smoke-niri.sh's default leg spawns a real
          # toplevel with a controlled Wayland app-id (foot's --app-id) so
          # ActiveWindow.qml's DesktopEntries.heuristicLookup has a genuine
          # focused window to resolve against the smoke-iconic fixture's
          # icon — foot needs no GPU/EGL context (wl_shm + pixman/fcft
          # software text rendering), matching the VM's headless llvmpipe
          # rendering everywhere else.
          pkgs.foot
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
        # M16 Task 4: on this pinned nixpkgs rev, `security.polkit.enable`
        # alone no longer gives a working `pkexec` — the setuid wrapper is
        # its own opt-in (`security.wrappers.pkexec.enable = cfg.
        # enablePkexecWrapper`, default false, nixos/modules/security/
        # polkit.nix) since a recent nixpkgs hardening change split it out
        # from the daemon itself. Without this, `pkexec` resolves to the
        # unwrapped `environment.systemPackages` binary at
        # /run/current-system/sw/bin/pkexec, which refuses to run at all
        # ("pkexec must be setuid root", exit 127) — reproduced directly.
        # The `--polkit` smoke leg's `pkexec true` needs the real wrapper.
        security.polkit.enablePkexecWrapper = true;

        # M6 Task 6 (enable now via services.formalshell.networkmanager/
        # bluetooth — M8 Task 3): the network panel needs a real
        # NetworkManager-managed device to enumerate (the virtio NIC gives a
        # genuine wired connection); the bluetooth panel needs bluez running
        # even though QEMU's aarch64 "virt" machine has no adapter at all —
        # its honest "NO ADAPTER" state is the expected, passing screenshot.

        # M14 Task 3: three mac80211_hwsim radios give the network panel a
        # genuine wifi story to go with the wired one above — wlan0 stays
        # NetworkManager's station device, wlan1/wlan2 are hostapd APs NM
        # must never touch (unmanaged below). qemu-vm.nix forces
        # networking.wireless.enable = mkVMOverride false (priority 10,
        # "used by nixos-rebuild build-vm") since a plain build-vm has no
        # radio at all; networkmanager.nix's own normal-priority
        # `wireless.enable = true` (set whenever NM is active and not
        # delegating to static networks) loses to that override, which is
        # why wpa_supplicant was silently absent from this VM's closure
        # before this task — confirmed via `nix-store -qR /run/current-system
        # | grep wpa`. The mkOverride 0 below is the identical fix NixOS's
        # own hwsim test suite uses for the same reason
        # (nixos/tests/wpa_supplicant.nix: "the override is needed because
        # the wifi is disabled with mkVMOverride in qemu-vm.nix").
        boot.kernelModules = [ "mac80211_hwsim" ];
        boot.extraModprobeConfig = "options mac80211_hwsim radios=3";
        networking.wireless.enable = lib.mkOverride 0 true;
        # Scopes the wireless module's own client/AP-conflict warning to just
        # the one interface it actually manages (wlan1/wlan2 are excluded
        # from NM below, not from this list — the warning's check only knows
        # about this option, not NM's own unmanaged exclusion, so leaving it
        # at its "all interfaces implicit" default flags a conflict that
        # isn't real).
        networking.wireless.interfaces = [ "wlan0" ];
        networking.networkmanager.unmanaged = [ "wlan1" "wlan2" ];

        # NetworkManager's own polkit policy defaults network-control to
        # allow_active=yes, but this headless, seatless VM never actually
        # marks any session "active" for polkit's purposes (no display
        # manager/seat to focus) — confirmed by reproducing it directly:
        # `nmcli device wifi connect FORMALTEST password ...` over ssh as
        # the "test" user (the exact account the shell itself runs as)
        # answers "Not authorized to control networking." even though
        # `loginctl` reports that same session's own Active=yes. Same
        # "nothing here is worth protecting" reasoning as
        # security.sudo.wheelNeedsPassword above, scoped to NM specifically
        # rather than security.polkit.extraConfig's own documented (and
        # much broader) "allow any local user to do anything" example.
        security.polkit.extraConfig = ''
          polkit.addRule(function(action, subject) {
            if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0)
              return polkit.Result.YES;
          });
        '';

        services.hostapd = {
          enable = true;
          # FORMALTEST: plain WPA2-Personal, the `--wifi` smoke leg's
          # wrong-password/connect/forget round trip.
          radios.wlan1 = {
            band = "2g";
            channel = 1;
            networks.wlan1 = {
              ssid = "FORMALTEST";
              authentication = {
                mode = "wpa2-sha256";
                wpaPasswordFile = pkgs.writeText "formaltest-psk" "formaltest-psk";
              };
            };
          };
          # FORMALTEST-EAP: hostapd's own integrated EAP server (eap_server=1,
          # no RADIUS daemon) speaking PEAP/MSCHAPv2 — the standard
          # wpa_supplicant/hostapd hwsim test topology. nixpkgs'
          # services.hostapd module only has typed options for
          # personal/SAE auth (no wpa-eap/ieee8021x knobs), so this network
          # sets `authentication.mode = "none"` (keeps the module's own
          # mode-driven optionalAttrs quiet — it would otherwise fight our
          # own wpa_key_mgmt) and supplies the real WPA-EAP config through
          # the freeform `settings`, whose `wpa = 2` beats the module's own
          # `wpa = mkDefault 0` at normal priority.
          radios.wlan2 = {
            band = "2g";
            channel = 6;
            networks.wlan2 = {
              ssid = "FORMALTEST-EAP";
              authentication.mode = "none";
              settings = {
                wpa = 2;
                wpa_key_mgmt = "WPA-EAP";
                rsn_pairwise = "CCMP";
                ieee8021x = 1;
                eap_server = 1;
                eap_user_file = toString (pkgs.writeText "formaltest-eap-users" ''
                  *	PEAP
                  "formaltest"	MSCHAPV2	"formaltest-eap-pw"	[2]
                '');
                server_cert = "${eapTestCert}/server.pem";
                private_key = "${eapTestCert}/server.key";
              };
            };
          };
        };

        # AP-side IP + DHCP so a successful hostapd association reaches a
        # genuine Connected state on the station side (NM's own DHCP client)
        # instead of stalling on NM's own May-Fail timeout. Neither AP
        # interface is NM- or networkd-managed, so this is a plain oneshot
        # rather than networking.interfaces.*; ordering after hostapd.service
        # (not just the udev device) means the address survives hostapd's
        # own interface-mode setup instead of racing it.
        systemd.services.hwsim-ap-addrs = {
          description = "static IPs for the hwsim AP interfaces";
          after = [ "hostapd.service" ];
          requires = [ "hostapd.service" ];
          before = [ "dnsmasq.service" ];
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.iproute2 ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "hwsim-ap-addrs" ''
              set -eu
              ip link set wlan1 up
              ip addr replace 10.90.1.1/24 dev wlan1
              ip link set wlan2 up
              ip addr replace 10.90.2.1/24 dev wlan2
            '';
          };
        };

        # The default nixos-fw chain only accepts loopback/established/ssh/
        # ping (confirmed via `iptables -L nixos-fw -n -v`: DHCP DISCOVER
        # packets arriving on wlan1 were counted straight into the refuse
        # rule) — trusting these two AP-only interfaces is what lets
        # dnsmasq's own UDP/67 actually receive the station's DHCP request,
        # the missing piece behind an otherwise-successful WPA handshake
        # (wpa_supplicant's own log showed CTRL-EVENT-CONNECTED, then a
        # locally-generated disconnect once NM's DHCP timeout gave up).
        networking.firewall.trustedInterfaces = [ "wlan1" "wlan2" ];

        services.dnsmasq = {
          enable = true;
          # DHCP only: port 0 disables dnsmasq's own DNS server so it never
          # touches resolv.conf/networking.nameservers (the SLiRP DNS fix at
          # the top of this file stays the only resolver).
          resolveLocalQueries = false;
          settings = {
            port = 0;
            interface = [ "wlan1" "wlan2" ];
            bind-interfaces = true;
            dhcp-range = [
              "10.90.1.10,10.90.1.100,255.255.255.0,1h"
              "10.90.2.10,10.90.2.100,255.255.255.0,1h"
            ];
          };
        };

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
