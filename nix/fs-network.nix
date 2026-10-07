{ lib, rustCommon, jq, testers, openssl, runCommand, writeText }:

# fs-network's check: clippy -D warnings and the unit tests, then the daemon
# test (tests/daemon.rs) inside a NixOS VM running NetworkManager against
# three mac80211_hwsim radios: wlan0 is the station, wlan1 and wlan2 are
# hostapd access points (WPA2-PSK and PEAP/MSCHAPv2). The radio setup mirrors
# nix/testvm.nix, which the smoke rig's --wifi leg runs against.
let
  testBinary = rustCommon.craneLib.mkCargoDerivation (rustCommon.checkArgs // {
    pname = "fs-network-daemon-test";
    nativeBuildInputs = rustCommon.checkArgs.nativeBuildInputs ++ [ jq ];
    buildPhaseCargoCommand = ''
      cargo clippy --release -p fs-network --all-targets -- -D warnings
      cargo test --release -p fs-network --lib
      cargo test --release -p fs-network --test daemon --no-run \
        --message-format=json > build.json
    '';
    installPhaseCommand = ''
      mkdir -p $out/bin
      exe=$(jq -r 'select(.executable != null and .target.name == "daemon") | .executable' build.json)
      cp "$exe" $out/bin/fs-network-daemon-test
    '';
  });

  # PEAP wraps a TLS tunnel, so hostapd's EAP server needs a certificate to
  # present. Nothing validates the chain: the client pins no CA.
  eapCert = runCommand "formaltest-eap-cert" { nativeBuildInputs = [ openssl ]; } ''
    mkdir -p "$out"
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "$out/server.key" -out "$out/server.pem" \
      -days 3650 -subj "/CN=formaltest-eap"
  '';
in
(testers.runNixOSTest {
  name = "fs-network";

  nodes.machine = { pkgs, ... }: {
    virtualisation.cores = 4;
    boot.kernelModules = [ "mac80211_hwsim" ];
    boot.extraModprobeConfig = "options mac80211_hwsim radios=3";

    # qemu-vm.nix forces wireless off with mkVMOverride; NetworkManager needs
    # the supplicant, as in nix/testvm.nix.
    networking.wireless.enable = lib.mkOverride 0 true;
    networking.wireless.interfaces = [ "wlan0" ];
    networking.networkmanager.enable = true;
    networking.networkmanager.unmanaged = [ "wlan1" "wlan2" ];
    networking.firewall.trustedInterfaces = [ "wlan1" "wlan2" ];

    services.hostapd = {
      enable = true;
      radios.wlan1 = {
        band = "2g";
        channel = 1;
        networks.wlan1 = {
          ssid = "FORMALTEST";
          authentication = {
            mode = "wpa2-sha256";
            wpaPasswordFile = writeText "formaltest-psk" "formaltest-psk";
          };
        };
      };
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
            eap_user_file = toString (writeText "formaltest-eap-users" ''
              *	PEAP
              "formaltest"	MSCHAPV2	"formaltest-eap-pw"	[2]
            '');
            server_cert = "${eapCert}/server.pem";
            private_key = "${eapCert}/server.key";
          };
        };
      };
    };

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

    services.dnsmasq = {
      enable = true;
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
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("NetworkManager.service")
    machine.wait_for_unit("hostapd.service")
    machine.wait_for_unit("dnsmasq.service")
    out = machine.succeed(
        "${testBinary}/bin/fs-network-daemon-test"
        " --ignored --test-threads=1 --nocapture 2>&1",
        timeout=900,
    )
    print(out)
  '';
}).overrideTestDerivation {
  # The mac's linux-builder advertises kvm but not nixos-test.
  requiredSystemFeatures = [ "kvm" ];
}
