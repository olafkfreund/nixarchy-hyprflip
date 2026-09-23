{
  description = "Hyprflip: two Hyprland windows as the faces of a rotating card";

  # Applies to direct `nix build`/`nix run` of this flake; NixOS consumers set
  # these substituters in their own config (docs/INSTALL.md).
  nixConfig = {
    extra-substituters = [
      "https://hyprland.cachix.org"
      "https://nixarchy.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE="
      "nixarchy.cachix.org-1:05JOuIlsQOWY2/5DQMq7JEA1hwlhgvmMWowMfka8mMM="
    ];
  };

  inputs = {
    # Hyprland main; flake.lock is the only pin (CMake reads it too). The
    # nightly workflow moves it after `nix flake check` passes.
    hyprland.url = "github:hyprwm/Hyprland";
    nixpkgs.follows = "hyprland/nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      hyprland,
    }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      pinnedHyprland = pkgs: hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          hl = pinnedHyprland pkgs;
        in
        rec {
          hyprflip = pkgs.callPackage ./nix/hyprflip.nix { hyprland = hl; };
          hy3 = pkgs.callPackage ./nix/hy3.nix { hyprland = hl; };
          default = hyprflip;
        }
      );

      overlays.default = final: _prev: {
        hyprflip = final.callPackage ./nix/hyprflip.nix { };
        hy3-hyprflip = final.callPackage ./nix/hy3.nix { };
      };

      nixosModules.default = ./nix/nixos.nix;
      homeManagerModules.default = ./nix/home-manager.nix;

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      checks = forAllSystems (
        pkgs:
        let
          inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) hyprflip hy3;
          hl = pinnedHyprland pkgs;

          nixos = lib.nixosSystem {
            inherit (pkgs.stdenv.hostPlatform) system;
            modules = [
              self.nixosModules.default
              {
                boot.isContainer = true;
                system.stateVersion = "25.11";
                programs.hyprland.package = hl;
                programs.hyprflip = {
                  enable = true;
                  containers.enable = true;
                };
              }
            ];
          };
          etc = nixos.config.environment.etc;

          # Stub the two Home Manager options the module touches.
          hm = lib.evalModules {
            specialArgs = { inherit pkgs; };
            modules = [
              self.homeManagerModules.default
              {
                options.assertions = lib.mkOption { type = lib.types.listOf lib.types.attrs; };
                options.wayland.windowManager.hyprland = {
                  package = lib.mkOption { type = lib.types.nullOr lib.types.package; };
                  plugins = lib.mkOption { type = lib.types.listOf lib.types.package; };
                };
                config.wayland.windowManager.hyprland.package = hl;
                config.programs.hyprflip = {
                  enable = true;
                  containers.enable = true;
                };
              }
            ];
          };
          plugins = hm.config.wayland.windowManager.hyprland.plugins;

          assertCheck =
            name: cond:
            assert lib.assertMsg cond "${name} failed";
            pkgs.runCommand name { } "touch $out";
        in
        {
          inherit hyprflip hy3;
          nixos-module = assertCheck "nixos-module" (
            etc."hyprflip/hyprflip.so".source == "${hyprflip}/lib/libhyprflip.so"
            && etc."hyprflip/libhy3.so".source == "${hy3}/lib/libhy3.so"
          );
          home-manager-module = assertCheck "home-manager-module" (
            map (p: p.outPath) plugins == [
              hyprflip.outPath
              hy3.outPath
            ]
          );
        }
      );
    };
}
