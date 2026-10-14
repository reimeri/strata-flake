{
  description = "Strata file manager for NixOS (with upstream RAR support)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkPkgs = system: import nixpkgs {
        inherit system;
        # Only Strata needs an exception: its default features include UnRAR.
        config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "strata";
      };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = mkPkgs system;
          strata = pkgs.callPackage ./package.nix { };
          strata-portal = pkgs.callPackage ./integration/portal-package.nix { inherit strata; };
        in { inherit strata strata-portal; default = strata; });

      apps = forAllSystems (system:
        let strata = {
          type = "app";
          program = "${self.packages.${system}.strata}/bin/strata";
          meta.description = "A fast, keyboard-first file manager for Linux";
        };
        in { inherit strata; default = strata; });

      nixosModules.strata = import ./modules/nixos.nix {
        packageForSystem = system: self.packages.${system}.strata;
      };
      nixosModules.default = self.nixosModules.strata;

      overlays.default = final: _prev: {
        strata = final.callPackage ./package.nix { };
      };

      checks = forAllSystems (system: {
        inherit (self.packages.${system}.strata.passthru.tests) version packaging;
      });
    };
}
