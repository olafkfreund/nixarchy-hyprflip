{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  # The exact Hyprland main build p620 runs; no package overrides.
  hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
in
{
  stdenv = hyprland.stdenv;

  packages = [
    hyprland
    hyprland.dev
    pkgs.cmake
    pkgs.ninja
    pkgs.gnumake
    pkgs.pkg-config
    pkgs.git
    pkgs.python3
    pkgs.binutils
    pkgs.foot
    pkgs.grim
    pkgs.wtype
    pkgs.lua5_5
    pkgs.libGL
  ]
  ++ hyprland.buildInputs;

  # ctypes loads xkbcommon by soname rather than through a linked executable.
  env.LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.libxkbcommon ];
}
