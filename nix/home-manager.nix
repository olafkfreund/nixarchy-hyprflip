{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  cfg = config.programs.hyprflip;
  hmHyprland = config.wayland.windowManager.hyprland.package;
  # Home Manager recommends a null package when NixOS installs Hyprland.
  defaultHyprland =
    if hmHyprland != null then
      hmHyprland
    else if osConfig != null then
      osConfig.programs.hyprland.package
    else
      null;
in
{
  options.programs.hyprflip = {
    enable = lib.mkEnableOption "the Hyprflip Hyprland plugin";
    containers.enable = lib.mkEnableOption "the experimental hy3 provider for multi-app cards";
    hyprlandPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = defaultHyprland;
      defaultText = lib.literalMD "`wayland.windowManager.hyprland.package`, else the NixOS `programs.hyprland.package`";
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

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hyprlandPackage != null;
        message = "programs.hyprflip.hyprlandPackage must be set: no Hyprland package found in Home Manager or NixOS.";
      }
    ];
    # hyprflip loads before hy3, as examples/containers-trial.lua requires.
    wayland.windowManager.hyprland.plugins = [
      cfg.package
    ]
    ++ lib.optional cfg.containers.enable cfg.hy3Package;
  };
}
