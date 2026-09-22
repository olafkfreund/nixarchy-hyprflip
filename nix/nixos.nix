{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.hyprflip;
in
{
  options.programs.hyprflip = {
    enable = lib.mkEnableOption "the Hyprflip Hyprland plugin at /etc/hyprflip/hyprflip.so";
    containers.enable = lib.mkEnableOption "the experimental hy3 provider at /etc/hyprflip/libhy3.so";
    hyprlandPackage = lib.mkOption {
      type = lib.types.package;
      default = config.programs.hyprland.package;
      defaultText = lib.literalExpression "config.programs.hyprland.package";
      description = "Hyprland the plugins are built against. Must be the compositor you run, version 0.56.2.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./hyprflip.nix { hyprland = cfg.hyprlandPackage; };
      defaultText = lib.literalMD "Hyprflip built against `hyprlandPackage`";
      description = "The Hyprflip core plugin package.";
    };
    hy3Package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./hy3.nix { hyprland = cfg.hyprlandPackage; };
      defaultText = lib.literalMD "patched hy3 built against `hyprlandPackage`";
      description = "The hy3 provider package used by containers.";
    };
  };

  # ponytail: nixpkgs has no Hyprland plugin option; users load these stable paths.
  config = lib.mkIf cfg.enable {
    environment.etc = {
      "hyprflip/hyprflip.so".source = "${cfg.package}/lib/libhyprflip.so";
    }
    // lib.optionalAttrs cfg.containers.enable {
      "hyprflip/libhy3.so".source = "${cfg.hy3Package}/lib/libhy3.so";
    };
  };
}
