{
  description = "FormalShell — brutalist QuickShell Wayland desktop shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, quickshell }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f system nixpkgs.legacyPackages.${system});
      qsFor = system: quickshell.packages.${system}.default;
    in
    {
      devShells = forAllSystems (system: pkgs: {
        default = pkgs.mkShell {
          packages = [
            (qsFor system)
            pkgs.qt6.qtdeclarative # qmllint, qmltestrunner, qmlls
            pkgs.matugen
            pkgs.just
          ];
          shellHook = ''
            [ -f .qmlls.ini ] || touch .qmlls.ini
          '';
        };
      });
    };
}
