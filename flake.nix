{
  description = "Hyprflip: two Hyprland windows as the faces of a rotating card";

  inputs = {
    # Same pin as devenv.yaml and hyprpm.toml (Hyprland v0.56.2).
    hyprland.url = "github:hyprwm/Hyprland/efb50993780079460b0cbed1363e2166a2de1d9f";
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

      # Upstream's lock supplies Glaze 8, but this compositor requires Glaze 7.
      # ponytail: duplicated in devenv.nix; move both to one overlay when the pin changes.
      pinnedHyprland =
        pkgs:
        let
          glaze = (pkgs.glaze.override { enableSSL = false; }).overrideAttrs {
            version = "7.2.0";
            src = pkgs.fetchFromGitHub {
              owner = "stephenberry";
              repo = "glaze";
              tag = "v7.2.0";
              hash = "sha256-f3NVRi3SXKo42hn0WCw7JsOK3EkdOVJIcuzhPorKjFY=";
            };
            cmakeFlags = [
              "-Dglaze_ENABLE_SSL=OFF"
              "-Dglaze_DISABLE_SIMD_WHEN_SUPPORTED=ON"
            ];
          };
        in
        hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland.override {
          glaze-hyprland = glaze;
        };
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
