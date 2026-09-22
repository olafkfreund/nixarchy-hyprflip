{
  lib,
  hyprland,
  cmake,
  ninja,
  pkg-config,
  lua5_5,
  libGL,
}:
# The compositor's own stdenv: the plugin must match its compiler ABI.
hyprland.stdenv.mkDerivation {
  pname = "hyprflip";
  version = "0.2.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../CMakeLists.txt
      ../src
      ../tests/core_test.cpp
      ../tests/motion_probe.cpp
    ];
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];
  buildInputs = [
    hyprland.dev
    lua5_5
    libGL
  ]
  ++ hyprland.buildInputs;

  cmakeFlags = [ (lib.cmakeBool "BUILD_TESTING" true) ];
  doCheck = true;

  # Home Manager loads "${pkg}/lib/lib${pname}.so".
  postInstall = ''
    ln -s hyprland/plugins/hyprflip.so $out/lib/libhyprflip.so
  '';

  meta = {
    description = "Hyprland plugin that shows two windows as the faces of a rotating card";
    homepage = "https://github.com/olafkfreund/nixarchy-hyprflip";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
