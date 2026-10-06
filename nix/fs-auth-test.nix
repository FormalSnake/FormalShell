{ testers, crane }:

# Runs on a Linux host, or on the mac with the guest on aarch64-linux.
testers.runNixOSTest {
  name = "fs-auth";

  nodes.machine = { pkgs, ... }: {
    users.users.alice = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      password = "right-pw";
    };
    # The same service nixosModules.formalshell declares for the lock screen.
    security.pam.services.formalshell-lock = { };
    security.polkit.enable = true;
    security.polkit.enablePkexecWrapper = true;
    # polkit 127 on NixOS ships only the socket-activated helper; this is the
    # setuid one older polkit spawns, for the fallback run.
    security.wrappers.polkit-agent-helper-1 = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${pkgs.polkit.out}/lib/polkit-1/polkit-agent-helper-1";
    };
    # pkexec routes to the agent registered for the caller's logind session,
    # so the polkit probe runs from this login shell.
    services.getty.autologinUser = "alice";
    environment.systemPackages = [ (pkgs.callPackage ./fs-auth-probes.nix { rustCommon = pkgs.callPackage ./rust-common.nix { inherit crane; }; }) ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    def pam(password):
        return machine.execute(
            f"echo {password} | su alice -s /bin/sh -c 'fs-auth-pam-probe formalshell-lock alice'"
        )

    status, out = pam("wrong-pw")
    print(out)
    assert status == 1, f"wrong password exited {status}"
    assert 'prompt echo=false "Password: "' in out, out
    assert "outcome Failed(\"Authentication failure\")" in out, out

    status, out = pam("right-pw")
    print(out)
    assert status == 0, f"right password exited {status}"
    assert "outcome Success" in out, out

    machine.wait_until_tty_matches("1", "alice@")

    def polkit(tag):
        machine.send_chars(
            f"printf 'wrong-pw\\nright-pw\\n' | fs-auth-polkit-probe /run/wrappers/bin/pkexec /run/current-system/sw/bin/true"
            f" > /tmp/polkit-{tag}.log 2>&1; echo $? > /tmp/polkit-{tag}.rc\n"
        )
        try:
            machine.wait_for_file(f"/tmp/polkit-{tag}.rc", timeout=180)
        except Exception:
            print(machine.execute(f"cat /tmp/polkit-{tag}.log; journalctl -b --no-pager -n 80 -u polkit.service -u 'polkit-agent-helper@*'; loginctl; ps -ef | grep -E 'pkexec|probe|helper'")[1])
            raise
        out = machine.succeed(f"cat /tmp/polkit-{tag}.log")
        print(out)
        rc = machine.succeed(f"cat /tmp/polkit-{tag}.rc").strip()
        assert rc == "0", f"{tag}: probe exited {rc}"
        assert "cancel rc=126" in out, out
        assert "auth rc=0 failed=1" in out, out

    polkit("socket")
    machine.succeed("journalctl -b -u 'polkit-agent-helper@*' | grep -q polkit-agent-helper")

    machine.succeed("systemctl stop polkit-agent-helper.socket")
    machine.succeed("rm -f /run/polkit/agent-helper.socket")
    polkit("setuid")
  '';
}
