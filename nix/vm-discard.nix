# Lets a guest's fstrim reach the qcow2 on the mac so a nix GC inside the VM
# gives its space back to the host instead of leaving the image at its
# high-water mark. qemu-vm.nix builds `drives` as a plain list with no
# per-element override, so the root drive is restated here with its own
# options plus discard; keep it in step with the root entry in
# nixos/modules/virtualisation/qemu-vm.nix (the nix-store image is a
# throwaway raw file in TMPDIR and needs nothing).
{ lib, config, ... }:
{
  virtualisation.qemu.drives = lib.mkIf (config.virtualisation.diskImage != null) (lib.mkForce (
    [
      {
        name = "root";
        file = ''"$NIX_DISK_IMAGE"'';
        driveExtraOpts = {
          cache = "writeback";
          werror = "report";
          discard = "unmap";
          detect-zeroes = "unmap";
        };
        deviceExtraOpts = {
          bootindex = "1";
          serial = "root";
        };
      }
    ]
    ++ lib.optional config.virtualisation.useNixStoreImage {
      name = "nix-store";
      file = ''"$TMPDIR"/store.img'';
      driveExtraOpts.format = "raw";
      deviceExtraOpts.bootindex = "2";
    }
  ));

  services.fstrim = {
    enable = true;
    interval = "hourly";
  };
}
