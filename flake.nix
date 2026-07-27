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
      # darwin gets no packages (quickshell is linux-only) but runs the pure
      # QML/JS unit tests and hosts the dev loop driving a linux VM for e2e —
      # see docs/superpowers/plans/2026-07-28-mac-e2e-rig.md
      darwinSystems = [ "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f system nixpkgs.legacyPackages.${system});
      forDarwin = f: nixpkgs.lib.genAttrs darwinSystems (system:
        f system nixpkgs.legacyPackages.${system});
      qsFor = system: quickshell.packages.${system}.default;
      qmlTests = pkgs: pkgs.runCommand "formalshell-qml-tests" {
        nativeBuildInputs = [ pkgs.qt6.qtdeclarative ];
        QML2_IMPORT_PATH = "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml";
      } ''
        cp -r ${./.}/shell shell; cp -r ${./.}/tests tests
        QT_QPA_PLATFORM=offscreen qmltestrunner -input tests
        touch $out
      '';
    in
    {
      packages = nixpkgs.lib.recursiveUpdate
        (forDarwin (system: pkgs: {
          # The aarch64-linux build capability the mac's nix daemon offloads to —
          # nixpkgs' own macOS remote-builder VM, pinned here rather than taken
          # from the flake registry so the rig is reproducible with the repo.
          # The override raises the guest off its 1-core/3G/20G defaults (a Qt
          # build and a store image do not fit those); it only rebuilds the four
          # darwin-side runner derivations, everything else still substitutes.
          # Driven by dev/linux-builder.sh.
          linux-builder = pkgs.darwin.linux-builder.override {
            modules = [{
              virtualisation.cores = 6;
              virtualisation.darwin-builder = { memorySize = 10240; diskSize = 61440; };
            }];
          };
        }))
        (forAllSystems (system: pkgs: rec {
          formalshell = pkgs.callPackage ./nix/package.nix { quickshell = qsFor system; };
          default = formalshell;
        }));

      homeModules = { formalshell = ./nix/hm-module.nix; default = ./nix/hm-module.nix; };

      checks = nixpkgs.lib.recursiveUpdate
        (forDarwin (system: pkgs: { qml-tests = qmlTests pkgs; }))
        (forAllSystems (system: pkgs: {
        qml-tests = qmlTests pkgs;

        qmllint = pkgs.runCommand "formalshell-qmllint" {
          nativeBuildInputs = [ pkgs.qt6.qtdeclarative ];
        } ''
          cd ${./.}
          qmllint -I ${qsFor system}/lib/qt-6/qml -I ${pkgs.qt6.qtdeclarative}/lib/qt-6/qml --bare $(find shell -name '*.qml') 2>&1 | tee $out.log
          touch $out
        '';
      }));

      devShells = nixpkgs.lib.recursiveUpdate
        (forDarwin (system: pkgs: {
          default = pkgs.mkShell {
            packages = [
              pkgs.qt6.qtdeclarative # qmltestrunner for the pure QML/JS tests
              pkgs.just
            ];
            QML2_IMPORT_PATH = "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml";
          };
        }))
        (forAllSystems (system: pkgs: {
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
      }));
    };
}
