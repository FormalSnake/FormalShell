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
      packages = forAllSystems (system: pkgs: rec {
        formalshell = pkgs.callPackage ./nix/package.nix { quickshell = qsFor system; };
        default = formalshell;
      });

      checks = forAllSystems (system: pkgs: {
        qml-tests = pkgs.runCommand "formalshell-qml-tests" {
          nativeBuildInputs = [ pkgs.qt6.qtdeclarative ];
          QML2_IMPORT_PATH = "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml";
        } ''
          cp -r ${./.}/shell shell; cp -r ${./.}/tests tests
          QT_QPA_PLATFORM=offscreen qmltestrunner -input tests
          touch $out
        '';
      });

      devShells = forAllSystems (system: pkgs: {
        default = pkgs.mkShell {
          packages = [
            (qsFor system)
            pkgs.qt6.qtdeclarative # qmllint, qmltestrunner, qmlls
            pkgs.matugen
            pkgs.just
          ];
          QML2_IMPORT_PATH = "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml";
          shellHook = ''
            [ -f .qmlls.ini ] || touch .qmlls.ini
          '';
        };
      });
    };
}
