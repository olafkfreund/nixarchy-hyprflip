{
  lib,
  hyprland,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  python3,
  pango,
  cairo,
}:
let
  # Must match the revision checked by integrations/hy3/CMakeLists.txt.
  rev = "12a73ab0adddbc39f839da320dcc2b028769fc58";
  hy3Source = fetchFromGitHub {
    owner = "outfoxxed";
    repo = "hy3";
    inherit rev;
    hash = "sha256-HCDDmRkDxQMWMIlTAjZ4vLIQ8e7VnHqBgaJ73u1ItnY=";
  };
in
hyprland.stdenv.mkDerivation {
  pname = "hy3";
  version = "0-unstable-2026-08-23-hyprflip";

  # The bridge includes ../../src from Hyprflip's core.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../integrations/hy3
      ../src
    ];
  };
  cmakeDir = "../integrations/hy3";

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    python3
  ];
  buildInputs = [
    hyprland.dev
    pango
    cairo
  ]
  ++ hyprland.buildInputs;

  cmakeFlags = [
    (lib.cmakeFeature "HY3_SOURCE_DIR" "${hy3Source}")
    (lib.cmakeFeature "HY3_SOURCE_REV" rev)
  ];

  meta = {
    description = "hy3 layout provider patched for Hyprflip's experimental multi-app cards";
    homepage = "https://github.com/outfoxxed/hy3";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
